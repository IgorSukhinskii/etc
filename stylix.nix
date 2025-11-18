{ pkgs, ... }:

{
  stylix = {
    enable = false;

    base16Scheme = "catppuccin-mocha";

    fonts = {
      monospace = {
        package = pkgs.jetbrains-mono;
        name = "JetBrainsMono";
      };
    };

    # targets.nixos-icons.enable = false;
  };
}

