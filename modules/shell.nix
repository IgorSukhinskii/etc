{ ... }:
{
  flake.homeManagerModules.shell =
    { config, ... }:
    {
      xdg.enable = true;

      home.shell.enableZshIntegration = true;

      home.shellAliases = {
        v = "nvim";
      };

      programs.zsh = {
        enable = true;
        dotDir = "${config.xdg.configHome}/zsh";
        sessionVariables = {
          EDITOR = "nvim";
          VISUAL = "nvim";
        };
      };

      programs.starship = {
        enable = true;
      };

      programs.atuin = {
        enable = true;
      };

      programs.carapace = {
        enable = true;
      };

      programs.nix-your-shell = {
        enable = true;
      };
    };
}
