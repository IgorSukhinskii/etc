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
          luaConfigRC.base16-polarity = nvfDag.entryBefore [ "pluginConfigs" ] /* lua */ ''
            local base16 = require("base16-colorscheme")
            local schemes = {
              dark  = ${dark},
              light = ${light},
            }

            -- Single entry point: reads vim.o.background and applies the matching palette.
            -- Fires from BOTH the native DEC mode 2031 mechanism AND our manual sync below.
            -- Firing ColorScheme afterwards lets bufferline and lualine re-derive their
            -- highlights from the new Normal/Comment colors (both plugins listen to it).
            local function apply_scheme()
              local p = (vim.o.background == "dark") and schemes.dark or schemes.light
              base16.setup(p)
              vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
            end
            vim.api.nvim_create_autocmd("OptionSet", {
              pattern = "background",
              callback = apply_scheme,
            })

            -- FocusGained fallback: sync vim.o.background from macOS, which triggers OptionSet → apply_scheme.
            -- Can be deleted once tmux ships DEC mode 2031 passthrough.
            local function sync_background()
              local want = vim.fn.system("defaults read -g AppleInterfaceStyle 2>/dev/null"):find("Dark")
                ~= nil and "dark" or "light"
              if vim.o.background ~= want then
                vim.o.background = want   -- triggers OptionSet → apply_scheme
              end
            end
            vim.api.nvim_create_autocmd("FocusGained", { callback = sync_background })

            -- Initial sync on startup: sets vim.o.background → OptionSet → apply_scheme.
            -- Runs before pluginConfigs, so lualine and bufferline see base16 already loaded.
            sync_background()
          '';
          luaConfigRC.base16-bufferline = nvfDag.entryAfter [ "pluginConfigs" ] /* lua */ ''
            local function apply_bufferline_hl()
              local p = (vim.o.background == "dark") and schemes.dark or schemes.light
              local hl = vim.api.nvim_set_hl
              -- Inactive / fill (base01 bg throughout; separator fg = base02 distinguishes tabs)
              hl(0, "BufferLineFill",                  { fg = p.base02, bg = p.base01 })
              hl(0, "BufferLineBackground",            { fg = p.base03, bg = p.base01 })
              hl(0, "BufferLineBufferVisible",         { fg = p.base04, bg = p.base01 })
              hl(0, "BufferLineNumbers",               { fg = p.base03, bg = p.base01 })
              hl(0, "BufferLineNumbersVisible",        { fg = p.base04, bg = p.base01 })
              hl(0, "BufferLineCloseButton",           { fg = p.base03, bg = p.base01 })
              hl(0, "BufferLineCloseButtonVisible",    { fg = p.base04, bg = p.base01 })
              hl(0, "BufferLineSeparator",             { fg = p.base02, bg = p.base01 })
              hl(0, "BufferLineSeparatorVisible",      { fg = p.base02, bg = p.base01 })
              hl(0, "BufferLineModified",              { fg = p.base0A, bg = p.base01 })
              hl(0, "BufferLineModifiedVisible",       { fg = p.base0A, bg = p.base01 })
              hl(0, "BufferLineDiagnostic",            { fg = p.base03, bg = p.base01 })
              hl(0, "BufferLineError",                 { fg = p.base08, bg = p.base01 })
              hl(0, "BufferLineWarning",               { fg = p.base0A, bg = p.base01 })
              hl(0, "BufferLineInfo",                  { fg = p.base0D, bg = p.base01 })
              hl(0, "BufferLineHint",                  { fg = p.base0C, bg = p.base01 })
              hl(0, "BufferLinePick",                  { fg = p.base08, bg = p.base01, bold = true })
              hl(0, "BufferLineTab",                   { fg = p.base03, bg = p.base01 })
              hl(0, "BufferLineTabSeparator",          { fg = p.base02, bg = p.base01 })
              hl(0, "BufferLineOffsetSeparator",       { fg = p.base02, bg = p.base01 })
              hl(0, "BufferLineTabClose",              { fg = p.base08, bg = p.base01 })
              -- Active / selected tab (base00 bg — matches editor background)
              hl(0, "BufferLineBufferSelected",        { fg = p.base05, bg = p.base00, bold = true })
              hl(0, "BufferLineNumbersSelected",       { fg = p.base05, bg = p.base00, bold = true })
              hl(0, "BufferLineCloseButtonSelected",   { fg = p.base08, bg = p.base00 })
              hl(0, "BufferLineSeparatorSelected",     { fg = p.base0D, bg = p.base00 })
              hl(0, "BufferLineIndicatorSelected",     { fg = p.base0D, bg = p.base00 })
              hl(0, "BufferLineModifiedSelected",      { fg = p.base0A, bg = p.base00 })
              hl(0, "BufferLineDiagnosticSelected",    { fg = p.base03, bg = p.base00 })
              hl(0, "BufferLineErrorSelected",         { fg = p.base08, bg = p.base00 })
              hl(0, "BufferLineWarningSelected",       { fg = p.base0A, bg = p.base00 })
              hl(0, "BufferLineInfoSelected",          { fg = p.base0D, bg = p.base00 })
              hl(0, "BufferLineHintSelected",          { fg = p.base0C, bg = p.base00 })
              hl(0, "BufferLinePickSelected",          { fg = p.base08, bg = p.base00, bold = true })
              hl(0, "BufferLineTabSelected",           { fg = p.base05, bg = p.base00 })
              hl(0, "BufferLineTabSeparatorSelected",  { fg = p.base0D, bg = p.base00 })
              -- Patch internal config so icon highlight derivation uses our bg values,
              -- then clear the icon cache so icons re-derive on next render.
              local cfg_hls = require("bufferline.config").highlights
              if cfg_hls then
                if cfg_hls.background then cfg_hls.background.bg = p.base01 end
                if cfg_hls.buffer_selected then cfg_hls.buffer_selected.bg = p.base00 end
              end
              require("bufferline.highlights").reset_icon_hl_cache()
            end
            apply_bufferline_hl()
            -- Fires after bufferline's own ColorScheme handler (registered earlier), overriding its output.
            vim.api.nvim_create_autocmd("ColorScheme", { callback = apply_bufferline_hl })
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
