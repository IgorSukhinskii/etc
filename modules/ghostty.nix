{ ... }:
{
  flake.homeManagerModules.terminal =
    { pkgs, ... }:
    {
      programs.ghostty = {
        enable = true;
        package = pkgs.ghostty-bin;
        settings = {
          macos-titlebar-style = "hidden";
          background-opacity = 0.9;
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
