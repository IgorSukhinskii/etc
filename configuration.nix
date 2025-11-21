{ pkgs, self, ... }:

{
  environment.systemPackages = with pkgs; [
  ];

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      upgrade = true;
    };
    taps = [
      "mhaeuser/mhaeuser"
    ];
    casks = [
      "logi-options+"
      "alt-tab"
      "raycast"
      "bitwarden"
      "battery-toolkit"
    ];
  };

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";
  # Because we are using Determinate Nix
  # nix.enable = false;

  # programs.zsh.enable = true;

  # Set Git commit hash for darwin-version.
  # No idea how to do this with 'self' so commented out
  # system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # Used for Homebrew
  system.primaryUser = "igor.sukhinskii";

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  security.pam.services.sudo_local.touchIdAuth = true;
  # User needs to be declared here because of home-manager (probably)
  users.users."igor.sukhinskii" = {
    name = "igor.sukhinskii";
    home = /Users/igor.sukhinskii;
  };
}
