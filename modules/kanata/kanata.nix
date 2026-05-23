{ inputs, ... }:
{
  flake.darwinModules.kanata =
    { config, lib, ... }:
    {
      imports = [ inputs.kanata-darwin.darwinModules.default ];

      services.kanata = {
        enable = true;
        daemon.enable = true;
        configSource = ./kanata.kbd;
      };

      # When the nix store path for kanata changes (e.g. after `nix flake update`),
      # macOS loses the Input Monitoring TCC entry because it tracks by binary path.
      # tccutil has the entitlements to modify the system TCC DB (sqlite3 cannot).
      # This script:
      #   1. Skips if the current binary is already authorized (same hash, no rebuild)
      #   2. Resets ListenEvent so the new binary appears in System Settings Input Monitoring
      #   3. Restarts kanata and opens the pane so the user can toggle it in one click
      system.activationScripts.extraActivation.text =
        let
          bin = "${config.services.kanata.package}/bin/kanata";
          user = config.services.kanata.user;
          db = "/Library/Application Support/com.apple.TCC/TCC.db";
        in
        lib.mkAfter ''
          _uid=$(id -u "${user}" 2>/dev/null || true)
          if [ -n "$_uid" ]; then
            _auth=$(/usr/bin/sqlite3 "${db}" \
              "SELECT auth_value FROM access WHERE service='kTCCServiceListenEvent' AND client='${bin}';" 2>/dev/null)
            if [ "$_auth" != "2" ]; then
              echo "kanata: binary path changed — resetting Input Monitoring TCC and opening System Settings"
              /usr/bin/tccutil reset ListenEvent
              sleep 0.3
              /bin/launchctl kickstart -k "gui/$_uid/org.kanata.daemon" 2>/dev/null || true
              /bin/launchctl asuser "$_uid" /usr/bin/open \
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent" 2>/dev/null &
              /bin/launchctl asuser "$_uid" /usr/bin/osascript -e \
                'display notification "Enable kanata in System Settings → Input Monitoring (one toggle)." with title "kanata: Input Monitoring needed"' 2>/dev/null &
            fi
          fi
        '';
    };
}
