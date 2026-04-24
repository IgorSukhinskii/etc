{ ... }:
{
  flake.homeManagerModules.tools =
    { pkgs, lib, ... }:
    {
      programs.bat.enable = true;

      programs.fd.enable = true;

      programs.gh = {
        enable = true;
        settings.git_protocol = "ssh";
      };

      programs.lsd = {
        enable = true;
        colors = {
          user = "white";
          group = "yellow";
          permission = {
            read = "dark_green";
            write = "dark_yellow";
            exec = "dark_red";
            exec-sticky = "dark_magenta";
            no-access = "dark_grey";
            octal = "dark_cyan";
            acl = "dark_cyan";
            context = "cyan";
          };
          attributes = {
            archive = "dark_green";
            read = "dark_yellow";
            hidden = "magenta";
            system = "magenta";
          };
          date = {
            hour-old = "green";
            day-old = "green";
            older = "dark_cyan";
          };
          size = {
            none = "dark_grey";
            small = "yellow";
            medium = "dark_yellow";
            large = "red";
          };
          inode = {
            valid = "magenta";
            invalid = "dark_grey";
          };
          links = {
            valid = "magenta";
            invalid = "dark_grey";
          };
          tree-edge = "dark_grey";
          git-status = {
            default = "dark_grey";
            unmodified = "dark_grey";
            ignored = "dark_grey";
            new-in-index = "dark_green";
            new-in-workdir = "dark_green";
            typechange = "dark_yellow";
            deleted = "dark_red";
            renamed = "dark_green";
            modified = "dark_yellow";
            conflicted = "dark_red";
          };
        };
      };

      programs.yazi = {
        enable = true;
        shellWrapperName = "yy";
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

      programs.ripgrep.enable = true;

      home.packages =
        with pkgs;
        [ ]
        ++ lib.optionals stdenv.isDarwin [
          qmk
          telegram-desktop
          brave
        ];
    };
}
