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

  # MacOS Settings
  system.defaults.screencapture.location = "~/Pictures";
  # Get as close to disabling Dock as possible
  system.defaults.dock = {
    autohide = true;
    autohide-delay = 0.0;
    launchanim = false;
    mru-spaces = false;
    orientation = "right";
    persistent-apps = [];
    persistent-others = [];
    show-recents = false;
    static-only = true;
    wvous-bl-corner = 1;
    wvous-br-corner = 1;
    wvous-tl-corner = 1;
    wvous-tr-corner = 1;
  };
  system.defaults.finder = {
    QuitMenuItem = true;
    CreateDesktop = true;
  };
  system.defaults.hitoolbox.AppleFnUsageType = "Do Nothing";
  system.defaults.NSGlobalDomain = {
    "com.apple.keyboard.fnState" = true;
    # _HIHideMenuBar = true;
    AppleICUForce24HourTime = true;
    AppleInterfaceStyle = "Dark";
    AppleInterfaceStyleSwitchesAutomatically = false;
    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticDashSubstitutionEnabled = false;
    NSAutomaticInlinePredictionEnabled = false;
    NSAutomaticPeriodSubstitutionEnabled = false;
    NSAutomaticQuoteSubstitutionEnabled = false;
    NSAutomaticSpellingCorrectionEnabled = false;
    NSAutomaticWindowAnimationsEnabled = false;
    NSDocumentSaveNewDocumentsToCloud = false;
    NSUseAnimatedFocusRing = false;
    NSWindowResizeTime = 0.0;
  };
  system.defaults.WindowManager = {
    EnableStandardClickToShowDesktop = false;
    StandardHideWidgets = true;
    StandardHideDesktopIcons = true;
  };
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToEscape = true;
    swapLeftCtrlAndFn = true;
  };

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
