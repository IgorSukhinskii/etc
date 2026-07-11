{ ... }:
let
  # Emit a tinted-nvim scheme table literal from a palette attrset (no leading # on values).
  mkSchemeLua = variant: p: ''
    {
      variant = "${variant}",
      base00 = "#${p.base00}",
      base01 = "#${p.base01}",
      base02 = "#${p.base02}",
      base03 = "#${p.base03}",
      base04 = "#${p.base04}",
      base05 = "#${p.base05}",
      base06 = "#${p.base06}",
      base07 = "#${p.base07}",
      base08 = "#${p.base08}",
      base09 = "#${p.base09}",
      base0A = "#${p.base0A}",
      base0B = "#${p.base0B}",
      base0C = "#${p.base0C}",
      base0D = "#${p.base0D}",
      base0E = "#${p.base0E}",
      base0F = "#${p.base0F}",
      base10 = "#${p.base10}",
      base11 = "#${p.base11}",
      base12 = "#${p.base12}",
      base13 = "#${p.base13}",
      base14 = "#${p.base14}",
      base15 = "#${p.base15}",
      base16 = "#${p.base16}",
      base17 = "#${p.base17}",
    }
  '';
in
{
  flake.homeManagerModules.neovim =
    {
      pkgs,
      config,
      ...
    }:

    let
      dark_scheme = mkSchemeLua "dark" config.themes.palette.dark;
      light_scheme = mkSchemeLua "light" config.themes.palette.light;
      neovimDir = "${config.local.flakeDir}/modules/neovim";
    in
    {
      programs.neovim = {
        enable = true;
        viAlias = true;
        vimAlias = true;
        withNodeJs = true;
        withPython3 = false;
        withRuby = false;

        extraPackages = with pkgs; [
          tree-sitter
          imagemagick
          poppler-utils
          ghostscript

          bash-language-server
          lua-language-server
          markdown-oxide
          nixd
          nixfmt
          nushell
          rust-analyzer
          tinymist
          typescript-language-server
          vscode-langservers-extracted
          yaml-language-server
          zls
        ];

        plugins = with pkgs.vimPlugins; [
          SchemaStore-nvim
          blink-cmp
          bufferline-nvim
          conform-nvim
          gitsigns-nvim
          indent-blankline-nvim
          lualine-nvim
          noice-nvim
          nvim-dap
          nvim-lspconfig
          nvim-lightbulb
          nvim-notify
          nvim-scrollbar
          plenary-nvim
          snacks-nvim
          telescope-nvim
          vim-illuminate
          which-key-nvim

          (nvim-treesitter.withPlugins (
            p: with p; [
              bash
              javascript
              json
              lua
              markdown
              markdown_inline
              nix
              nu
              python
              rust
              tsx
              typescript
              typst
              wgsl
              yaml
              zig
            ]
          ))

          # Guard vim.o.background assignment in tinted.load() so it only fires
          # after VimEnter. Without this, calling tinted.load() during startup
          # sets background with the script's SID, which can break automatic
          # terminal background detection.
          (tinted-nvim.overrideAttrs (_: {
            postPatch = ''
              substituteInPlace lua/tinted-nvim/init.lua \
                --replace-fail \
                  'vim.o.background = palette.variant' \
                  'if vim.v.vim_did_enter == 1 then vim.o.background = palette.variant end'
            '';
          }))
        ];

        initLua = ''
          vim.g.etc_neovim_dir = ${builtins.toJSON neovimDir}
          vim.g.etc_neovim_schemes = {
            dark = ${dark_scheme},
            light = ${light_scheme},
          }
          assert(loadfile(${builtins.toJSON "${neovimDir}/init.lua"}))()
        '';
      };
    };
}
