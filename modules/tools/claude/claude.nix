{ ... }:
{
  # No `flake.darwinModules.claude` any more: claude-code used to be a Homebrew
  # cask, on the assumption that brew tracked releases faster than nixpkgs. It is
  # the other way round. Anthropic publishes two channels --
  #   .../claude-code-releases/stable  (what the cask follows)
  #   .../claude-code-releases/latest  (what nixpkgs' update.sh follows)
  # -- and `stable` is a deliberately lagging staged rollout, tens of releases
  # behind. The manifest pinned below tracks `latest` directly, so this is now
  # strictly fresher than the cask ever was.

  flake.homeManagerModules.claude =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      # nixpkgs' claude-code derives everything -- version, download URL and
      # checksum -- from a manifest JSON, exposed as an overridable argument
      # (`manifest ? lib.importJSON ./manifest.zst.json`). Vendoring our own copy
      # therefore pins an exact release without waiting for a nixpkgs bump: the
      # package stays nixpkgs' (wrapper, ripgrep/procps PATH, DISABLE_AUTOUPDATER),
      # only the version pointer is ours.
      #
      # This file must live in the store, so it is a normal repo file read at eval
      # time -- unlike configs/claude/settings.json, which is deliberately an
      # out-of-store path so edits apply without a rebuild. Changing the manifest
      # *should* require a rebuild, hence the different treatment.
      #
      # Refresh with `claude-manifest-update`, then rebuild.
      claudePkg = pkgs.claude-code.override {
        manifest = lib.importJSON ./manifest.zst.json;
      };
      claudeBin = "${claudePkg}/bin/claude";

      # Our declarative settings live as hand-authored JSON in the repo and are
      # loaded via `--settings`, which claude treats as the `flagSettings` layer:
      # higher priority than the writable `userSettings` (~/.config/claude/
      # settings.json), and claude *refuses to write to it* (it throws on that
      # source). So the repo file is the source of truth (it overrides anything
      # claude persists), while claude's own settings.json stays unmanaged and
      # writable — its runtime writes (/tui, /model, theme, onboarding state, …)
      # no longer hit a read-only /nix/store symlink (the original EACCES).
      #
      # We point --settings straight at the live working-copy file (not a store
      # copy), so edits to it take effect on the next `claude` launch with no
      # rebuild. Only the path is baked in; the content is read fresh at runtime.
      settingsFile = "${config.local.flakeDir}/configs/claude/settings.json";

      manifestFile = "${config.local.flakeDir}/modules/tools/claude/manifest.zst.json";

      claudeWrapper = pkgs.writeShellScriptBin "claude" ''
        export DISABLE_AUTOUPDATER=1
        if [ -n "$TMUX" ]; then
          # let tmux know that claude accepts extended keys
          printf '\033[>4;2m'
          # on exit, let tmux know that we no longer accept extkeys
          trap 'printf "\033[>4;0m"' EXIT
        fi
        ${claudeBin} --dangerously-skip-permissions --settings "${settingsFile}" "$@"
      '';
      askClaude = pkgs.writeShellScriptBin "ask-claude" ''
        if [ $# -eq 0 ]; then
          echo "Usage: ?? <question>" >&2
          exit 1
        fi
        claude -p "$*"
      '';

      # Fetch the newest `latest`-channel manifest into the repo. Mirrors what
      # nixpkgs' own pkgs/by-name/cl/claude-code/update.sh does, but writes here.
      # Deliberately does not rebuild: the manifest change should show up as a
      # reviewable diff first.
      claudeManifestUpdate = pkgs.writeShellScriptBin "claude-manifest-update" ''
        set -euo pipefail
        base=https://downloads.claude.ai/claude-code-releases
        target=${lib.escapeShellArg manifestFile}

        version="''${1:-$(${lib.getExe pkgs.curl} -fsSL "$base/latest")}"
        current=$(${lib.getExe pkgs.jq} -r .version "$target" 2>/dev/null || echo none)

        if [ "$version" = "$current" ]; then
          echo "claude-code: already at $current"
          exit 0
        fi

        ${lib.getExe pkgs.curl} -fsSL "$base/$version/manifest.zst.json" -o "$target"
        echo "claude-code: $current -> $version"
        echo "run 'nix-rebuild' to apply, then commit $target"
      '';
    in
    {
      home.packages = [
        claudeWrapper
        askClaude
        claudeManifestUpdate
      ];
      home.shellAliases."??" = "ask-claude";

      # No `settings` here: writing it would materialize a read-only settings.json
      # symlink into /nix/store, which is exactly what caused the EACCES on
      # claude's runtime writes. Declarative settings live in the repo JSON loaded
      # via `--settings` (see the settingsFile comment above); ~/.config/claude/
      # settings.json is left unmanaged so claude can write it freely.
      programs.claude-code = {
        enable = true;
        package = null;
        configDir = "${config.xdg.configHome}/claude";
      };
    };
}
