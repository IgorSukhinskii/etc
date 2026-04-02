{ ... }:
{
  flake.homeManagerModules.shell =
    { config, ... }:
    {
      xdg.enable = true;

      home.shell.enableZshIntegration = true;

      home.shellAliases = {
        v = "nvim";
      };

      programs.zsh = {
        enable = true;
        dotDir = "${config.xdg.configHome}/zsh";
        sessionVariables = {
          EDITOR = "nvim";
          VISUAL = "nvim";
          CARGO_HOME = "${config.xdg.dataHome}/cargo";
          BUN_INSTALL = "${config.xdg.dataHome}/bun";
          NPM_CONFIG_CACHE = "${config.xdg.cacheHome}/npm";
          NPM_CONFIG_PREFIX = "${config.xdg.dataHome}/npm";
          DOCKER_CONFIG = "${config.xdg.configHome}/docker";
          AZURE_CONFIG_DIR = "${config.xdg.configHome}/azure";
          GEM_HOME = "${config.xdg.dataHome}/gem";
          GEM_SPEC_CACHE = "${config.xdg.cacheHome}/gem";
        };
      };

      programs.starship = {
        enable = true;
      };

      programs.atuin = {
        enable = true;
      };

      programs.carapace = {
        enable = true;
      };

      programs.nix-your-shell = {
        enable = true;
      };

      programs.fzf = {
        enable = true;
        defaultOptions = [ "--color 16" ];
      };
    };
}
