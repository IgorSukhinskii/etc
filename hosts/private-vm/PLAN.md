# private-vm — design, current state, roadmap

A Lima-managed NixOS VM on the work Mac that isolates personal data + private
browsing from InTune/Defender surveillance. This doc exists so future sessions
can pick up the work without re-deriving the design from scratch.

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

## Architecture decisions (and why)

| Decision | Why |
|---|---|
| Lima (vz mode) | User already uses colima; lightweight; Apple Virtualization.framework is native on M-series |
| NixOS guest | Declarative, fits existing flake; image is reproducible |
| `plain: true` in lima.yaml | NixOS doesn't satisfy Lima's cloud-init probes; plain mode skips them |
| SSH tunnel for RDP (vs Lima portForwards) | Plain mode disables portForwards; SSH tunnel is what Lima does under the hood anyway |
| Xorg + openbox + xrdp (vs Wayland) | xrdp requires Xorg (`xorgxrdp` driver); experimental Wayland backend is not production-ready |
| FreeRDP or Windows App as client | User already uses Windows App for office; FreeRDP is FOSS alternative with no Microsoft telemetry |
| Firefox starts via openbox autostart | Default xrdp lifecycle: connect → fresh session → Firefox starts; disconnect → session killed → Firefox killed. Zero idle cost when no RDP client connected |
| openbox no-decor + maximize rule on Firefox | Avoids triple chrome (macOS + openbox + Firefox); keeps the "looks like native macOS browser window" feel |
| `--impure` build reading `~/.ssh/id_ed25519.pub` and `~/.lima/_config/user.pub` | Pubkeys live only in local-only qcow image, never committed to the public repo |
| `nix.linux-builder` (120GB/12GB/6c) | Mac is aarch64-darwin; needs Linux builder for aarch64-linux image build. Default 20GB was too small for a full GUI closure |

## Current state (working)

- `private-vm-build` → builds qcow via nixos-generators (with `--impure` to read host pubkeys)
- `private-vm-start` → boots VM via Lima in plain mode, ignores Lima's cosmetic "fatal" probe timeout, waits for SSH, opens RDP tunnel on host 127.0.0.1:3389
- `private-vm-stop` → tears down RDP tunnel + stops Lima
- SSH into VM: `ssh -F ~/.lima/private-vm/ssh.config lima-private-vm` (works as `igor@private-vm`)
- xrdp on guest port 3389 → tunneled to host 3389
- pipewire + `services.xrdp.audio.enable` enabled (untested end-to-end)

## Known gotchas

- **`.git/objects` permission errors after `nix-rebuild`** — `sudo darwin-rebuild` occasionally creates a git object as root in `.git/objects/<hash>/`. Fix: `sudo chown -R $(whoami):staff .git/objects/`.
- **Lima always emits `level=fatal msg="did not receive an event with the 'running' status"`** — cosmetic. NixOS doesn't satisfy Lima's probes. The launcher ignores this exit code; the VM is fine.
- **Pubkey changes need image + VM rebuild** — if the host pubkey or Lima pubkey changes, `private-vm-build` + `limactl delete private-vm` + `private-vm-start`.
- **`limactl` is not on host PATH** by default — it's available via colima's deps. To get it directly, add `lima` to `home.packages` (TODO).

## Key files

- `flake.nix` — adds `nixos-generators` input
- `hosts/private-vm/flake-module.nix` — declares `nixosConfigurations.private-vm` (for eval) + `packages.private-vm-image` (qcow build)
- `hosts/private-vm/config.nix` — host options, sshd, user `igor`, pubkey wiring (--impure reads)
- `hosts/private-vm/vm.nix` — Xorg + openbox + xrdp + pipewire + Firefox autostart with no-decor rule
- `hosts/private-vm/lima.yaml` — template (PLACEHOLDER_IMAGE_PATH rewritten by launcher)
- `modules/nix-dev.nix` — `private-vm-{build,start,stop}` wrapper scripts
- `modules/darwin/nix.nix` — `nix.linux-builder` config (120GB disk, 12GB RAM, 6 cores)

## Roadmap

### Immediate next steps

1. **xrdp password for `igor`** — xrdp wants password auth and the user has no password set. Either set a password in the NixOS config or configure xrdp PAM differently. Needed before RDP login can actually succeed.
2. **Add `lima` to `home.packages`** so `limactl` is on PATH for debugging.
3. **End-to-end RDP smoke test** from Windows App or FreeRDP to verify Firefox actually appears.

### Medium-term

4. **Tmux/sessionizer integration** — `dir=project=session` model. Add a `~/sessions/private-notes/` stub directory; sessionizer detects it, runs `private-vm-start`, opens a tmux session named `private-notes` with `default-command` set to SSH into the VM at a particular path. Each new pane in the session is automatically an SSH shell in the VM. SSH `ControlMaster`/`ControlPersist` in `~/.ssh/config` so subsequent panes are cheap.
5. **LUKS-encrypted `/home/igor/private`** dataset, NOT root. On-demand unlock so VM can boot without secrets being accessible.
6. **Host daemon + vsock + Touch ID Keychain integration** for one-touch unlock. Small Swift/Go binary on the host, listens on a vsock port, calls Keychain (triggers biometric), returns passphrase over vsock to a VM-side `unlock`/`lock` pair. Always keep an offline LUKS passphrase backup (paper or personal device password manager).
7. **VPN inside the VM** — Mullvad recommended (anonymous payment, established) or self-hosted WireGuard on a VPS. Hides DNS, SNI, destination IPs from Defender's network extension.

### Cleanup / nice-to-have

8. **Migrate off `nixos-generators`** to upstream `system.build.images` (deprecation warning in eval; NixOS 25.05+ supports it natively). Do this AFTER the full stack is proven working — premature swap could conflate failures.
9. **Suppress Lima's cosmetic "fatal" log** in the launcher output (currently visible but ignored).
10. **GUI browser refinements** — `userChrome.css` in Firefox to slim chrome, `/dynamic-resolution` already wired into FreeRDP for live resize.

## Workflow commands

```bash
private-vm-build           # build qcow image (--impure under the hood)
private-vm-start           # boot Lima + open RDP tunnel (idempotent)
private-vm-stop            # tear down RDP tunnel + stop Lima

# Direct SSH (after start)
ssh -F ~/.lima/private-vm/ssh.config lima-private-vm

# Verify state
lsof -iTCP:3389 -sTCP:LISTEN   # RDP tunnel?
lsof -iTCP:60022 -sTCP:LISTEN  # SSH proxy?

# Connect with FreeRDP (when ready)
xfreerdp /v:127.0.0.1:3389 /u:igor /dynamic-resolution \
  /size:1600x1000 /scale:140 /sound:sys:pulse +clipboard /cert:ignore
```
