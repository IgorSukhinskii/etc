{ lib, ... }:
{
  options.flake.darwinModules = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.unspecified;
    default = { };
  };

  options.flake.homeManagerModules = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.unspecified;
    default = { };
  };

  # Declared so `flake.lib.*` can be contributed from more than one module
  # (the resolver/wiring helpers in lib.nix, the private-vm launcher, …) and
  # merged instead of colliding.
  options.flake.lib = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.unspecified;
    default = { };
  };
}
