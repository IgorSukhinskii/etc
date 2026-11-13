# Daily cleanup, so disk use stays bounded without anyone remembering a command.
# - Docker: unused images and stopped containers older than 3 days, and
#   anonymous volumes no container uses (test databases; named volumes stay).
# - agenda gc in ~/w: removes finished or idle trees that lose nothing, ages out
#   scratch (rules: tool-agenda's README).
{ config, pkgs, ... }:
let
  user = config.host.username;
  home = toString config.host.homeDirectory;
in
{
  virtualisation.docker.autoPrune = {
    enable = true;
    dates = "daily";
    flags = [
      "--all"
      "--filter"
      "until=72h"
    ];
  };

  systemd.services.docker-volume-prune = {
    description = "Remove anonymous Docker volumes no container uses";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    serviceConfig.Type = "oneshot";
    script = "${pkgs.docker}/bin/docker volume prune -f";
    startAt = "daily";
  };

  systemd.services.agenda-gc = {
    description = "agenda gc in ~/w";
    after = [ "home-igor-w.mount" ];
    requires = [ "home-igor-w.mount" ];
    path = [
      pkgs.git
      pkgs.openssh
    ];
    serviceConfig = {
      Type = "oneshot";
      User = user;
      WorkingDirectory = "${home}/w";
      ExecStart = "${home}/.local/bin/agenda gc";
    };
    startAt = "*-*-* 04:30:00";
  };
}
