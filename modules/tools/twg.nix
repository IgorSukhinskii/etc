{ ... }:
{
  # Atlassian's Teamwork Graph CLI (Jira, Confluence, Bitbucket; OAuth 2.1),
  # installed like the harnesses: the vendor's installer runs once into
  # ~/.local/bin. twg's own upkeep only notifies about releases, so a daily
  # launchd agent runs `twg upgrade --yes`: new releases land without waiting
  # for nixpkgs or a rebuild. Sign-in stays manual: `twg login`, then
  # `twg upkeep enable` for the background token refresh. Atlassian's agent
  # skills (`twg skills install`) are deliberately not installed.
  #
  # Mac only. WSL calls the Windows twg.exe instead of holding a second login
  # (hosts/wsl/twg.nix).
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

      launchd.agents.twg-upgrade = {
        enable = true;
        config = {
          Label = "local.twg-upgrade";
          ProgramArguments = [
            "${binDir}/twg"
            "upgrade"
            "--yes"
          ];
          EnvironmentVariables.PATH = installPath;
          StartCalendarInterval = [
            {
              Hour = 9;
              Minute = 25;
            }
          ];
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/twg-upgrade.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/twg-upgrade.error.log";
        };
      };
    };
}
