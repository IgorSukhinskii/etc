{ lib, inputs, ... }:
{
  # Truly-shared base for both the bootstrap image and the full in-VM config.
  # The user-facing username comes from flake.privateVm.username (vars.nix),
  # so the codebase has one source of truth and forks just change vars.nix.
  options.host = {
    username = lib.mkOption {
      type = lib.types.str;
      default = inputs.self.privateVm.username;
    };
    stateVersion = lib.mkOption {
      type = lib.types.str;
      default = "25.05";
    };
  };

  config = {
    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
    };
    security.sudo.wheelNeedsPassword = false;
    system.stateVersion = "25.05";
  };
}
