{ ... }:
{
  flake.homeManagerModules.opencode =
    { pkgs, lib, ... }:
    {
      programs.opencode.enable = true;
    };
}
