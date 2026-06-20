# Host-local: WSL-singular terminal. wezterm runs on the Windows side and reads
# its config from native NTFS (see the activation block below), so this module
# only makes sense on the WSL host and is appended directly to its
# home-manager.sharedModules rather than living in the global module registry.
{
  pkgs,
  config,
  lib,
  ...
}:
let
  d = config.themes.palette.dark;
  l = config.themes.palette.light;

  # Renders a base24 palette attrset as a Lua table literal.
  mkPaletteTable =
    palette: "{ ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k} = '#${v}',") palette)} }";
in
{
  # Mirror the generated config to the Windows side on rebuild so wezterm
  # reads it from native NTFS. Avoids the 9P startup tax, lets the terminal
  # launch when WSL is down, and restores live config-reload on edits.
  home.activation.installWeztermConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    winHome=/mnt/c/Users/igor.sukhinskii
    if [ -d "$winHome" ]; then
      run install -Dm644 \
        ${config.home.homeDirectory}/.config/wezterm/wezterm.lua \
        "$winHome/.config/wezterm/wezterm.lua"
    fi
  '';

  home.file.".config/wezterm/wezterm.lua".text = # lua
    ''
      local wezterm = require 'wezterm'
      local act = wezterm.action
      local config = wezterm.config_builder()

      config.default_prog = { 'wsl.exe', '--cd', '~' }
      config.window_decorations = 'RESIZE'
      config.enable_tab_bar = false
      config.enable_kitty_keyboard = true
      config.audible_bell = 'Disabled'
      config.font = wezterm.font('JetBrainsMono Nerd Font')

      -- wezterm's default ctrl+tab / ctrl+shift+tab swap tabs; we have no
      -- tabs (tmux is the multiplexer), so pass the KKP encodings through
      -- so tmux can see them. Mirrors modules/ghostty.nix.
      config.keys = {
        { key = 'Tab', mods = 'CTRL',       action = act.SendString '\x1b[9;5u' },
        { key = 'Tab', mods = 'CTRL|SHIFT', action = act.SendString '\x1b[9;6u' },
      }

      -- Single base24 → wezterm.colors mapping, applied to whichever
      -- palette the OS appearance picks. Mirrors modules/themes/ghostty.nix.
      local function colors_from(p)
        return {
          foreground    = p.base05,
          background    = p.base00,
          cursor_bg     = p.base05,
          cursor_fg     = p.base00,
          cursor_border = p.base05,
          selection_bg  = p.base02,
          selection_fg  = p.base05,
          ansi    = { p.base00, p.base08, p.base0B, p.base0A, p.base0D, p.base0E, p.base0C, p.base05 },
          brights = { p.base03, p.base12, p.base14, p.base13, p.base16, p.base17, p.base15, p.base07 },
          -- Extra base24 slots, mirrors modules/themes/ghostty.nix indices 16-21.
          indexed = {
            [16] = p.base09,
            [17] = p.base0F,
            [18] = p.base01,
            [19] = p.base02,
            [20] = p.base04,
            [21] = p.base06,
          },
        }
      end

      local palettes = {
        dark  = ${mkPaletteTable d},
        light = ${mkPaletteTable l},
      }

      -- wezterm reloads this file when the OS appearance changes, so a
      -- plain get_appearance() call here gives live polarity switching.
      local appearance = wezterm.gui.get_appearance()
      local palette = appearance:find('Dark') and palettes.dark or palettes.light
      config.colors = colors_from(palette)

      return config
    '';
}
