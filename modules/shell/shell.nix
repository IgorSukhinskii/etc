{ ... }:
{
  home.shell.enableZshIntegration = true;

  home.shellAliases = {
    rebuild = "sudo darwin-rebuild switch --flake ~/etc";
    v = "nvim";
  };

  programs.zsh = {
    enable = true;
    sessionVariables = {
      EDITOR = "nvim";
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
}
