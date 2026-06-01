{ ... }:
{
  flake.homeManagerModules.shell =
    { config, ... }:
    {
      xdg.enable = true;

      home.shell.enableZshIntegration = true;

      home.shellAliases = {
        v = "nvim";
        iosevka-build = "bash ${config.home.homeDirectory}/etc/iosevka/build.sh";
        iosevka-setup = "bash ${config.home.homeDirectory}/etc/iosevka/setup.sh";
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
        enableZshIntegration = false;
      };

      programs.zsh.initContent = ''
        eval "$(nix-your-shell zsh)"
      '';

      programs.fzf = {
        enable = true;
        defaultOptions = [ "--color 16" ];
      };

      programs.vivid = {
        enable = true;
        enableZshIntegration = true;
        activeTheme = "ansi";
        themes.ansi = builtins.fetchurl {
          url = "https://raw.githubusercontent.com/sharkdp/vivid/master/themes/ansi.yml";
          sha256 = "1gv9xmdgn2pw64z4gbw02nv634lxkl0wwzv72mc717b1aw4qwcwq";
        };
      };
    };
}
