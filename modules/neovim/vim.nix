{ inputs, ... }:
let
  nvfDag = inputs.nvf.lib.nvim.dag;

  # Emit a Lua table literal for a palette attrset (no leading # on values).
  mkPaletteLua = p: ''
    {
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

      dark = mkPaletteLua config.themes.palette.dark;
      light = mkPaletteLua config.themes.palette.light;
    in
    {
      programs.nvf = {
        enable = true;

        settings.vim = {
          viAlias = true;
          vimAlias = true;
          startPlugins = with pkgs.vimPlugins; [
            SchemaStore-nvim
            base16-nvim
          ];
          clipboard = {
            enable = true;
            registers = "unnamed,unnamedplus";
          };
          debugger.nvim-dap.enable = true;
          git.gitsigns.enable = true;
          statusline.lualine = {
            enable = true;
            setupOpts.options.theme = "base16";
          };
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
            setupOpts.defaults.layout_strategy = "flex";
          };
          luaConfigRC.telescope = /* lua */ ''
            require("telescope").setup({
              defaults = {
                layout_config = {
                  flip_columns = 120,
                  flip_lines = 40,
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
          binds.whichKey.enable = true;
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
          luaConfigRC.base16-polarity = nvfDag.entryAfter [ "optionsScript" ] /* lua */ ''
            local base16 = require("base16-colorscheme")
            local schemes = {
              dark  = ${dark},
              light = ${light},
            }
            local function is_dark()
              return vim.fn.system("defaults read -g AppleInterfaceStyle 2>/dev/null"):find("Dark") ~= nil
            end
            local function apply_scheme()
              base16.setup(is_dark() and schemes.dark or schemes.light)
            end
            apply_scheme()
            vim.api.nvim_create_autocmd("FocusGained", { callback = apply_scheme })
          '';
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
