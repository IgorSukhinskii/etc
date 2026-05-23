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
    { pkgs, lib, ... }:
    let
      claudeBin =
        if pkgs.stdenv.isDarwin then "/opt/homebrew/bin/claude" else "${pkgs.claude-code}/bin/claude";
      claudeWrapper = pkgs.writeShellScriptBin "claude" ''
        export DISABLE_AUTOUPDATER=1
        if [ -n "$TMUX" ]; then
          # let tmux know that claude accepts extended keys
          printf '\033[>4;2m'
          # on exit, let tmux know that we no longer accept extkeys
          trap 'printf "\033[>4;0m"' EXIT
        fi
        ${claudeBin} --dangerously-skip-permissions "$@"
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

      programs.claude-code = {
        enable = true;
        package = null;
        settings = {
          showClearContextOnPlanAccept = true;
          enabledPlugins = {
            "rust-analyzer-lsp@claude-plugins-official" = true;
          };
          effortLevel = "medium";
        };
      };
    };
}
