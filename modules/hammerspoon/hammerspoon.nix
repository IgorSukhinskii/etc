{ ... }:
{
  # ── darwin: set XDG config path (avoids ~/.hammerspoon/) ─────────────────
  flake.darwinModules.hammerspoon =
    { ... }:
    {
      homebrew.casks = [ "hammerspoon" ];
      system.defaults.CustomUserPreferences."org.hammerspoon.Hammerspoon" = {
        MJConfigFile = "~/.config/hammerspoon/init.lua";
      };
    };

  # ── home-manager: generate init.lua with theme palettes ──────────────────
  flake.homeManagerModules.hammerspoon =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      dark = config.themes.palette.dark;
      light = config.themes.palette.light;
      # Keys are base16/24 identifiers (e.g. base00) — always valid Lua identifiers
      # Render one palette attrset as a Lua table body: key = "#hex", ...
      luaPalette =
        colors: lib.concatStringsSep ", " (lib.mapAttrsToList (name: hex: ''${name} = "#${hex}"'') colors);
    in
    lib.mkIf pkgs.stdenv.isDarwin {
      home.file = {
        ".config/hammerspoon/init.lua".source = ./init.lua;
        ".config/hammerspoon/launcher.html".source = ./launcher.html;
        ".config/hammerspoon/launcher.css".source = ./launcher.css;
        ".config/hammerspoon/launcher.js".source = ./launcher.js;
        ".config/hammerspoon/theme.css".source = ./theme.css;
        ".config/hammerspoon/palette.lua".text = /* lua */ ''
          return {
            dark  = { ${luaPalette dark} },
            light = { ${luaPalette light} },
          }
        '';
      };

      home.activation.reloadHammerspoon = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        /usr/bin/open -g hammerspoon://reload
      '';
    };
}
