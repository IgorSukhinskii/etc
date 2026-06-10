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
  users.users.${user} = {
    isNormalUser = true;
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

  networking.firewall.allowedTCPPorts = [ 3389 ];
}
