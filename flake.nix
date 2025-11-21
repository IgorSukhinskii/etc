{
  description = "Igor's nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    stylix.url = "github:nix-community/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, stylix }:

  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#Igors-MacBook-Pro
    darwinConfigurations."Igors-MacBook-Pro" = nix-darwin.lib.darwinSystem {
      modules = [
        ./configuration.nix
        home-manager.darwinModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users."igor.sukhinskii" = import ./home.nix;
        }
        stylix.darwinModules.stylix
        ./stylix.nix
      ];
    };
  };
}
