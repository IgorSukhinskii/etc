{ ... }:
{
  flake.homeManagerModules.tmux =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      paneCenterScript = pkgs.writeScriptBin "tmux-pane-center" (
        "#!${pkgs.nushell}/bin/nu\n" + builtins.readFile ./tmux-pane-center.nu
      );
      paneNavScript = pkgs.writeScriptBin "tmux-nav" (
        "#!${pkgs.nushell}/bin/nu\n" + builtins.readFile ./tmux-nav.nu
      );

      cfg = config.programs.tmux.sessionizer;

      # bash array literal: (~/etc ~/vault ~)
      directPathsBash = "(${lib.concatMapStringsSep " " (d: d.path) cfg.directDirs})";

      # bash associative array entries: ["~/etc"]="" ["~"]="default"
      nameOverridesBash = lib.concatMapStrings (d: "[\"${d.path}\"]=\"${d.name}\" ") cfg.directDirs;

      # find commands for each scan dir, one per line
      scanFindsBash = lib.concatMapStringsSep "\n  " (
        d: "find ${d} -maxdepth 1 -mindepth 1 -type d 2>/dev/null"
      ) cfg.scanDirs;

      sessionizer = pkgs.writeShellScriptBin "sessionizer" ''
        declare -A SESSION_NAMES=(${nameOverridesBash})
        direct_paths=${directPathsBash}

        scan_results=$(
          ${scanFindsBash}
        )

        direct_display=$(printf '%s\n' "''${direct_paths[@]}" | sed "s|^$HOME|~|")
        scan_display=$(echo "$scan_results" | sed "s|^$HOME|~|")

        selected=$(printf '%s\n%s' "$direct_display" "$scan_display" \
          | sed '/^[[:space:]]*$/d' \
          | ${pkgs.fzf}/bin/fzf --tmux 40%)
        [ -z "$selected" ] && exit 0

        path=$(echo "$selected" | sed "s|^~|$HOME|")

        if [ -n "''${SESSION_NAMES[$selected]+x}" ] && [ -n "''${SESSION_NAMES[$selected]}" ]; then
          name="''${SESSION_NAMES[$selected]}"
        else
          name=$(basename "$path" | tr . _)
        fi

        tmux has-session -t "$name" 2>/dev/null || tmux new-session -ds "$name" -c "$path"
        tmux switch-client -t "$name"
      '';
      # builtins.fromJSON decodes \uXXXX at eval time, keeping source ASCII-safe
      capL = builtins.fromJSON ''"\uE0B6"''; # left rounded half-circle
      capR = builtins.fromJSON ''"\uE0B4"''; # right rounded half-circle
      # ANSI terminal color references — tmux reads these from the terminal palette,
      # so Ghostty's polarity switch propagates automatically (no hook needed).
      bg = "colour0"; # ANSI 0  = base00 (background)
      bgDim = "colour19"; # ANSI 19  = base02 (dimer background)
      fg = "colour7"; # ANSI 7  = base05 (foreground)
      yellow = "colour3"; # ANSI 3  = base0A (yellow)
      blue = "colour4"; # ANSI 4  = base0D (blue)
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
        set -g extended-keys-format csi-u
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
        set -g status-style default
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
            color = bgDim;
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
      options.programs.tmux.sessionizer = {
        directDirs = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                path = lib.mkOption { type = lib.types.str; };
                name = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                };
              };
            }
          );
          default = [ ];
        };
        scanDirs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      };

      config = {
        programs.tmux.sessionizer.directDirs = [
          { path = "~/etc"; }
          { path = "~/vault"; }
          {
            path = "~";
            name = "default";
          }
        ];
        programs.tmux.sessionizer.scanDirs = [
          "~/code"
          "~/projects"
        ];

        home.packages = [
          sessionizer
          paneCenterScript
          paneNavScript
          nextMeetingScript
          pkgs.nushell
        ];

        home.shellAliases.mux = "tmux new -A -s default -c ~/";

        programs.tmux = {
          enable = true;
          keyMode = "vi";
          mouse = true;
          baseIndex = 1;
          escapeTime = 0;
          terminal = "tmux-256color";
          # Clear __HM_SESS_VARS_SOURCED from tmux's server environment so that
          # each new pane gets a fresh run of hm-session-vars.sh (picking up any
          # new session variables added by a nix-rebuild). Without this, the tmux
          # server inherits the guard from the shell that started it and new panes
          # always skip re-sourcing. Subshells within a pane are unaffected because
          # the guard is set normally once the pane's own shell has sourced the file.
          extraConfig = ''
            set-environment -gu __HM_SESS_VARS_SOURCED
          ''
          + terminalConfig
          + keymapConfig
          + statuslineConfig;
        };
      };
    };
}
