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
    kanata-darwin = {
      url = "github:not-in-stock/kanata-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
