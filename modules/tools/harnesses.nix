{ ... }:
{
  # Claude Code and Codex, installed by their vendors' official installers into
  # ~/.local/bin and otherwise left alone: default config dirs, no config from
  # this repo. t3 is the interface that drives them, and the place that updates
  # them (its provider card runs `claude update` / `codex update`; claude also
  # updates itself). Versions are deliberately not declared here: model releases
  # often need a same-day harness release, which nixpkgs and Homebrew lag.
  #
  # History: until 2026-10 this repo pinned claude through nixpkgs with a
  # wrapper and settings layer, installed codex as a Homebrew cask with a
  # managed config.toml, and carried opencode, playwright-mcp and a shared
  # skills tree, from when the CLIs were the primary interface.
  flake.homeManagerModules.harnesses =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      binDir = "${config.home.homeDirectory}/.local/bin";

      installers = {
        claude = "curl -fsSL https://claude.ai/install.sh | bash";
        codex = "curl -fsSL https://chatgpt.com/codex/install.sh | sh";
      };

      # binDir first: the installers then find PATH already set up and leave
      # the home-manager-owned shell profiles alone. util-linux for flock:
      # without it the codex installer locks with a directory that an
      # interrupted install leaves behind, and the next activation waits on it
      # past home-manager's 5-minute timeout.
      installPath = "${binDir}:${
        lib.makeBinPath (
          [
            pkgs.bash
            pkgs.curl
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
            pkgs.gnused
            pkgs.gawk
            pkgs.gnutar
            pkgs.gzip
          ]
          ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.util-linux
        )
      }:/usr/bin:/bin";
    in
    {
      home.activation.harnesses = lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatStrings (
          lib.mapAttrsToList (bin: install: ''
            if [ ! -x ${binDir}/${bin} ]; then
              run env PATH="${installPath}" CODEX_NON_INTERACTIVE=1 bash -c ${lib.escapeShellArg install} \
                || warnEcho "${bin}: install failed (offline?); run nix-rebuild again later"
            fi
          '') installers
        )
      );
    };
}
