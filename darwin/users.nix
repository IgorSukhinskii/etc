{ config, ... }:
{
  users.users.${config.host.username} = {
    name = config.host.username;
    home = config.host.homeDirectory;
  };
}
