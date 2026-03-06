{ ... }:
{
  flake.darwinModules.nix =
    { config, ... }:
    {
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      nix.settings.trusted-users = [
        "root"
        config.host.username
      ];
      nix.gc = {
        automatic = true;
        interval = {
          Hour = 9;
          Minute = 25;
          Weekday = 5;
        };
        options = "--delete-older-than 30d";
      };
      nix.optimise.automatic = true;
      nixpkgs.hostPlatform = "aarch64-darwin";
      nixpkgs.config.allowUnfree = true;
      system.stateVersion = 6;
    };
}
