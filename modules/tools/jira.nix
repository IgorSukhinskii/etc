{ pkgs, lib, ... }:
let
  jiraBin = "${pkgs.jira-cli-go}/bin/jira";
  jiraWrapper = pkgs.writeShellScriptBin "jira" ''
    set -euo pipefail
    token="$(security find-generic-password -a "$USER" -s jira-api-token -w 2>/dev/null)" || {
      echo "Keychain item 'jira-api-token' not found" >&2
      exit 1
    }
    exec env \
      JIRA_AUTH_TYPE="basic" \
      JIRA_API_TOKEN="$token" \
      "${jiraBin}" "$@"
  '';
in
lib.mkIf pkgs.stdenv.isDarwin {
  home.packages = [ jiraWrapper ];
}
