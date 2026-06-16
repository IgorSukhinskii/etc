{
  lib,
  pkgs,
  inputs,
  ...
}:
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

    # Required in both the bootstrap image (for private-vm-init-home which
    # formats and opens the LUKS volume before the first full rebuild) and in
    # the full runtime config (for private-vm-unlock / private-vm-lock).
    boot.kernelModules = [ "dm-crypt" ];
    environment.systemPackages = with pkgs; [
      cryptsetup
      e2fsprogs
    ];
    # Marker read by starship to render the VM glyph in the prompt.
    environment.variables.IN_PRIVATE_VM = "1";
  };
}
