{ ... }:
{
  flake.homeManagerModules.tmux =
    { pkgs, ... }:
    let
      whichKeyInit =
        pkgs.runCommand "tmux-which-key-init-quiet" { nativeBuildInputs = [ pkgs.ripgrep ]; }
          ''
            rg -v '^display -p.*\[tmux-which-key\]' \
              ${pkgs.tmuxPlugins.tmux-which-key}/share/tmux-plugins/tmux-which-key/plugin/init.example.tmux \
              > $out
          '';
      sessionizer = pkgs.writeShellScriptBin "sessionizer" ''
        selected=$(printf '%s\n' ~/etc ~/vault \
          $(find ~/code -maxdepth 1 -mindepth 1 -type d 2>/dev/null) \
          | ${pkgs.fzf}/bin/fzf --tmux 40%)
        [ -z "$selected" ] && exit 0
        name=$(basename "$selected" | tr . _)
        tmux has-session -t "$name" 2>/dev/null || tmux new-session -ds "$name" -c "$selected"
        tmux switch-client -t "$name"
      '';
    in
    {
      home.packages = [ sessionizer ];

      programs.fzf.enable = true;

      programs.tmux = {
        enable = true;
        keyMode = "vi";
        mouse = true;
        baseIndex = 1;
        escapeTime = 0;
        terminal = "tmux-256color";
        plugins = [ ];
        extraConfig = ''
          set -g extended-keys on

          # True color + image passthrough (sixel/kitty for ghostty)
          set -as terminal-features ",ghostty:RGB"
          set -g allow-passthrough on
          set -ga update-environment TERM_PROGRAM

          # Ctrl+Tab / Ctrl+Shift+Tab to cycle windows without prefix
          bind -n C-Tab   next-window
          bind -n C-S-Tab previous-window

          # Quick jump to named sessions (prefix + e/n)
          bind e switch-client -t etc
          bind n switch-client -t notes

          # Status bar: show prefix indicator (native, no plugin)
          set -g status-right '#{?client_prefix,#[reverse] ^B #[noreverse] ,} %H:%M'

          # Copy-on-select (vi mode)
          bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-selection-no-clear

          # Pane split shortcuts preserving current path
          bind | split-window -h -c "#{pane_current_path}"
          bind - split-window -v -c "#{pane_current_path}"

          # Session picker via sessionizer
          bind s run-shell "sessionizer"

          # which-key: source pre-built init file from the nix store directly.
          # plugin.sh.tmux (the normal run-shell entry point) tries to cp files
          # into the read-only nix store and exits via `set -e`, so Space binding
          # is never registered. Sourcing init.example.tmux bypasses that entirely.
          source-file ${whichKeyInit}
        '';
      };
    };
}
