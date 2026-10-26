{ ... }:
{
  # Atlassian's Teamwork Graph CLI (Jira, Confluence, Bitbucket; OAuth 2.1),
  # installed like the harnesses: the vendor's installer runs once into
  # ~/.local/bin and twg then updates itself (`twg update`). Nix only declares
  # that it is wanted, so new releases don't wait for nixpkgs. Sign-in stays
  # manual: `twg login` (browser or device code), then `twg setup` for the
  # background token refresh and its agent skills.
  #
  # Mac only for now. WSL is meant to call the Windows twg.exe through interop
  # rather than hold a second login; that shim belongs in hosts/wsl once DEV1's
  # Windows side has twg.
  flake.homeManagerModules.twg =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      binDir = "${config.home.homeDirectory}/.local/bin";
      install = "curl -fsSL --retry 2 https://teamwork-graph.atlassian.com/cli/install | bash -s -- --yes --skip-login --skip-skills";

      # binDir first, as in harnesses.nix: the installer then finds PATH set
      # up and leaves the home-manager-owned shell profiles alone.
      installPath = "${binDir}:${
        lib.makeBinPath [
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
      }:/usr/bin:/bin";
    in
    {
      home.activation.twg = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -x ${binDir}/twg ]; then
          run env PATH="${installPath}" bash -c ${lib.escapeShellArg install} \
            || warnEcho "twg: install failed (offline?); run nix-rebuild again later"
        fi
      '';
    };
}
