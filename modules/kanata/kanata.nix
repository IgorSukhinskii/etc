{ inputs, ... }:
{
  flake.darwinModules.kanata =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.kanata-darwin.darwinModules.default ];

      services.kanata = {
        enable = true;
        daemon.enable = true;
        configSource = ./kanata.kbd;

        # Pinned on purpose -- see the `nixpkgs-kanata` comment in flake.nix.
        # macOS TCC identifies this binary by absolute path + ad-hoc cdhash, both
        # of which a rebuild changes, so tracking `nixpkgs` means re-granting
        # Input Monitoring and Accessibility after every update. kanata is a local,
        # offline tool whose config lives read-only in the store, so freezing it
        # costs little; the trade is documented in flake.nix.
        #
        # Must stay `kanata-with-cmd`, not `kanata`: that is what kanata-darwin's
        # `package` option defaults to (module.nix: mkPackageOption ... default =
        # "kanata-with-cmd"), and the two differ by the `cmd` cargo feature, hence
        # by store path. Switching to plain `kanata` would silently invalidate both
        # TCC grants -- the symptom is kanata starting fine, validating its config,
        # then failing with `failed to open keyboard device(s)`.
        package = inputs.nixpkgs-kanata.legacyPackages.${pkgs.stdenv.hostPlatform.system}.kanata-with-cmd;
      };

      # Read-only permission check.
      #
      # This deliberately does NOT repair anything. The previous version called
      # `/usr/bin/tccutil reset ListenEvent`, which takes no bundle identifier and
      # therefore resets Input Monitoring for *every* client on the system -- and
      # it fired whenever the sqlite lookup returned anything other than "2",
      # including when the lookup merely failed to read. With the package pinned
      # the grants are stable, so a warning is the correct behaviour and a
      # system-wide reset is pure downside.
      #
      # kanata needs BOTH grants. Input Monitoring alone is not enough: without
      # Accessibility it starts, validates its config, enters the event loop and
      # then fails with `failed to open keyboard device(s)` (kanata issue #1211).
      system.activationScripts.extraActivation.text =
        let
          bin = "${config.services.kanata.package}/bin/kanata";
          db = "/Library/Application Support/com.apple.TCC/TCC.db";
        in
        lib.mkAfter ''
          _missing=""
          for _svc in kTCCServiceListenEvent kTCCServiceAccessibility; do
            _auth=$(/usr/bin/sqlite3 "${db}" \
              "SELECT auth_value FROM access WHERE service='$_svc' AND client='${bin}';" 2>/dev/null)
            [ "$_auth" = "2" ] || _missing="$_missing $_svc"
          done
          if [ -n "$_missing" ]; then
            echo "kanata: MISSING TCC grant(s):$_missing"
            echo "kanata:   binary: ${bin}"
            echo "kanata:   Add it under System Settings -> Privacy & Security ->"
            echo "kanata:   Input Monitoring AND Accessibility (both are required)."
            echo "kanata:   The file picker hides /nix/store; press Cmd-Shift-G and paste the path."
          fi
        '';
    };
}
