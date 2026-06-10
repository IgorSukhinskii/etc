{ inputs, ... }:
{
  flake.nixosConfigurations.private-vm = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      ./config.nix
      ./vm.nix
      ../../nixos/nix.nix
      ../../nixos/users.nix
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.backupFileExtension = "hm-backup";
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = {
          isDarwin = false;
        };
        home-manager.sharedModules = (builtins.attrValues inputs.self.homeManagerModules) ++ [
          inputs.nvf.homeManagerModules.default
        ];
      }
    ];
    specialArgs = { inherit inputs; };
  };

  perSystem =
    { pkgs, system, ... }:
    {
      packages.private-vm-image = inputs.nixos-generators.nixosGenerate {
        system = "aarch64-linux";
        format = "qcow";
        modules = [
          ./config.nix
          ./vm.nix
          ../../nixos/nix.nix
          ../../nixos/users.nix
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.backupFileExtension = "hm-backup";
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {
              isDarwin = false;
            };
            home-manager.sharedModules = (builtins.attrValues inputs.self.homeManagerModules) ++ [
              inputs.nvf.homeManagerModules.default
            ];
          }
        ];
        specialArgs = { inherit inputs; };
      };
    };
}
