{ ... }:
{
  flake.darwinModules.homebrew =
    { ... }:
    {
      homebrew = {
        enable = true;
        onActivation = {
          autoUpdate = false;
          cleanup = "zap";
          upgrade = false;
        };
        taps = [ "mhaeuser/mhaeuser" ];
        casks = [
          "alt-tab"
          "raycast"
          "bitwarden"
          "battery-toolkit"
          "qmk-toolbox"
          "vial"
          "figma"
        ];
      };
    };

  flake.homeManagerModules.homebrew =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      script = pkgs.writeShellScript "brew-cask-update" ''
        set -e
        /opt/homebrew/bin/brew update
        /opt/homebrew/bin/brew upgrade --cask
        /opt/homebrew/bin/brew cleanup
      '';
    in
    lib.mkIf pkgs.stdenv.isDarwin {
      launchd.agents.brew-cask-update = {
        enable = true;
        config = {
          Label = "local.brew-cask-update";
          ProgramArguments = [ "${script}" ];
          StartCalendarInterval = [
            {
              Hour = 9;
              Minute = 20;
            }
          ];
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/brew-cask-update.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/brew-cask-update.error.log";
        };
      };
    };
}
