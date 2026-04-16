{ inputs, ... }:
{
  flake.homeManagerModules.themes =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      parseScheme =
        yamlFile:
        let
          json = pkgs.runCommand "scheme-json" { } "${pkgs.yq-go}/bin/yq -o json ${yamlFile} > $out";
          raw = builtins.fromJSON (builtins.readFile json);
        in
        lib.mapAttrs (_: v: lib.removePrefix "#" v) raw.palette;

      resolvePalette =
        spec: if builtins.isPath spec || builtins.isString spec then parseScheme spec else spec;

      # Pre-parse sources for the dark theme composition
      hard = parseScheme (inputs.base24-schemes + "/base16/gruvbox-dark-hard.yaml");
      gruvbox24 = parseScheme (inputs.base24-schemes + "/base24/gruvbox-dark.yaml");

      schemeType = with lib.types; either path (attrsOf str);
    in
    {
      options.themes = {
        dark = lib.mkOption {
          type = schemeType;
          description = "Dark theme: path to YAML, or attrset of hex color values.";
        };
        light = lib.mkOption {
          type = schemeType;
          description = "Light theme: path to YAML, or attrset of hex color values.";
        };
        palette = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
          readOnly = true;
          description = "Resolved palettes keyed by dark/light.";
        };
      };

      config.themes = {
        dark = {
          inherit (gruvbox24) # default gradient
            base00
            base01
            base02
            base03
            base04
            base05
            base06
            base07
            ;
          inherit (hard) # bright colors from hard
            base08
            base09
            base0A
            base0B
            base0C
            base0D
            base0E
            base0F
            ;
          # base10/base11: stronger-bg from base24 (hard has no equivalent)
          inherit (gruvbox24) base10 base11;
          # Muted originals → bright alternate slots
          base12 = gruvbox24.base08;
          base13 = gruvbox24.base0A;
          base14 = gruvbox24.base0B;
          base15 = gruvbox24.base0C;
          base16 = gruvbox24.base0D;
          base17 = gruvbox24.base0E;
        };

        light = inputs.base24-schemes + "/base24/ayu-light.yaml";

        palette = lib.mapAttrs (_: resolvePalette) {
          inherit (config.themes) dark light;
        };
      };
    };
}
