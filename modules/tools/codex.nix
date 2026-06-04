{ ... }:
{
  flake.darwinModules.codex =
    { ... }:
    {
      homebrew.casks = [
        "codex"
      ];
    };

  flake.homeManagerModules.codex =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      codexWrapper = pkgs.writeShellScriptBin "codex" ''
        /opt/homebrew/bin/codex --profile local "$@"
      '';
    in
    lib.mkIf pkgs.stdenv.isDarwin {
      home.packages = [ codexWrapper ];

      programs.codex = {
        enable = true;
        package = null;
        enableMcpIntegration = true;
        settings = {
          approval_policy = "never";
          sandbox_mode = "danger-full-access";
          model_reasoning_effort = "medium";
          sqlite_home = "${config.xdg.dataHome}/codex";
          log_dir = "${config.xdg.stateHome}/codex/log";
        };
      };
    };
}
