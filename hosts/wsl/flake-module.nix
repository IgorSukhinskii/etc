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
      (inputs.self.lib.mkHmModule {
        profiles = [
          "base"
          "ai"
        ];
        # WSL-singular: the terminal (writes wezterm.lua to the Windows side),
        # the t3 server, twg (calls the Windows twg.exe), and ~/w on the XFS work disk.
        extra = [
          ./wezterm.nix
          ./t3.nix
          ./twg.nix
          ./work.nix
        ];
      })
    ];
    specialArgs = { inherit inputs; };
  };
}
