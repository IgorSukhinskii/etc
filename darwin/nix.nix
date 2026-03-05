{ config, ... }:
{
  nix.settings.experimental-features = "nix-command flakes";
  nix.settings.trusted-users = [
    "root"
    config.host.username
  ];
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;
  system.stateVersion = 6;
}
