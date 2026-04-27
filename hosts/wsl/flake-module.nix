{ inputs, ... }:
{
  flake.nixosConfigurations.wsl = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      inputs.nixos-wsl.nixosModules.wsl
      ./config.nix
      ../../nixos/nix.nix
      ../../nixos/users.nix
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = {
          isDarwin = false;
        };
        home-manager.sharedModules = (builtins.attrValues inputs.self.homeManagerModules) ++ [
          inputs.nvf.homeManagerModules.default
          # zen-browser intentionally omitted (headless)
        ];
      }
    ];
    specialArgs = { inherit inputs; };
  };
}
