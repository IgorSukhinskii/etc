{ ... }:
{
  flake.homeManagerModules.dev =
    { pkgs, ... }:
    {
      programs.git = {
        enable = true;
        settings = {
          user.name = "Igor Sukhinskii";
          user.email = "igor.sukhinskii@gmail.com";
          init.defaultBranch = "main";
        };
        includes = [
          {
            condition = "hasconfig:remote.*.url:*visualstudio.com*/**";
            contents.user.email = "igor.sukhinskii@mirasys.com";
          }
          {
            condition = "hasconfig:remote.*.url:*dev.azure.com*/**";
            contents.user.email = "igor.sukhinskii@mirasys.com";
          }
        ];
      };

      programs.delta = {
        enable = true;
        enableGitIntegration = true;
        options.syntax-theme = "base16-stylix";
      };

      programs.direnv = {
        enable = true;
        silent = true;
      };

      programs.lazygit = {
        enable = true;
        enableZshIntegration = false;
        settings = {
          git.pagers = [
            {
              colorArg = "always";
              pager = "delta --paging=never";
            }
          ];
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
      ];
    };
}
