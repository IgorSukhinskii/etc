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
  # private-vm-rebuild. Creates the real user (host.username) under whom
  # interactive sessions (vm ssh, xpra-forwarded GUI apps) run. The
  # bootstrap `nixos` user persists from bootstrap.nix and remains the
  # host-side ops account.
  networking.hostName = "private-vm";
  networking.extraHosts = ''
    192.168.5.2 host.private
  '';

  # The user-facing user — SSH (for terminal/tmux work) + xpra (for GUI).
  # nixos is still the host→VM bootstrap account used by private-vm-rebuild
  # (Lima's ssh.config bakes User=nixos at first start), but everyday work
  # — `vm ssh`, in-VM tmux, etc. — happens as this user.
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
    linger = true;
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

  environment.systemPackages = with pkgs; [
    firefox
    xpra
  ];

  # PulseAudio source for xpra's `--speaker=on` forwarding. xpra captures
  # the guest pulse sink and streams it over the SSH/xpra transport to
  # the host's CoreAudio. Without a running pulse server in the guest,
  # `--speaker=on` has nothing to read and guest apps fall back to "no
  # audio device" (Firefox silently mutes).
  #
  # qemu exposes no audio device to the guest (/proc/asound/cards is
  # empty); pipewire/wireplumber fabricates an `auto_null` sink that
  # behaves like /dev/null but exposes a usable `auto_null.monitor`
  # source. Guest apps (Firefox &c.) play into `auto_null`; xpra is
  # pointed at `auto_null.monitor` via PULSE_SOURCE in the user unit
  # below.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
  };

  home-manager.users.${user} = {
    home.stateVersion = config.host.stateVersion;
    programs.home-manager.enable = true;

    home.sessionVariables = {
      DISPLAY = ":100";
    };

    # Headless xpra server: a persistent X session that lives in the
    # background, owned by the user, with no display until something
    # attaches. Guest-launched GUI apps render into this server (via
    # DISPLAY=:100, set in home.sessionVariables above); the host's
    # `vm gui` client attaches over SSH and surfaces whatever windows
    # exist as host-native macOS windows. Detach = windows keep running
    # invisibly; reattach = they reappear. Closing the last window does
    # not stop the server.
    #
    # Defined under home-manager (not top-level systemd.user) so the
    # unit is installed ONLY for this user. A top-level systemd.user.*
    # entry would install for every user with a running user@.service —
    # including `nixos` (the bootstrap account Lima/private-vm-rebuild
    # logs in as) — and both servers would race for X display :100,
    # whose Xvfb abstract socket `@xpra/100` is a system-global name.
    # nixos wins (lower uid, earlier login), igor's unit crashloops
    # with "You already have an xpra server running at '@xpra/100'",
    # and `vm gui` (which attaches as igor) hits a dead socket.
    #
    # --daemon=no keeps xpra in the foreground so systemd owns the
    # lifecycle. --bind-tcp is NOT set: clients attach via SSH only,
    # using xpra's ssh:// URL scheme, which tunnels over stdio — no
    # additional TCP port.
    systemd.user.services.xpra = {
      Unit.Description = "xpra headless X server on :100";
      Install.WantedBy = [ "default.target" ];
      Service = {
        Type = "simple";
        # pulseaudio package is on PATH for `pactl`, which xpra uses to
        # probe the pulse server (sink/source enumeration). The
        # `--pulseaudio=no` flag means "don't start a private pulse
        # daemon" — xpra still uses the system pipewire-pulse over its
        # standard socket (/run/user/1001/pulse/native via
        # XDG_RUNTIME_DIR). xpra's gstreamer pulsesrc would otherwise
        # try to capture from a hardcoded `Xpra-Speaker` device that
        # only exists when `--pulseaudio=yes` spawns its own daemon —
        # surfacing as "Failed to connect stream: No such entity" in
        # the audio capture gst pipeline. We override that target by
        # setting `PULSE_SOURCE=auto_null.monitor` (pulsesrc honours
        # the env var when no explicit `device=` is configured).
        #
        # Note: xpra's `--audio-source=NAME` option takes a GStreamer
        # source-plugin name (`pulse`, `alsa`, `test`, …), NOT a Pulse
        # source name; passing a Pulse source there errors with
        # "unknown source plugin". Hence the env-var route.
        Environment = [
          "PATH=${pkgs.xpra}/bin:${pkgs.xorg.xauth}/bin:${pkgs.pulseaudio}/bin:/run/current-system/sw/bin"
          # GStreamer pulsesrc honours PULSE_SOURCE when no explicit
          # device= is set. Pin it to the monitor of the fabricated
          # `auto_null` sink (the only sink in this audio-card-less
          # guest); without this, xpra's pulsesrc tries to connect to
          # the long-gone `Xpra-Speaker` device that the legacy
          # `--pulseaudio=yes` mode used to create, and fails the
          # capture with "No such entity".
          "PULSE_SOURCE=auto_null.monitor"
        ];
        # Pre-seed ~/.Xauthority with a fresh MIT-MAGIC-COOKIE for :100
        # before xpra starts. xpra itself shells out to `xauth` to write
        # this cookie, but in nixpkgs' xpra build that subprocess fails
        # with ENOENT even though xauth is on the unit PATH (some
        # internal env-stripping in xpra's spawn path). Without the
        # cookie, Xorg comes up but every X client (firefox, xclock,
        # ...) gets "Authorization required, but no authorization
        # protocol specified" and bails. Doing it ourselves bypasses
        # the broken xpra→xauth call. The cookie is regenerated on
        # every (re)start so a previous run's cookie can't shadow this
        # one.
        ExecStartPre = pkgs.writeShellScript "xpra-seed-xauth" ''
          set -eu
          cookie=$(${pkgs.coreutils}/bin/head -c 16 /dev/urandom | ${pkgs.coreutils}/bin/od -An -tx1 | ${pkgs.coreutils}/bin/tr -d ' \n')
          ${pkgs.coreutils}/bin/rm -f "$HOME/.Xauthority"
          ${pkgs.xorg.xauth}/bin/xauth -f "$HOME/.Xauthority" add :100 MIT-MAGIC-COOKIE-1 "$cookie"
        '';
        ExecStart = ''
          ${pkgs.xpra}/bin/xpra start :100 \
            --daemon=no \
            --start-via-proxy=no \
            --pulseaudio=no \
            --notifications=no \
            --systemd-run=no \
            --mdns=no \
            --webcam=no \
            --html=off \
            --bell=no \
            --speaker=on \
            --microphone=no \
            --printing=no \
            --file-transfer=off \
            --opengl=yes
        '';
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };

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

  # Guest-side DRM device via the standard 2D virtio-gpu-pci. The host
  # qemu wrapper attaches `-device virtio-gpu-pci` (no host GL required).
  # hardware.graphics.enable brings in mesa which, via the virtio_gpu kernel
  # module + llvmpipe, provides software EGL on /dev/dri/renderD128. xpra's
  # `--opengl=yes` uses that EGL path for GL compositing — meaningfully
  # better compositing quality than --opengl=no, without needing hardware GL.
  # Hardware GPU (virglrenderer/rutabaga) deferred: virglrenderer requires
  # epoxy/egl.h absent from nixpkgs libepoxy on Darwin; rutabaga requires
  # qemu's loadable-module system which nixpkgs disables on Darwin.
  hardware.graphics.enable = true;

  # Guest-side driver for virtio-balloon-pci. Under qemu (Phase 1) the
  # host wrapper attaches the device with free-page-reporting=on, so the
  # guest's virtio_balloon driver proactively reports newly-freed PFNs
  # to qemu. On macOS qemu MADV_FREE_REUSABLE's the reported pages —
  # they stay in qemu's RSS but are marked purgeable (instantly
  # reclaimable under host pressure, no swap I/O).
  boot.kernelModules = [
    "virtio_balloon"
    "virtio_gpu"
  ];

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
