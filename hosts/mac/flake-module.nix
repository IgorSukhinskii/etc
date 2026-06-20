{ inputs, ... }:
{
  flake.darwinConfigurations.mac = inputs.nix-darwin.lib.darwinSystem {
    modules = (builtins.attrValues inputs.self.darwinModules) ++ [
      ./config.nix
      inputs.home-manager.darwinModules.home-manager
      (inputs.self.lib.mkHmModule {
        profiles = [
          "base"
          "ai"
          "browser"
          "darwinDesktop"
        ];
        # Mac-side control plane for the Lima private-vm guest (see
        # modules/private-vm/default.nix).
        extra = [ inputs.self.lib.privateVmHm ];
      })
    ];
    specialArgs = { inherit inputs; };
  };
}
