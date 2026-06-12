# private-vm volume split plan

Focused implementation note for moving private-vm from "mutable Lima instance
disk is the VM" to "disposable instance disk + explicit durable volumes".

## Goal

The Lima instance root disk should be disposable. A fresh instance should be
recreated from a known Nix-built bootstrap image, attach durable volumes, and
converge via `private-vm-rebuild`.

Target restore path:

```bash
private-vm-start
private-vm-rebuild
private-vm-rdp
```

First-time path:

```bash
private-vm-build
private-vm-start
private-vm-keychain-set
private-vm-init-home
private-vm-rebuild
```

Longer term, add `private-vm-up` as the high-level "make it usable" wrapper.

## Host paths

Use stable, intentional locations:

- Lima state:
  `${XDG_STATE_HOME:-$HOME/.local/state}/private-vm/lima`
- Bootstrap image out-link:
  `${XDG_DATA_HOME:-$HOME/.local/share}/private-vm/images/bootstrap`
- Encrypted user home disk:
  `$HOME/data/private-vm/home.qcow2`

The bootstrap image path should no longer depend on `~/etc/result`. Use
`nix build --out-link "$imageLink" "$flakeDir#private-vm-image"` and point Lima
at the qcow2 under that out-link.

## Volume roles

- Disposable root:
  `$LIMA_HOME/private-vm/disk`
  Runtime scratch. Safe to delete with the Lima instance.

- `/nix`:
  Lima named disk `private-nix`, stored under `$LIMA_HOME/_disks/private-nix`.
  Whole `/nix` tree, not just `/nix/store`. This is a persistent cache/state
  volume for Nix store paths, DB, profiles, and GC roots. Recoverable if lost,
  but avoids expensive rebuild/download after instance deletion.

- `/persistence`:
  Lima named disk `private-persistence`, stored under
  `$LIMA_HOME/_disks/private-persistence`. Small system-state volume. Start by
  only formatting/mounting it; bind-mounting specific paths comes after the disk
  lifecycle is proven.

- `/home/${user}`:
  Lima named disk `private-home`, but with its backing `datadisk` symlinked to
  `$HOME/data/private-vm/home.qcow2`. This keeps user data visibly owned by an
  explicit directory while still fitting Lima's named-disk attachment model.

Local Lima 2.1.2 finding: `additionalDisks` accepts named Lima disks, not
arbitrary host file paths. `limactl disk import` copies into
`$LIMA_HOME/_disks/<name>/datadisk`; it does not keep the original file path.
So the home disk needs the symlink approach if the backing file must live under
`~/data/private-vm/`.

## Lima disks

`hosts/private-vm/lima.yaml` should attach:

```yaml
additionalDisks:
  - name: "private-home"
    format: false
  - name: "private-nix"
    format: false
  - name: "private-persistence"
    format: false
```

Host wrapper should ensure these exist before `limactl start`.

## Bootstrap-safe volume lifecycle

`private-vm-unlock` already uses the bootstrap `nixos` SSH channel and does not
require the real user to exist. Keep that property.

Change `private-vm-lock` to use the same `nixos` SSH channel instead of
`private-vm-ssh`, so lock/unlock works before the full system has been applied.

`private-vm-rebuild` should continue to own unlock during convergence:

1. start VM
2. if home disk is LUKS-initialized and not mounted, unlock it
3. push runtime credentials
4. rsync flake
5. run `nixos-rebuild switch`

## Disk discovery inside guest

Do not hardcode `/dev/vdb`, `/dev/vdc`, etc.

Lima's cidata ISO contains the authoritative mapping, even in plain mode:

```text
LIMA_CIDATA_DISK_0_NAME=private-home
LIMA_CIDATA_DISK_0_DEVICE=vdb
```

Current observed VM layout had `vdc` as the `cidata` ISO, so assuming `vdc` is
`private-nix` would be wrong.

Add a guest helper script in the bootstrap closure that:

1. mounts `/dev/disk/by-label/cidata` read-only under `/run/private-vm/cidata`
2. reads `param.env`
3. resolves a Lima disk name to `/dev/$DEVICE`
4. unmounts cidata when done

Use it for `private-home`, `private-nix`, and `private-persistence`.

## `/nix` first-boot seeding

Bootstrap config should declare:

```nix
fileSystems."/nix" = {
  device = "/dev/disk/by-label/private-nix";
  fsType = "ext4";
  neededForBoot = true;
  options = [
    "nofail"
    "x-systemd.device-timeout=1s"
  ];
};
```

First boot with a blank `private-nix` disk:

1. `/dev/disk/by-label/private-nix` does not exist.
2. `nofail` lets boot continue with the bootstrap `/nix` from the root disk.
3. `private-nix-init.service` runs after SSH-capable boot.
4. It resolves the `private-nix` device via Lima cidata.
5. If the disk already has label `private-nix`, exit successfully.
6. If the disk is blank:
   - `mkfs.ext4 -L private-nix "$device"`
   - mount at `/mnt/nix-seed`
   - `rsync -aHAX /nix/ /mnt/nix-seed/`
   - unmount
   - write `/run/private-vm/private-nix-reboot-required`
7. If the disk has any unknown signature, fail loudly and refuse to clobber.

`private-vm-start` should handle the one-time reboot:

1. wait for SSH
2. check for `/run/private-vm/private-nix-reboot-required`
3. if present, run `sudo systemctl reboot`
4. wait for SSH to drop
5. wait for SSH to return

Subsequent boots mount `/nix` from `private-nix` in initrd because the label now
exists. No reseed and no reboot.

Reason for the reboot: mounting the new disk over `/nix` while the running
system is executing paths from rootfs `/nix` is possible with ordering games but
fragile. The one-time reboot is simpler and only happens once per
`private-nix` disk lifetime.

## `/persistence` first pass

Add `private-persistence-init.service`:

1. resolve `private-persistence` via Lima cidata
2. if label `private-persistence` exists, mount it at `/persistence`
3. if blank, `mkfs.ext4 -L private-persistence`, then mount it
4. if unknown signature, fail loudly and refuse to clobber

Do not bind-mount real state in the same pass. After disk lifecycle is proven,
persist candidates are:

- `/etc/machine-id`
- SSH host keys
- `/var/lib/private-vm`
- `/var/lib/nixos`

## Host wrapper checklist

Implement in `modules/nix-dev.nix`:

- constants for `LIMA_HOME`, image out-link, and home disk path
- `private-vm-build` uses stable image out-link, not `~/etc/result`
- `private-vm-start` resolves image from the stable out-link
- host-side ensure function:
  - create `$LIMA_HOME/_config/user{,.pub}` if missing
  - create `$HOME/data/private-vm`
  - ensure `$HOME/data/private-vm/home.qcow2` exists when explicitly requested
    by home init path
  - ensure `$LIMA_HOME/_disks/private-home/datadisk` symlinks to that home image
  - auto-create Lima named disks `private-nix` and `private-persistence`
- `private-vm-start` handles the `/nix` seed reboot marker
- `private-vm-lock` uses bootstrap `nixos` SSH

Be careful with destructive behavior:

- auto-create cache/state disks (`private-nix`, `private-persistence`)
- never delete or overwrite `$HOME/data/private-vm/home.qcow2`
- formatting home remains explicit through `private-vm-init-home`

## Verification

Before deleting old state:

```bash
nix eval --impure .#darwinConfigurations.mac.system --raw
nix eval --impure .#private-vm-image.drvPath
git diff --check
```

After rebuilding host wrappers:

1. create/start fresh under new `LIMA_HOME`
2. verify blank `private-nix` seeds, writes marker, reboots once, then mounts
   `/nix` from the persistent disk
3. verify `/persistence` formats and mounts
4. run `private-vm-keychain-set`
5. run `private-vm-init-home`
6. run `private-vm-rebuild`
7. run `private-vm-rdp`

