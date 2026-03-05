{ config, ... }:
{
  users.users.${config.host.username} = {
    isNormalUser = true;
    home = toString config.host.homeDirectory;
  };
}
