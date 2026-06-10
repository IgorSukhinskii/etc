{ inputs, ... }:
let
  # Bootstrap = what the qcow image is built from. Truly minimal: shared base
  # (config.nix) + the image-only profile (bootstrap.nix). No home-manager,
  # no user-specific data, no GUI stack.
  bootstrapModules = [
    ./config.nix
    ./bootstrap.nix
  ];

  # Full = what `nixos-rebuild switch --flake .#private-vm` applies inside the
  # running VM. Layers the real user, GUI stack, and home-manager wiring on
  # top of the bootstrap base.
  fullModules = bootstrapModules ++ [
    ./full.nix
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

  mkVm =
    modules:
    inputs.nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      inherit modules;
      specialArgs = { inherit inputs; };
    };
in
{
  flake.nixosConfigurations.private-vm = mkVm fullModules;
  flake.nixosConfigurations.private-vm-bootstrap = mkVm bootstrapModules;

  perSystem =
    { ... }:
    {
      packages.private-vm-image =
        inputs.self.nixosConfigurations.private-vm-bootstrap.config.system.build.images.qemu-efi;
    };
}
