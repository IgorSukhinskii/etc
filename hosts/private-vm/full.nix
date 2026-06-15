{
  config,
  pkgs,
  ...
}:
let
  user = config.host.username;
in
{
  # In-VM steady-state config. Layered on bootstrap.nix; applied by
  # private-vm-rebuild. Creates the real user (host.username) for desktop /
  # RDP sessions. The bootstrap `nixos` user persists from bootstrap.nix and
  # remains the host-side ops account.
  networking.hostName = "private-vm";

  # The user-facing user — SSH (for terminal/tmux work) + RDP (for desktop).
  # nixos is still the host→VM bootstrap account used by private-vm-rebuild
  # (Lima's ssh.config bakes User=nixos at first start), but everyday work
  # — `private-vm-ssh`, in-VM tmux, etc. — happens as this user.
  # uid pinned so the encrypted /home volume (which carries file ownership in
  # its ext4 inode table) stays consistent across system-disk wipes. Without
  # this, NixOS allocates dynamically via /var/lib/nixos/uid-map — state that
  # lives on the root fs and gets wiped, risking a uid drift that would
  # orphan every file on the LUKS volume.
  #
  # 1001 (not 1000) because `nixos` (the bootstrap user) is pinned at 1000 in
  # bootstrap.nix and would collide silently otherwise — NixOS's user-activation
  # writes both into /etc/passwd without rejecting, and uid → name resolution
  # then non-deterministically picks one, breaking ownership labels.
  users.users.${user} = {
    isNormalUser = true;
    uid = 1001;
    home = "/home/${user}";
    extraGroups = [
      "wheel"
      "audio"
      "video"
    ];
    shell = pkgs.zsh;
    hashedPasswordFile = "/var/lib/private-vm/passwd.hash";
  };

  # The per-user pubkey path `/var/lib/private-vm/%u.pub` is configured in
  # bootstrap.nix's `services.openssh.authorizedKeysFiles` — sshd reads
  # `${user}.pub` at connection time. private-vm-rebuild pushes the file
  # before each switch.
  programs.zsh.enable = true;
  programs.nix-ld.enable = true;
  nix.settings.trusted-users = [
    "root"
    user
  ];

  services.xserver = {
    enable = true;
    windowManager.openbox.enable = true;
    displayManager.startx.enable = true;
  };

  services.xrdp = {
    enable = true;
    defaultWindowManager = "${pkgs.openbox}/bin/openbox-session";
    openFirewall = true;
    audio.enable = true;
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
  };

  environment.systemPackages = with pkgs; [
    firefox
    openbox
  ];

  home-manager.users.${user} = {
    home.stateVersion = config.host.stateVersion;
    programs.home-manager.enable = true;

    programs.zsh.initContent = ''
      _cursor_shape() {
        case ''${KEYMAP-} in
          vicmd|visual) print -n '\e[1 q' ;;
          *) print -n '\e[5 q' ;;
        esac
      }
      zle-keymap-select() { _cursor_shape; }
      zle-line-init() { _cursor_shape; }
      zle -N zle-keymap-select
      zle -N zle-line-init
      _cursor_reset() { print -n '\e[0 q'; }
      preexec_functions+=(_cursor_reset)
    '';

    xdg.configFile."openbox/autostart".text = ''
      firefox &
    '';

    xdg.configFile."openbox/rc.xml".text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <openbox_config xmlns="http://openbox.org/3.4/rc">
        <applications>
          <application name="firefox">
            <decor>no</decor>
            <maximized>true</maximized>
          </application>
        </applications>
      </openbox_config>
    '';
  };

  # Home Manager activation invokes `nix` as the user. During `nixos-rebuild
  # switch`, a directly-started nix-daemon can leave the socket present but
  # refusing connections; repair that as root before the user unit runs.
  systemd.services.private-nix-daemon-ready = {
    description = "Ensure the Nix daemon socket accepts connections";
    path = with pkgs; [
      coreutils
      nix
      systemd
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      wait_for_nix() {
        for _ in $(seq 1 30); do
          if NIX_REMOTE=daemon nix store ping >/dev/null 2>&1; then
            return 0
          fi
          sleep 1
        done
        return 1
      }

      if wait_for_nix; then
        exit 0
      fi

      systemctl stop nix-daemon.service nix-daemon.socket || true
      rm -f /nix/var/nix/daemon-socket/socket
      systemctl reset-failed nix-daemon.service nix-daemon.socket || true
      systemctl start nix-daemon.socket
      if wait_for_nix; then
        exit 0
      fi

      echo "nix daemon did not become reachable before Home Manager activation" >&2
      exit 1
    '';
  };

  systemd.services."home-manager-${user}" = {
    after = [
      "private-nix-daemon-ready.service"
      "nix-daemon.socket"
    ];
    wants = [
      "private-nix-daemon-ready.service"
      "nix-daemon.socket"
    ];
    path = with pkgs; [
      nix
    ];
    preStart = ''
      for _ in $(seq 1 30); do
        if NIX_REMOTE=daemon nix store ping >/dev/null 2>&1; then
          exit 0
        fi
        sleep 1
      done
      echo "nix daemon did not become reachable before Home Manager activation" >&2
      exit 1
    '';
  };

  # Mount /nix from the external private-nix volume in stage-1. Required so
  # the initrd can find the closure pointed at by init=<path> on the kernel
  # cmdline — gens 2..N's closures live only on private-nix, never on rootfs.
  # Bootstrap.nix deliberately does NOT carry this: the bootstrap image is
  # self-sufficient and its initrd only needs rootfs /nix. After first boot,
  # `private-nix-init` formats/seeds the volume; every subsequent in-VM
  # `nixos-rebuild switch` produces an initrd (from this full.nix) that
  # mounts /nix here, making cold boot of new generations work. Without
  # this, gens 2..N only survive as live-activated user-space pivots and
  # any cold restart drops to emergency mode.
  fileSystems."/nix" = {
    device = "/dev/disk/by-label/private-nix";
    fsType = "ext4";
    neededForBoot = true;
  };

  # Encrypted home volume. Mounted manually via private-vm-unlock (host script)
  # after Touch ID + cryptsetup luksOpen. noauto: systemd does not attempt to
  # mount at boot (the LUKS container is closed until explicitly unlocked).
  # nofail: belt-and-suspenders so any stray dependency doesn't block boot.
  # The dm-crypt device /dev/mapper/private-home is created by luksOpen with
  # that fixed name; the mapping name is the stable identifier we use here.
  fileSystems."/home/${user}" = {
    device = "/dev/mapper/private-home";
    fsType = "ext4";
    options = [
      "nofail"
      "noauto"
    ];
  };

  networking.firewall.allowedTCPPorts = [ 3389 ];

  # Guest-side driver for virtio-balloon-pci. Under qemu (Phase 1) the
  # host wrapper attaches the device with free-page-reporting=on, so the
  # guest's virtio_balloon driver proactively reports newly-freed PFNs
  # to qemu. On macOS qemu MADV_FREE_REUSABLE's the reported pages —
  # they stay in qemu's RSS but are marked purgeable (instantly
  # reclaimable under host pressure, no swap I/O).
  boot.kernelModules = [ "virtio_balloon" ];

  # Periodic page-cache drop. FPR only reports pages the *guest*
  # considers free (in the buddy allocator). Page cache pages are
  # "used, but reclaimable" from the guest's perspective and never get
  # returned to the host on their own — so without this, Linux fills
  # RAM with file-backed cache from build/I/O activity and the host
  # holds that footprint forever. Echoing 3 to drop_caches forces the
  # guest to reclaim cache + reclaimable slab → those pages become
  # guest-free → FPR reports them → macOS marks them purgeable. Net
  # effect: keeps qemu's "instantly reclaimable" pool large, so host
  # memory pressure resolves via cheap MADV_FREE reclaim rather than
  # via compressing or swapping qemu's RSS.
  #
  # Only runs under low load to avoid yanking cache out from under an
  # active workload (the kernel re-reads pages, but the latency spike is
  # visible). Cheap enough at 15-minute cadence; safe to tune.
  systemd.services.private-vm-drop-caches = {
    description = "Drop page cache + reclaimable slab when guest is idle";
    serviceConfig.Type = "oneshot";
    path = [
      pkgs.coreutils
      pkgs.gawk
    ];
    script = ''
      load1=$(awk '{print $1}' /proc/loadavg)
      if awk "BEGIN { exit !($load1 < 0.5) }"; then
        sync
        echo 3 > /proc/sys/vm/drop_caches
      fi
    '';
  };

  systemd.timers.private-vm-drop-caches = {
    description = "Periodic idle page-cache drop";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "15min";
      AccuracySec = "1min";
    };
  };
}
