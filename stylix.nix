{ pkgs, ... }:

{
  stylix = {
    enable = true;

    autoEnable = true;

    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";

    fonts = {
      monospace = {
        package = pkgs.jetbrains-mono;
        name = "JetBrainsMono";
      };
    };

    # targets.nixos-icons.enable = false;
  };
}

