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

  # ── home-manager: link config files + generate palette ───────────────────
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

      hsDir = ./.;

      # Recursively collect all regular files under `dir` as paths relative to `base`.
      # Excludes `hammerspoon.nix` and `.luarc.json` (Nix/editor artefacts, not HS config).
      allFiles =
        dir: prefix:
        lib.concatLists (
          lib.mapAttrsToList (
            name: type:
            if type == "regular" then
              [ "${prefix}${name}" ]
            else if type == "directory" then
              allFiles "${dir}/${name}" "${prefix}${name}/"
            else
              [ ]
          ) (builtins.readDir dir)
        );

      excluded = [
        "hammerspoon.nix"
        ".luarc.json"
      ];

      sourceFiles = builtins.filter (f: !builtins.elem f excluded) (allFiles hsDir "");
    in
    lib.mkIf pkgs.stdenv.isDarwin {
      home.file =
        lib.listToAttrs (
          map (relPath: {
            name = ".config/hammerspoon/${relPath}";
            value = {
              source = "${hsDir}/${relPath}";
            };
          }) sourceFiles
        )
        // {
          ".config/hammerspoon/palette.lua".text = # lua
            ''
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
