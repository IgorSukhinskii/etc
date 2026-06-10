let
  username = "igor";
  homeDirectory = /home/igor;
  stateVersion = "25.05";
in
{ lib, pkgs, ... }:
{
  options.host = {
    username = lib.mkOption { type = lib.types.str; };
    homeDirectory = lib.mkOption { type = lib.types.path; };
    stateVersion = lib.mkOption { type = lib.types.str; };
  };

  config = {
    host = { inherit username homeDirectory stateVersion; };

    networking.hostName = "private-vm";

    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
    };

    programs.zsh.enable = true;
    programs.nix-ld.enable = true;

    users.users.${username} = {
      extraGroups = [
        "wheel"
        "audio"
        "video"
      ];
      shell = pkgs.zsh;
      # Read pubkeys directly from host $HOME; requires --impure build.
      # The wrapper in modules/nix-dev.nix (private-vm-build) passes --impure.
      # - Host pubkey: lets the user SSH in interactively.
      # - Lima pubkey: lets Lima's host agent authenticate post-boot health checks.
      openssh.authorizedKeys.keys =
        let
          readKey =
            p:
            lib.optionals (builtins.pathExists p) [
              (lib.removeSuffix "\n" (builtins.readFile p))
            ];
        in
        readKey "/Users/igor.sukhinskii/.ssh/id_ed25519.pub"
        ++ readKey "/Users/igor.sukhinskii/.lima/_config/user.pub";
    };

    security.sudo.wheelNeedsPassword = false;

    system.stateVersion = stateVersion;

    home-manager.users.${username} = {
      home.stateVersion = stateVersion;
      programs.home-manager.enable = true;
    };
  };
}
