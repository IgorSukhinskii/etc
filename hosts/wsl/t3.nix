# Host-local: the t3 server, so the Mac and the phone pair with this WSL
# instance directly (no SSH in the path). Same rule as
# modules/tools/harnesses.nix: this file declares only that t3 is installed and
# running, and with which settings. t3's installer, `t3 service install` and its
# in-app updater own the binary, the systemd unit and the version.
#
# The unit is t3's, not ours: it runs t3's service launcher, which picks the
# active version from a state file only `t3 service install` writes and
# self-updates by switching it. Our settings go in a drop-in on top.
#
# Reachability is the Windows host's job: WSL's NAT localhost forwarding puts
# `port` on Windows' 127.0.0.1, and a portproxy there publishes it to the LAN on
# a different port. The two must differ, or the proxy (listening on 0.0.0.0)
# and the forwarder both claim 127.0.0.1:<port>.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  binDir = "${config.home.homeDirectory}/.local/bin";
  unitDir = "${config.xdg.configHome}/systemd/user";
  port = 3775;

  # The installer is piped into `sh`.
  installPath = lib.makeBinPath [
    pkgs.bash
    pkgs.curl
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gnutar
    pkgs.gzip
  ];

  # As in home-manager's own systemd activation: when run from the NixOS
  # module's service, XDG_RUNTIME_DIR is not set.
  systemctl = ''env XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" ${pkgs.systemd}/bin/systemctl --user'';
in
{
  # Read by `t3 serve`; the launcher passes its environment through.
  xdg.configFile."systemd/user/t3code.service.d/etc.conf" = {
    text = ''
      [Service]
      Environment=T3CODE_HOST=0.0.0.0
      Environment=T3CODE_PORT=${toString port}
      Environment=T3CODE_TELEMETRY_ENABLED=false
    '';
    # Only if it is running: a first install is left to the activation below.
    onChange = ''
      ${systemctl} daemon-reload || true
      if ${systemctl} is-active --quiet t3code.service; then
        ${systemctl} restart t3code.service || true
      fi
    '';
  };

  home.activation.t3 = lib.hm.dag.entryAfter [ "onFilesChange" "reloadSystemd" ] ''
    if [ ! -x ${binDir}/t3 ]; then
      run env PATH="${installPath}" T3CODE_CHANNEL=nightly \
        ${pkgs.bash}/bin/sh -c 'curl -fsSL https://t3.codes/install.sh | sh' \
        || warnEcho "t3: install failed (offline?); run nix-rebuild again later"
    fi
    # Only when missing: once t3 has updated itself, an older CLI refuses to
    # rewrite the unit (it would be a downgrade).
    if [ -x ${binDir}/t3 ] && [ ! -e ${unitDir}/t3code.service ]; then
      run env XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
        PATH="${
          lib.makeBinPath [
            pkgs.systemd
            pkgs.coreutils
          ]
        }" \
        ${binDir}/t3 service install \
        || warnEcho "t3: service install failed (no user systemd yet?); run nix-rebuild again later"
    fi
  '';
}
