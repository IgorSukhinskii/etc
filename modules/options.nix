{ lib, ... }:
{
  options.flake.darwinModules = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.unspecified;
    default = {};
  };

  options.flake.homeManagerModules = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.unspecified;
    default = {};
  };
}
