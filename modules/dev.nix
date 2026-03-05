{ ... }:
{
  flake.homeManagerModules.dev = { pkgs, ... }: {
    programs.git = {
      enable = true;
      settings = {
        user.name = "Igor Sukhinskii";
        user.email = "igor.sukhinskii@mirasys.com";
        init.defaultBranch = "main";
      };
    };

    programs.direnv = {
      enable = true;
      silent = true;
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

    home.packages = with pkgs; [
      colima
      docker
      devenv
      nixd
      nixfmt
      difftastic
    ];
  };
}
