{
  description = "Igor's nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvf = {
      url = "github:NotAShelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake/beta";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      nixpkgs,
      home-manager,
      stylix,
      nvf,
      zen-browser,
    }:
    {
      # Build darwin flake using:
      # $ darwin-rebuild build --flake .#Igors-MacBook-Pro
      darwinConfigurations."Igors-MacBook-Pro" = nix-darwin.lib.darwinSystem {
        modules = [
          ./system
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.sharedModules = [
              nvf.homeManagerModules.default
              zen-browser.homeModules.beta
            ];
            home-manager.users."igor.sukhinskii" = import ./home;
          }
          stylix.darwinModules.stylix
          ./stylix
        ];
      };
    };
}
