{ inputs, ... }:
{
  imports = [
    inputs.stylix.darwinModules.stylix
    ./mac.nix
    ./nix.nix
    ./users.nix
    ./homebrew.nix
    ./stylix.nix
  ];
}
