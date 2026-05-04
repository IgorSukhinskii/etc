{ inputs, ... }:
let
  nvfDag = inputs.nvf.lib.nvim.dag;

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
      lib,
      pkgs,
      config,
      ...
    }:

    let
      lang = {
        enable = true;
        format.enable = true;
        lsp.enable = true;
        treesitter.enable = true;
      };

      dark_scheme = mkSchemeLua "dark" config.themes.palette.dark;
      light_scheme = mkSchemeLua "light" config.themes.palette.light;
      indicator_icon = builtins.fromJSON ''"\u258E"''; # ▎
    in
    {
      programs.nvf = {
        enable = true;

        settings.vim = {
          viAlias = true;
          vimAlias = true;
          # Keep the CLI on PATH for health checks and parser tooling, even though
          # parsers themselves are primarily supplied declaratively by Nix.
          extraPackages = [ pkgs.tree-sitter ];
          # Prefer the newer nixpkgs package until nvf's bundled lightbulb source catches up.
          pluginOverrides.nvim-lightbulb = pkgs.vimPlugins.nvim-lightbulb;
          startPlugins = with pkgs.vimPlugins; [
            SchemaStore-nvim
            # Guard vim.o.background assignment in tinted.load() so it only fires
            # after VimEnter. Without this, calling tinted.load() during the VIMINIT
            # script chain sets background with the script's SID (not -8), causing
            # Neovim 0.12's VimEnter check to delete the built-in TermResponse
            # background-detection autocmd, breaking automatic dark/light switching.
            (tinted-nvim.overrideAttrs (_: {
              postPatch = ''
                substituteInPlace lua/tinted-nvim/init.lua \
                  --replace-fail \
                    'vim.o.background = palette.variant' \
                    'if vim.v.vim_did_enter == 1 then vim.o.background = palette.variant end'
              '';
            }))
          ];
          clipboard = {
            enable = true;
            registers = "unnamed,unnamedplus";
          };
          debugger.nvim-dap.enable = true;
          git.gitsigns.enable = true;
          statusline.lualine = {
            enable = true;
            setupOpts.options.theme = "tinted";
          };
          tabline.nvimBufferline = {
            enable = true;
            setupOpts.options = {
              indicator = {
                icon = indicator_icon;
                style = "icon";
              };
              numbers = "none";
              hover = {
                enabled = false;
              };
              tab_size = 14;
            };
          };
          lsp = {
            enable = true;
            formatOnSave = true;
            lightbulb.enable = true;
            # nvf adds legacy alias filetypes that trip vim.lsp health despite working detection.
            servers.ts_ls.filetypes = lib.mkForce [
              "javascript"
              "javascriptreact"
              "typescript"
              "typescriptreact"
            ];
            # Keep yamlls aligned with real Neovim filetypes to avoid false-positive health warnings.
            servers."yaml-language-server".filetypes = lib.mkForce [ "yaml" ];
          };
          treesitter.enable = true;
          autocomplete.blink-cmp = {
            enable = true;
            setupOpts = {
              keymap.preset = "super-tab";
              signature.enabled = true;
            };
          };
          telescope = {
            enable = true;
            setupOpts.defaults.layout_strategy = "flex";
          };
          filetree.nvimTree = {
            enable = true;
            mappings.toggle = "tt";
            openOnSetup = false;
            setupOpts = {
              git.enable = true;
              modified.enable = true;
              renderer.highlight_git = true;
              renderer.icons.show.git = true;
              update_focused_file.enable = true;
            };
          };
          binds.whichKey.enable = true;
          languages = {
            enableDAP = true;
            enableTreesitter = true;
            python = lang // {
              lsp.enable = false;
            };
            ts = lang;
            bash = lang;
            lua = lang;
            yaml = {
              enable = true;
              lsp.enable = true;
              treesitter.enable = true;
            };
            markdown = lang // {
              extraDiagnostics.enable = true;
              lsp.servers = [ "markdown-oxide" ];
            };
            json = lang // {
              lsp.servers = [ "jsonls" ];
            };
            nu = {
              enable = true;
              lsp.enable = true;
              treesitter.enable = true;
            };
            zig = {
              enable = true;
              lsp.enable = true;
              treesitter.enable = true;
            };
            rust = lang;
            wgsl = {
              enable = true;
            };
          };
          luaConfigRC.tinted-polarity = nvfDag.entryBefore [ "pluginConfigs" ] (
            builtins.replaceStrings [ "__DARK_SCHEME__" "__LIGHT_SCHEME__" ] [ dark_scheme light_scheme ] (
              builtins.readFile ./tinted-polarity.lua
            )
          );
          luaConfigRC.tinted-bufferline = nvfDag.entryAfter [ "pluginConfigs" ] (
            builtins.readFile ./tinted-bufferline.lua
          );
          luaConfigRC.schemastore = builtins.readFile ./schemastore.lua;
          luaConfigRC.buffercycle = /* lua */ ''
            vim.keymap.set("n", "<C-Tab>",   "<Cmd>BufferLineCycleNext<CR>", { desc = "Next buffer" })
            vim.keymap.set("n", "<C-S-Tab>", "<Cmd>BufferLineCyclePrev<CR>", { desc = "Prev buffer" })
          '';
          visuals.indent-blankline.enable = true;
          visuals.nvim-scrollbar.enable = true;
          ui.illuminate.enable = true;
          ui.noice = {
            enable = true;
            setupOpts.lsp.signature.enabled = true;
          };
          notify.nvim-notify.enable = true;
        };
      };
    };
}
