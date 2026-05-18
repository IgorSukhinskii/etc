{ ... }:
{
  flake.homeManagerModules.tmuxLayout =
    { pkgs, lib, ... }:
    let
      windows = [
        {
          name = "code";
          cmd = "nvim";
        }
        {
          name = "ai";
          cmd = "claude --dangerously-skip-permissions";
        }
        {
          name = "git";
          cmd = "lazygit";
        }
        {
          name = "shell";
          cmd = "";
        }
      ];
      declEntries = lib.concatMapStringsSep "\n  " (w: ''WINS[${w.name}]="${w.cmd}"'') windows;
      windowOrder = lib.concatStringsSep " " (map (w: w.name) windows);
      tmuxLayout = pkgs.writeShellScriptBin "tmux-layout" ''
        if [ -z "$TMUX" ]; then
          echo "tmux-layout: must be run inside a tmux session" >&2
          exit 1
        fi

        declare -A WINS
        ${declEntries}

        session_root=$(tmux display-message -p '#{session_path}')
        existing=$(tmux list-windows -F '#W' 2>/dev/null)

        for name in ${windowOrder}; do
          echo "$existing" | grep -qx "$name" && continue

          cmd="''${WINS[$name]}"
          tmux new-window -d -n "$name" -c "$session_root"
          [ -n "$cmd" ] && tmux send-keys -t ":$name" "$cmd" Enter
          true
        done
      '';
    in
    {
      home.packages = [
        tmuxLayout
      ];
    };
}
