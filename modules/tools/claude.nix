{ ... }:
{
  flake.darwinModules.claude =
    { ... }:
    {
      homebrew.casks = [
        "claude-code"
      ];
    };
  flake.homeManagerModules.claude =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      claudeBin =
        if pkgs.stdenv.isDarwin then "/opt/homebrew/bin/claude" else "${pkgs.claude-code}/bin/claude";

      # Our declarative settings live as hand-authored JSON in the repo and are
      # loaded via `--settings`, which claude treats as the `flagSettings` layer:
      # higher priority than the writable `userSettings` (~/.config/claude/
      # settings.json), and claude *refuses to write to it* (it throws on that
      # source). So the repo file is the source of truth (it overrides anything
      # claude persists), while claude's own settings.json stays unmanaged and
      # writable — its runtime writes (/tui, /model, theme, onboarding state, …)
      # no longer hit a read-only /nix/store symlink (the original EACCES).
      #
      # We point --settings straight at the live working-copy file (not a store
      # copy), so edits to it take effect on the next `claude` launch with no
      # rebuild. Only the path is baked in; the content is read fresh at runtime.
      settingsFile = "${config.local.flakeDir}/configs/claude/settings.json";

      claudeWrapper = pkgs.writeShellScriptBin "claude" ''
        export DISABLE_AUTOUPDATER=1
        if [ -n "$TMUX" ]; then
          # let tmux know that claude accepts extended keys
          printf '\033[>4;2m'
          # on exit, let tmux know that we no longer accept extkeys
          trap 'printf "\033[>4;0m"' EXIT
        fi
        ${claudeBin} --dangerously-skip-permissions --settings "${settingsFile}" "$@"
      '';
      askClaude = pkgs.writeShellScriptBin "ask-claude" ''
        if [ $# -eq 0 ]; then
          echo "Usage: ?? <question>" >&2
          exit 1
        fi
        claude -p "$*"
      '';
    in
    {
      home.packages = [
        claudeWrapper
        askClaude
      ];
      home.shellAliases."??" = "ask-claude";

      # No `settings` here: writing it would materialize a read-only settings.json
      # symlink into /nix/store, which is exactly what caused the EACCES on
      # claude's runtime writes. Declarative settings live in the repo JSON loaded
      # via `--settings` (see the settingsFile comment above); ~/.config/claude/
      # settings.json is left unmanaged so claude can write it freely.
      programs.claude-code = {
        enable = true;
        package = null;
        configDir = "${config.xdg.configHome}/claude";
      };
    };
}
