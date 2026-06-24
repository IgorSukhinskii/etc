# private-vm GUI — cocoa-way + waypipe (Wayland), handover

Status: **BLOCKED on a waypipe-darwin transport bug.** Investigation handed
off mid-flight. This doc has everything needed to resume on the
**waypipe-darwin** side with no further input.

Date of handover: 2026-06-24. Host: Apple **M4 Pro**, **macOS 26.5.1 (25F80)**.

---

## 1. Goal & why this approach

We want to launch a **guest GUI app (primarily the zen browser)** in the Lima
NixOS VM and see it as a **native macOS window** on the host. The old approach
(xpra) is dead: it broke on macOS Tahoe (GTK3's Cocoa menu integration mutates
NSMenu off the main thread → `NSInternalInconsistencyException`).

### Selection criteria (from the original request)
1. Clean text rendering (no blur)
2. Good mac screen scaling (HiDPI/Retina)
3. One host window = one guest window
4. Closing host window = closing guest window
5. No guest window decorations / traffic lights
6. Wayland compatibility
7. GPU compatibility (when rutabaga lands upstream)
8. No persistent open VM window (headless)
9. CLI ergonomics (one command opens a host window)

Hard requirement: **launch guest browser, see it on host.**

### Why cocoa-way (research conclusion)
Remote-display tools split into (a) **buffer/protocol transports** (ssh -X,
xpra, **waypipe**, wprs) that need a host-side compositor to turn surfaces into
native windows, and (b) **whole-desktop pixel streamers** (VNC, RDP,
Sunshine/Moonlight) which are structurally wrong for per-window seamlessness.

On macOS the missing piece was always a **native Wayland→Cocoa compositor**.
That changed in 2026 with **cocoa-way** (https://github.com/J-x-Z/cocoa-way) — a
native macOS Wayland compositor written in Rust (Smithay) that renders each
guest Wayland toplevel as its own **Metal-backed NSWindow**, fed by
**waypipe-darwin** (https://github.com/J-x-Z/waypipe-darwin, a macOS-patched
waypipe). It is the only option that natively satisfies the headline goal and
fixes xpra's two big gaps (crisp text, Wayland). Alternatives (wprs, weston-RDP,
Sunshine) either still need cocoa-way underneath or are whole-desktop. Both
cocoa-way and waypipe-darwin are by the **same single developer (J-x-Z)** and
are early/experimental — maturity was the known risk, now realized.

### The pipeline
```
guest Wayland app  →  waypipe server (guest, NixOS)  →  SSH  →
waypipe-darwin client (mac)  →  cocoa-way compositor  →  native NSWindow (Metal)
```
`waypipe` IS the compositor from the app's POV — **no guest-side compositor /
Xserver is needed.** cocoa-way does the real compositing on the Mac.

---

## 2. What was implemented (committed in this repo)

All in the commit that adds this file. Migration xpra → cocoa-way+waypipe:

- **`modules/private-vm/default.nix`**
  - `darwinModules.private-vm`: dropped the `xpra` cask; added `homebrew.taps =
    [{ name = "j-x-z/tap"; trusted = true; }]` and `homebrew.brews` now has
    `cocoa-way` + `waypipe-darwin` (+ existing `age-plugin-se`).
    - `trusted = true` is required because **Homebrew 6.0** refuses non-official
      taps unless trusted; the nix-darwin tap `trusted` option emits
      `tap "...", trusted: true` in the Brewfile. **This needed a nix-darwin
      bump** (flake.lock: nix-darwin → 2026-06-18) — the option is post-2026-06.
  - `vmGui` (`vm gui [app]`) fully rewritten: starts cocoa-way once (background,
    reused; logs `/tmp/cocoa-way.log`), finds its socket at
    `$TMPDIR/cocoa-way/wayland-1` (clears stale socket on relaunch to avoid an
    ECONNREFUSED race), then `exec waypipe --compress=zstd ssh <args>
    lima-private-vm env PATH=… MOZ_ENABLE_WAYLAND=1 NIXOS_OZONE_WL=1 <app>`.
    - The `env PATH=…` is essential: waypipe execs the app in a **non-login SSH
      session** whose PATH lacks the home-manager per-user profile. zen lives at
      `/etc/profiles/per-user/igor/bin` (useUserPackages). Without the explicit
      PATH, `vm gui zen` fails with "No such file or directory".
    - The **zen binary is `zen-beta`**, not `zen`. `vm gui` defaults to
      `firefox` (a debug browser) when no arg is given.

- **`hosts/private-vm/full.nix`**
  - systemPackages: dropped `xpra`; added `waypipe`, plus debug tools `foot`
    (minimal SHM client) and `wayland-utils` (`wayland-info`). `firefox` kept as
    a debug browser (zen is the real target, installed via the `browser` HM
    profile).
  - Added `environment.sessionVariables = { MOZ_ENABLE_WAYLAND=1;
    NIXOS_OZONE_WL=1; }`.
  - Removed the entire headless-xpra systemd user unit + xauth seeding +
    `DISPLAY=:100`.
  - pipewire kept but **inert** for host audio (waypipe carries no audio).

- **`modules/zen.nix`** (`!isDarwin` branch): `gfx.webrender.software = true` +
  `media.ffmpeg.vaapi.enabled = false`. The guest has no real GPU (software
  llvmpipe) and cocoa-way advertises **no `zwp_linux_dmabuf`** (only wl_shm
  XRGB8888/ARGB8888), so zen must render into wl_shm, not dmabuf. (Correct
  regardless of the transport bug.)

- **`flake.lock`**: nix-darwin `2026-05-17 → 2026-06-18` (only that input).

### Host one-time step (already done, declarative now)
The tap trust is declarative via `trusted = true`. If a fresh machine ever
errors with "Refusing to load formula … untrusted tap", run once:
`/opt/homebrew/bin/brew trust j-x-z/tap`.

---

## 3. Diagnostic journey & the conclusion

Every app over `vm gui` shows a **black window**. We ruled out, in order:

| Hypothesis | Test | Result |
|---|---|---|
| Client/toolkit-specific | `foot`, `firefox`, `zen-beta` | all black |
| GPU/dmabuf buffers | `gfx.webrender.software=true` (wl_shm) | still black; WebRender confirmed compositing frames via `MOZ_LOG` |
| Buffer format | `wayland-info`: cocoa-way offers wl_shm `XR24`/`AR24`, no dmabuf | format is supported |
| waypipe **wire version** skew | guest waypipe **0.11.0** AND pinned upstream **0.10.5** | both black |
| Redraw-only-on-window-event | resize/move the cocoa-way window | still black |
| Fixed in newer cocoa-way | cocoa-way **1.0.1** changelog | no renderer changes (PATH/dylib/container only) |

cocoa-way logs (with `RUST_LOG=cocoa_way=debug`):
`RENDER: N tiles present but nothing rendered — likely unsupported buffer
format or no committed buffer yet` (src/main.rs:594), and **never** the
"unsupported buffer format … not wl_shm" branch (src/main.rs:497).

### THE decisive test (renderer vs transport)
We built cocoa-way from source and wrote a **minimal native macOS wl_shm
client** (`render-test`, see §4) that creates an xdg_toplevel and commits a
solid-red ARGB8888 buffer **directly to cocoa-way, bypassing waypipe entirely**.

Result — cocoa-way log:
```
New client connected
New XDG Toplevel Created
get_buffer_pixels: Argb8888  1600x1200  stride=6400
```
`get_buffer_pixels` (src/render.rs:11) **was called**, no "nothing rendered"
warning → cocoa-way **renders the buffer (red window).**

### Conclusion
**cocoa-way's renderer works. The bug is in the waypipe-darwin transport.**
Through waypipe, the committed buffer never reaches `get_buffer_pixels`; at
render time the surface's `current.buffer` is `None` (the `497` branch is not
hit either), i.e. **buffers committed through waypipe-darwin do not land as a
live `NewBuffer` in cocoa-way's commit state.** A direct native client commits
a buffer the exact same compositor renders fine.

This also explains why none of the earlier changes helped — they were all on
the wrong side of the pipe.

---

## 4. The repro harness (already built)

Cloned at **`~/projects/cocoa-way`** (a clone of upstream + our additions, on a
local branch — see `git log`):

- `flake.nix` — dev shell: `rustc`/`cargo` (1.95, satisfies edition 2024),
  `pkg-config`, `libxkbcommon`, `pixman`. (cocoa-way's `build.rs` only
  pkg-config-probes `xkbcommon` + `pixman-1`; Metal/AppKit come from the SDK.)
- `test-client/src/bin/render-test.rs` — the native wl_shm client above.
- `test-client/src/bin/connect-test.rs` — tiny `UnixStream::connect` probe.
- `test-client/Cargo.toml` — added `wayland-protocols` + `tempfile` deps.

**Build note:** the user's env sets `CARGO_TARGET_DIR=~/.cache/cargo-target`
and `CARGO_HOME=~/.local/share/cargo`, so binaries land in
`~/.cache/cargo-target/release/`, NOT `./target`.

Build + run everything from inside the flake shell:
```sh
cd ~/projects/cocoa-way
nix develop --command cargo build --release            # builds cocoa-way + test-client
```

**Confirm cocoa-way's renderer works (expect a SOLID RED window):**
```sh
tgt="${CARGO_TARGET_DIR:-$HOME/.cache/cargo-target}/release"
rt="${TMPDIR%/}/cocoa-way"
pkill -f cocoa-way; sleep 1; rm -f "$rt/wayland-1"   # avoid stale-socket race
RUST_LOG=cocoa_way=debug "$tgt/cocoa-way" >/tmp/cw.log 2>&1 &
until [ -S "$rt/wayland-1" ]; do sleep 0.2; done; sleep 0.5
env XDG_RUNTIME_DIR="$rt" WAYLAND_DISPLAY=wayland-1 "$tgt/render-test"
# -> red window; /tmp/cw.log shows "get_buffer_pixels: Argb8888 ...".
```
Gotcha: cocoa-way is started fresh by `vm gui` via pgrep; a **stale
`wayland-1` socket** from a Cmd-Q'd instance causes ECONNREFUSED. Always
`rm -f "$rt/wayland-1"` before a fresh manual start. `connect_to_env`
returning `NoCompositor` from a rust wayland client = it hit a stale/dead
socket, not a real failure.

### cocoa-way internals worth knowing (source in ~/projects/cocoa-way/src)
- `render.rs::get_buffer_pixels` — reads a wl_shm buffer via smithay
  `with_buffer_contents`, copies BGRA, forces alpha. **Correct.**
- `main.rs` ~455–604 — the per-tile render loop. For each surface it inspects
  `current.buffer`: `NewBuffer` → cache/`get_buffer_pixels`→`draw_pixels`
  (`rendered_count++`); `None` → `draw_from_cache`; logs `594` if
  `rendered_count == 0`.
- `state.rs` — `CompositorHandler` (commit), `ShmHandler`, `delegate_shm!`,
  advertises wl_shm `Argb8888`/`Xrgb8888`. **This is where to instrument
  commits** (see §5 step 1).

---

## 5. NEXT STEPS — investigate waypipe-darwin (concrete, no input needed)

Goal: find why a buffer committed through waypipe-darwin doesn't become a live
`NewBuffer` in cocoa-way, then fix it (PR to waypipe-darwin if needed). The
same dev owns both repos, so a cocoa-way-side fix is also acceptable.

### Step 0 — reconfirm the split is still true
Run the §4 red-window test. If red → renderer still fine, proceed.

### Step 1 — pinpoint WHICH side drops the buffer (fastest, ~30 min)
We have cocoa-way source + build. **Instrument cocoa-way's commit handler** to
log every surface commit and whether a buffer was attached, then reproduce via
waypipe and read the log.

- In `~/projects/cocoa-way/src/state.rs`, find `impl CompositorHandler … fn
  commit(&mut self, surface)` and add a `log::info!` dumping the surface id and
  the `BufferAssignment` (NewBuffer/Removed/None) pulled from
  `cached_state.get::<SurfaceAttributes>().current().buffer`. (Mirror how
  main.rs reads it.)
- Rebuild: `nix develop --command cargo build --release`.
- Run that locally-built cocoa-way as the `vm gui` compositor. Either:
  - temporarily point `vm gui` at it (edit `cocoa_way=` in the `vmGui` script —
    rebuild host with `nix-rebuild`), **or** simpler: start the built cocoa-way
    manually (as in §4) and run the waypipe client by hand (Step 2 command).
- `vm gui foot` (or the Step 2 manual command) and read the log:
  - **NewBuffer IS logged for the content surface** but render still sees None →
    bug is **cocoa-way commit/render state timing** (e.g. a later
    buffer-less commit clears `current.buffer`; the initial NewBuffer frame
    isn't rendered/cached). Fix likely in cocoa-way main.rs/state.rs.
  - **NewBuffer is NEVER logged** (only buffer-less commits / no attach) → bug
    is **waypipe-darwin** not replaying attach/commit (or its SHM pool) to
    cocoa-way. Go to Step 3.

### Step 2 — reproduce the black with a controllable waypipe client
`vm gui` uses `/opt/homebrew/bin/waypipe` (waypipe-darwin 0.10.6). To get debug
logging and use a local build, run the client by hand against a running
cocoa-way (replicates what `vmGui` execs):
```sh
rt="${TMPDIR%/}/cocoa-way"
export LIMA_HOME="${XDG_STATE_HOME:-$HOME/.local/state}/private-vm/lima"
ssh_cfg="$LIMA_HOME/private-vm/ssh.config"
~/etc-private-vm-helpers... # or just: vm start  (ensure VM up)
env XDG_RUNTIME_DIR="$rt" WAYLAND_DISPLAY=wayland-1 \
  /opt/homebrew/bin/waypipe --debug --compress=zstd ssh \
    -F "$ssh_cfg" -l igor \
    -o ControlPath="$LIMA_HOME/private-vm/ssh-igor.sock" \
    -o ControlMaster=auto -o ControlPersist=600 -o StreamLocalBindUnlink=yes \
    lima-private-vm \
    env PATH=/etc/profiles/per-user/igor/bin:/run/current-system/sw/bin:/usr/bin:/bin \
      foot
```
`--debug` (or `-d`) makes waypipe log its object/buffer tracking. The guest
side (`waypipe server`, nixpkgs 0.11.0) is auto-spawned by `waypipe ssh`. Note:
the guest-side "degenerate damage rectangle" ERRs are waypipe rejecting
zero-area damage from `foot` — a red herring (zen sends proper damage and is
also black).

### Step 3 — dig into waypipe-darwin source
```sh
git clone https://github.com/J-x-Z/waypipe-darwin.git ~/projects/waypipe-darwin
```
It's Rust (Cargo `version = 0.10.6`), built with meson+cargo like upstream
waypipe. Write a `flake.nix` dev shell (model on `~/projects/cocoa-way/flake.nix`
+ upstream nixpkgs `waypipe` build inputs: `meson ninja pkg-config cargo rustc
lz4 zstd` and optionally `ffmpeg vulkan-loader shaderc rust-bindgen`).

Prime suspects (the fork's stated patches): **"replaced `memfd_create` with
temporary file-based SHM for Darwin"** and "unnamed socket handling". The
**client side** (mac) creates the wl_shm pool/buffer on cocoa-way from a
tempfile fd. Look at:
- how the client creates the `wl_shm_pool` + `wl_buffer` and issues
  `attach`/`damage`/`commit` to the downstream (cocoa-way) compositor;
- whether the tempfile-backed pool is sized/mmapped/synced such that the buffer
  is valid at the moment `commit` is replayed;
- attach/commit **ordering** vs frame callbacks (could be committing before the
  buffer content is ready, or a buffer-less commit landing last).

Compare the client's emitted sequence against what our `render-test` does
(attach → damage → commit, once), which cocoa-way renders fine.

### Step 4 — fix & validate
Patch waypipe-darwin (or cocoa-way per Step 1), rebuild, rerun Step 2 with
`foot` → expect a rendered terminal, then `vm gui zen-beta`. If fixing
waypipe-darwin, build a bottle or point `vm gui`'s `waypipe=` at the local
build; upstream a PR to J-x-Z/waypipe-darwin.

### If we file instead of fix
Issue is essentially written in §3. File at **J-x-Z/waypipe-darwin** (or
cocoa-way), include the `render-test` harness as the repro, and the key line:
*cocoa-way renders direct native wl_shm clients (`get_buffer_pixels: Argb8888`)
but every waypipe-darwin-forwarded client is black ("tiles present but nothing
rendered") — buffers don't land as a live NewBuffer.* Tested guest waypipe
0.11.0 and 0.10.5; macOS 26.5 / M4 Pro; cocoa-way 1.0.0.

---

## 6. Versions / facts (pin these in any bug report)
- macOS 26.5.1 (25F80), Apple M4 Pro.
- cocoa-way: brew **1.0.0** (upstream tag 1.0.1 exists, no render changes).
- waypipe-darwin: brew, binary reports **`waypipe 0.10.6`** (fork's own version;
  there is **no upstream `v0.10.6` tag** — upstream goes 0.10.0..0.10.5, 0.10.7,
  0.11.0).
- guest waypipe: nixpkgs **0.11.0** (tested), also pinned **0.10.5** (tested).
- cocoa-way globals (`wayland-info`): wl_compositor v5, xdg_wm_base v6, wl_shm
  (XR24/AR24 only, **no dmabuf**), wp_viewporter, wp_fractional_scale_manager_v1,
  zxdg_decoration_manager_v1, seat, etc.

## 7. Loose ends (unrelated to the transport bug)
- **Decorations (criterion #5):** cocoa-way draws server-side titlebars; no
  documented off-switch. `zxdg_decoration_manager_v1` is advertised, so SSD-off
  may be reachable. Revisit after rendering works.
- **`vm gui` post-quit hang:** waypipe/ssh ControlPersist lingers after the app
  exits; Ctrl-C for now. Tidy in `vmGui` once unblocked.
- **Audio:** waypipe carries none. pipewire kept in the guest as the future
  capture point (forward `auto_null.monitor` to a host PulseAudio over SSH).
