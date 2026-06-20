{ ... }:
{
  flake.darwinModules.terminal-fonts =
    { pkgs, ... }:
    {
      fonts.packages = [
        pkgs.nerd-fonts.jetbrains-mono # kept as plain-font fallback
        pkgs.nerd-fonts.symbols-only # Nerd Font icon glyphs for Iosevka
      ];
    };

  flake.homeManagerModules.terminal =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      opacity = 1.0;
      # This file is owned by the iosevka build script after first build.
      # The activation script below bootstraps it with the JetBrains fallback.
      iosevkaConf = "${config.xdg.configHome}/ghostty/iosevka.conf";
    in
    {
      # Create iosevka.conf with a sane default if it doesn't exist yet.
      # The build script (~/etc/iosevka/build.sh) overwrites it on each build.
      home.activation.bootstrapIosevkaFont = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f "${iosevkaConf}" ]; then
          echo "font-family = JetBrainsMono Nerd Font" > "${iosevkaConf}"
        fi
      '';

      programs.ghostty = {
        enable = true;
        package = pkgs.ghostty-bin;
        settings = {
          macos-titlebar-style = "hidden";
          macos-option-as-alt = "left";
          background-opacity = opacity;
          background-opacity-cells = true;
          # font-family lives in iosevka.conf; config-file is processed here (after b/c-*)
          config-file = iosevkaConf;
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
