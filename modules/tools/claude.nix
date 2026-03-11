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
    { pkgs, ... }:
    let
      claudeWrapper = pkgs.writeShellScriptBin "claude" ''
        export DISABLE_AUTOUPDATER=1
        if [ -n "$TMUX" ]; then
          # let tmux know that claude accepts extended keys
          printf '\033[>4;2m'
          # on exit, let tmux know that we no longer accept extkeys
          trap 'printf "\033[>4;0m"' EXIT
        fi
        /opt/homebrew/bin/claude "$@"
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
    };
}
