{ ... }:
{
  flake.darwinModules.skhd =
    { ... }:
    {
      services.skhd = {
        enable = true;
        skhdConfig = ''
          hyper - t : open ~/Applications/Home\ Manager\ Apps/Ghostty.app
        '';
      };
    };
}
