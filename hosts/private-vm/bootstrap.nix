{ lib, pkgs, ... }:
let
  # Lima's per-host agent pubkey — the one impure read. Lima generates this on
  # first `limactl` use; it's the hypervisor's bootstrap identity, not personal.
  limaHomeEnv = builtins.getEnv "LIMA_HOME";
  limaHome = if limaHomeEnv != "" then limaHomeEnv else builtins.getEnv "HOME" + "/.lima";
  limaPubkey = limaHome + "/_config/user.pub";
  privateVmDiskDevice = pkgs.writeShellScriptBin "private-vm-disk-device" ''
    set -euo pipefail

    name="''${1:?usage: private-vm-disk-device <lima-disk-name>}"
    cidata=/run/private-vm/cidata
    mounted=0

    mkdir -p "$cidata"
    if ! mountpoint -q "$cidata"; then
      mount -o ro /dev/disk/by-label/cidata "$cidata"
      mounted=1
    fi

    cleanup() {
      if [[ "$mounted" == 1 ]]; then
        umount "$cidata"
      fi
    }
    trap cleanup EXIT

    param="$cidata/lima.env"
    if ! grep -q '^LIMA_CIDATA_DISKS=' "$param" 2>/dev/null; then
      param="$cidata/param.env"
    fi
    if [[ ! -r "$param" ]]; then
      echo "cidata param.env not readable at $param" >&2
      exit 1
    fi

    idx=$(
      awk -F= -v name="$name" '
        $1 ~ /^LIMA_CIDATA_DISK_[0-9]+_NAME$/ && $2 == name {
          sub(/^LIMA_CIDATA_DISK_/, "", $1)
          sub(/_NAME$/, "", $1)
          print $1
          exit
        }
      ' "$param"
    )
    if [[ -z "$idx" ]]; then
      echo "Lima disk not found in cidata: $name" >&2
      exit 1
    fi

    device=$(
      awk -F= -v key="LIMA_CIDATA_DISK_''${idx}_DEVICE" '
        $1 == key { print $2; exit }
      ' "$param"
    )
    if [[ -z "$device" ]]; then
      echo "Lima disk $name has no DEVICE entry in cidata" >&2
      exit 1
    fi

    device="''${device#/dev/}"
    printf '/dev/%s\n' "$device"
  '';
in
{
  # Image-only profile. Boots, accepts SSH from Lima, runs nixos-rebuild
  # against the in-repo flake. Stays small (~2GB closure).
  services.openssh.enable = true;

  # Bootstrap user is generic "nixos" — not the host owner. This is the
  # hypervisor's ops account: SSH-only, used by private-vm-rebuild. The
  # user-facing user (host.username from vars.nix) is created by full.nix
  # and only exists for RDP/desktop sessions. Both coexist after the rebuild.
  # uid pinned at 1000 to match what NixOS's dynamic allocator would have
  # given it anyway (first normal user). Pinning makes the layout explicit so
  # the real user (see full.nix) can pin its own uid right after without
  # colliding with whichever order the allocator happens to walk in.
  users.users.nixos = {
    isNormalUser = true;
    uid = 1000;
    home = "/home/nixos";
    extraGroups = [ "wheel" ];
    shell = pkgs.bash;
    # The actual Lima pubkey is read by sshd from /var/lib/private-vm/lima.pub
    # at connection time (see services.openssh.authorizedKeysFiles below) —
    # NOT via this declarative `keys` list, because the in-VM rebuild can't
    # do the host-side --impure read and would otherwise wipe the entry.
    # We only keep `authorizedKeys.keys` populated AT IMAGE BUILD so the very
    # first SSH (before private-vm-rebuild has had a chance to push lima.pub)
    # still works. After the first rebuild, sshd uses /var/lib/private-vm/lima.pub.
    openssh.authorizedKeys.keys = lib.optionals (builtins.pathExists limaPubkey) [
      (lib.removeSuffix "\n" (builtins.readFile limaPubkey))
    ];
    # See [[nixos-sshd-locked-account]] memory: accounts with null password
    # are `!`-locked in shadow and PAM rejects them even on pubkey auth.
    # The value is never used — PasswordAuthentication=false at the sshd
    # level blocks any password-based login.
    initialPassword = "bootstrap";
  };

  # Runtime sshd_config paths sshd will check on every connection. The
  # `lima.pub` path is pushed by private-vm-rebuild before each switch, so
  # it survives the activation that would otherwise drop authorized_keys.d
  # entries. The per-user `%u.pub` covers the real user (igor.pub).
  services.openssh.authorizedKeysFiles = [
    ".ssh/authorized_keys"
    "/etc/ssh/authorized_keys.d/%u"
    "/var/lib/private-vm/lima.pub"
    "/var/lib/private-vm/%u.pub"
  ];

  nix.settings.experimental-features = "nix-command flakes";
  nix.settings.trusted-users = [
    "root"
    "nixos"
  ];
  nixpkgs.config.allowUnfree = true;

  # Filesystem + bootloader for the running VM. These match what the qemu-efi
  # image profile (nixpkgs/nixos/modules/virtualisation/disk-image.nix) writes
  # at image build time — kept here as `mkDefault` so:
  #   - Image build: disk-image.nix's plain defs override our mkDefault (same values).
  #   - In-VM `nixos-rebuild switch`: only our mkDefault applies — disk-image.nix
  #     isn't loaded outside the image build path.
  # Without these, the rebuild fails the "fileSystems / boot.loader" assertions.
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };
  fileSystems."/boot" = lib.mkDefault {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.grub.enable = lib.mkDefault false;
  boot.growPartition = lib.mkDefault true;

  systemd.services.private-nix-init = {
    description = "Mount or seed the persistent private-vm /nix volume";
    wantedBy = [ "sysinit.target" ];
    before = [
      "local-fs.target"
      "sshd.service"
    ];
    after = [
      "systemd-udev-settle.service"
    ];
    wants = [
      "systemd-udev-settle.service"
    ];
    path = with pkgs; [
      coreutils
      e2fsprogs
      gawk
      rsync
      util-linux
      privateVmDiskDevice
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      DefaultDependencies = false;
    };
    script = ''
      set -euo pipefail

      mkdir -p /nix
      if label_device=$(blkid -L private-nix 2>/dev/null); then
        if ! mountpoint -q /nix; then
          mount "$label_device" /nix
        fi
        exit 0
      fi

      device=$(private-vm-disk-device private-nix)
      if wipefs -n "$device" | grep -q .; then
        echo "$device has an unknown signature; refusing to format private-nix" >&2
        exit 1
      fi

      mkfs.ext4 -F -L private-nix "$device"
      mkdir -p /mnt/nix-seed
      mount "$device" /mnt/nix-seed
      rsync -aHAX --numeric-ids /nix/ /mnt/nix-seed/
      umount /mnt/nix-seed
      touch /run/private-vm/private-nix-reboot-required
    '';
  };

  systemd.services.private-persistence-init = {
    description = "Format and mount the private-vm persistence volume";
    wantedBy = [ "multi-user.target" ];
    after = [
      "local-fs.target"
      "private-nix-init.service"
    ];
    path = with pkgs; [
      coreutils
      e2fsprogs
      gawk
      util-linux
      privateVmDiskDevice
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      mkdir -p /persistence
      if mountpoint -q /persistence; then
        exit 0
      fi

      if label_device=$(blkid -L private-persist 2>/dev/null || blkid -L private-persiste 2>/dev/null); then
        mount "$label_device" /persistence
        exit 0
      fi

      device=$(private-vm-disk-device private-persistence)
      if wipefs -n "$device" | grep -q .; then
        echo "$device has an unknown signature; refusing to format private-persistence" >&2
        exit 1
      fi

      mkfs.ext4 -F -L private-persist "$device"
      mount "$device" /persistence
    '';
  };

  environment.systemPackages = with pkgs; [
    git
    privateVmDiskDevice
    rsync
  ];
}
