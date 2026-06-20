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

      # Import only the Hammerspoon config files into the store, excluding this
      # module file and editor artefacts. Without the filter, `${hsDir}/...`
      # would coerce the whole directory (including hammerspoon.nix) into a
      # single store path, so editing this file would rehash every linked config
      # source even though their contents are unchanged.
      excludedNames = [
        "hammerspoon.nix"
        ".luarc.json"
      ];

      hsDir = builtins.path {
        path = ./.;
        name = "hammerspoon-config";
        filter = path: _type: !builtins.elem (baseNameOf path) excludedNames;
      };

      # Recursively collect all regular files under `dir` as paths relative to `base`.
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

      sourceFiles = allFiles hsDir "";
    in
    {
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
