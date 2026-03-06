{ inputs, ... }:
{
  imports = [ inputs.git-hooks.flakeModule ];

  flake.homeManagerModules.nix-dev =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        nixd
        nixfmt
      ];

      # Neovim nix language support — colocated here so formatter stays in sync
      # with the pre-commit hook below. Both use nixfmt (RFC 166 style).
      programs.nvf.settings.vim.languages.nix = {
        enable = true;
        format = {
          enable = true;
          type = [ "nixfmt" ];
        };
        lsp = {
          enable = true;
          servers = [ "nixd" ];
        };
        treesitter.enable = true;
      };
    };

  perSystem =
    { config, pkgs, ... }:
    {
      pre-commit.settings.hooks.nixfmt.enable = true;
      devShells.default = pkgs.mkShell {
        shellHook = config.pre-commit.shellHook;
      };
    };
}
