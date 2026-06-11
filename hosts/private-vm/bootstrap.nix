{ lib, pkgs, ... }:
let
  # Lima's per-host agent pubkey — the one impure read. Lima generates this on
  # first `limactl` use; it's the hypervisor's bootstrap identity, not personal.
  limaHomeEnv = builtins.getEnv "LIMA_HOME";
  limaHome = if limaHomeEnv != "" then limaHomeEnv else builtins.getEnv "HOME" + "/.lima";
  limaPubkey = limaHome + "/_config/user.pub";
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

  environment.systemPackages = with pkgs; [
    git
    rsync
  ];
}
