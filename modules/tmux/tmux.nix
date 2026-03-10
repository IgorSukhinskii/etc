{ ... }:
{
  flake.homeManagerModules.tmux =
    { pkgs, ... }:
    let
      paneCenterScript = pkgs.writeScriptBin "tmux-pane-center" (
        "#!${pkgs.nushell}/bin/nu\n" + builtins.readFile ./tmux-pane-center.nu
      );
      paneNavScript = pkgs.writeScriptBin "tmux-nav" (
        "#!${pkgs.nushell}/bin/nu\n" + builtins.readFile ./tmux-nav.nu
      );
      sessionizer = pkgs.writeShellScriptBin "sessionizer" ''
        selected=$(printf '%s\n' ~/etc ~/vault \
          $(find ~/code -maxdepth 1 -mindepth 1 -type d 2>/dev/null) \
          | ${pkgs.fzf}/bin/fzf --tmux 40%)
        [ -z "$selected" ] && exit 0
        name=$(basename "$selected" | tr . _)
        tmux has-session -t "$name" 2>/dev/null || tmux new-session -ds "$name" -c "$selected"
        tmux switch-client -t "$name"
      '';
      # builtins.fromJSON decodes \uXXXX at eval time, keeping source ASCII-safe
      capL = builtins.fromJSON ''"\uE0B6"''; # left rounded half-circle
      capR = builtins.fromJSON ''"\uE0B4"''; # right rounded half-circle
      # Base16 ANSI slot semantics (hold across all Stylix themes)
      bg = "colour0"; # base00 — terminal background (text on coloured pills)
      yellow = "colour3"; # base0A — yellow/warm accent
      blue = "colour4"; # base0D — blue/cool accent
      fg = "colour7"; # base05 — terminal foreground (inactive/subtle pills)
      # Rounded pill: capL + coloured fill + capR.
      # Each #[attr] is a separate block — no commas in ternary branches,
      # safe to embed in #{?client_prefix,...} without escaping.
      pill =
        {
          color,
          content,
          bold ? false,
        }:
        "#[fg=${color}]#[bg=default]${capL}"
        + "#[fg=${bg}]#[bg=${color}]"
        + (if bold then "#[bold]" else "")
        + "${content}"
        + "#[fg=${color}]#[bg=default]"
        + (if bold then "#[nobold]" else "")
        + "${capR}";
      timePillNormal = pill {
        color = fg;
        content = "%H:%M";
      };
      timePillPrefix = pill {
        color = yellow;
        content = "%H:%M";
        bold = true;
      };

      terminalConfig = ''
        set -g renumber-windows on
        set -g extended-keys on
        set -g focus-events on

        # True color + image passthrough (sixel/kitty for ghostty)
        set -as terminal-features ",xterm-ghostty:RGB:extkeys"
        set -g allow-passthrough on
        set -ga update-environment TERM_PROGRAM
      '';

      keymapConfig = ''
        # Change prefix from Ctrl-b to Ctrl-a
        unbind C-b
        set -g prefix C-a
        bind-key C-a send-prefix

        # Ctrl+Tab / Ctrl+Shift+Tab to cycle windows without prefix
        bind -n C-Tab   next-window
        bind -n C-BTab  previous-window

        # Quick jump to named sessions (prefix + e/n)
        bind e switch-client -t etc
        bind n switch-client -t notes

        # Copy-on-select (vi mode)
        bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-selection-no-clear

        # Pane split shortcuts preserving current path
        bind | split-window -h -c "#{pane_current_path}"
        bind - split-window -v -c "#{pane_current_path}"

        # Reload config
        bind r source-file ~/.config/tmux/tmux.conf \; display "config reloaded"

        # Session picker via sessionizer
        bind C-s run-shell "sessionizer"

        # Workspace layout (create standard windows)
        bind C-w run-shell "tmux-layout"

        # Ring-buffer pane navigation (wrapping, auto-centers)
        bind -n M-j run-shell "tmux-nav D"
        bind -n M-k run-shell "tmux-nav U"

        # Window scrolling (horizontal axis)
        bind -n M-h previous-window
        bind -n M-l next-window

        # Center current pane without moving (e.g. after mouse click)
        bind -n M-Space run-shell "tmux-pane-center"

        # Zoom/focus toggle
        bind -n M-z resize-pane -Z
      '';

      statuslineConfig = ''
        # Status bar on top with rounded-pill style
        set -g status-position top
        set -g status-left-length 40
        set -g status-right-length 20
        set -g status-interval 60

        # Session pill: yellow background
        set -g status-left '${
          pill {
            color = yellow;
            content = " #S ";
            bold = true;
          }
        }  ' # two-space separator at the end

        # Window pills: inactive = fg (colour7), active = blue (colour4)
        set -g window-status-separator ""
        set -g window-status-format '${
          pill {
            color = fg;
            content = "#W";
          }
        } ' # one-space separator at the end
        set -g window-status-current-format '${
          pill {
            color = blue;
            content = "#W";
            bold = true;
          }
        } ' # one-space separator at the end

        # Time pill: fg normally, yellow when prefix held
        set -g status-right '#{?client_prefix,${timePillPrefix},${timePillNormal}}'
      '';
    in
    {
      home.packages = [
        sessionizer
        paneCenterScript
        paneNavScript
        pkgs.nushell
      ];

      programs.tmux = {
        enable = true;
        keyMode = "vi";
        mouse = true;
        baseIndex = 1;
        escapeTime = 0;
        terminal = "tmux-256color";
        extraConfig = terminalConfig + keymapConfig + statuslineConfig;
      };
    };
}
