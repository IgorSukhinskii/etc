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
    in
    {
      programs.nvf = {
        enable = true;

        settings.vim = {
          viAlias = true;
          vimAlias = true;
          startPlugins = with pkgs.vimPlugins; [
            SchemaStore-nvim
            tinted-nvim
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
              separator_style = "slant";
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
          luaConfigRC.tinted-polarity = nvfDag.entryBefore [ "pluginConfigs" ] /* lua */ ''
            local tinted = require("tinted-nvim")
            tinted.setup({
              apply_scheme_on_startup = false,
              schemes = {
                ["base24-dark"]  = ${dark_scheme},
                ["base24-light"] = ${light_scheme},
              },
            })

            local function sync_background()
              local is_dark = vim.fn.system("defaults read -g AppleInterfaceStyle 2>/dev/null"):find("Dark") ~= nil
              local scheme = is_dark and "base24-dark" or "base24-light"
              if tinted.get_scheme() ~= scheme then
                tinted.load(scheme)
              end
            end

            -- DEC mode 2031 sets vim.o.background directly; keep scheme in sync.
            -- Guard against re-entrancy: tinted.load() sets background, which fires OptionSet again.
            vim.api.nvim_create_autocmd("OptionSet", {
              pattern = "background",
              callback = function()
                local scheme = (vim.o.background == "dark") and "base24-dark" or "base24-light"
                if tinted.get_scheme() ~= scheme then
                  tinted.load(scheme)
                end
              end,
            })

            -- FocusGained fallback: sync from macOS dark mode state.
            -- Can be removed once tmux ships DEC mode 2031 passthrough.
            vim.api.nvim_create_autocmd("FocusGained", { callback = sync_background })

            -- Initial sync on startup — runs before pluginConfigs so lualine and
            -- bufferline see the correct highlights when they register their handlers.
            sync_background()
          '';
          luaConfigRC.tinted-bufferline = nvfDag.entryAfter [ "pluginConfigs" ] /* lua */ ''
            local tinted = require("tinted-nvim")

            local function apply_bufferline_hl()
              local p = tinted.get_palette()
              if not p then return end
              local is_dark = vim.o.background == "dark"
              local hl = vim.api.nvim_set_hl

              -- Three-tier bg: fill(base10/base02) < inactive(base01) < active(base00)
              local fill_bg     = is_dark and p.base11 or p.base03
              local inactive_bg = p.base02
              local active_bg   = p.base00

              -- Fill area (bar behind all tabs)
              hl(0, "BufferLineFill",                       { fg = p.base03, bg = fill_bg })

              -- Inactive / background tabs
              hl(0, "BufferLineBackground",                 { fg = p.base04, bg = inactive_bg })
              hl(0, "BufferLineBufferVisible",              { fg = p.base04, bg = inactive_bg })
              hl(0, "BufferLineCloseButton",                { fg = p.base04, bg = inactive_bg })
              hl(0, "BufferLineCloseButtonVisible",         { fg = p.base04, bg = inactive_bg })
              hl(0, "BufferLineModified",                   { fg = p.base09, bg = inactive_bg })
              hl(0, "BufferLineModifiedVisible",            { fg = p.base09, bg = inactive_bg })
              hl(0, "BufferLineDuplicate",                  { fg = p.base03, bg = inactive_bg, italic = true })
              hl(0, "BufferLineDuplicateVisible",           { fg = p.base03, bg = inactive_bg, italic = true })
              -- Diagnostics (inactive background state)
              hl(0, "BufferLineDiagnostic",                 { fg = p.base04, bg = inactive_bg })
              hl(0, "BufferLineError",                      { fg = p.base08, bg = inactive_bg })
              hl(0, "BufferLineErrorDiagnostic",            { fg = p.base08, bg = inactive_bg })
              hl(0, "BufferLineWarning",                    { fg = p.base09, bg = inactive_bg })
              hl(0, "BufferLineWarningDiagnostic",          { fg = p.base09, bg = inactive_bg })
              hl(0, "BufferLineInfo",                       { fg = p.base0D, bg = inactive_bg })
              hl(0, "BufferLineInfoDiagnostic",             { fg = p.base0D, bg = inactive_bg })
              hl(0, "BufferLineHint",                       { fg = p.base0C, bg = inactive_bg })
              hl(0, "BufferLineHintDiagnostic",             { fg = p.base0C, bg = inactive_bg })
              hl(0, "BufferLinePick",                       { fg = p.base08, bg = inactive_bg, bold = true })
              -- Diagnostics (visible in split, not focused) — must match inactive bg or icons go wrong
              hl(0, "BufferLineDiagnosticVisible",          { fg = p.base04, bg = inactive_bg })
              hl(0, "BufferLineErrorVisible",               { fg = p.base08, bg = inactive_bg })
              hl(0, "BufferLineErrorDiagnosticVisible",     { fg = p.base08, bg = inactive_bg })
              hl(0, "BufferLineWarningVisible",             { fg = p.base09, bg = inactive_bg })
              hl(0, "BufferLineWarningDiagnosticVisible",   { fg = p.base09, bg = inactive_bg })
              hl(0, "BufferLineInfoVisible",                { fg = p.base0D, bg = inactive_bg })
              hl(0, "BufferLineInfoDiagnosticVisible",      { fg = p.base0D, bg = inactive_bg })
              hl(0, "BufferLineHintVisible",                { fg = p.base0C, bg = inactive_bg })
              hl(0, "BufferLineHintDiagnosticVisible",      { fg = p.base0C, bg = inactive_bg })
              hl(0, "BufferLinePickVisible",                { fg = p.base08, bg = inactive_bg, bold = true })
              -- Separators (slant): fg = fill_bg (the cut-through glyph), bg = tab body
              hl(0, "BufferLineSeparator",                  { fg = fill_bg, bg = inactive_bg })
              hl(0, "BufferLineSeparatorVisible",           { fg = fill_bg, bg = inactive_bg })
              -- Tab bar (vim tabs, not buffer tabs)
              hl(0, "BufferLineTab",                        { fg = p.base04, bg = inactive_bg })
              hl(0, "BufferLineTabSeparator",               { fg = fill_bg, bg = inactive_bg })
              hl(0, "BufferLineTabClose",                   { fg = p.base08, bg = inactive_bg })
              hl(0, "BufferLineOffsetSeparator",            { fg = p.base02, bg = fill_bg })

              -- Active / selected tab (matches editor bg)
              hl(0, "BufferLineBufferSelected",             { fg = p.base05, bg = active_bg, bold = true })
              hl(0, "BufferLineCloseButtonSelected",        { fg = p.base08, bg = active_bg })
              hl(0, "BufferLineModifiedSelected",           { fg = p.base09, bg = active_bg })
              hl(0, "BufferLineDuplicateSelected",          { fg = p.base04, bg = active_bg, italic = true })
              hl(0, "BufferLineIndicatorVisible",           { fg = p.base03, bg = inactive_bg })
              hl(0, "BufferLineIndicatorSelected",          { fg = p.base0D, bg = active_bg })
              -- Diagnostics (selected) — bold = true so name stays bold regardless of diagnostic state
              hl(0, "BufferLineDiagnosticSelected",         { fg = p.base04, bg = active_bg, bold = true })
              hl(0, "BufferLineErrorSelected",              { fg = p.base08, bg = active_bg, bold = true })
              hl(0, "BufferLineErrorDiagnosticSelected",    { fg = p.base08, bg = active_bg, bold = true })
              hl(0, "BufferLineWarningSelected",            { fg = p.base09, bg = active_bg, bold = true })
              hl(0, "BufferLineWarningDiagnosticSelected",  { fg = p.base09, bg = active_bg, bold = true })
              hl(0, "BufferLineInfoSelected",               { fg = p.base0D, bg = active_bg, bold = true })
              hl(0, "BufferLineInfoDiagnosticSelected",     { fg = p.base0D, bg = active_bg, bold = true })
              hl(0, "BufferLineHintSelected",               { fg = p.base0C, bg = active_bg, bold = true })
              hl(0, "BufferLineHintDiagnosticSelected",     { fg = p.base0C, bg = active_bg, bold = true })
              hl(0, "BufferLinePickSelected",               { fg = p.base08, bg = active_bg, bold = true })
              -- Separators (slant, selected): fg = fill bg (the cut-through), bg = active tab body
              hl(0, "BufferLineSeparatorSelected",          { fg = fill_bg, bg = active_bg })
              hl(0, "BufferLineTabSelected",                { fg = p.base05, bg = active_bg })
              hl(0, "BufferLineTabSeparatorSelected",       { fg = fill_bg, bg = active_bg })

              -- Patch internal config so icon bg derivation uses our values,
              -- then clear the icon cache so icons re-derive on next render.
              local cfg_hls = require("bufferline.config").highlights
              if cfg_hls then
                if cfg_hls.background      then cfg_hls.background.bg      = inactive_bg end
                if cfg_hls.buffer_visible  then cfg_hls.buffer_visible.bg  = inactive_bg end
                if cfg_hls.buffer_selected then cfg_hls.buffer_selected.bg = active_bg   end
              end
              require("bufferline.highlights").reset_icon_hl_cache()
            end

            apply_bufferline_hl()
            -- vim.schedule defers our handler to run after ALL synchronous autocmds
            -- (including bufferline's own handler), so our patches win.
            vim.api.nvim_create_autocmd({ "ColorScheme" }, {
              callback = function() vim.schedule(apply_bufferline_hl) end,
            })
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
