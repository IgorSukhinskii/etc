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
    telescope = {
      enable = true;
      setupOpts = {
        defaults = {
          layout_strategy = "flex";
        };
      };
    };
    luaConfigRC.telescope = builtins.readFile ./telescope.lua;
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
  };
}
