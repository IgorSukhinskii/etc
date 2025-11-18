{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "igor.sukhinskii";
  home.homeDirectory = /Users/igor.sukhinskii;

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "25.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
  ];

  home.shell.enableZshIntegration = true;

  home.shellAliases = {
    rebuild = "sudo darwin-rebuild switch --flake ~/etc";
    v = "nvim";
  };

  programs.zsh = {
    enable = true;
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "Igor Sukhinskii";
      user.email = "igor.sukhinskii@mirasys.com";
      init.defaultBranch = "main";
    };
  };

  programs.ghostty = {
    enable = true;
    package = pkgs.emptyDirectory; # Ghostty is installed via Homebrew in configuration.nix
    settings = {
      theme = "Gruvbox Dark Hard";
      window-decoration = "none";
    };
  };

  programs.atuin = {
    enable = true;
  };

  programs.yazi = {
    enable = true;
    settings = {
      mgr = {
        show_hidden = true;
        sort_by = "mtime";
        sort_dir_first = true;
        sort_reverse = true;
        ratio = [1 3 4];
      };
    };
  };

  programs.lsd = {
    enable = true;
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
  };

  programs.nix-your-shell = {
    enable = true;
  };

  programs.carapace = {
    enable = true;
  };

  programs.starship = {
    enable = true;
  };

  editorconfig = {
    enable = true;
    settings."*" = {
      charset = "utf-8";
      end_of_line = "lf";
      trim_trailing_whitespace = true;
      insert_final_newline = true;
      max_line_width = 100;
      indent_style = "space";
      indent_size = 2;
    };
  };
}
