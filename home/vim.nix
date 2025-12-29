let
  lang = {
    enable = true;
    format.enable = true;
    lsp.enable = true;
    treesitter.enable = true;
  };
in {
  enable = true;

  settings.vim = {
    # additionalRuntimePaths = [ ./nvim ];
    viAlias = true;
    vimAlias = true;
    clipboard = {
      enable = true;
      registers = "unnamed,unnamedplus";
    };
    lsp = {
      enable = true;
      formatOnSave = true;
      lightbulb.enable = true;
    };
    telescope = {
      enable = true;
    };
    binds = {
      whichKey = {
        enable = true;
      };
    };
    languages = {
      nix =
        lang
        // {
          lsp.servers = ["nixd"];
          format.type = ["nixfmt"];
        };
      python = lang;
      ts = lang;
    };
  };
}
