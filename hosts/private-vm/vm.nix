{
  config,
  pkgs,
  lib,
  ...
}:
{
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

  home-manager.users.${config.host.username} = {
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
