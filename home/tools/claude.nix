{ pkgs, ... }:
let
  claudeWrapper = pkgs.writeShellScriptBin "claude" ''
    export DISABLE_AUTOUPDATER=1
    exec /opt/homebrew/bin/claude "$@"
  '';
in
{
  home.packages = [ claudeWrapper ];
}
