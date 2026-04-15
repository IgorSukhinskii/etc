{ ... }:
{
  flake.darwinModules.terminal-fonts =
    { pkgs, ... }:
    {
      fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];
    };

  flake.homeManagerModules.terminal =
    { pkgs, ... }:
    {
      programs.ghostty = {
        enable = true;
        package = pkgs.ghostty-bin;
        settings = {
          macos-titlebar-style = "hidden";
          macos-option-as-alt = "left";
          background-opacity = 0.9;
          background-opacity-cells = true;
          font-family = "JetBrainsMono Nerd Font";
          theme = "dark:gruvbox-dark,light:gruvbox-light";
          # ghostty `unbind` removes its own action but macOS text-input has no
          # terminal encoding for Ctrl+Tab, so the key is silently dropped.
          # `csi:` explicitly sends the kitty keyboard protocol sequence to the PTY:
          # \e[9;5u = Tab (code 9), Ctrl modifier (5 in KKP); \e[9;6u = Ctrl+Shift
          keybind = [
            "ctrl+tab=csi:9;5u"
            "ctrl+shift+tab=csi:9;6u"
          ];
        };
      };
    };
}
