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
          qemu = inputs.nixpkgs-stable.legacyPackages.${prev.stdenv.hostPlatform.system}.qemu;
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
        # ephemeral: wipe qcow2 on every start. Combined with the launchd
        # overrides below this means the builder VM only exists while a
        # host-side aarch64-linux build is in progress (currently just
        # `vm build`). Trade-off: every build pays cold-cache startup; in
        # return the builder consumes ~0 RAM and ~0 disk at rest.
        ephemeral = true;
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

      # On-demand builder. Upstream module hardcodes RunAtLoad + KeepAlive
      # which keeps the qemu process resident 24/7. Flip both off so the
      # daemon is loaded (nix knows the buildMachine exists) but dormant;
      # `vm build` wraps `launchctl kickstart` around the actual build.
      launchd.daemons.linux-builder.serviceConfig = {
        RunAtLoad = pkgs.lib.mkForce false;
        KeepAlive = pkgs.lib.mkForce false;
      };

      # Let the host user start/stop the builder without a password prompt
      # so wrappers like `vm build` can do it transparently. Scope is the
      # two exact launchctl invocations — does not widen sudo beyond that.
      security.sudo.extraConfig = ''
        ${config.host.username} ALL=(root) NOPASSWD: /bin/launchctl kickstart system/org.nixos.linux-builder
        ${config.host.username} ALL=(root) NOPASSWD: /bin/launchctl kill TERM system/org.nixos.linux-builder
      '';

      nixpkgs.hostPlatform = "aarch64-darwin";
      nixpkgs.config.allowUnfree = true;
      system.stateVersion = 6;
    };
}
