{ ... }:
{
  flake.homeManagerModules.tools =
    { pkgs, ... }:
    {
      programs.bat = {
        enable = true;
      };

      programs.lsd = {
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

      programs.ripgrep.enable = true;

      home.packages = with pkgs; [
        fd
        qmk
        telegram-desktop
        brave
      ];
    };
}
