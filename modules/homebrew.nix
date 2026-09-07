{ ... }:
{
  flake.darwinModules.homebrew =
    { ... }:
    {
      homebrew = {
        enable = true;
        onActivation = {
          autoUpdate = false;
          # DANGER: `zap`, unlike `uninstall`, runs each removed cask's zap stanza,
          # which deletes *user data*, not just the app. Removing `claude-code`
          # from the list below once wiped ~/.claude, ~/.claude.json and all of
          # ~/.config/claude (project histories, history.jsonl, memory/) in a
          # single activation -- recoverable only because brew trashes instead of
          # unlinking. Before deleting any cask from `casks`, read its zap stanza
          # (`brew info --cask <name>`) and back up anything it lists.
          #
          # This also collides with the hand-installed j-x-z/tap formulae that the
          # private-vm GUI needs (cocoa-way, waypipe-darwin): every activation
          # tries to remove them and is saved only by brew's dependency check.
          cleanup = "zap";
          extraFlags = [ "--force" ];
          upgrade = false;
        };
        casks = [
          "alt-tab"
          "raycast"
          "bitwarden"
          "qmk-toolbox"
          "vial"
          "figma"
          "windows-app"
          "steam"
          "spotify"
          "t3-code"
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
    {
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
