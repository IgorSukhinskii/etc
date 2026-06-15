{ inputs, ... }:
{
  flake.homeManagerModules.private-vm =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      flakeDir = "${config.home.homeDirectory}/etc";
      limaHome = "\${XDG_STATE_HOME:-$HOME/.local/state}/private-vm/lima";
      imageLink = "\${XDG_DATA_HOME:-$HOME/.local/share}/private-vm/images/bootstrap";
      homeDisk = "$HOME/data/private-vm/home.qcow2";
      vmUser = inputs.self.privateVm.username;

      keychainHelper = import ../../hosts/private-vm/keychain-helper.nix { inherit pkgs vmUser; };
      touchIdPrompt = keychainHelper.touchIdPrompt;
      vmKeychainSet = keychainHelper.privateVmKeychainSet;

      vmEnsureVolumes = pkgs.writeShellScript "vm-ensure-volumes" ''
        set -euo pipefail

        require_home=0
        if [[ "''${1:-}" == "--require-home" ]]; then
          require_home=1
        fi

        export LIMA_HOME="${limaHome}"
        limactl="${pkgs.lima}/bin/limactl"
        home_disk="${homeDisk}"

        mkdir -p "$LIMA_HOME/_config" "$(dirname "$home_disk")"

        if [[ ! -f "$LIMA_HOME/_config/user" || ! -f "$LIMA_HOME/_config/user.pub" ]]; then
          ssh-keygen -q -t ed25519 -N "" -C lima -f "$LIMA_HOME/_config/user"
        fi

        disk_exists() {
          "$limactl" disk list 2>/dev/null | awk 'NR > 1 { print $1 }' | grep -Fxq "$1"
        }

        ensure_lima_disk() {
          local name="$1"
          local size="$2"
          if ! disk_exists "$name"; then
            "$limactl" disk create "$name" --size "$size" >&2
          fi
        }

        ensure_lima_disk private-nix 80GiB
        ensure_lima_disk private-persistence 8GiB

        home_dir="$LIMA_HOME/_disks/private-home"
        home_link="$home_dir/datadisk"
        mkdir -p "$home_dir"

        if [[ -L "$home_link" ]]; then
          target=$(readlink "$home_link")
          if [[ "$target" != "$home_disk" ]]; then
            echo "private-home datadisk points at unexpected target: $target" >&2
            exit 1
          fi
        elif [[ -e "$home_link" ]]; then
          if [[ -e "$home_disk" ]]; then
            home_size=$(stat -f%z "$home_disk")
            link_size=$(stat -f%z "$home_link")
            if [[ "$home_size" -le 1048576 && "$link_size" -ge 42949672960 ]]; then
              rm "$home_disk"
              mv "$home_link" "$home_disk"
              ln -s "$home_disk" "$home_link"
            else
              echo "refusing to overwrite existing Lima private-home datadisk: $home_link" >&2
              echo "home image also exists at: $home_disk" >&2
              exit 1
            fi
          else
            mv "$home_link" "$home_disk"
            ln -s "$home_disk" "$home_link"
          fi
        else
          ln -s "$home_disk" "$home_link"
        fi

        if [[ "$require_home" == 1 && ! -e "$home_disk" ]]; then
          truncate -s 40G "$home_disk"
        fi

        if [[ "$require_home" == 1 && ! -e "$home_disk" ]]; then
          echo "home disk image missing: $home_disk" >&2
          echo "run: vm init-home" >&2
          exit 1
        fi
      '';

      vmBuild = pkgs.writeShellScriptBin "vm-build" ''
        # Build the bootstrap qcow. --impure is required because the image
        # bakes in Lima's per-host agent pubkey ($LIMA_HOME/_config/user.pub)
        # as the trust anchor for first SSH. That's the only host-specific
        # read; everything else (real pubkey, password hash) is pushed at
        # runtime.
        #
        # linux-builder lifecycle: the launchd daemon is configured dormant
        # (RunAtLoad=false, KeepAlive=false in modules/darwin/nix.nix).
        # Kickstart it for the build, kill it after — combined with
        # ephemeral=true this keeps the builder out of RAM/disk at rest.
        set -euo pipefail

        export LIMA_HOME="${limaHome}"
        image_link="${imageLink}"
        mkdir -p "$(dirname "$image_link")"
        "${vmEnsureVolumes}"

        builder_label=system/org.nixos.linux-builder

        cleanup() {
          sudo /bin/launchctl kill TERM "$builder_label" 2>/dev/null || true
        }
        trap cleanup EXIT

        sudo /bin/launchctl kickstart "$builder_label"

        # Wait for the builder's SSH port. cold start of qemu + nixos boot
        # is typically 10-30s; cap at 120s.
        for i in $(seq 1 120); do
          if ${pkgs.netcat}/bin/nc -z localhost 31022 2>/dev/null; then
            break
          fi
          sleep 1
        done
        if ! ${pkgs.netcat}/bin/nc -z localhost 31022 2>/dev/null; then
          echo "linux-builder did not become reachable on :31022 within 120s" >&2
          exit 1
        fi

        nix build --impure --out-link "$image_link" "${flakeDir}#private-vm-image" "$@"
      '';

      vmStart = pkgs.writeShellScriptBin "vm-start" ''
        # Boot the Lima VM and wait for SSH. No RDP tunnel here — that's
        # vm rdp's job. Idempotent.
        set -euo pipefail

        flake_dir="${flakeDir}"
        template="$flake_dir/hosts/private-vm/lima.yaml"
        export LIMA_HOME="${limaHome}"
        image_link="${imageLink}"
        rendered="$LIMA_HOME/_private-vm-rendered.yaml"
        limactl="${pkgs.lima}/bin/limactl"

        "${vmEnsureVolumes}" --require-home

        # Upstream system.build.images names the qcow after system.nixos.label,
        # not "nixos.qcow2" — glob for it.
        if ! image=$(ls "$image_link"/*.qcow2 2>/dev/null | head -1) || [[ -z "$image" ]]; then
          echo "image missing — building..." >&2
          "${vmBuild}/bin/vm-build" >&2
          image=$(ls "$image_link"/*.qcow2 | head -1)
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

        wait_for_ssh() {
          local attempts="$1"
          for i in $(seq 1 "$attempts"); do
            if ssh -F "$LIMA_HOME/private-vm/ssh.config" -o BatchMode=yes \
                 -o ConnectTimeout=2 lima-private-vm true 2>/dev/null; then
              return 0
            fi
            sleep 1
          done
          return 1
        }

        # Wait for SSH. cloud-init runs at first boot so this can take longer
        # on a fresh VM (image cold-start + cloud-init + sshd).
        if ! wait_for_ssh 90; then
          echo "VM did not become SSH-reachable in 90s" >&2
          exit 1
        fi

        if ssh -F "$LIMA_HOME/private-vm/ssh.config" lima-private-vm \
             "test -e /run/private-vm/private-nix-reboot-required" 2>/dev/null; then
          echo "private-nix seeded — rebooting once to mount persistent /nix" >&2
          ssh -F "$LIMA_HOME/private-vm/ssh.config" lima-private-vm "sudo systemctl reboot" 2>/dev/null || true
          for i in {1..30}; do
            if ! ssh -F "$LIMA_HOME/private-vm/ssh.config" -o BatchMode=yes \
                 -o ConnectTimeout=2 lima-private-vm true 2>/dev/null; then
              break
            fi
            sleep 1
          done
          if wait_for_ssh 120; then
            echo "VM ready after private-nix reboot" >&2
            exit 0
          fi
          echo "VM did not return after private-nix seed reboot" >&2
          exit 1
        fi
        echo "VM ready" >&2
      '';

      vmSsh = pkgs.writeShellScriptBin "vm-ssh" ''
        # SSH as the user-facing account. The `nixos` bootstrap user is reserved
        # for vm rebuild and not surfaced here.
        #
        # ControlPath override: vm rebuild opens a master as nixos using the
        # ControlPath from ssh.config; a default `-o User=${vmUser}` would
        # silently reuse that nixos channel. Per-user socket = independent
        # multiplexing.
        #
        # Note: works only after the first successful vm rebuild, which creates
        # the user and installs their pubkey.
        export LIMA_HOME="${limaHome}"
        exec ssh -F "$LIMA_HOME/private-vm/ssh.config" \
          -o User=${vmUser} \
          -o ControlPath="$LIMA_HOME/private-vm/ssh-${vmUser}.sock" \
          -o ControlMaster=auto \
          -o ControlPersist=600 \
          lima-private-vm "$@"
      '';

      vmRebuild = pkgs.writeShellScriptBin "vm-rebuild" ''
        # Idempotent provision + rebuild. Always SSHes as `nixos` (the
        # bootstrap user — Lima's ssh.config bakes that in at first start).
        # Pushes:
        #   - passwd.hash (xrdp PAM)
        #   - ${vmUser}.pub (real user's SSH key, for vm ssh)
        # both into /var/lib/private-vm/. Rotation = re-run this with new
        # source files. Then rsyncs etc/ → /home/nixos/etc and runs
        # nixos-rebuild switch inside the VM (uses the VM's own builder —
        # no host linux-builder involvement after the initial image).
        set -euo pipefail

        "${vmStart}/bin/vm-start"

        export LIMA_HOME="${limaHome}"
        ssh_cfg="$LIMA_HOME/private-vm/ssh.config"
        flake_dir="${flakeDir}"

        # If the home disk is LUKS-initialized but not yet mounted, unlock
        # before running nixos-rebuild. home-manager activation writes dotfiles
        # to /home/${vmUser}; without the encrypted volume mounted those writes
        # land on the root disk and get shadowed on first unlock.
        if ssh -F "$ssh_cfg" lima-private-vm \
             'dev=$(sudo private-vm-disk-device private-home) && sudo cryptsetup isLuks "$dev"' 2>/dev/null; then
          if ! ssh -F "$ssh_cfg" lima-private-vm "mountpoint -q /home/${vmUser}" 2>/dev/null; then
            echo "home volume not mounted — unlocking..." >&2
            "${vmUnlock}/bin/vm-unlock"
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

      vmRdp = pkgs.writeShellScriptBin "vm-rdp" ''
        # Ensure VM up + RDP tunnel up + password from Keychain → launch FreeRDP.
        # First-time setup:
        #   security add-generic-password -a igor -s private-vm-rdp -w
        # The xrdp session starts whatever openbox autostarts (Firefox by
        # default in full.nix).
        set -euo pipefail

        "${vmStart}/bin/vm-start"
        "${vmUnlock}/bin/vm-unlock"

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

      vmStop = pkgs.writeShellScriptBin "vm-stop" ''
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

      vmNew = pkgs.writeShellScriptBin "vm-new" ''
        # Create a new VM-backed project: host stub in ~/projects/<name> with a
        # .private-vm marker, and matching ~/projects/<name> inside the VM.
        set -euo pipefail

        name="''${1:-}"
        if [[ -z "$name" ]]; then
          echo "usage: vm new <name>" >&2
          exit 1
        fi

        host_dir="$HOME/projects/$name"
        vm_dir="~/projects/$name"
        marker="$host_dir/.private-vm"

        if [[ -e "$host_dir" ]]; then
          echo "error: $host_dir already exists" >&2
          exit 1
        fi

        "${vmStart}/bin/vm-start"
        "${vmUnlock}/bin/vm-unlock"

        mkdir -p "$host_dir"
        printf 'VM_DIR=%s\n' "$vm_dir" > "$marker"

        "${vmSsh}/bin/vm-ssh" "mkdir -p $vm_dir"

        echo "created: $host_dir (stub)" >&2
        echo "created: $vm_dir (inside VM)" >&2
        echo "switch with: sessionizer → $name" >&2
      '';

      vmInitHome = pkgs.writeShellScriptBin "vm-init-home" ''
        # One-time: format the private-home disk as LUKS + ext4, mount at /home/${vmUser}.
        # Run AFTER vm keychain-set and BEFORE the first vm rebuild.
        # SSH uses the nixos bootstrap account — ${vmUser} doesn't exist yet at this stage.
        set -euo pipefail

        export LIMA_HOME="${limaHome}"
        ssh_cfg="$LIMA_HOME/private-vm/ssh.config"
        vm_nixos() { ssh -F "$ssh_cfg" lima-private-vm "$@"; }

        "${vmEnsureVolumes}" --require-home
        "${vmStart}/bin/vm-start"

        home_device=$(vm_nixos "sudo private-vm-disk-device private-home")
        if [[ -z "$home_device" ]]; then
          echo "error: private-home disk not found in Lima cidata." >&2
          exit 1
        fi

        # Guard: refuse to re-format an already-initialized LUKS volume
        if vm_nixos "sudo cryptsetup isLuks '$home_device'" 2>/dev/null; then
          echo "error: $home_device is already a LUKS volume — home already initialized." >&2
          echo "Use 'vm unlock' to open it." >&2
          echo "To start over, remove $HOME/data/private-vm/home.qcow2 manually." >&2
          exit 1
        fi

        echo "This will format $home_device as a LUKS-encrypted ext4 home volume." >&2
        echo "ALL DATA on it will be destroyed. Type 'yes' to continue:" >&2
        read -r confirm
        [[ "$confirm" == "yes" ]] || { echo "Aborted." >&2; exit 1; }

        # Touch ID + passphrase from Keychain
        /usr/bin/swift "${touchIdPrompt}" "Initialize private-vm home volume"
        pw=$(security find-generic-password -a "${vmUser}" -s private-vm-luks -w)

        echo "Formatting LUKS container..." >&2
        printf '%s' "$pw" | vm_nixos \
          "sudo cryptsetup luksFormat --batch-mode --key-file=- '$home_device'"

        echo "Opening LUKS container..." >&2
        printf '%s' "$pw" | vm_nixos \
          "sudo cryptsetup luksOpen --key-file=- '$home_device' private-home"

        echo "Creating ext4 filesystem..." >&2
        vm_nixos "sudo mkfs.ext4 -L private-home /dev/mapper/private-home"

        echo "Mounting..." >&2
        vm_nixos "sudo mkdir -p /home/${vmUser} && sudo mount /dev/mapper/private-home /home/${vmUser}"

        echo "" >&2
        echo "Home volume initialized and mounted at /home/${vmUser}." >&2
        echo "Next: run 'vm rebuild' to provision the full config." >&2
      '';

      vmUnlock = pkgs.writeShellScriptBin "vm-unlock" ''
        # Open the LUKS home volume and mount it. Idempotent: no-op if already
        # mounted. Runs entirely over the `nixos` SSH channel so it works on a
        # virgin VM where the real user (${vmUser}) does not exist yet — this
        # is the path vm rebuild takes on first provisioning.
        set -euo pipefail

        "${vmStart}/bin/vm-start"

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
          home_device=$(ssh -F "$ssh_cfg" lima-private-vm "sudo private-vm-disk-device private-home")
          printf '%s' "$pw" | ssh -F "$ssh_cfg" lima-private-vm \
            "sudo cryptsetup luksOpen --key-file=- '$home_device' private-home"
        fi

        # Explicit mount (not fstab-based): fstab entry comes from full.nix,
        # which has not yet been applied on a virgin VM. /home/${vmUser} also
        # may not exist yet — create it as the mountpoint.
        ssh -F "$ssh_cfg" lima-private-vm \
          "sudo mkdir -p /home/${vmUser} && sudo mount /dev/mapper/private-home /home/${vmUser}"
        echo "home volume unlocked and mounted" >&2
      '';

      vmLock = pkgs.writeShellScriptBin "vm-lock" ''
        # Unmount the home volume and close the LUKS container.
        # --force kicks any process holding /home/${vmUser} (SSH sessions, RDP
        # desktop, etc.) so the unmount can proceed.
        set -euo pipefail
        force=0
        case "''${1:-}" in
          -f|--force) force=1 ;;
          "") ;;
          *) echo "usage: vm lock [--force]" >&2; exit 1 ;;
        esac
        "${vmStart}/bin/vm-start"
        export LIMA_HOME="${limaHome}"
        ssh_cfg="$LIMA_HOME/private-vm/ssh.config"
        if [ "$force" = 1 ]; then
          ssh -F "$ssh_cfg" lima-private-vm "
            sudo loginctl terminate-user ${vmUser} 2>/dev/null || true
            sleep 1
            sudo pkill -KILL -u ${vmUser} 2>/dev/null || true
            sleep 1
            sudo umount /home/${vmUser}
            sync
            for i in 1 2 3 4 5; do
              sudo cryptsetup luksClose private-home && exit 0
              sleep 1
            done
            exit 1
          "
        else
          ssh -F "$ssh_cfg" lima-private-vm \
            "sudo umount /home/${vmUser} && sudo cryptsetup luksClose private-home"
        fi
        echo "home volume locked" >&2
      '';

      vm = pkgs.writeShellScriptBin "vm" ''
        set -euo pipefail
        cmd="''${1:-}"
        shift || true
        case "$cmd" in
          build)        exec "${vmBuild}/bin/vm-build" "$@" ;;
          start)        exec "${vmStart}/bin/vm-start" "$@" ;;
          stop)         exec "${vmStop}/bin/vm-stop" "$@" ;;
          ssh)          exec "${vmSsh}/bin/vm-ssh" "$@" ;;
          rebuild)      exec "${vmRebuild}/bin/vm-rebuild" "$@" ;;
          rdp)          exec "${vmRdp}/bin/vm-rdp" "$@" ;;
          lock)         exec "${vmLock}/bin/vm-lock" "$@" ;;
          unlock)       exec "${vmUnlock}/bin/vm-unlock" "$@" ;;
          new)          exec "${vmNew}/bin/vm-new" "$@" ;;
          init-home)    exec "${vmInitHome}/bin/vm-init-home" "$@" ;;
          keychain-set) exec "${vmKeychainSet}/bin/private-vm-keychain-set" "$@" ;;
          *)
            echo "usage: vm <command> [args]" >&2
            echo "" >&2
            echo "commands:" >&2
            echo "  start          boot the VM (builds image if needed)" >&2
            echo "  stop           shut down the VM" >&2
            echo "  build          build the bootstrap qcow image" >&2
            echo "  rebuild        deploy NixOS config to the VM" >&2
            echo "  ssh [args]     open a shell or run a command in the VM" >&2
            echo "  rdp            launch FreeRDP desktop session" >&2
            echo "  lock           unmount and close the encrypted home volume" >&2
            echo "  unlock         open and mount the encrypted home volume" >&2
            echo "  new <name>     create a new VM-backed project" >&2
            echo "  init-home      one-time: format and mount the home LUKS volume" >&2
            echo "  keychain-set   one-time: store the LUKS passphrase in Keychain" >&2
            exit 1 ;;
        esac
      '';
    in
    {
      home.packages = [
        vm
      ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        pkgs.lima
        pkgs.freerdp
      ];
    };
}
