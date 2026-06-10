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
          cmd = "claude";
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

        vm_ssh=$(tmux show-environment PRIVATE_VM_SSH 2>/dev/null | grep -v '^-' | sed 's/^PRIVATE_VM_SSH=//')
        vm_dir=$(tmux show-environment PRIVATE_VM_DIR 2>/dev/null | grep -v '^-' | sed 's/^PRIVATE_VM_DIR=//')

        for name in ${windowOrder}; do
          echo "$existing" | grep -qx "$name" && continue

          cmd="''${WINS[$name]}"
          if [[ -n "$vm_ssh" && -n "$cmd" ]]; then
            # Run the command inside the VM; drop back to a VM shell on exit.
            tmux new-window -d -n "$name" "$vm_ssh -t 'cd $vm_dir && $cmd; exec \$SHELL'"
          elif [[ -n "$vm_ssh" ]]; then
            # Shell window: default-command provides the VM shell.
            tmux new-window -d -n "$name"
          else
            tmux new-window -d -n "$name" -c "$session_root"
            [ -n "$cmd" ] && tmux send-keys -t ":$name" "$cmd" Enter
          fi
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
