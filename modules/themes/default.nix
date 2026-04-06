{ inputs, ... }:
{
  flake.homeManagerModules.themes =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      options.themes = {
        dark = lib.mkOption {
          type = lib.types.path;
          description = "Path to the base24 dark scheme YAML file.";
        };
        light = lib.mkOption {
          type = lib.types.path;
          description = "Path to the base24 light scheme YAML file.";
        };
        palette = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
          readOnly = true;
          description = "Parsed base24 palettes keyed by 'dark'/'light'. Access as config.themes.palette.dark.base00 (hex without #).";
        };
      };

      config.themes = {
        dark = inputs.base24-schemes + "/base24/gruvbox-dark.yaml";
        light = inputs.base24-schemes + "/base24/ayu-light.yaml";

        palette = lib.mapAttrs (
          _: yamlFile:
          let
            json = pkgs.runCommand "base24-json" { } "${pkgs.yq-go}/bin/yq -o json ${yamlFile} > $out";
            raw = builtins.fromJSON (builtins.readFile json);
          in
          # Strip leading '#' so consumers can add their own prefix (e.g. "#${p.base00}")
          lib.mapAttrs (_: v: lib.removePrefix "#" v) raw.palette
        ) { inherit (config.themes) dark light; };
      };
    };
}
