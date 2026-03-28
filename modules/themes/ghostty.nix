{ ... }:
{
  flake.homeManagerModules.ghostty-themes =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      mkGhosttyTheme =
        name: p:
        pkgs.writeText "ghostty-theme-${name}" ''
          palette = 0=#${p.base00}
          palette = 1=#${p.base08}
          palette = 2=#${p.base0B}
          palette = 3=#${p.base0A}
          palette = 4=#${p.base0D}
          palette = 5=#${p.base0E}
          palette = 6=#${p.base0C}
          palette = 7=#${p.base05}
          palette = 8=#${p.base03}
          palette = 9=#${p.base12}
          palette = 10=#${p.base14}
          palette = 11=#${p.base13}
          palette = 12=#${p.base16}
          palette = 13=#${p.base17}
          palette = 14=#${p.base15}
          palette = 15=#${p.base07}
          palette = 16=#${p.base09}
          palette = 17=#${p.base0F}
          palette = 18=#${p.base01}
          palette = 19=#${p.base02}
          palette = 20=#${p.base04}
          palette = 21=#${p.base06}
          background = ${p.base00}
          foreground = ${p.base05}
          cursor-color = ${p.base05}
          selection-background = ${p.base02}
          selection-foreground = ${p.base05}
        '';
    in
    {
      home.file.".config/ghostty/themes/gruvbox-dark".source =
        mkGhosttyTheme "dark" config.themes.palette.dark;
      home.file.".config/ghostty/themes/gruvbox-light".source =
        mkGhosttyTheme "light" config.themes.palette.light;
    };
}
