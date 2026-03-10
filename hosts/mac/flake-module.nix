{ inputs, ... }:
{
  flake.darwinConfigurations.mac = inputs.nix-darwin.lib.darwinSystem {
    modules = (builtins.attrValues inputs.self.darwinModules) ++ [
      ./config.nix
      inputs.home-manager.darwinModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.sharedModules = (builtins.attrValues inputs.self.homeManagerModules) ++ [
          inputs.nvf.homeManagerModules.default
          inputs.zen-browser.homeModules.beta
        ];
      }
    ];
    specialArgs = { inherit inputs; };
  };
}
