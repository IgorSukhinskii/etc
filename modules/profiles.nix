{ lib, config, ... }:
{
  options.flake.profiles = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf (lib.types.listOf lib.types.str));
    default = { };
    description = ''
      Profile -> [module name] taxonomy, grouped by module class (currently
      only `hm`). Single source of truth for host composition; resolved into a
      `home-manager.sharedModules` list by `flake.lib.mkHmSharedModules`.
    '';
  };

  config.flake.profiles.hm = {
    base = [
      "shell"
      "tools"
      "neovim"
      "starship"
      "tmux"
      "tmuxLayout"
      "nix-dev"
      "dev"
      "themes"
    ];
    ai = [
      "claude"
      "codex"
      "opencode"
      "playwright"
    ];
    # `zen-browser` is the external module (inputs.zen-browser.homeModules.beta),
    # registered into flake.homeManagerModules during the zen surgery (Phase 4);
    # `zen` is our config layered on top.
    browser = [
      "zen-browser"
      "zen"
    ];
    darwinDesktop = [
      "sketchybar"
      "hammerspoon"
      "ical"
      "jira"
      "openwhispr"
      "tridactyl"
      "copilot"
      "homebrew"
      "terminal"
      "ghostty-themes"
    ];
  };

  # Completeness: every registered home-manager module must be classified into a
  # profile. Genuinely host-singular modules (e.g. the WSL wezterm terminal, the
  # mac-side private-vm launcher) live in hosts/<h>/ off the registry and are
  # appended directly, so they never need an entry here.
  config.perSystem =
    { pkgs, ... }:
    {
      checks.hm-profiles-complete =
        let
          hostLocalHm = [ "local-llm" ];
          classified = lib.unique (lib.concatLists (lib.attrValues config.flake.profiles.hm));
          registry = lib.attrNames config.flake.homeManagerModules;
          orphans = lib.subtractLists (classified ++ hostLocalHm) registry;
        in
        if orphans == [ ] then
          pkgs.runCommand "hm-profiles-complete" { } "touch $out"
        else
          throw "Unclassified home-manager modules (add to a profile in modules/profiles.nix or to hostLocalHm): ${lib.concatStringsSep ", " orphans}";
    };
}
