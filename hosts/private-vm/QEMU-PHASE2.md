# private-vm Phase 2: retire RDP, route GUI apps via xpra

This document is a staged execution plan for replacing the current
"RDP-into-a-Linux-desktop" GUI model with per-window forwarding via
[xpra](https://github.com/Xpra-org/xpra). It is written to be executed
by an agent starting with no prior conversation context. Phase 1 (the
vz → qemu migration with FPR balloon, see `QEMU-MIGRATION.md`) must be
complete and stable first.

## Goal & motivation

The Phase 1 host-memory work landed cleanly under qemu, but the GUI
story carried over from the vz era and never matched how the VM is
actually used. The VM is an SSH-primary, GUI-secondary tool: 95% of
interaction is `vm ssh` + tmux + nvim. The remaining 5% is "open
Firefox at this URL" or "render this PDF" — explicitly invoked,
short-lived, ideally indistinguishable from a native Mac app.

The current stack (xrdp + openbox + FreeRDP) implements the opposite
shape — "remote desktop session" — and three concrete symptoms fall
out of that mismatch:

1. **Window decorations are wrong.** openbox's
   `<decor>no</decor><maximized>true</maximized>` rule for Firefox
   doesn't apply: Firefox draws its own client-side titlebar regardless
   of WM hints, and xrdp's session geometry races with openbox's
   place-then-maximize. Net effect: a Firefox window with its own
   chrome inside an openbox session inside an RDP window inside a Mac
   window. Three nested surfaces, none of them right.
2. **Scaling can only be wrong on one display.** xrdp negotiates one
   DPI per session at connect time. Move the FreeRDP window from
   built-in Retina to an external 1× display (or vice versa) and font
   sizes stay frozen at the original scale. No knob fixes this inside
   the "one session, one geometry" model.
3. **The VM has a shape on screen.** Even with the above fixed, RDP
   gives you a window labelled "private-vm" containing a foreign WM.
   That's the wrong surface for a tool that should fade into the
   background.

xpra solves all three by changing the unit of transport from "a
session" to "a window." Each guest X11 window is wrapped on the host
side in a real macOS-native frame; decorations come from the host, not
the guest. Per-window scale is renegotiated per attach (and on display
change). When no window is open, the VM has no visible surface at all.

### Why not native qemu display?

A cocoa/sdl/gtk qemu display window is opened by the qemu process at
start time and lives for the process lifetime. That means either the
window is always present (the VM has a shape on screen — the thing we
want to avoid) or the GUI option is gone until the next `vm start`.
Neither matches "GUI strictly optional, SSH primary." xpra preserves
that property: the guest X server (Xvfb-backed, embedded in xpra) runs
in the background; nothing is visible on the host until you explicitly
attach.

### Why not just keep RDP and fix the openbox config?

Even with a perfectly-tuned openbox rc.xml, Firefox's CSD still draws
its own titlebar, and xrdp still negotiates one DPI per session. The
two symptoms are structural to "session-shaped transport," not to the
specific WM. Switching transport is the only fix.

### Why xpra and not Waypipe / ssh -Y / VNC / SPICE?

- **Waypipe** forwards Wayland surfaces over SSH, with results as good
  as xpra or better. macOS has no Wayland compositor, so the host can't
  consume them. Disqualified.
- **ssh -Y / X11 forwarding** requires XQuartz on the host; XQuartz on
  Apple Silicon is functional but not native-feeling, and per-window
  scaling under XQuartz inherits the same one-DPI-per-server problem
  RDP has. Disqualified.
- **VNC** is full-screen-only, same surface problem as RDP. SPICE has
  per-window potential but spice-gl on darwin is unproven, the macOS
  client (`remote-viewer`) is GTK and clunky, and SPICE without GL
  reduces to "a slightly different RDP." Disqualified.
- **xpra** runs a real X server in the guest (Xvfb), wraps each X
  window in a host-native frame on attach, supports detach (apps keep
  running invisibly), supports per-attach DPI, and has a working —
  unflashy but functional — macOS client in nixpkgs. Selected.

### What about GPU acceleration?

Deferred to **Phase 2.5**. xpra pixel-encodes per window like xrdp
does for the whole session; transport bandwidth is fine on a local
Lima VM. Guest-side GPU (a custom qemu build with virglrenderer + a
`virtio-gpu-gl-pci` device + mesa in the guest) only helps if Firefox
itself feels slow under xpra. We measure first. See "Out of scope"
below for the deferral details.

## Pre-flight checks

Before making any changes, verify these still hold:

1. **Phase 1 is in.** `vmType: qemu` in `hosts/private-vm/lima.yaml`,
   FPR balloon attached, idle host RSS sits well under the configured
   ceiling. If Phase 1 is not done or is unstable, do that first; this
   plan layers on top.

2. **VM is currently running** with the RDP stack and you can confirm
   the symptoms above (or have already accepted them as the
   motivation). Specifically:
   ```
   vm ssh "systemctl is-active xrdp"
   ```
   Expect: `active`.

3. **xpra exists in nixpkgs** on both sides:
   ```
   nix eval --raw nixpkgs#xpra.version
   nix eval --raw nixpkgs#xpra.meta.platforms 2>&1 | grep -E 'darwin|linux'
   ```
   Expect: a version string, and platforms containing both
   `aarch64-darwin` and `aarch64-linux`. If darwin is missing, stop —
   xpra's macOS client is a hard dependency.

4. **Current `vm rdp` works** (so there's a known-good rollback target):
   ```
   vm rdp
   ```
   Expect: a FreeRDP window appears showing Firefox in an openbox
   session. Close it.

## What this plan changes

Five pieces, all in `~/etc/`:

1. **`hosts/private-vm/full.nix`** — gut the RDP/desktop stack
   (`services.xrdp`, `services.xserver`, openbox, pipewire, port 3389
   firewall hole, openbox home-manager config) and replace with: xpra
   package + a user systemd unit that runs `xpra start :100` headless.
2. **`hosts/private-vm/full.nix`** — add `DISPLAY=:100` to the user's
   zsh environment when in an SSH session, so guest-launched GUI apps
   render into the xpra server without ceremony.
3. **`modules/private-vm/default.nix`** — replace `vmRdp` with `vmGui`,
   a small host launcher that opens an xpra client attached to the
   guest server over SSH.
4. **`modules/private-vm/default.nix`** — swap `pkgs.freerdp` for
   `pkgs.xpra` in the host `home.packages` list. Update the `vm`
   dispatcher: `rdp` → `gui`.
5. **`hosts/private-vm/lima.yaml`** — no changes needed.
   `keychain-helper.nix` and `keychain-helper.swift` also stay
   untouched (they manage the LUKS passphrase, unrelated to RDP).

## Step 1: Add xpra to the guest and run it as a user service

Edit `~/etc/hosts/private-vm/full.nix`.

### 1a. Add the xpra package

In `environment.systemPackages`, drop `openbox` and add `xpra`:

```nix
environment.systemPackages = with pkgs; [
  firefox
  xpra
];
```

(`firefox` stays — it's still the app you want to launch.)

### 1b. Add the user systemd unit

Add a new `systemd.user.services.xpra` block. xpra bundles its own
Xvfb, so we do NOT need `services.xserver.enable`:

```nix
# Headless xpra server: a persistent X session that lives in the
# background, owned by the user, with no display until something
# attaches. Guest-launched GUI apps render into this server (via
# DISPLAY=:100, set in zsh init below); the host's `vm gui` client
# attaches over SSH and surfaces whatever windows exist as
# host-native macOS windows. Detach = windows keep running
# invisibly; reattach = they reappear. Closing the last window does
# not stop the server.
#
# `--daemon=no` keeps xpra in the foreground so systemd owns the
# lifecycle. `--bind-tcp` is NOT set: clients attach via SSH only,
# using xpra's `ssh://` URL scheme, which uses xpra's stdio protocol
# over an SSH stdin/stdout pipe — no additional TCP port.
systemd.user.services.xpra = {
  description = "xpra headless X server on :100";
  wantedBy = [ "default.target" ];
  path = with pkgs; [ xpra xorg.xauth ];
  serviceConfig = {
    Type = "simple";
    ExecStart = ''
      ${pkgs.xpra}/bin/xpra start :100 \
        --daemon=no \
        --start-via-proxy=no \
        --pulseaudio=no \
        --notifications=no \
        --systemd-run=no \
        --mdns=no \
        --webcam=no \
        --html=off \
        --bell=no \
        --speaker=no \
        --microphone=no \
        --printing=no \
        --file-transfer=off \
        --opengl=no
    '';
    Restart = "on-failure";
    RestartSec = "2s";
  };
};
```

The flag set is deliberately conservative: every optional channel
(audio, notifications, mdns, file transfer, printing, webcam) is off.
We turn things on individually as we discover we need them. Keeping
the surface small now makes "did this flag break it" easy to bisect
later.

`--opengl=no` is set explicitly because we have no host GL transport
configured (Phase 2.5). xpra will pixel-encode every window. Fine for
Firefox UI, possibly visible jank for WebGL — measure, don't predict.

### 1c. Make sure user lingering is enabled

A user systemd unit only runs when the user has an active session
*unless* lingering is enabled. We want xpra running whether or not
anyone has SSH'd in:

```nix
users.users.${user}.linger = true;
```

(Add this inside the existing `users.users.${user}` block.)

## Step 2: Remove the RDP/desktop stack from the guest

Still in `~/etc/hosts/private-vm/full.nix`, remove:

1. The entire `services.xserver` block (lines ~54–58):
   ```nix
   # DELETE:
   services.xserver = {
     enable = true;
     windowManager.openbox.enable = true;
     displayManager.startx.enable = true;
   };
   ```
2. The entire `services.xrdp` block (lines ~60–65):
   ```nix
   # DELETE:
   services.xrdp = {
     enable = true;
     defaultWindowManager = "${pkgs.openbox}/bin/openbox-session";
     openFirewall = true;
     audio.enable = true;
   };
   ```
3. The pipewire/rtkit block (lines ~67–72) — it was added to feed xrdp
   audio. We're not forwarding audio in v1.
   ```nix
   # DELETE:
   security.rtkit.enable = true;
   services.pipewire = {
     enable = true;
     pulse.enable = true;
     alsa.enable = true;
   };
   ```
4. The openbox xdg.configFile entries inside the home-manager block
   (lines ~98–112): `openbox/autostart` and `openbox/rc.xml`. They
   become dead config.
5. The firewall rule (line ~209):
   ```nix
   # DELETE:
   networking.firewall.allowedTCPPorts = [ 3389 ];
   ```

Leave everything else in `full.nix` alone — the LUKS home volume, the
`/nix` stage-1 mount, the FPR balloon kernel module, the drop_caches
timer, the home-manager zsh setup, etc.

## Step 3: Wire `DISPLAY=:100` into the guest shell environment

The whole point of the persistent xpra server is that any GUI app
launched in the guest with `DISPLAY=:100` renders into it. We want
this to be transparent — `firefox` in `vm ssh`, no preamble.

In the home-manager block in `full.nix`, extend the existing
`programs.zsh.initContent` (or add a sibling `home.sessionVariables`).
The cleanest option is `home.sessionVariables`:

```nix
home-manager.users.${user} = {
  # ... existing config ...
  home.sessionVariables = {
    DISPLAY = ":100";
  };
};
```

`home.sessionVariables` is sourced by both login shells and the user
systemd environment, so the xpra unit and your interactive shells see
a consistent value. (The xpra server itself does not read `DISPLAY` to
pick its own display number — `:100` is passed as a positional arg in
the unit's ExecStart — so there's no chicken/egg.)

## Step 4: Add the `vm gui` host launcher

In `~/etc/modules/private-vm/default.nix`, replace the `vmRdp` binding
with `vmGui`. Locate the `vmRdp = pkgs.writeShellScriptBin "vm-rdp"
...` block (around line 347) and replace it wholesale with:

```nix
vmGui = pkgs.writeShellScriptBin "vm-gui" ''
  # Attach an xpra client to the guest's :100 server over SSH. The
  # guest runs a persistent, headless xpra server as a user systemd
  # unit (full.nix). Apps launched in the guest with DISPLAY=:100 —
  # which is the default in the guest user's session env — render
  # into that server. This command surfaces those windows on the
  # Mac as native macOS windows. Closing the windows does not stop
  # the server; closing this client does not stop the apps.
  #
  # No additional ports: xpra speaks its protocol over the SSH
  # stdio channel via the ssh:// URL scheme. Reuses Lima's SSH
  # config so authentication is identical to `vm ssh`.
  set -euo pipefail
  export LIMA_HOME="${limaHome}"
  ssh_cfg="$LIMA_HOME/private-vm/ssh.config"

  # Boot the VM if needed — `vm gui` should be a one-shot from cold
  # just like `vm ssh` is.
  "${vmStart}/bin/vm-start"

  # --ssh tells xpra exactly how to invoke ssh. We pass the Lima
  # ssh.config so host key, port, identity, and user all match
  # `vm ssh`. The trailing :100 selects the display.
  exec ${pkgs.xpra}/bin/xpra attach \
    --ssh="ssh -F $ssh_cfg" \
    "ssh://lima-private-vm/100"
'';
```

Then in the `vm` dispatcher (around line 581), change:

```nix
rdp)          exec "${vmRdp}/bin/vm-rdp" "$@" ;;
```

to:

```nix
gui)          exec "${vmGui}/bin/vm-gui" "$@" ;;
```

And in the usage block (around line 596), change:

```nix
echo "  rdp            launch FreeRDP desktop session" >&2
```

to:

```nix
echo "  gui            attach an xpra client (surface guest GUI apps)" >&2
```

Finally, in `home.packages` (around line 612), swap `pkgs.freerdp` for
`pkgs.xpra`:

```nix
home.packages = [
  vm
]
++ lib.optionals pkgs.stdenv.isDarwin [
  pkgs.lima
  pkgs.xpra
  qemuWrapper
];
```

The host xpra package brings the GTK-based macOS client. It is not
gorgeous but the windows it produces ARE real macOS windows: the host
window server owns the frame, decorations, and resize, so per-display
scaling tracks the display the window is on, and titlebars look
native.

## Step 5: Apply

```
nix-rebuild
```

Then redeploy the guest:

```
vm rebuild
```

This pushes the new generation into the VM. The xrdp service stops on
the next activation; the xpra user service starts.

Note: `vm rebuild` activates the new config live but does not cold-boot.
Phase 1's warning about gens 2..N living only as activated user-space
pivots applies here too — if you want to verify cold-boot survives,
`vm stop && vm start` after a successful rebuild.

## Step 6: Verification

### 6a. xpra is running, xrdp is gone

```
vm ssh "systemctl --user is-active xpra && \
  ! systemctl is-active xrdp && echo OK"
```

Expect: `active`, then `OK`. If xrdp is still active, the deployment
didn't pick up the removal — check `vm rebuild` output.

```
vm ssh "xpra info :100 | head -20"
```

Expect: xpra version banner and session info. If this fails with "no
sessions found," the user service didn't start — `systemctl --user
status xpra` will show why (usually a missing dep or a typo in the
ExecStart flags).

### 6b. Guest can launch a GUI app and the host can see it

In one terminal:

```
vm gui
```

A small "Xpra" window may briefly appear and then go idle (no windows
to show yet). Leave it.

In another terminal:

```
vm ssh firefox
```

Within a few seconds Firefox should appear as a discrete macOS window
— with macOS-style window controls, drop shadow, and a native Cmd-Q to
close.

If Firefox launches but no window appears on the host:
- Check the xpra client log for connection errors.
- Verify `DISPLAY=:100` is actually exported in the SSH shell:
  `vm ssh 'echo $DISPLAY'` should print `:100`.
- Verify the app is connecting to the right server:
  `vm ssh "xpra info :100 | grep -i windows"` should show a window
  count > 0 once Firefox is up.

### 6c. Detach/reattach preserves running apps

With Firefox open on the host:

1. Close the xpra client window on the Mac (the Firefox surface goes
   away).
2. `vm ssh "xpra info :100 | grep -i windows"` — window count should
   still be > 0. Firefox is still running, just invisible.
3. `vm gui` again. Firefox reappears at its previous position/size.

If Firefox actually exits when you detach, `--exit-with-children=yes`
got set somewhere — check the systemd unit's ExecStart.

### 6d. Per-display scaling

Drag the Firefox window from your Retina display to an external 1×
monitor (or vice versa). Text should re-render at the new scale within
~1s of being dropped. There WILL be a brief blur or repaint flash —
xpra renegotiates pixel encoding for the new DPI. That's expected.

If text stays frozen at the old scale, the xpra client isn't picking
up the display change. Quit and relaunch `vm gui` as a workaround;
file an upstream bug if reproducible.

### 6e. No persistent VM surface

```
vm ssh "pkill -u ${user} firefox || true"
```

Close the xpra client. Nothing should be visible from the VM. `ps`,
Dock, Mission Control — no VM-related window anywhere. This is the
property we care most about.

## Troubleshooting

**xpra user service won't start.** Most common cause: the user has no
linger, so the user@.service doesn't run when no one's logged in.
Verify:

```
vm ssh "loginctl show-user ${user} | grep Linger"
```

Expect: `Linger=yes`. If not, `users.users.${user}.linger = true;`
didn't make it in.

**Guest GUI apps complain "cannot open display".** `DISPLAY` not set
in the shell. Check `vm ssh 'env | grep DISPLAY'`. If empty,
`home.sessionVariables.DISPLAY = ":100"` didn't activate — `vm
rebuild` may need a fresh login (close existing SSH multiplexed
connections: `ssh -O exit lima-private-vm` from a host shell with the
right config in `~/.ssh/config`, then reconnect).

**xpra client connects but no window appears.** Run a known-trivial
app to isolate the X server vs the specific app:

```
vm ssh "xclock"
```

If xclock shows up, the problem is app-specific (Firefox is unhappy
about something — fonts, profile, gpu). If xclock also fails to
appear, the xpra server is not actually rendering — check `xpra info
:100` for an "error" line.

**Latency feels bad.** Default xpra encoding picks rgb24/png for
Firefox UI, which is high-quality but bandwidth-heavy. On a local
Lima VM bandwidth is not the bottleneck — CPU is. If the host feels
sluggish dragging windows around, try `--encoding=rgb` or
`--encoding=jpeg` on the client side via the launcher (add to the
`xpra attach` line). Don't pre-optimize; measure first.

**xpra client window is itself a single Mac window containing all
guest windows.** That's xpra's "desktop" mode, the opposite of what
we want. We want "seamless" mode (per-window frames). Seamless is
the default for `xpra start <display>` (as opposed to `xpra
start-desktop`); if you see desktop mode, the unit's ExecStart was
misedited. Check it says `xpra start :100`, not `xpra start-desktop
:100`.

## Rollback

Reverting Phase 2 is local-only:

```
cd ~/etc
git diff hosts/private-vm/full.nix modules/private-vm/default.nix
# review
git checkout hosts/private-vm/full.nix modules/private-vm/default.nix
nix-rebuild
vm rebuild
```

xrdp comes back, openbox starts again, `vm rdp` returns. The VM's
named disks and home volume are untouched.

If `vm rebuild` doesn't immediately revive xrdp (it sometimes lingers
in failed state from the activation that disabled it), kick it:

```
vm ssh "sudo systemctl reset-failed xrdp && sudo systemctl restart xrdp"
```

## What this plan does NOT do (and why)

- **No guest GPU / virglrenderer.** Deferred to **Phase 2.5**. Plan
  surface: custom qemu build (`pkgs.qemu.override { openGLSupport =
  true; virglSupport = true; sdlSupport = true; }`), wrap with the
  same wrapper used for FPR, attach `-device virtio-gpu-gl-pci`,
  install mesa + `virtio_gpu` kernel module in the guest. xpra has
  experimental GL transport (`--opengl=yes`) that would let the GPU
  acceleration flow through to the host, but it's unproven on darwin
  and not worth the bring-up cost until xpra-without-GL is measured.
  Trigger: revisit only if Firefox under xpra feels visibly slow on
  realistic workloads.
- **No audio forwarding.** ~~pipewire/rtkit ripped out in Step 2.~~
  *Post-landing addendum (2026-06-15):* audio is now wired through.
  See **Phase 2.1: audio** below for the actual config that ships.
- **No auto-attach.** `vm gui` is explicit. A future enhancement could
  watch the guest for "window count went from 0 to 1" and launch the
  client automatically (WSLg-style). Easy bolt-on; defer until the
  manual flow proves annoying.
- **No `xdg-open` host-callback.** Guest `xdg-open https://...` opens
  in guest Firefox via xpra, not in host Safari. If you want
  guest-side `xdg-open` to route certain MIME types to host
  applications, that needs a small shim talking back over SSH.
  Out-of-scope for v1.
- **No clipboard, file-transfer tuning.** xpra's clipboard forwarding
  is on by default and usually works. File transfer is off in the
  unit; turn it on if/when needed.
- **`keychain-helper.nix` / `.swift` stay.** They manage the LUKS
  passphrase for the encrypted home volume, unrelated to RDP. The
  only RDP-specific keychain bit was an inline `private-vm-rdp`
  lookup inside `vmRdp`, which goes away with that script.
- **Firefox profile is unchanged.** The CSD-titlebar issue that
  motivated some of this disappears for free: in a real macOS window,
  Firefox's CSD looks correct because the host frame around it is
  already native. No about:config edits needed.

## Definition of done for Phase 2

All of:

- [ ] `nix-rebuild` succeeds after the changes.
- [ ] `vm rebuild` succeeds and the guest's new generation activates.
- [ ] xpra user service is `active`; xrdp is no longer active
      (step 6a).
- [ ] `vm gui` opens a client; `vm ssh firefox` produces a native
      macOS window (step 6b).
- [ ] Detach/reattach preserves running apps (step 6c).
- [ ] Per-display scaling works on display change (step 6d).
- [ ] When no apps are running and the client is closed, the VM has
      no surface visible anywhere (step 6e).
- [ ] No regressions in `vm ssh`, `vm rebuild`, `vm lock`, `vm
      unlock`, FPR memory reclaim, or cold-boot (`vm stop && vm
      start`).

Once all checked: commit the two changed files
(`hosts/private-vm/full.nix`, `modules/private-vm/default.nix`) as a
single commit titled along the lines of:
`feat(private-vm): retire xrdp for xpra per-window forwarding`.

Phase 2.5 (guest GPU, only if xpra-without-GL feels slow) will be
planned in a separate document if and when it's needed.

## Phase 2.1: audio (landed 2026-06-15)

Sound from guest apps (Firefox, mpv, ...) now reaches the host's
CoreAudio output via xpra's `--speaker=on` channel. The path is:

```
guest app (Firefox)
  -> pipewire-pulse (auto_null sink, virtual)
    -> auto_null.monitor (source)
      -> xpra gstreamer pulsesrc (PULSE_SOURCE=auto_null.monitor)
        -> opus codec
          -> xpra SSH transport
            -> host xpra client
              -> macOS CoreAudio
```

What this required (all in `hosts/private-vm/full.nix`):

1. **Re-add `services.pipewire` + `security.rtkit` to the guest.** The
   Phase 2 deferral note above ("ripped out in Step 2") is reversed.
   We need a pulse-compatible server in the guest for any audio to
   exist at all — qemu exposes no audio hardware to the guest
   (`/proc/asound/cards` is empty), so without pipewire there is no
   sink for Firefox to play into and `--speaker=on` captures silence.
   pipewire/wireplumber synthesizes an `auto_null` sink in this
   audio-card-less environment, which is fine: it behaves like
   /dev/null on the output side but exposes a real `auto_null.monitor`
   source we can capture from.

2. **Flip the xpra unit's `--speaker=no` → `--speaker=on`.**

3. **Set `PULSE_SOURCE=auto_null.monitor` in the xpra unit's
   `Environment`.** This is the non-obvious one. With
   `--pulseaudio=no` (we use the system pipewire-pulse, not a private
   xpra-spawned daemon), xpra's gstreamer pulsesrc still defaults to a
   hardcoded `Xpra-Speaker` device that only exists under
   `--pulseaudio=yes`, and capture fails with `Failed to connect
   stream: No such entity`. Setting `PULSE_SOURCE` redirects pulsesrc
   to the actual monitor source.

   **Trap to remember:** xpra's `--audio-source=NAME` flag takes a
   GStreamer source-plugin name (`pulse`, `alsa`, `test`, ...), NOT a
   Pulse source name. Passing `--audio-source=auto_null.monitor` (or
   `--audio-source=monitor`) errors with `unknown source plugin`. The
   only working route to pin the Pulse source is the env var.

4. **Add pulseaudio to the unit `PATH`.** xpra runs `pactl` at startup
   to probe the pulse server; without it on PATH, xpra reports
   `audio.pulseaudio.found=False` and refuses to start its capture
   pipeline.

5. **Pre-seed `~/.Xauthority` via `ExecStartPre`.** Unrelated to audio
   but landed in the same iteration: nixpkgs' xpra wrapper fails its
   internal `xauth` subprocess with ENOENT even though xauth is on
   PATH (some env-stripping in xpra's spawn path). Without the cookie,
   every X client (including Firefox) gets `Authorization required,
   but no authorization protocol specified`. The pre-seed bypasses
   xpra's broken xauth call.

6. **Move the xpra unit into `home-manager.users.${user}.systemd.user.services`.**
   Also unrelated to audio but landed together. As a top-level
   `systemd.user.services.xpra` it installed for *every* user with a
   running `user@.service` — including the bootstrap `nixos` account
   that Lima uses — and the two units raced for X display `:100`,
   whose Xvfb abstract socket `@xpra/100` is a system-global name.
   `nixos` won (lower uid, earlier login), `igor`'s unit crashlooped,
   and `vm gui` (which attaches as `igor`) hit a dead socket.

### Audio verification

```
vm ssh "/run/current-system/sw/bin/pactl list short sinks"
# expect: auto_null  PipeWire  ...  IDLE (or RUNNING while playing)

vm ssh "/run/current-system/sw/bin/pactl list short sources"
# expect: auto_null.monitor  PipeWire  ...

vm ssh "journalctl --user -u xpra -n 200 | grep -i 'audio capture'"
# expect: "audio capture using 'opus' audio codec"
# NOT:    "Failed to connect stream: No such entity"
```

Then `vm gui`, `vm ssh firefox`, navigate to anything with sound — it
plays through the Mac.
