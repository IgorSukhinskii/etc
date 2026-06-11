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
      limaHome = "\${XDG_STATE_HOME:-$HOME/.local/state}/private-vm/lima";
      # User-facing username inside the VM (RDP login, owns home data).
      # Bootstrap/ops user is hardcoded "nixos" — see hosts/private-vm/bootstrap.nix.
      vmUser = inputs.self.privateVm.username;

      # Touch ID + Keychain helpers for encrypted home volume.
      # touchIdPrompt: store path to the Swift script; call as /usr/bin/swift ${touchIdPrompt} "<reason>".
      # privateVmKeychainSet: one-time setup that stores the LUKS passphrase.
      keychainHelper = import ../hosts/private-vm/keychain-helper.nix { inherit pkgs vmUser; };
      touchIdPrompt = keychainHelper.touchIdPrompt;
      privateVmKeychainSet = keychainHelper.privateVmKeychainSet;

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
        # Build the bootstrap qcow. --impure is required because the image
        # bakes in Lima's per-host agent pubkey ($LIMA_HOME/_config/user.pub)
        # as the trust anchor for first SSH. That's the only host-specific
        # read; everything else (real pubkey, password hash) is pushed at
        # runtime.
        set -euo pipefail

        export LIMA_HOME="${limaHome}"
        mkdir -p "$LIMA_HOME/_config"

        # Ensure Lima's bootstrap identity exists before the impure Nix build
        # reads it from hosts/private-vm/bootstrap.nix. `limactl info` reports
        # the path but does not create the key on its own.
        if [[ ! -f "$LIMA_HOME/_config/user" || ! -f "$LIMA_HOME/_config/user.pub" ]]; then
          ssh-keygen -q -t ed25519 -N "" -C lima -f "$LIMA_HOME/_config/user"
        fi

        exec nix build --impure "${flakeDir}#private-vm-image" "$@"
      '';

      privateVmStart = pkgs.writeShellScriptBin "private-vm-start" ''
        # Boot the Lima VM and wait for SSH. No RDP tunnel here — that's
        # private-vm-rdp's job. Idempotent.
        set -euo pipefail

        flake_dir="${flakeDir}"
        template="$flake_dir/hosts/private-vm/lima.yaml"
        export LIMA_HOME="${limaHome}"
        rendered="$LIMA_HOME/_private-vm-rendered.yaml"
        limactl="${pkgs.lima}/bin/limactl"

        if [[ ! -f "$LIMA_HOME/_config/user.pub" ]]; then
          echo "Lima identity missing — rebuilding image for new LIMA_HOME..." >&2
          "${privateVmBuild}/bin/private-vm-build" >&2
        fi

        # Upstream system.build.images names the qcow after system.nixos.label,
        # not "nixos.qcow2" — glob for it.
        if ! image=$(ls "$flake_dir"/result/*.qcow2 2>/dev/null | head -1) || [[ -z "$image" ]]; then
          echo "image missing — building..." >&2
          "${privateVmBuild}/bin/private-vm-build" >&2
          image=$(ls "$flake_dir"/result/*.qcow2 | head -1)
        fi

        mkdir -p "$(dirname "$rendered")"
        sed "s|PLACEHOLDER_IMAGE_PATH|$image|" "$template" > "$rendered"

        status=$("$limactl" list --format '{{.Status}}' private-vm 2>/dev/null || echo "Missing")
        # --timeout=20s: in plain mode Lima's SSH-readiness check tries to
        # exec a script that reads from /mnt/lima-cidata/param.env, which
        # plain mode never mounts. The check then hangs until the default
        # 10-minute timeout. Cut that short — our own wait loop below
        # verifies SSH is actually reachable.
        case "$status" in
          Running) echo "VM already running" >&2 ;;
          Stopped) "$limactl" start --timeout=20s private-vm --tty=false >&2 || true ;;
          *)       "$limactl" start --timeout=20s --name=private-vm "$rendered" --tty=false >&2 || true ;;
        esac

        # Wait for SSH. cloud-init runs at first boot so this can take longer
        # on a fresh VM (image cold-start + cloud-init + sshd).
        for i in {1..90}; do
          if ssh -F "$LIMA_HOME/private-vm/ssh.config" -o BatchMode=yes \
               -o ConnectTimeout=2 lima-private-vm true 2>/dev/null; then
            echo "VM ready" >&2
            exit 0
          fi
          sleep 1
        done
        echo "VM did not become SSH-reachable in 90s" >&2
        exit 1
      '';

      privateVmSsh = pkgs.writeShellScriptBin "private-vm-ssh" ''
        # SSH as the user-facing user (set in hosts/private-vm/vars.nix) — the
        # account you'd want for terminal/tmux work. The `nixos` bootstrap user
        # is reserved for private-vm-rebuild and not surfaced here.
        #
        # ControlPath override: SSH multiplexes by (host, port) using the
        # ControlPath from ssh.config. private-vm-rebuild opens that master as
        # nixos, so a default `-o User=${vmUser}` would silently reuse the
        # nixos channel. Per-user socket = independent multiplexing.
        #
        # Note: this only works after the first successful private-vm-rebuild,
        # since that's what creates the user + installs their pubkey.
        export LIMA_HOME="${limaHome}"
        exec ssh -F "$LIMA_HOME/private-vm/ssh.config" \
          -o User=${vmUser} \
          -o ControlPath="$LIMA_HOME/private-vm/ssh-${vmUser}.sock" \
          -o ControlMaster=auto \
          -o ControlPersist=600 \
          lima-private-vm "$@"
      '';

      privateVmRebuild = pkgs.writeShellScriptBin "private-vm-rebuild" ''
        # Idempotent provision + rebuild. Always SSHes as `nixos` (the
        # bootstrap user — Lima's ssh.config bakes that in at first start).
        # Pushes:
        #   - passwd.hash (xrdp PAM)
        #   - ${vmUser}.pub (real user's SSH key, for private-vm-ssh)
        # both into /var/lib/private-vm/. Rotation = re-run this with new
        # source files. Then rsyncs etc/ → /home/nixos/etc and runs
        # nixos-rebuild switch inside the VM (uses the VM's own builder —
        # no host linux-builder involvement after the initial image).
        set -euo pipefail

        "${privateVmStart}/bin/private-vm-start"

        export LIMA_HOME="${limaHome}"
        ssh_cfg="$LIMA_HOME/private-vm/ssh.config"
        flake_dir="${flakeDir}"

        # If the home disk is LUKS-initialized but not yet mounted, unlock
        # before running nixos-rebuild. home-manager activation writes dotfiles
        # to /home/${vmUser}; without the encrypted volume mounted those writes
        # land on the root disk and get shadowed on first unlock.
        if ssh -F "$ssh_cfg" lima-private-vm "sudo cryptsetup isLuks /dev/vdb" 2>/dev/null; then
          if ! ssh -F "$ssh_cfg" lima-private-vm "mountpoint -q /home/${vmUser}" 2>/dev/null; then
            echo "home volume not mounted — unlocking..." >&2
            "${privateVmUnlock}/bin/private-vm-unlock"
          fi
        fi
        passwd_hash="''${XDG_CONFIG_HOME:-$HOME/.config}/private-vm/passwd.hash"
        pubkey="$HOME/.ssh/id_ed25519.pub"
        lima_pubkey="$LIMA_HOME/_config/user.pub"

        for f in "$passwd_hash" "$pubkey" "$lima_pubkey"; do
          if [[ ! -f "$f" ]]; then
            echo "missing required file: $f" >&2
            exit 1
          fi
        done

        ssh -F "$ssh_cfg" lima-private-vm 'sudo mkdir -p /var/lib/private-vm'
        scp -F "$ssh_cfg" "$passwd_hash"  lima-private-vm:/tmp/passwd.hash
        scp -F "$ssh_cfg" "$pubkey"       lima-private-vm:/tmp/${vmUser}.pub
        scp -F "$ssh_cfg" "$lima_pubkey"  lima-private-vm:/tmp/lima.pub
        ssh -F "$ssh_cfg" lima-private-vm '
          sudo install -m0600 /tmp/passwd.hash    /var/lib/private-vm/passwd.hash &&
          sudo install -m0644 /tmp/${vmUser}.pub  /var/lib/private-vm/${vmUser}.pub &&
          sudo install -m0644 /tmp/lima.pub       /var/lib/private-vm/lima.pub &&
          rm -f /tmp/passwd.hash /tmp/${vmUser}.pub /tmp/lima.pub
        '

        ${pkgs.rsync}/bin/rsync -az --delete \
          --exclude='.git' \
          --exclude='.direnv' \
          --exclude='result' \
          --exclude='result-*' \
          -e "ssh -F $ssh_cfg" \
          "$flake_dir/" lima-private-vm:etc/

        ssh -F "$ssh_cfg" lima-private-vm \
          'sudo nixos-rebuild switch --flake "$HOME/etc#private-vm"'
      '';

      privateVmRdp = pkgs.writeShellScriptBin "private-vm-rdp" ''
        # Ensure VM up + RDP tunnel up + password from Keychain → launch FreeRDP.
        # First-time setup:
        #   security add-generic-password -a igor -s private-vm-rdp -w
        # The xrdp session starts whatever openbox autostarts (Firefox by
        # default in full.nix).
        set -euo pipefail

        "${privateVmStart}/bin/private-vm-start"
        "${privateVmUnlock}/bin/private-vm-unlock"

        export LIMA_HOME="${limaHome}"
        ssh_cfg="$LIMA_HOME/private-vm/ssh.config"
        if ! ${pkgs.lsof}/bin/lsof -iTCP:3389 -sTCP:LISTEN >/dev/null 2>&1; then
          ssh -F "$ssh_cfg" -L 3389:127.0.0.1:3389 -N -f lima-private-vm
          echo "RDP tunnel: 127.0.0.1:3389 -> private-vm:3389" >&2
        fi

        if ! pw=$(security find-generic-password -a ${vmUser} -s private-vm-rdp -w 2>/dev/null); then
          echo "No keychain entry. Create one with:" >&2
          echo "  security add-generic-password -a ${vmUser} -s private-vm-rdp -w" >&2
          exit 1
        fi

        # Prefer sdl-freerdp (SDL backend, native macOS) over xfreerdp (X11,
        # needs XQuartz). nixpkgs' freerdp 3.x ships both.
        if command -v sdl-freerdp >/dev/null 2>&1; then
          rdp=sdl-freerdp
        elif command -v xfreerdp >/dev/null 2>&1; then
          rdp=xfreerdp
        else
          rdp=""
        fi

        if [[ -n "$rdp" ]]; then
          # Note: /p: places the password in argv (visible in `ps`). Fine on a
          # single-user laptop; harden via askpass if that ever changes.
          # /sound:sys:mac — CoreAudio backend; /sound:sys:pulse crashes on
          # macOS because PulseAudio doesn't exist and the disconnect handler
          # assert-fails when the channel can't initialise.
          exec "$rdp" /v:127.0.0.1:3389 /u:${vmUser} "/p:$pw" \
            /dynamic-resolution /size:1600x1000 /scale:140 \
            /sound:sys:mac +clipboard /cert:ignore
        else
          printf '%s' "$pw" | pbcopy
          echo "No FreeRDP found. Password copied to clipboard." >&2
          echo "Connect with Windows App to 127.0.0.1:3389 as ${vmUser}." >&2
        fi
      '';

      privateVmStop = pkgs.writeShellScriptBin "private-vm-stop" ''
        # Stop the VM and tear down any RDP tunnel.
        set -euo pipefail
        export LIMA_HOME="${limaHome}"
        limactl="${pkgs.lima}/bin/limactl"

        pids=$(${pkgs.lsof}/bin/lsof -iTCP:3389 -sTCP:LISTEN -t 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
          kill $pids || true
        fi

        "$limactl" stop private-vm 2>&1 | tail -3
      '';

      privateVmProjectNew = pkgs.writeShellScriptBin "private-vm-project-new" ''
        # Create a new VM-backed project: host stub in ~/projects/<name> with a
        # .private-vm marker, and matching ~/projects/<name> inside the VM.
        set -euo pipefail

        name="''${1:-}"
        if [[ -z "$name" ]]; then
          echo "usage: private-vm-project-new <name>" >&2
          exit 1
        fi

        host_dir="$HOME/projects/$name"
        vm_dir="~/projects/$name"
        marker="$host_dir/.private-vm"

        if [[ -e "$host_dir" ]]; then
          echo "error: $host_dir already exists" >&2
          exit 1
        fi

        "${privateVmStart}/bin/private-vm-start"
        "${privateVmUnlock}/bin/private-vm-unlock"

        mkdir -p "$host_dir"
        printf 'VM_DIR=%s\n' "$vm_dir" > "$marker"

        "${privateVmSsh}/bin/private-vm-ssh" "mkdir -p $vm_dir"

        echo "created: $host_dir (stub)" >&2
        echo "created: $vm_dir (inside VM)" >&2
        echo "switch with: sessionizer → $name" >&2
      '';

      privateVmInitHome = pkgs.writeShellScriptBin "private-vm-init-home" ''
        # One-time: format /dev/vdb as LUKS + ext4, mount at /home/${vmUser}.
        # Run AFTER private-vm-keychain-set and BEFORE the first private-vm-rebuild.
        # SSH uses the nixos bootstrap account — igor doesn't exist yet at this stage.
        # Pre-requisite:
        #   LIMA_HOME=${limaHome} limactl disk create private-home --size 40GiB
        set -euo pipefail

        export LIMA_HOME="${limaHome}"
        ssh_cfg="$LIMA_HOME/private-vm/ssh.config"
        vm_nixos() { ssh -F "$ssh_cfg" lima-private-vm "$@"; }

        "${privateVmStart}/bin/private-vm-start"

        # Verify the additional disk is attached
        if ! vm_nixos "test -b /dev/vdb" 2>/dev/null; then
          echo "error: /dev/vdb not found." >&2
          echo "Create the Lima disk first:" >&2
          echo "  LIMA_HOME=$LIMA_HOME ${pkgs.lima}/bin/limactl disk create private-home --size 40GiB" >&2
          exit 1
        fi

        # Guard: refuse to re-format an already-initialized LUKS volume
        if vm_nixos "sudo cryptsetup isLuks /dev/vdb" 2>/dev/null; then
          echo "error: /dev/vdb is already a LUKS volume — home already initialized." >&2
          echo "Use private-vm-unlock to open it." >&2
          echo "To start over: limactl disk delete private-home && limactl disk create private-home --size 40GiB" >&2
          exit 1
        fi

        echo "This will format /dev/vdb as a LUKS-encrypted ext4 home volume." >&2
        echo "ALL DATA on it will be destroyed. Type 'yes' to continue:" >&2
        read -r confirm
        [[ "$confirm" == "yes" ]] || { echo "Aborted." >&2; exit 1; }

        # Touch ID + passphrase from Keychain
        /usr/bin/swift "${touchIdPrompt}" "Initialize private-vm home volume"
        pw=$(security find-generic-password -a "${vmUser}" -s private-vm-luks -w)

        echo "Formatting LUKS container..." >&2
        printf '%s' "$pw" | vm_nixos \
          "sudo cryptsetup luksFormat --batch-mode --key-file=- /dev/vdb"

        echo "Opening LUKS container..." >&2
        printf '%s' "$pw" | vm_nixos \
          "sudo cryptsetup luksOpen --key-file=- /dev/vdb private-home"

        echo "Creating ext4 filesystem..." >&2
        vm_nixos "sudo mkfs.ext4 -L private-home /dev/mapper/private-home"

        echo "Mounting..." >&2
        vm_nixos "sudo mkdir -p /home/${vmUser} && sudo mount /dev/mapper/private-home /home/${vmUser}"

        echo "" >&2
        echo "Home volume initialized and mounted at /home/${vmUser}." >&2
        echo "Next: run private-vm-rebuild to provision the full config." >&2
      '';

      privateVmUnlock = pkgs.writeShellScriptBin "private-vm-unlock" ''
        # Open the LUKS home volume and mount it. Idempotent: no-op if already
        # mounted. Runs entirely over the `nixos` SSH channel so it works on a
        # virgin VM where the real user (${vmUser}) does not exist yet — this
        # is the path private-vm-rebuild takes on first provisioning.
        set -euo pipefail

        "${privateVmStart}/bin/private-vm-start"

        export LIMA_HOME="${limaHome}"
        ssh_cfg="$LIMA_HOME/private-vm/ssh.config"

        # Idempotent: skip Touch ID if already mounted
        if ssh -F "$ssh_cfg" lima-private-vm "mountpoint -q /home/${vmUser}" 2>/dev/null; then
          exit 0
        fi

        # Touch ID + passphrase from Keychain
        /usr/bin/swift "${touchIdPrompt}" "Unlock private-vm home volume"
        pw=$(security find-generic-password -a "${vmUser}" -s private-vm-luks -w)

        # Open LUKS container (passphrase via stdin). Guard for idempotency:
        # if /dev/mapper/private-home already exists, luksOpen would error.
        if ! ssh -F "$ssh_cfg" lima-private-vm "[ -e /dev/mapper/private-home ]" 2>/dev/null; then
          printf '%s' "$pw" | ssh -F "$ssh_cfg" lima-private-vm \
            "sudo cryptsetup luksOpen --key-file=- /dev/vdb private-home"
        fi

        # Explicit mount (not fstab-based): fstab entry comes from full.nix,
        # which has not yet been applied on a virgin VM. /home/${vmUser} also
        # may not exist yet — create it as the mountpoint.
        ssh -F "$ssh_cfg" lima-private-vm \
          "sudo mkdir -p /home/${vmUser} && sudo mount /dev/mapper/private-home /home/${vmUser}"
        echo "home volume unlocked and mounted" >&2
      '';

      privateVmLock = pkgs.writeShellScriptBin "private-vm-lock" ''
        # Unmount the home volume and close the LUKS container.
        set -euo pipefail
        "${privateVmSsh}/bin/private-vm-ssh" \
          "sudo umount /home/${vmUser} && sudo cryptsetup luksClose private-home"
        echo "home volume locked" >&2
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
          privateVmRebuild
          privateVmSsh
          privateVmRdp
          privateVmStop
          privateVmProjectNew
          privateVmKeychainSet
          privateVmInitHome
          privateVmUnlock
          privateVmLock
        ]
        ++ lib.optionals stdenv.isDarwin [
          nixDarwinModule
          lima
          freerdp
        ];

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
