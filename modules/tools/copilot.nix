{ ... }:
{
  flake.darwinModules.copilot =
    { ... }:
    {
      homebrew.casks = [
        "copilot-cli"
      ];
    };
  flake.homeManagerModules.copilot =
    { pkgs, ... }:
    let
      copilotWrapper = pkgs.writeShellScriptBin "copilot" ''
        /opt/homebrew/bin/copilot "$@"
      '';
    in
    {
      home.packages = [ copilotWrapper ];
    };
}
