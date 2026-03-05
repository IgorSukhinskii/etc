{ config, ... }:
{
  nix.settings.experimental-features = "nix-command flakes";
  nix.settings.trusted-users = [
    "root"
    config.host.username
  ];
  nixpkgs.config.allowUnfree = true;
}
