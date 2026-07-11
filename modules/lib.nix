{
  lib,
  config,
  ...
}:
let
  # Always-on HM module carrying host-local options that every HM eval needs
  # regardless of profile. Appended to sharedModules below, so it is never routed
  # through the profile registry / completeness check.
  #
  # `local.flakeDir` is the single source of truth for the working-copy location
  # of this repo on the current host. It cannot be derived from the flake (`self`
  # resolves to an immutable /nix/store copy, decoupled from the working tree by
  # design), so it must be a declared value — but the default adapts per host via
  # `config.home.homeDirectory`, so no host needs to set it unless the repo lives
  # somewhere other than ~/etc. Consumed by nix-rebuild, the git pre-commit hook
  # installer, out-of-store config symlinks (e.g. claude), and the tmux session
  # preset.
  localOptions =
    { config, lib, ... }:
    {
      options.local.flakeDir = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/etc";
        example = "/home/alice/dotfiles";
        description = ''
          Absolute path to the working copy (not the /nix/store copy) of this
          flake repository on the current host. Override only on hosts where the
          repo is not cloned at ~/etc.
        '';
      };
    };

  # Turn a list of profile names into a home-manager.sharedModules list: union
  # the profiles' module names, resolve each to its registered module, and append
  # the host-local options (wanted on every host). Hosts append their own one-offs
  # via `extra`.
  mkHmSharedModules =
    profiles:
    let
      names = lib.unique (lib.concatMap (p: config.flake.profiles.hm.${p}) profiles);
    in
    map (n: config.flake.homeManagerModules.${n}) names ++ [ localOptions ];
in
{
  flake.lib.mkHmSharedModules = mkHmSharedModules;

  # The whole home-manager wiring block, identical across hosts except for the
  # module set. Hosts pass their profile list (+ any host-local `extra` modules);
  # the home-manager.{darwin,nixos}Modules.home-manager import stays per-host
  # since it differs by platform.
  flake.lib.mkHmModule =
    {
      profiles ? [ ],
      extra ? [ ],
    }:
    {
      home-manager.backupFileExtension = "hm-backup";
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.sharedModules = mkHmSharedModules profiles ++ extra;
    };
}
