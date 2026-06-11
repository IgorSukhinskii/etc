{ inputs, ... }:
{
  flake.darwinModules.nix =
    { config, pkgs, ... }:
    {
      # qemu 11.0.0 on nixpkgs-unstable aborts on macOS 26 with an HVF
      # SMCR_EL1 assertion (nixpkgs #528299, qemu-project/qemu#3533), which
      # crashes the linux-builder VM at boot. Pin qemu to the nixos-26.05
      # stable channel (qemu 10.2.2) until the upstream fix lands on
      # nixpkgs-unstable, then remove this overlay + the nixpkgs-stable input.
      nixpkgs.overlays = [
        (final: prev: {
          qemu = inputs.nixpkgs-stable.legacyPackages.${prev.system}.qemu;
        })
      ];

      nix.settings.allow-import-from-derivation = true;
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      nix.settings.trusted-users = [
        "root"
        config.host.username
      ];
      nix.settings.substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      nix.settings.trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSeBs="
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

      nix.linux-builder = {
        enable = true;
        ephemeral = false;
        maxJobs = 4;
        config = {
          virtualisation = {
            darwin-builder = {
              diskSize = 120 * 1024;
              memorySize = 12 * 1024;
            };
            cores = 6;
          };
        };
      };

      nixpkgs.hostPlatform = "aarch64-darwin";
      nixpkgs.config.allowUnfree = true;
      system.stateVersion = 6;
    };
}
