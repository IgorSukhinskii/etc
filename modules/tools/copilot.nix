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
    { pkgs, lib, ... }:
    let
      copilotWrapper = pkgs.writeShellScriptBin "copilot" ''
        /opt/homebrew/bin/copilot "$@"
      '';
    in
    lib.mkIf pkgs.stdenv.isDarwin {
      home.packages = [ copilotWrapper ];
    };
}
