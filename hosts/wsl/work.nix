# The workspace (~/w) lives on the XFS work disk at /work, for reflink copies
# (copy-on-write trees). WSL can't attach a VHD from inside, so setup-igor's
# Windows task `\remote-workspace\wsl-work-volume` attaches and mounts it at
# logon; this unit asks for it again whenever WSL boots without it.
#
# Fail closed: the ext4 directory under the mount point is empty and immutable
# (`chattr +i`, set once by hand), so without the disk ~/w refuses writes
# instead of filling the Linux root.
{ config, pkgs, ... }:
let
  home = toString config.host.homeDirectory;
  schtasks = "/mnt/c/Windows/System32/schtasks.exe";
in
{
  systemd.services.work-volume = {
    description = "XFS work disk at /work (asks Windows to attach it)";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    path = [
      pkgs.util-linux
      pkgs.coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 200;
    };
    script = ''
      mountpoint -q /work && exit 0
      ${schtasks} /Run /TN '\remote-workspace\wsl-work-volume' || true
      for _ in $(seq 1 180); do
        mountpoint -q /work && exit 0
        sleep 1
      done
      echo "/work did not appear: ${home}/w stays unavailable" >&2
      exit 1
    '';
  };

  systemd.mounts = [
    {
      what = "/work/w";
      where = "${home}/w";
      type = "none";
      options = "bind";
      wantedBy = [ "multi-user.target" ];
      requires = [ "work-volume.service" ];
      after = [ "work-volume.service" ];
      unitConfig.DefaultDependencies = false;
      before = [ "umount.target" ];
      conflicts = [ "umount.target" ];
    }
  ];
}
