{
  description = "Igor's nix config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Stable channel kept solely to source a working `qemu` for the darwin
    # linux-builder. qemu 11.0.0 in nixpkgs-unstable aborts on macOS 26 with
    # an HVF SMCR_EL1 assertion (nixpkgs #528299, qemu-project/qemu#3533).
    # Remove this input + the overlay in modules/darwin/nix.nix once the
    # upstream qemu fix lands on unstable.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
    base24-schemes = {
      url = "github:tinted-theming/schemes";
      flake = false;
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake/beta";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
    kanata-darwin = {
      url = "github:not-in-stock/kanata-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # kanata is deliberately pinned and must NOT follow `nixpkgs`. macOS TCC keys
    # the Input Monitoring / Accessibility grants on the binary's absolute path
    # *and* its ad-hoc cdhash (the binary is `adhoc, linker-signed`: no Team ID,
    # no stable identity). Both change on every rebuild, so an unpinned kanata
    # loses both permissions on each `nix flake update` and the daemon dies until
    # they are re-granted by hand. Freezing the derivation freezes the store path.
    # Bumping this rev is a deliberate act that costs one manual re-grant of both
    # permissions -- see modules/kanata/kanata.nix.
    nixpkgs-kanata.url = "github:NixOS/nixpkgs/17de0b976395537756f30a3e78f2f06e5cec89ed";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];

      imports = [
        (inputs.import-tree ./modules)
        ./hosts/mac/flake-module.nix
        ./hosts/wsl/flake-module.nix
        ./hosts/private-vm/vars.nix
        ./hosts/private-vm/flake-module.nix
      ];
    };
}
