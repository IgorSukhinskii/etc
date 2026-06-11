# private-vm — design, current state, roadmap

A Lima-managed NixOS VM on the work Mac that isolates personal data + private
browsing from InTune/Defender surveillance. This doc exists so future sessions
can pick up the work without re-deriving the design from scratch.

## Status (2026-06-11)

Operational end-to-end on the smoke-test path:
- ✅ Image build (~2.6 GB)
- ✅ VM boots, SSH-as-`nixos` works via Lima's pubkey
- ✅ `private-vm-rebuild` pushes credentials + rsyncs `etc/` + runs in-VM `nixos-rebuild switch`
- ✅ SSH-as-`igor` works for terminal/tmux (via per-user ControlPath)
- ✅ `private-vm-rdp` launches `sdl-freerdp` (CoreAudio backend) and reaches xrdp

Rough but functional. Several real polish items below.

## Threat model

Work Mac runs Microsoft Defender for Endpoint via InTune. It hooks the
**Endpoint Security framework** (kernel-level), so on the host it sees:

- All filesystem ops (paths, names, contents)
- All processes and their syscalls
- All network connections — IPs, ports, SNI hostnames, plaintext DNS
- Potentially HTTPS contents if an MITM CA is installed in the host trust store

It **cannot** see inside a VM: the guest has its own kernel and ES doesn't
hook into guest syscalls. The hypervisor is one host process doing block I/O
to one disk image file. That's the trust boundary.

Goal: personal notes + a private browser, fully above board, just not
passively surveilled.

## Architecture

Near-generic NixOS image (only Lima's agent pubkey is baked) + runtime
credential push + in-VM `nixos-rebuild` for the full config.

The image trusts exactly one thing: Lima's per-host agent pubkey, which is
the hypervisor's bootstrap key. That's the trust anchor. Everything else —
your real SSH pubkey, the password hash for RDP, Lima's continued access
after the first rebuild — is delivered at runtime by `private-vm-rebuild`
into `/var/lib/private-vm/`, and sshd reads it via
`services.openssh.authorizedKeysFiles`.

Two distinct users:
- **`nixos`** — bootstrap/ops user, baked into the image, has Lima's pubkey
  via two paths: `/etc/ssh/authorized_keys.d/nixos` (image-time bake, for
  the very first boot) and `/var/lib/private-vm/lima.pub` (runtime push, for
  every subsequent rebuild). Used by `private-vm-rebuild` only. Generic —
  same identity regardless of host owner. Has `initialPassword = "bootstrap"`
  so PAM's `account` check doesn't reject it as locked (see
  [[nixos-sshd-locked-account]]).
- **`${host.username}` (`igor` by default, in `hosts/private-vm/vars.nix`)** —
  the real user. Created by the in-VM rebuild. SSH (for terminal/tmux work
  via `private-vm-ssh`) + RDP (for the desktop session). Owns home directory.
  Authenticated by `${user}.pub` (real SSH pubkey, runtime) and `passwd.hash`
  (for xrdp PAM, runtime), both pushed to `/var/lib/private-vm/`.

```
1. Image (private-vm-build, rare; --impure for the one Lima pubkey read)
   Minimal closure: kernel, systemd, sshd, nix+flakes, git, rsync,
   `nixos` user with sudo + Lima's pubkey authorised + initialPassword.
   No real user, no GUI stack, no home-manager. ~2.6 GB.

2. Boot (private-vm-start)
   Lima boots the qcow in plain mode (--timeout=20s so Lima's
   cidata-dependent SSH check fails fast). Our wait loop verifies
   SSH-as-nixos actually responds before returning.

3. Provision + rebuild (private-vm-rebuild — idempotent)
   As nixos:
     - scp passwd.hash    → /var/lib/private-vm/passwd.hash
     - scp ${user}.pub    → /var/lib/private-vm/${user}.pub
     - scp lima.pub       → /var/lib/private-vm/lima.pub
     - rsync etc/         → /home/nixos/etc
     - sudo nixos-rebuild switch --flake ~/etc#private-vm
   The full config (`full.nix`) then:
     - Creates the user from host.username
     - Activates xrdp + openbox + Firefox + pipewire
   sshd reads runtime pubkey files via authorizedKeysFiles, so the activation
   can wipe authorized_keys.d entries without locking us out.

4. Use
   private-vm-ssh   — SSH as ${user} (per-user ControlPath to avoid sharing
                      the nixos channel that private-vm-rebuild opens)
   private-vm-rdp   — Tunnel + Keychain password + sdl-freerdp → desktop as ${user}
```

## Decisions (and why)

| Decision | Why |
|---|---|
| Lima (vz mode) | Apple Virtualization.framework is native on M-series; user already uses colima |
| NixOS guest | Declarative, fits existing flake |
| Lima's agent pubkey baked via `--impure` (one read) | Lima's `cidata.iso` uses 8.3 filenames (`USER_DAT`, `META_DAT`) and Lima-specific format — not cloud-init NoCloud-compatible. Going through Lima's pubkey at build time is simpler than generating our own NoCloud ISO + attaching it. |
| Generic `nixos` user in image, real user (`host.username`) added by rebuild | Image is portable across host owners — fork, change `vars.nix`, no other edits. SSH-as-nixos cleanly separates ops access from desktop session. |
| Username lives in `hosts/private-vm/vars.nix` as `flake.privateVm.username` | Single source of truth — read by `config.host.username` (NixOS) and `vmUser` (launcher scripts) |
| `services.openssh.authorizedKeysFiles` instead of `users.users.<u>.openssh.authorizedKeys.keyFiles` | keyFiles inlines content into the closure at eval time — forbidden in pure mode and would require image rebuild on every key rotation. authorizedKeysFiles is read by sshd at connection time. |
| `initialPassword = "bootstrap"` for the nixos user | NixOS leaves accounts with no password as `!`-locked, and sshd's PAM `account` check rejects locked accounts even on pubkey auth. The password value is never used — `PasswordAuthentication=false` blocks SSH password login. |
| `plain: true` + `--timeout=20s` on limactl start | Plain mode skips Lima's cidata mount and guestagent. The default 10-min SSH readiness check would hang because Lima's probe expects a file plain mode never mounts. |
| Per-user ControlPath in `private-vm-ssh` | SSH multiplexes by (host, port) and pins the master to whichever user opened it first. private-vm-rebuild opens the shared master as nixos; without a per-user socket, private-vm-ssh would silently land in the nixos channel. |
| In-VM `nixos-rebuild` (not host-cross-built) | Incremental, preserves runtime state, doesn't need linux-builder after image build |
| rsync over SSH (vs Lima `mounts:`) | Explicit; works under any hypervisor |
| Upstream `system.build.images.qemu-efi` | nixos-generators deprecated; upstream module is the new path |
| Xorg + openbox + xrdp (vs Wayland) | xrdp requires Xorg (`xorgxrdp` driver); Wayland backend is experimental |
| `sdl-freerdp` (not `xfreerdp`) on macOS | nixpkgs ships both; xfreerdp needs an X server (XQuartz) and fails with "failed to open display" on plain macOS. sdl-freerdp uses Metal/SDL natively. |
| `/sound:sys:mac` (not pulse) | `pulse` is PulseAudio which isn't on macOS; pulse init fails and the disconnect handler null-derefs, crashing the client. CoreAudio backend is `mac`. |
| FreeRDP from nixpkgs (not Homebrew) | Already in nixpkgs binary cache for aarch64-darwin; matches the rest of the Nix-managed toolchain |

## Files

- `flake.nix` — flake inputs
- `hosts/private-vm/vars.nix` — `flake.privateVm.username` (single source of truth)
- `hosts/private-vm/flake-module.nix` — `nixosConfigurations.{private-vm,private-vm-bootstrap}` + `packages.private-vm-image`
- `hosts/private-vm/bootstrap.nix` — image-only config: sshd, `nixos` user with Lima's pubkey, nix flakes, git, rsync, `services.openssh.authorizedKeysFiles` runtime paths, filesystem + bootloader settings (mkDefault, image profile overrides during disk-image build)
- `hosts/private-vm/config.nix` — shared base: host options, sshd, sudo, stateVersion
- `hosts/private-vm/full.nix` — real user with `hashedPasswordFile`, Xorg+openbox+xrdp+pipewire+Firefox, home-manager wiring
- `hosts/private-vm/lima.yaml` — VM resources (40 GiB), `plain: true`, user.name=nixos
- `modules/nix-dev.nix` — `private-vm-{build,start,rebuild,ssh,rdp,stop}` wrappers; adds `lima` + `freerdp` to PATH on darwin
- `modules/darwin/nix.nix` — linux-builder config (used by `private-vm-build` only)

## Workflow

```bash
# One-time setup
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/private-vm"
nix run nixpkgs#mkpasswd -- -m sha-512 > "${XDG_CONFIG_HOME:-$HOME/.config}/private-vm/passwd.hash"
security add-generic-password -a "$(nix eval --raw .#privateVm.username)" -s private-vm-rdp -w   # same password

# First-time provisioning (or after a fresh limactl delete)
private-vm-build            # bootstrap qcow (rare; uses linux-builder)
private-vm-start            # boot Lima
private-vm-rebuild          # push creds + etc + nixos-rebuild switch (~15-30 min first time)
private-vm-rdp              # Firefox via RDP

# Iteration loop
# edit etc/...
private-vm-rebuild          # fast incremental rebuild inside the VM (seconds-minutes)

# Diagnostic
private-vm-ssh              # shell as ${user}
ssh -F ~/.lima/private-vm/ssh.config lima-private-vm   # shell as nixos (ops)
lsof -iTCP:3389 -sTCP:LISTEN     # RDP tunnel up?
```

## Known gotchas

- **`.git/objects` permission errors after `nix-rebuild`** — `sudo darwin-rebuild` occasionally creates a git object as root in `.git/objects/<hash>/`. Fix: `sudo chown -R $(whoami):staff .git/objects/`.
- **`nix build` ignores untracked files** — when you add a new file (e.g. `vars.nix`), `nix build` of a dirty git tree won't see it until you `git add` it. Won't fail loudly — files just go missing in the build.
- **First `private-vm-rebuild` activation is slow** — dbus-broker reload + restart of every unit cascades for several minutes the first time. Subsequent rebuilds (when most of the closure is already there) take seconds.
- **`switch-to-configuration-ng` 0.1.0 wedges on first activation** — Rust rewrite enters a userspace tight loop (no syscalls, ~100% CPU, single thread, tiny RSS) after restarting the user dbus-broker. Worked around in `bootstrap.nix` with `system.switch.enableNg = false` + `enable = true`, reverting to the Perl switch. Re-enable once `switch-to-configuration-ng > 0.1.x` and the bug is fixed upstream. If you ever hit the wedge again with ng on: `sudo systemctl kill -s KILL nixos-rebuild-switch-to-configuration.service` + `reset-failed`, then disable ng before retrying.
- **Killed `private-vm-rebuild` leaves a stale systemd unit** — `nixos-rebuild-switch-to-configuration.service` lingers as "already loaded or has a fragment file". Fix: `private-vm-ssh sudo systemctl reset-failed nixos-rebuild-switch-to-configuration.service` and `... stop ...`, then retry.
- **Pre-uid-pin home volumes need a one-time chown** — `full.nix` pins `users.users.${user}.uid = 1000` so the LUKS home volume's ownership survives system-disk wipes. Volumes formatted before this pin landed have files owned by whatever uid the dynamic allocator picked (typically 1001 if anything else got 1000 first). Symptom: `home-manager-igor.service` fails fast (~40 ms, exit 1) on first activation after a reset because HM can't write into `~/.config/`. Fix once: `ssh -F ~/.lima/private-vm/ssh.config lima-private-vm 'sudo chown -R 1000:100 /home/${user}'`, then `sudo systemctl restart home-manager-${user}.service`. From the pin onward this won't drift again.
- **TOFU on first SSH** — first connection adds the VM host key to known_hosts. Acceptable.
- **Lima's "fatal" exit code in plain mode** — Lima's SSH-readiness check expects a cidata file plain mode never mounts, so the foreground wait would hit a 10-min timeout. We set `--timeout=20s` to cut that short; our own SSH check verifies for real.

## Roadmap

### Polish on what's already working

- [ ] **RDP window sizing** — `sdl-freerdp` flashes a black fullscreen Mac space, opens Firefox at fixed size that doesn't conform to the RDP window, and Firefox keeps its own decorations. `openbox/rc.xml` already has a Firefox `<decor>no</decor> <maximized>true</maximized>` rule — investigate why it doesn't apply (window class match, openbox version, xrdp display size override). Goal: window behaves like a native macOS Firefox.
- [ ] **Stop putting RDP password in argv** — FreeRDP warns: `/p:` is visible in `ps`. Options: `/from-stdin` and pipe the password into `sdl-freerdp` stdin; `/args-from:<fd>`; or `FREERDP_ASKPASS` env var pointing at a binary that prints the password. Stdin pipe is the simplest fit for our Keychain lookup.
- [x] **`private-vm-ssh` + tmux integration** — VM-backed projects live as stubs in `~/projects/<name>/` with a `.private-vm` marker (`VM_DIR=~/projects/<name>`). Sessionizer detects the marker, starts the VM, sets `default-command` + `PRIVATE_VM_SSH`/`PRIVATE_VM_DIR` session env vars. `tmux-layout` is VM-aware: non-empty-cmd windows run `private-vm-ssh -t 'cd $vm_dir && $cmd; exec $SHELL'`; shell windows use default-command. `private-vm-ssh` now has `ControlMaster=auto ControlPersist=600` so pane splits are cheap. New projects: `private-vm-project-new <name>` creates both stub and VM-side dir.
- [ ] **Terminal integration inside the SSH session** — verify TERM, locale, true-colour, image protocols (kitty/iTerm-style) work from the host terminal through the SSH session. Currently zsh + starship look fine from the screenshot but worth verifying things like image preview in yazi, ghostty's nice features, etc.
- [ ] **Image size optimisation** — bootstrap qcow is 2.6 GB; could trim more by dropping unused systemd targets, locales, etc. Mostly cosmetic.

### Host-side cleanup

- [ ] **Shrink the linux-builder qcow (115 GB on disk)** — only used for image rebuilds now. Drop to ~40 GB in `modules/darwin/nix.nix` and recreate, OR run `fstrim -av` inside the builder + `qemu-img convert -O qcow2 -c` on host. Biggest single reclaim available.
- [ ] **`/nix/store` GC** — `nix-collect-garbage -d` on user + sudo; precede with `find ~/projects ~/code -maxdepth 3 -name "result" -type l` to clean up stale GC roots. Follow with `nix store optimise`.
- [ ] **Backup story** — none yet. Especially relevant once we have an encrypted /home volume (below) — the raw volume file is what you'd back up.

### Persistence & encryption

- [x] **Separate `/home` volume + LUKS encryption + Touch ID unlock** — Lima named disk (`limactl disk create private-home --size 40GiB`, survives `limactl delete`). `/dev/vdb` formatted as LUKS + ext4 via `private-vm-init-home` (one-time, before first `private-vm-rebuild`). NixOS mounts it at `/home/${user}` with `nofail noauto`; boot proceeds with volume locked. `private-vm-unlock` (host script): Touch ID via `/usr/bin/swift hosts/private-vm/keychain-helper.swift` → passphrase from macOS Keychain → SSH `cryptsetup luksOpen` + `mount`. `private-vm-lock`: reverse. `private-vm-rebuild` + `private-vm-rdp` + sessionizer all call `private-vm-unlock` automatically (idempotent). `private-vm-keychain-set`: one-time passphrase setup; always keep an offline backup in your password manager.

  One-time setup sequence:
  ```
  limactl disk create private-home --size 40GiB
  private-vm-build && private-vm-start
  private-vm-keychain-set
  private-vm-init-home
  private-vm-rebuild
  ```

- [ ] **Split `/nix` onto its own Lima named disk** — natural next step toward
  impermanence. `/nix` (store + db + profiles + gcroots, the whole tree) on a
  separate persistent volume means a `limactl delete + build + start` cycle
  doesn't re-download the closure — first rebuild after wipe is just system
  activation + `/boot` repopulation, seconds instead of minutes. Content-
  addressable store paths make the split safe; the `/nix/var/nix/db` SQLite
  must stay with the store (split them and `nix-store --verify` lies). One-
  time format dance like `private-vm-init-home` but no LUKS (nothing secret
  in `/nix`). Bootstrap config needs a `fileSystems."/nix"` entry and first-
  boot handling for an unformatted `/dev/vdc`. Standalone change; do after the
  current unlock fix is in. Full erase-your-darlings (tmpfs `/` + bind-mounts
  for `/var/lib/nixos`, `/etc/machine-id`, ssh host keys) is the natural step
  *after* that, but much more invasive and not required for the speed win.

### Network

- [ ] **VPN inside the VM** — Mullvad (anonymous payment, established) or self-hosted WireGuard on a VPS. Hides DNS, SNI, destination IPs from Defender's network extension. Adds another layer below the VM-isolation boundary.

### Nice-to-have

- [ ] **`private-vm-rdp <app>`** — accept an app name; SSH-launch it into the xrdp session before connecting, so the same wrapper can open Firefox, Obsidian, etc. Today the session always runs whatever openbox autostarts (Firefox).
- [ ] **Firefox `userChrome.css`** to slim chrome further (independent of openbox decorations).
- [ ] **Commit Lima pubkey to `vars.nix`** as an alternative to the `--impure` build — would eliminate the one impure read and make the build fully reproducible. Tradeoff: not portable across hosts (each fork has a different Lima key). Probably not worth doing.
- [ ] **Suppress Lima's cosmetic logs** in `private-vm-start` output.

### Workflow / ergonomics

- [ ] **In-VM editing workflow for `etc/`** — canonical source after rebuild lives at `/home/nixos/etc`, owned by nixos. If you want to iterate on config from inside the VM as `igor` (e.g. via tmux SSH session), you'd need either to add `igor` to the group that owns `/home/nixos/etc`, or to canonicalise the flake source to a shared path like `/var/lib/private-vm-etc`. Today the assumption is "edit on host, push via private-vm-rebuild". Worth deciding before this becomes a pain point.
- [ ] **Host pubkey rotation** — if your `~/.ssh/id_ed25519.pub` ever changes (new key, new laptop), `private-vm-rebuild` pushes the new pubkey to `/var/lib/private-vm/${user}.pub`; sshd picks it up at the next connection. No image rebuild needed. Worth knowing; document the gotcha that the rebuild SSH itself goes via Lima's key so pubkey rotation can't lock out the rebuild path.
- [ ] **Lima agent key rotation** — if `~/.lima/_config/user.pub` changes (Lima reinstall, manual delete), the image baked with the old key won't accept SSH from the new key. Need a `private-vm-build` + `limactl delete + start` cycle. `private-vm-rebuild` would then also push the new `lima.pub` so subsequent rebuilds use it.

### In-VM housekeeping

- [ ] **In-VM `/nix/store` GC** — separate from host. The VM accumulates store paths every `private-vm-rebuild`. Add a scheduled `nix-collect-garbage -d` inside the VM (systemd timer, weekly) so the 40 GiB disk doesn't fill silently. Eventually we'll want this metric exposed somehow so it's not a surprise.
- [ ] **Logging / observability inside the VM** — journald defaults only. No log shipping, no dashboards. If something breaks at 2am and the VM was running fine yesterday, the only forensic trail is `journalctl` inside. Worth thinking about a minimal "what changed recently" pane in the desktop session (uptime, last rebuild, recent service failures).

### Open questions

- Does `private-vm-rebuild` need to push `lima.pub` every single time? After the first push, it's stable until Lima regenerates its agent key (which doesn't happen on its own). Pushing every time is harmless but could be elided.
- Is the `/etc/ssh/authorized_keys.d/nixos` entry in the image still needed? With `/var/lib/private-vm/lima.pub` pushed by every rebuild, the image-baked entry only matters for the very first boot before any rebuild has run. Could simplify the impure-read story by moving that file to runtime push as well — but then the FIRST private-vm-rebuild would have to authenticate via something else (password? a different bootstrap mechanism?).
