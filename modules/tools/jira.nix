{ ... }:
{
  flake.homeManagerModules.jira =
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
      # Prints the Atlassian API token from Keychain — same token works for both
      # Jira and Confluence. Usage:
      #   TOKEN=$(atlassian-token)
      #   curl -u "you@example.com:$TOKEN" https://yourorg.atlassian.net/wiki/rest/api/...
      atlassianToken = pkgs.writeShellScriptBin "atlassian-token" ''
        set -euo pipefail
        security find-generic-password -a "$USER" -s jira-api-token -w 2>/dev/null || {
          echo "Keychain item 'jira-api-token' not found" >&2
          exit 1
        }
      '';
    in
    {
      home.packages = [
        jiraWrapper
        atlassianToken
      ];
    };
}
