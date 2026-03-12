{ ... }:
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
    in
    {
      programs.nvf = {
        enable = true;

        settings.vim = {
          viAlias = true;
          vimAlias = true;
          startPlugins = with pkgs.vimPlugins; [
            SchemaStore-nvim
          ];
          clipboard = {
            enable = true;
            registers = "unnamed,unnamedplus";
          };
          debugger.nvim-dap = {
            enable = true;
          };
          git.gitsigns.enable = true;
          statusline.lualine.enable = true;
          tabline.nvimBufferline.enable = true;
          lsp = {
            enable = true;
            formatOnSave = true;
            lightbulb.enable = true;
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
            setupOpts = {
              defaults = {
                layout_strategy = "flex";
              };
            };
          };
          # These options are not in nvf yet, so we load them via lua
          luaConfigRC.telescope = /* lua */ ''
            require("telescope").setup({
              defaults = {
                layout_config = {
                  flip_columns = 120;
                  flip_lines = 40;
                  vertical = { preview_cutoff = 0 },
                },
              },
            })
          '';
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
          binds = {
            whichKey = {
              enable = true;
            };
          };
          languages = {
            enableDAP = true;
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
          };
          luaConfigRC.schemastore = builtins.readFile ./schemastore.lua;
          luaConfigRC.buffercycle = /* lua */ ''
            vim.keymap.set("n", "<C-Tab>",   "<Cmd>BufferLineCycleNext<CR>", { desc = "Next buffer" })
            vim.keymap.set("n", "<C-S-Tab>", "<Cmd>BufferLineCyclePrev<CR>", { desc = "Prev buffer" })
          '';
          visuals.indent-blankline.enable = true;
          visuals.nvim-scrollbar.enable = true;
          ui.illuminate.enable = true;
          ui.noice.enable = true;
        };
      };
    };
}
