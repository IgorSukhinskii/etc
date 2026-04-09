{ ... }:
{
  flake.darwinModules.mac =
    { config, ... }:
    {
      system.primaryUser = config.host.username;

      system.defaults.screencapture.location = "~/Pictures";

      system.defaults.dock = {
        autohide = true;
        autohide-delay = 0.0;
        launchanim = false;
        mru-spaces = false;
        orientation = "right";
        persistent-apps = [ ];
        persistent-others = [ ];
        show-recents = false;
        static-only = true;
        wvous-bl-corner = 1;
        wvous-br-corner = 1;
        wvous-tl-corner = 1;
        wvous-tr-corner = 1;
      };

      system.defaults.finder = {
        QuitMenuItem = true;
        CreateDesktop = false;
      };

      system.defaults.hitoolbox.AppleFnUsageType = "Do Nothing";

      system.defaults.NSGlobalDomain = {
        AppleICUForce24HourTime = true;
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
        # ctrl↔fn swap handled by kanata (avoids hidutil double-processing kanata's virtual output)
      };

      networking.hostName = "mac";

      security.pam.services.sudo_local = {
        touchIdAuth = true;
        reattach = true;
      };
    };
}
