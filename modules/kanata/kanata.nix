{ inputs, ... }:
{
  flake.darwinModules.kanata =
    { ... }:
    {
      imports = [ inputs.kanata-darwin.darwinModules.default ];

      services.kanata = {
        enable = true;
        daemon.enable = true;
        configSource = ./kanata.kbd;
      };
    };
}
