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
    wsl.interop.enabled = true;
    wsl.interop.includePath = true;
    wsl.wslConf.automount.options = "metadata,uid=1000,gid=100,umask=22,fmask=11";

    # Docker daemon (no colima needed on Linux)
    virtualisation.docker.enable = true;
    users.users.${username}.extraGroups = [ "docker" ];

    # Enable zsh system-wide so it appears in /etc/shells
    programs.zsh.enable = true;
    users.users.${username}.shell = pkgs.zsh;

    # Allow unpatched ELF binaries (ad-hoc downloaded CLIs)
    programs.nix-ld.enable = true;

    home-manager.users.${username} = {
      home.username = username;
      home.homeDirectory = homeDirectory;
      home.stateVersion = stateVersion;
      programs.home-manager.enable = true;
    };
  };
}
