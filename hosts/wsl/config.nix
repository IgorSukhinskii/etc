let
  username = "igor";
  homeDirectory = /home/igor;
  stateVersion = "25.05";
in
{ lib, pkgs, ... }:
{
  options.host = {
    username = lib.mkOption { type = lib.types.str; };
    homeDirectory = lib.mkOption { type = lib.types.path; };
    stateVersion = lib.mkOption { type = lib.types.str; };
  };

  config = {
    host = { inherit username homeDirectory stateVersion; };

    # WSL
    wsl.enable = true;
    wsl.defaultUser = username;
    wsl.nativeSystemd = true;
    wsl.interop.register = true;
    wsl.interop.includePath = true;
    wsl.wslConf.automount.options = "metadata,uid=1000,gid=100,umask=22,fmask=11";

    # Docker daemon (no colima needed on Linux)
    virtualisation.docker.enable = true;

    # Enable zsh system-wide so it appears in /etc/shells
    programs.zsh.enable = true;

    users.users.${username} = {
      extraGroups = [ "docker" ];
      shell = pkgs.zsh;
    };

    # Allow unpatched ELF binaries (ad-hoc downloaded CLIs)
    programs.nix-ld.enable = true;

    system.stateVersion = stateVersion;

    home-manager.users.${username} = {
      home.stateVersion = stateVersion;
      programs.home-manager.enable = true;
    };
  };
}
