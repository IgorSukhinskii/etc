{ ... }:
{
  flake.homeManagerModules.terminal = { pkgs, ... }: {
    programs.ghostty = {
      enable = true;
      package = pkgs.ghostty-bin;
      settings = {
        macos-titlebar-style = "hidden";
        background-opacity = 0.9;
      };
    };

    programs.tmux = {
      enable = true;
      keyMode = "vi";
      mouse = true;
      plugins = with pkgs.tmuxPlugins; [
        tmux-which-key
        prefix-highlight
      ];
    };
  };
}
