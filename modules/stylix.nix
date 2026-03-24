{ inputs, ... }:
{
  flake.darwinModules.stylix =
    { pkgs, ... }:
    {
      imports = [ inputs.stylix.darwinModules.stylix ];

      stylix = {
        enable = true;

        autoEnable = true;

        base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-hard.yaml";

        fonts = {
          monospace = {
            package = pkgs.jetbrains-mono;
            name = "JetBrainsMono";
          };
        };
      };
    };
}
