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
        # WSL-singular terminal (writes wezterm.lua to the Windows side).
        extra = [ ./wezterm.nix ];
      })
    ];
    specialArgs = { inherit inputs; };
  };
}
