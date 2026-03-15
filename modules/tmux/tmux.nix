{ ... }:
{
  flake.homeManagerModules.tmux =
    { pkgs, config, ... }:
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
      # Base16 hex colors from Stylix — all 16 available, theme-safe.
      # config.lib.stylix.colors.baseXX returns hex without '#' (e.g. "1e1e2e").
      c = config.lib.stylix.colors;
      bg = "#${c.base00}"; # terminal background
      fgDim = "#${c.base04}"; # dark foreground / Surface2
      fg = "#${c.base05}"; # default foreground
      yellow = "#${c.base0A}";
      blue = "#${c.base0D}";
      # (omitting red/orange/brown — add if needed)
      # Primitive: left cap + content on `color` bg, then reset to default.
      # Standalone-safe (resets bg after content) and composable (pillRight overrides bg next).
      pillLeft =
        {
          color,
          content,
          bold ? false,
          textColor ? bg,
        }:
        "#[fg=${color}]#[bg=default]${capL}"
        + "#[fg=${textColor}]#[bg=${color}]"
        + (if bold then "#[bold]" else "")
        + content
        + "#[fg=${color}]#[bg=default]"
        + (if bold then "#[nobold]" else "");

      # Primitive: set `color` bg + content + right cap.
      # When placed immediately after pillLeft, the bg override creates the visual split.
      pillRight =
        {
          color,
          content,
          bold ? false,
          textColor ? bg,
        }:
        "#[fg=${textColor}]#[bg=${color}]"
        + (if bold then "#[bold]" else "")
        + content
        + "#[fg=${color}]#[bg=default]"
        + (if bold then "#[nobold]" else "")
        + capR;

      # Single-color rounded pill — backward-compatible, built from primitives.
      # pillLeft resets to default; pillRight re-sets same color, creating a seamless pill.
      pill =
        {
          color,
          content,
          bold ? false,
          textColor ? bg,
        }:
        pillLeft {
          inherit color bold;
          content = "";
        }
        + pillRight {
          inherit
            color
            content
            bold
            textColor
            ;
        };
      timePillNormal = pill {
        color = fg;
        content = "%H:%M";
      };
      timePillPrefix = pill {
        color = yellow;
        content = "%H:%M";
        bold = true;
      };
      # Calendar pill — shows next meeting title + start time via ical (EventKit CLI).
      calPill = pill {
        color = blue;
        content = "  #(${nextMeetingScript}/bin/tmux-next-meeting)";
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
        set -g status-right-length 60
        set -g status-interval 30

        # Session pill: yellow background
        set -g status-left '${
          pill {
            color = yellow;
            content = " #S ";
            bold = true;
          }
        }  ' # two-space separator at the end

        # Window pills: split-pill (#index|title)
        set -g window-status-separator " "
        set -g window-status-format '${
          pillLeft {
            color = fg;
            content = "#I ";
          }
        }${
          pillRight {
            color = fgDim;
            content = " #W";
            textColor = fg;
          }
        }'
        set -g window-status-current-format '${
          pillLeft {
            color = blue;
            content = "#I ";
            bold = true;
          }
        }${
          pillRight {
            color = fg;
            content = " #W";
          }
        }'

        set -g status-right '#{?#{==:#{#(${nextMeetingScript}/bin/tmux-next-meeting)},},,${calPill} }#{?client_prefix,${timePillPrefix},${timePillNormal}}'
      '';
      nextMeetingScript = pkgs.writeShellScriptBin "tmux-next-meeting" ''
        export PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:$PATH"
        output=$(ical upcoming -n 1 -o json --no-color 2>/dev/null)
        [ -z "$output" ] || [ "$output" = "[]" ] && exit 0
        title=$(echo "$output" | ${pkgs.jq}/bin/jq -r '.[0].title' 2>/dev/null)
        start=$(echo "$output" | ${pkgs.jq}/bin/jq -r '.[0].start_date' 2>/dev/null)
        time=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$start" "+%H:%M" 2>/dev/null)
        printf '%s %s\n' "$title" "$time" | cut -c1-28
      '';
    in
    {
      home.packages = [
        sessionizer
        paneCenterScript
        paneNavScript
        nextMeetingScript
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
