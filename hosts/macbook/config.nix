let
  username = "igor.sukhinskii";
  homeDirectory = /Users/igor.sukhinskii;
  stateVersion = "25.05";
in
{ lib, ... }:
{
  options.host = {
    username = lib.mkOption { type = lib.types.str; };
    homeDirectory = lib.mkOption { type = lib.types.path; };
    stateVersion = lib.mkOption { type = lib.types.str; };
  };

  config = {
    host = { inherit username homeDirectory stateVersion; };

    home-manager.users.${username} = {
      home.username = username;
      home.homeDirectory = homeDirectory;
      home.stateVersion = stateVersion;
      programs.home-manager.enable = true;
    };
  };
}
