{ inputs, ... }:
{
  flake.homeManagerModules.nix-dev =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      flakeDir = "${config.home.homeDirectory}/etc";

      nixHmModule = pkgs.writeShellScriptBin "nix-hm-module" ''
        # Print the home-manager programs/<name>.nix module for the HM version
        # pinned in flake.lock. Always reflects the pinned version.
        set -euo pipefail

        name=''${1:?Usage: nix-hm-module <program-name>}

        hm=$(nix eval --raw --impure --expr "(builtins.getFlake \"path:${flakeDir}\").inputs.home-manager.outPath" 2>/dev/null \
          || find /nix/store -maxdepth 1 -name "*home-manager*source*" -type d 2>/dev/null \
             | sort | tail -1)

        module="$hm/modules/programs/$name.nix"
        if [[ -f "$module" ]]; then
          cat "$module"
        else
          echo "Not found: $module" >&2
          echo "Partial name matches in $hm/modules/programs/:" >&2
          ls "$hm/modules/programs/" | rg -i "$name" >&2 || echo "(none)" >&2
          exit 1
        fi
      '';

      nixDarwinModule = pkgs.writeShellScriptBin "nix-darwin-module" ''
        # Print paths of nix-darwin module files matching <name>.
        # Output is file paths only — read the ones you need with the Read tool.
        set -euo pipefail

        name=''${1:?Usage: nix-darwin-module <module-name>}

        nd=$(nix eval --raw --impure --expr "(builtins.getFlake \"path:${flakeDir}\").inputs.nix-darwin.outPath" 2>/dev/null \
          || find /nix/store -maxdepth 1 -name "*nix-darwin*source*" -type d 2>/dev/null \
             | sort | tail -1)

        result=$(rg --files --iglob "*$name.nix" "$nd/modules" 2>/dev/null)
        if [[ -n "$result" ]]; then
          echo "$result"
        else
          echo "No module found for: $name" >&2
          exit 1
        fi
      '';

      nixSrcSearch = pkgs.writeShellScriptBin "nix-src-search" ''
        # Search an app's source in the nix store for files matching <file-glob>
        # that contain <pattern>. Prints file paths + matching lines (preview only).
        # Use the Read tool to get full file contents after identifying the right file.
        set -euo pipefail

        pkg=''${1:?Usage: nix-src-search <package> <file-glob> <grep-pattern>}
        glob=''${2:?provide a file glob e.g. "*.go" or "*.rs"}
        pattern=''${3:?provide a grep pattern e.g. "Pagers|Config"}

        src=$(nix eval --raw "nixpkgs#$pkg.src.outPath" 2>/dev/null \
          || find /nix/store -maxdepth 1 -iname "*''${pkg}*" -type d 2>/dev/null | head -1)

        if [[ -z "$src" ]]; then
          echo "No store path found for: $pkg" >&2
          exit 1
        fi

        if [[ ! -d "$src" ]]; then
          echo "Source not in store, fetching: $src" >&2
          nix build --no-link "nixpkgs#''${pkg}.src" >&2
        fi

        echo "Searching in: $src"
        echo ""
        rg -l --glob "$glob" "$pattern" "$src" 2>/dev/null \
          | head -20 \
          | while read -r f; do
              echo "--- $f ---"
              rg -n "$pattern" "$f" | head -10
              echo ""
            done
      '';

      privateVmBuild = pkgs.writeShellScriptBin "private-vm-build" ''
        # Build the private-vm qcow image. --impure is required because the
        # config reads ~/.ssh/id_ed25519.pub directly from the host (kept out
        # of the repo). Extra args are forwarded to nix build.
        set -euo pipefail
        exec nix build --impure "${flakeDir}#private-vm-image" "$@"
      '';

      privateVmStart = pkgs.writeShellScriptBin "private-vm-start" ''
        # Boot the private-vm Lima instance (plain mode) and open an SSH tunnel
        # for RDP. Idempotent: safe to run repeatedly.
        set -euo pipefail

        flake_dir="${flakeDir}"
        image="$flake_dir/result/nixos.qcow2"
        template="$flake_dir/hosts/private-vm/lima.yaml"
        rendered="$HOME/.lima/_private-vm-rendered.yaml"
        limactl="${pkgs.lima}/bin/limactl"

        if [[ ! -e "$image" ]]; then
          echo "image missing — building..." >&2
          "${privateVmBuild}/bin/private-vm-build" >&2
        fi

        mkdir -p "$(dirname "$rendered")"
        sed "s|PLACEHOLDER_IMAGE_PATH|$image|" "$template" > "$rendered"

        status=$("$limactl" list --format '{{.Status}}' private-vm 2>/dev/null || echo "Missing")
        case "$status" in
          Running) echo "VM already running" >&2 ;;
          Stopped) "$limactl" start private-vm --tty=false >&2 || true ;;
          *)       "$limactl" start --name=private-vm "$rendered" --tty=false >&2 || true ;;
        esac

        # Wait for SSH to actually answer (lima's "fatal" timeout doesn't mean dead).
        for i in {1..60}; do
          if ssh -F "$HOME/.lima/private-vm/ssh.config" -o BatchMode=yes \
               -o ConnectTimeout=2 lima-private-vm true 2>/dev/null; then
            break
          fi
          sleep 1
        done

        # Open RDP tunnel if not already up.
        if ! ${pkgs.lsof}/bin/lsof -iTCP:3389 -sTCP:LISTEN >/dev/null 2>&1; then
          ssh -F "$HOME/.lima/private-vm/ssh.config" \
              -L 3389:127.0.0.1:3389 -N -f lima-private-vm
          echo "RDP tunnel: 127.0.0.1:3389 -> private-vm:3389" >&2
        else
          echo "RDP tunnel already established" >&2
        fi

        echo "Ready. SSH: ssh -F ~/.lima/private-vm/ssh.config lima-private-vm" >&2
      '';

      privateVmStop = pkgs.writeShellScriptBin "private-vm-stop" ''
        # Stop the private-vm Lima instance and tear down the RDP tunnel.
        set -euo pipefail
        limactl="${pkgs.lima}/bin/limactl"

        # Kill any SSH tunnel forwarding 3389.
        pids=$(${pkgs.lsof}/bin/lsof -iTCP:3389 -sTCP:LISTEN -t 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
          kill $pids || true
        fi

        "$limactl" stop private-vm 2>&1 | tail -3
      '';

      nixRebuild = pkgs.writeShellScriptBin "nix-rebuild" ''
        # Rebuild and switch to the nix-darwin config for this machine.
        # Uses short hostname as config attribute.
        set -euo pipefail

        flake_dir="${flakeDir}"
        hostname=$(hostname -s | tr '[:upper:]' '[:lower:]')

        if [[ "$(uname -s)" == "Darwin" ]]; then
          exec sudo darwin-rebuild switch --flake "''${flake_dir}#''${hostname}"
        else
          exec sudo nixos-rebuild switch --flake "''${flake_dir}#''${hostname}"
        fi
      '';

      nixfmtHook = pkgs.writeShellScript "pre-commit-nixfmt" ''
        set -eo pipefail
        staged=$(git diff --cached --name-only --diff-filter=ACM | grep '\.nix$' || true)
        [ -z "$staged" ] && exit 0
        ${pkgs.nixfmt}/bin/nixfmt $staged
        changed=$(git diff --name-only $staged)
        if [ -n "$changed" ]; then
          echo "nixfmt: reformatted files, please git add and re-commit:"
          printf '%s\n' $changed
          exit 1
        fi
      '';
    in
    {
      home.packages =
        with pkgs;
        [
          ripgrep
          nixd
          nixfmt
          nixHmModule
          nixSrcSearch
          nixRebuild
          privateVmBuild
          privateVmStart
          privateVmStop
        ]
        ++ lib.optionals stdenv.isDarwin [ nixDarwinModule ];

      # Neovim nix language support — colocated here so formatter stays in sync
      # with the pre-commit hook below. Both use nixfmt (RFC 166 style).
      programs.nvf.settings.vim.languages.nix = {
        enable = true;
        format = {
          enable = true;
          type = [ "nixfmt" ];
        };
        lsp = {
          enable = true;
          servers = [ "nixd" ];
        };
        treesitter.enable = true;
      };

      home.activation.installNixfmtHook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p "${flakeDir}/.git/hooks"
        $DRY_RUN_CMD ln -sf ${nixfmtHook} "${flakeDir}/.git/hooks/pre-commit"
      '';
    };
}
