let
  lang = {
    enable = true;
    format.enable = true;
    lsp.enable = true;
    treesitter.enable = true;
  };
in
{
  enable = true;

  settings.vim = {
    viAlias = true;
    vimAlias = true;
    clipboard = {
      enable = true;
      registers = "unnamed,unnamedplus";
    };
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
    binds = {
      whichKey = {
        enable = true;
      };
    };
    languages = {
      nix = lang // {
        lsp.servers = [ "nixd" ];
        format.type = [ "nixfmt" ];
      };
      python = lang // {
        lsp.enable = false;
      };
      ts = lang;
      bash = lang;
      lua = lang;
    };
    visuals.indent-blankline.enable = true;
    ui.illuminate.enable = true;
    ui.noice.enable = true;
  };
}
