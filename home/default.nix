{ config, pkgs, ... }:
let
  jiraBin = "${pkgs.jira-cli-go}/bin/jira";
  jiraWrapper = pkgs.writeShellScriptBin "jira" ''
    set -euo pipefail
    token="$(security find-generic-password -a "$USER" -s jira-api-token -w 2>/dev/null)" || {
      echo "Keychain item 'jira-api-token' not found" >&2
      exit 1
    }
    exec env \
      JIRA_AUTH_TYPE="basic" \
      JIRA_API_TOKEN="$token" \
      "${jiraBin}" "$@"
  '';
in
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
    colima
    docker
    qmk
    jiraWrapper
    ollama
    telegram-desktop
    brave
    nixd
    nixfmt
    difftastic
    ripgrep
    fd
  ];

  home.shell.enableZshIntegration = true;

  home.shellAliases = {
    rebuild = "sudo darwin-rebuild switch --flake ~/etc";
    v = "nvim";
  };

  programs.zsh = {
    enable = true;
    sessionVariables = {
      EDITOR = "nvim";
    };
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
    package = pkgs.ghostty-bin;
    settings = {
      macos-titlebar-style = "hidden";
      background-opacity = 0.9;
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
        ratio = [
          1
          3
          4
        ];
      };
    };
    initLua = /* lua */ ''
      require("auto-layout").setup({
        breakpoint_large = 80,  -- new large window threshold, defaults to 100
        breakpoint_medium = 50,  -- new medium window threshold, defaults to 50
      })
    '';
    plugins = {
      auto-layout = pkgs.fetchFromGitHub {
        owner = "luccahuguet";
        repo = "auto-layout.yazi";
        rev = "e24bee9f6dd15ff80eae1b3dc1a6b06ee7e66121";
        hash = "sha256-4vRIGU/ArXhW9ervhyNhpfDN7UF4pqVYnxi6FExlgGk=";
      };
    };
  };

  programs.lsd = {
    enable = true;
  };

  programs.nvf = import ./vim;

  programs.zellij = import ./zellij;

  programs.nix-your-shell = {
    enable = true;
  };

  programs.carapace = {
    enable = true;
  };

  programs.starship = {
    enable = true;
  };

  programs.lazygit = {
    enable = true;
    settings = {
      git = {
        pagers = [ { externalDiffCommand = "difft --color=always"; } ];
      };
    };
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
