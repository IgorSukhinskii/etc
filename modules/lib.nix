{
  lib,
  config,
  inputs,
  ...
}:
let
  # Turn a list of profile names into a home-manager.sharedModules list: union
  # the profiles' module names, resolve each to its registered module, and append
  # nvf (wanted on every host). Hosts append their own one-offs via `extra`.
  mkHmSharedModules =
    profiles:
    let
      names = lib.unique (lib.concatMap (p: config.flake.profiles.hm.${p}) profiles);
    in
    map (n: config.flake.homeManagerModules.${n}) names ++ [ inputs.nvf.homeManagerModules.default ];
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
