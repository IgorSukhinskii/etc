{ inputs, ... }:
let
  nvfDag = inputs.nvf.lib.nvim.dag;

  # Generate a complete base16 Lua colorscheme from a palette attrset.
  # p is { base00 = "1d2021"; base01 = ...; } (no leading #).
  mkScheme = name: p: ''
    vim.cmd("hi clear")
    if vim.fn.exists("syntax_on") == 1 then vim.cmd("syntax reset") end
    vim.o.termguicolors = true
    vim.g.colors_name = "${name}"

    local p = {
      base00 = "#${p.base00}", -- background
      base01 = "#${p.base01}", -- lighter bg (status bars, line number bg)
      base02 = "#${p.base02}", -- selection bg
      base03 = "#${p.base03}", -- comments / invisibles
      base04 = "#${p.base04}", -- dark fg (status bars)
      base05 = "#${p.base05}", -- default fg
      base06 = "#${p.base06}", -- light fg
      base07 = "#${p.base07}", -- lightest fg
      base08 = "#${p.base08}", -- red
      base09 = "#${p.base09}", -- orange
      base0A = "#${p.base0A}", -- yellow
      base0B = "#${p.base0B}", -- green
      base0C = "#${p.base0C}", -- cyan
      base0D = "#${p.base0D}", -- blue
      base0E = "#${p.base0E}", -- magenta
      base0F = "#${p.base0F}", -- brown
    }

    local hi = function(g, o) vim.api.nvim_set_hl(0, g, o) end

    -- Editor
    hi("Normal",           { fg = p.base05, bg = p.base00 })
    hi("NormalNC",         { fg = p.base05, bg = p.base00 })
    hi("NormalFloat",      { fg = p.base05, bg = p.base01 })
    hi("FloatBorder",      { fg = p.base04, bg = p.base01 })
    hi("FloatShadow",      { bg = p.base00 })
    hi("Cursor",           { fg = p.base00, bg = p.base05 })
    hi("CursorLine",       { bg = p.base01 })
    hi("CursorColumn",     { bg = p.base01 })
    hi("CursorLineNr",     { fg = p.base05 })
    hi("LineNr",           { fg = p.base03 })
    hi("SignColumn",       { fg = p.base03, bg = p.base00 })
    hi("ColorColumn",      { bg = p.base01 })
    hi("FoldColumn",       { fg = p.base03, bg = p.base00 })
    hi("Folded",           { fg = p.base03, bg = p.base01 })
    hi("VertSplit",        { fg = p.base02 })
    hi("WinSeparator",     { fg = p.base02 })
    hi("StatusLine",       { fg = p.base04, bg = p.base02 })
    hi("StatusLineNC",     { fg = p.base03, bg = p.base01 })
    hi("TabLine",          { fg = p.base03, bg = p.base01 })
    hi("TabLineSel",       { fg = p.base05, bg = p.base02 })
    hi("TabLineFill",      { bg = p.base01 })
    hi("Visual",           { bg = p.base02 })
    hi("VisualNOS",        { bg = p.base02 })
    hi("Search",           { fg = p.base00, bg = p.base0A })
    hi("IncSearch",        { fg = p.base00, bg = p.base09 })
    hi("CurSearch",        { fg = p.base00, bg = p.base0A })
    hi("MatchParen",       { fg = p.base0A, underline = true })
    hi("Pmenu",            { fg = p.base05, bg = p.base01 })
    hi("PmenuSel",         { fg = p.base01, bg = p.base05 })
    hi("PmenuSbar",        { bg = p.base02 })
    hi("PmenuThumb",       { bg = p.base04 })
    hi("WildMenu",         { fg = p.base00, bg = p.base0A })
    hi("Directory",        { fg = p.base0D })
    hi("Title",            { fg = p.base0D, bold = true })
    hi("NonText",          { fg = p.base03 })
    hi("SpecialKey",       { fg = p.base03 })
    hi("Conceal",          { fg = p.base03 })
    hi("Ignore",           { fg = p.base03 })
    hi("Underlined",       { underline = true })
    hi("Bold",             { bold = true })
    hi("Italic",           { italic = true })
    hi("ModeMsg",          { fg = p.base05, bold = true })
    hi("MoreMsg",          { fg = p.base0D })
    hi("Question",         { fg = p.base0D })
    hi("QuickFixLine",     { bg = p.base01 })
    hi("SpellBad",         { undercurl = true, sp = p.base08 })
    hi("SpellCap",         { undercurl = true, sp = p.base0D })
    hi("SpellLocal",       { undercurl = true, sp = p.base0C })
    hi("SpellRare",        { undercurl = true, sp = p.base0E })

    -- Diff
    hi("DiffAdd",          { fg = p.base0B, bg = p.base00 })
    hi("DiffChange",       { fg = p.base0D, bg = p.base00 })
    hi("DiffDelete",       { fg = p.base08, bg = p.base00 })
    hi("DiffText",         { fg = p.base0C, bg = p.base00 })
    hi("diffAdded",        { fg = p.base0B })
    hi("diffRemoved",      { fg = p.base08 })
    hi("diffChanged",      { fg = p.base0D })
    hi("diffOldFile",      { fg = p.base0A })
    hi("diffNewFile",      { fg = p.base0B })
    hi("diffFile",         { fg = p.base0D })
    hi("diffLine",         { fg = p.base03 })
    hi("diffIndexLine",    { fg = p.base0C })

    -- Diagnostics
    hi("DiagnosticError",              { fg = p.base08 })
    hi("DiagnosticWarn",               { fg = p.base0A })
    hi("DiagnosticInfo",               { fg = p.base0D })
    hi("DiagnosticHint",               { fg = p.base0C })
    hi("DiagnosticUnderlineError",     { undercurl = true, sp = p.base08 })
    hi("DiagnosticUnderlineWarn",      { undercurl = true, sp = p.base0A })
    hi("DiagnosticUnderlineInfo",      { undercurl = true, sp = p.base0D })
    hi("DiagnosticUnderlineHint",      { undercurl = true, sp = p.base0C })
    hi("DiagnosticVirtualTextError",   { fg = p.base08 })
    hi("DiagnosticVirtualTextWarn",    { fg = p.base0A })
    hi("DiagnosticVirtualTextInfo",    { fg = p.base0D })
    hi("DiagnosticVirtualTextHint",    { fg = p.base0C })
    hi("DiagnosticSignError",          { fg = p.base08 })
    hi("DiagnosticSignWarn",           { fg = p.base0A })
    hi("DiagnosticSignInfo",           { fg = p.base0D })
    hi("DiagnosticSignHint",           { fg = p.base0C })

    -- Messages
    hi("ErrorMsg",         { fg = p.base08, bold = true, italic = true })
    hi("WarningMsg",       { fg = p.base0A })
    hi("healthError",      { fg = p.base08 })
    hi("healthSuccess",    { fg = p.base0B })
    hi("healthWarning",    { fg = p.base0A })

    -- Syntax
    hi("Comment",          { fg = p.base03, italic = true })
    hi("String",           { fg = p.base0B })
    hi("Character",        { fg = p.base0B })
    hi("Number",           { fg = p.base09 })
    hi("Float",            { fg = p.base09 })
    hi("Boolean",          { fg = p.base09 })
    hi("Constant",         { fg = p.base09 })
    hi("Identifier",       { fg = p.base08 })
    hi("Function",         { fg = p.base0D })
    hi("Statement",        { fg = p.base0E })
    hi("Conditional",      { fg = p.base0E })
    hi("Repeat",           { fg = p.base0E })
    hi("Label",            { fg = p.base0E })
    hi("Operator",         { fg = p.base05 })
    hi("Keyword",          { fg = p.base0E })
    hi("Exception",        { fg = p.base0E })
    hi("PreProc",          { fg = p.base0A })
    hi("Include",          { fg = p.base0E })
    hi("Define",           { fg = p.base0E })
    hi("Macro",            { fg = p.base0E })
    hi("PreCondit",        { fg = p.base0A })
    hi("Type",             { fg = p.base0A })
    hi("StorageClass",     { fg = p.base0A })
    hi("Structure",        { fg = p.base0A })
    hi("Typedef",          { fg = p.base0A })
    hi("Special",          { fg = p.base0C })
    hi("SpecialChar",      { fg = p.base0C })
    hi("Tag",              { fg = p.base0A })
    hi("Delimiter",        { fg = p.base05 })
    hi("SpecialComment",   { fg = p.base0C })
    hi("Debug",            { fg = p.base08 })
    hi("Error",            { fg = p.base08 })
    hi("Todo",             { fg = p.base0A, bg = p.base01, bold = true })

    -- Treesitter
    hi("@variable",                    { fg = p.base05 })
    hi("@variable.builtin",            { fg = p.base09 })
    hi("@variable.parameter",          { fg = p.base08 })
    hi("@variable.member",             { fg = p.base08 })
    hi("@constant",                    { fg = p.base09 })
    hi("@constant.builtin",            { fg = p.base0E })
    hi("@constant.macro",              { fg = p.base0E })
    hi("@module",                      { fg = p.base0A })
    hi("@module.builtin",              { fg = p.base0C })
    hi("@label",                       { fg = p.base0E })
    hi("@string",                      { fg = p.base0B })
    hi("@string.regexp",               { fg = p.base08 })
    hi("@string.escape",               { fg = p.base0C })
    hi("@string.special.url",          { fg = p.base0D, underline = true })
    hi("@string.special.symbol",       { fg = p.base0E })
    hi("@character",                   { fg = p.base0B })
    hi("@character.special",           { fg = p.base0C })
    hi("@boolean",                     { fg = p.base09 })
    hi("@number",                      { fg = p.base09 })
    hi("@number.float",                { fg = p.base09 })
    hi("@type",                        { fg = p.base0A })
    hi("@type.builtin",                { fg = p.base0A })
    hi("@type.definition",             { fg = p.base0A })
    hi("@attribute",                   { fg = p.base09 })
    hi("@attribute.builtin",           { fg = p.base09 })
    hi("@property",                    { fg = p.base08 })
    hi("@function",                    { fg = p.base0D })
    hi("@function.builtin",            { fg = p.base0C })
    hi("@function.call",               { fg = p.base0D })
    hi("@function.method",             { fg = p.base0D })
    hi("@function.method.call",        { fg = p.base0D })
    hi("@constructor",                 { fg = p.base0A })
    hi("@operator",                    { fg = p.base05 })
    hi("@keyword",                     { fg = p.base0E })
    hi("@keyword.coroutine",           { fg = p.base08 })
    hi("@keyword.function",            { fg = p.base0E })
    hi("@keyword.operator",            { fg = p.base05 })
    hi("@keyword.import",              { fg = p.base0E })
    hi("@keyword.type",                { fg = p.base0E })
    hi("@keyword.modifier",            { fg = p.base0E })
    hi("@keyword.repeat",              { fg = p.base0E })
    hi("@keyword.return",              { fg = p.base0E })
    hi("@keyword.debug",               { fg = p.base0E })
    hi("@keyword.exception",           { fg = p.base0E })
    hi("@keyword.conditional",         { fg = p.base0E })
    hi("@keyword.conditional.ternary", { fg = p.base05 })
    hi("@keyword.directive",           { fg = p.base0A })
    hi("@keyword.directive.define",    { fg = p.base0E })
    hi("@keyword.export",              { fg = p.base0C })
    hi("@punctuation.delimiter",       { fg = p.base05 })
    hi("@punctuation.bracket",         { fg = p.base05 })
    hi("@punctuation.special",         { fg = p.base0C })
    hi("@comment",                     { fg = p.base03, italic = true })
    hi("@comment.documentation",       { fg = p.base03, italic = true })
    hi("@comment.error",               { fg = p.base00, bg = p.base08 })
    hi("@comment.warning",             { fg = p.base00, bg = p.base0A })
    hi("@comment.todo",                { fg = p.base00, bg = p.base0D })
    hi("@comment.note",                { fg = p.base00, bg = p.base0C })
    hi("@markup",                      { fg = p.base05 })
    hi("@markup.strong",               { fg = p.base05, bold = true })
    hi("@markup.italic",               { fg = p.base05, italic = true })
    hi("@markup.strikethrough",        { fg = p.base05, strikethrough = true })
    hi("@markup.underline",            { underline = true })
    hi("@markup.heading",              { fg = p.base0D, bold = true })
    hi("@markup.quote",                { fg = p.base0C })
    hi("@markup.math",                 { fg = p.base0D })
    hi("@markup.link",                 { fg = p.base0A })
    hi("@markup.link.url",             { fg = p.base0E, underline = true })
    hi("@markup.link.label",           { fg = p.base0E })
    hi("@markup.raw",                  { fg = p.base0C })
    hi("@markup.list",                 { fg = p.base0C })
    hi("@markup.list.checked",         { fg = p.base0B })
    hi("@markup.list.unchecked",       { fg = p.base03 })
    hi("@tag",                         { fg = p.base0E })
    hi("@tag.builtin",                 { fg = p.base0C })
    hi("@tag.attribute",               { fg = p.base0D })
    hi("@tag.delimiter",               { fg = p.base05 })
    hi("@diff.plus",                   { fg = p.base0B })
    hi("@diff.minus",                  { fg = p.base08 })
    hi("@diff.delta",                  { fg = p.base0D })
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

      colorschemePlugin = pkgs.vimUtils.buildVimPlugin {
        name = "gruvbox-polarity";
        src = pkgs.runCommand "gruvbox-polarity-src" { } ''
          mkdir -p $out/colors
          cp ${pkgs.writeText "gruvbox-dark.lua" (mkScheme "gruvbox-dark" config.themes.palette.dark)} \
            $out/colors/gruvbox-dark.lua
          cp ${pkgs.writeText "gruvbox-light.lua" (mkScheme "gruvbox-light" config.themes.palette.light)} \
            $out/colors/gruvbox-light.lua
        '';
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
            colorschemePlugin
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
          luaConfigRC.gruvbox-polarity = nvfDag.entryAfter [ "optionsScript" ] /* lua */ ''
            local function is_dark()
              return vim.fn.system("defaults read -g AppleInterfaceStyle 2>/dev/null"):find("Dark") ~= nil
            end
            local function apply_scheme()
              vim.cmd(is_dark() and "colorscheme gruvbox-dark" or "colorscheme gruvbox-light")
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
