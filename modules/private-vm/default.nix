{ inputs, ... }:
{
  # xpra's nixpkgs derivation is Linux-only (xorg-server, pulseaudioFull,
  # python-uinput, systemd, …). Upstream ships macOS as a separate py2app
  # bundle; the brew cask wraps it. Install the cask on the host so the
  # `vm gui` launcher has an `xpra` binary on PATH.
  flake.darwinModules.private-vm =
    { ... }:
    {
      # age-plugin-se from Homebrew: Touch ID-gated Secure Enclave access for
      # the LUKS passphrase store. A nix-built copy of the plugin can't talk
      # to the SE (codesigning context not preserved through the sandbox).
      homebrew.brews = [ "age-plugin-se" ];
      homebrew.casks = [ "xpra" ];
    };

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

      secretHelper = import ../../hosts/private-vm/secret-helper.nix { inherit pkgs vmUser; };
      privateVmSecret = secretHelper.privateVmSecret;

      # Lima looks up qemu via $QEMU_SYSTEM_AARCH64 before PATH (see Lima's
      # pkg/driver/qemu/qemu.go Exe()). We point that env var at this wrapper
      # so Lima invokes it exactly as it would the real qemu. On real VM
      # start we inject:
      #   virtio-balloon-pci:  FPR → guest returns freed pages to host
      #   virtio-gpu-pci:      2D virtio GPU → guest gets a DRM device so
      #                        Mesa EGL can run via software (llvmpipe), which
      #                        xpra's --opengl=yes uses for GL compositing.
      #
      # Hardware GPU (rutabaga) status (2026-06-17):
      #   rutabaga_gfx supports Darwin and the nixpkgs override builds cleanly
      #   (needs install_name_tool postInstall fix for the dylib). But:
      #   - QEMU 10.x: virtio-gpu-rutabaga crashes in virtio_memory_listener_commit
      #     (NULL deref during device realize) — upstream QEMU bug.
      #   - QEMU 11.x: rutabaga device initializes, but HVF fails with an SDK
      #     assertion in hvf/sysreg.c.inc (HV_SYS_REG_SMCR_EL1 value mismatch).
      #     rutabaga + TCG works but is too slow to be useful.
      #   Revisit when nixpkgs ships QEMU ≥ 11 with the HVF assertion fixed.
      #
      # Probe invocations (--version, -accel help, etc.) don't carry -machine
      # virt, so they pass through unchanged.
      realQemu = "${pkgs.qemu}/bin/qemu-system-aarch64";
      qemuWrapperBin = pkgs.writeShellApplication {
        name = "qemu-system-aarch64";
        runtimeInputs = [ ];
        text = ''
          # Detect "real VM start" vs Lima probe (--version, -accel help,
          # etc.). Real starts always include the aarch64 `virt` machine,
          # passed by Lima 2.x as a single argv element `virt,accel=hvf`
          # (not bare `virt`). Match the prefix.
          is_start=0
          for arg in "$@"; do
            if [[ "$arg" == virt || "$arg" == virt,* ]]; then
              is_start=1
              break
            fi
          done

          if (( is_start == 0 )); then
            exec ${realQemu} "$@"
          fi

          exec ${realQemu} "$@" \
            -device virtio-balloon-pci,free-page-reporting=on \
            -device virtio-gpu-pci
        '';
      };
      # Lima resolves firmware (EDK2 edk2-aarch64-code.fd) relative to the
      # qemu binary's directory. Compose a small prefix where bin/ holds our
      # wrapper and share/ symlinks pkgs.qemu's share tree (firmware lives
      # there).
      qemuWrapper = pkgs.runCommand "qemu-system-aarch64-fpr-wrapper" { } ''
        mkdir -p $out/bin
        ln -s ${qemuWrapperBin}/bin/qemu-system-aarch64 $out/bin/qemu-system-aarch64
        ln -s ${pkgs.qemu}/share $out/share
      '';

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
        # Boot the Lima VM and wait for SSH. Idempotent.
        set -euo pipefail

        flake_dir="${flakeDir}"
        template="$flake_dir/hosts/private-vm/lima.yaml"
        export LIMA_HOME="${limaHome}"
        image_link="${imageLink}"
        rendered="$LIMA_HOME/_private-vm-rendered.yaml"
        limactl="${pkgs.lima}/bin/limactl"

        # Lima looks up qemu via this env var before falling back to PATH
        # (Lima's pkg/driver/qemu/qemu.go Exe()). The wrapper injects
        # -device virtio-balloon-pci,free-page-reporting=on so freed guest
        # pages are returned to the macOS host (Free Page Reporting).
        export QEMU_SYSTEM_AARCH64="${qemuWrapper}/bin/qemu-system-aarch64"

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
        #   - passwd.hash (user password hash, for sudo)
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

      vmGui = pkgs.writeShellScriptBin "vm-gui" ''
        # Attach an xpra client to the guest's :100 server over SSH. The
        # guest runs a persistent, headless xpra server as a user systemd
        # unit (full.nix). Apps launched in the guest with DISPLAY=:100 —
        # the default in the guest user's session env — render into that
        # server. This command surfaces those windows on the Mac as native
        # macOS windows. Closing the windows does not stop the server;
        # closing this client does not stop the apps.
        #
        # No additional ports: xpra speaks its protocol over the SSH
        # stdio channel via the ssh:// URL scheme. Reuses Lima's SSH
        # config so authentication is identical to `vm ssh`.
        set -euo pipefail
        export LIMA_HOME="${limaHome}"
        ssh_cfg="$LIMA_HOME/private-vm/ssh.config"

        "${vmStart}/bin/vm-start"

        # xpra is the brew cask (Linux-only in nixpkgs). Invoke the app
        # bundle binary directly: the /opt/homebrew/bin/xpra symlink
        # routes through a launcher script that uses $0's dirname to
        # locate PythonExecWrapper, which breaks under the symlink.
        # The cask also installs unsigned-and-quarantined; if Gatekeeper
        # kills xpra on first run, strip quarantine once:
        #   xattr -dr com.apple.quarantine /Applications/Xpra.app
        #
        # Per-user ControlPath (same pattern as vm-ssh): Lima's
        # ssh.config has `User nixos` baked in and a shared ControlPath.
        # With ControlMaster auto + ControlPersist, plain `-l ${vmUser}`
        # silently multiplexes through the existing nixos channel and
        # xpra's UDS peercred check fails (uid mismatch). Force a fresh,
        # ${vmUser}-owned ssh transport.
        # --encoding=h264: with the guest GPU (virtio-gpu-gl-pci +
        # virglrenderer), xpra uses its GL compositing path and can encode
        # via h264. On a loopback VM h264 is smoother than rgb for scrolling
        # (fewer full-frame sends) and macOS decodes it in VideoToolbox.
        # --quality=95: high quality, still visually lossless for UI text.
        # --speed=100: prioritise frame rate over compression ratio
        # (bandwidth is free on loopback).
        exec /Applications/Xpra.app/Contents/MacOS/Xpra attach \
          --ssh="ssh -F $ssh_cfg -l ${vmUser} -o ControlPath=$LIMA_HOME/private-vm/ssh-${vmUser}.sock -o ControlMaster=auto -o ControlPersist=600" \
          --encoding=h264 \
          --quality=95 \
          --speed=100 \
          "ssh://${vmUser}@lima-private-vm/100"
      '';

      vmStop = pkgs.writeShellScriptBin "vm-stop" ''
        set -euo pipefail
        export LIMA_HOME="${limaHome}"
        "${pkgs.lima}/bin/limactl" stop private-vm 2>&1 | tail -3
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
        # Run AFTER vm secret-set and BEFORE the first vm rebuild.
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

        # Touch ID is enforced inside `private-vm-secret get` by the
        # Secure Enclave's access control on the age identity's private
        # key — no separate app-level prompt.
        #
        # init-home needs the passphrase for two cryptsetup invocations
        # (luksFormat then luksOpen). We prefer one Touch ID prompt over
        # two, so we pipe the secret into a single SSH session that
        # consumes it once and reuses it via a guest-side shell variable.
        # The exposure is guest-side only; on the host the secret never
        # lands in a shell variable, env var, or temp file.
        #
        # `pw=$(cat)` slurps stdin verbatim — the secret has no trailing
        # newline (cryptsetup's --key-file=- treats stdin bytes as raw key
        # data, including any trailing newline). `read -r` would refuse a
        # final line without a newline under `set -e`.
        #
        # Sensitive SSH bypasses the persistent ControlMaster socket so
        # the secret-carrying channel is its own transport.
        echo "Formatting and opening LUKS container, then mounting..." >&2
        ${privateVmSecret}/bin/private-vm-secret get | ssh -F "$ssh_cfg" \
          -o ControlMaster=no \
          -o ControlPath=none \
          -o ControlPersist=no \
          -o ForwardAgent=no \
          -o ClearAllForwardings=yes \
          -o PermitLocalCommand=no \
          -o RequestTTY=no \
          -o LogLevel=ERROR \
          lima-private-vm "
            set -euo pipefail
            pw=\$(cat)
            printf '%s' \"\$pw\" | sudo cryptsetup luksFormat --batch-mode --key-file=- '$home_device'
            printf '%s' \"\$pw\" | sudo cryptsetup luksOpen   --key-file=- '$home_device' private-home
            unset pw
            sudo mkfs.ext4 -L private-home /dev/mapper/private-home
            sudo mkdir -p /home/${vmUser}
            sudo mount /dev/mapper/private-home /home/${vmUser}
          "

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

        # Sensitive SSH: per-invocation transport (no ControlMaster reuse,
        # no agent forwarding, no port/x forwardings, no local command).
        # See TOUCHID-SSH-HARDENING.md §4–§5.
        ssh_secret() {
          ssh -F "$ssh_cfg" \
            -o ControlMaster=no \
            -o ControlPath=none \
            -o ControlPersist=no \
            -o ForwardAgent=no \
            -o ClearAllForwardings=yes \
            -o PermitLocalCommand=no \
            -o RequestTTY=no \
            -o LogLevel=ERROR \
            lima-private-vm "$@"
        }

        # Open LUKS container. Guard for idempotency: if the mapper
        # device already exists, skip the second luksOpen (which would
        # error). The secret never lands in a host-side shell variable —
        # `private-vm-secret get` writes the raw passphrase bytes to stdout
        # (no trailing newline issues — `cryptsetup --key-file=-` reads up
        # to the first newline or EOF) and pipes directly into the remote
        # `cryptsetup --key-file=-`.
        if ! ssh -F "$ssh_cfg" lima-private-vm "[ -e /dev/mapper/private-home ]" 2>/dev/null; then
          home_device=$(ssh -F "$ssh_cfg" lima-private-vm "sudo private-vm-disk-device private-home")
          ${privateVmSecret}/bin/private-vm-secret get | \
            ssh_secret "sudo cryptsetup luksOpen --key-file=- '$home_device' private-home"
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
          gui)          exec "${vmGui}/bin/vm-gui" "$@" ;;
          lock)         exec "${vmLock}/bin/vm-lock" "$@" ;;
          unlock)       exec "${vmUnlock}/bin/vm-unlock" "$@" ;;
          new)          exec "${vmNew}/bin/vm-new" "$@" ;;
          init-home)       exec "${vmInitHome}/bin/vm-init-home" "$@" ;;
          secret-set)      exec "${privateVmSecret}/bin/private-vm-secret" set "$@" ;;
          secret-get)      exec "${privateVmSecret}/bin/private-vm-secret" get "$@" ;;
          secret-delete)   exec "${privateVmSecret}/bin/private-vm-secret" delete "$@" ;;
          *)
            echo "usage: vm <command> [args]" >&2
            echo "" >&2
            echo "commands:" >&2
            echo "  start          boot the VM (builds image if needed)" >&2
            echo "  stop           shut down the VM" >&2
            echo "  build          build the bootstrap qcow image" >&2
            echo "  rebuild        deploy NixOS config to the VM" >&2
            echo "  ssh [args]     open a shell or run a command in the VM" >&2
            echo "  gui            attach an xpra client (surface guest GUI apps)" >&2
            echo "  lock           unmount and close the encrypted home volume" >&2
            echo "  unlock         open and mount the encrypted home volume" >&2
            echo "  new <name>     create a new VM-backed project" >&2
            echo "  init-home      one-time: format and mount the home LUKS volume" >&2
            echo "  secret-set [--replace]   store the LUKS passphrase (Secure Enclave + Touch ID)" >&2
            echo "  secret-get               print the LUKS passphrase to stdout (Touch ID required)" >&2
            echo "  secret-delete            remove the local secret + identity files" >&2
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
        qemuWrapper
      ];
    };
}
