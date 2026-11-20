let
  username = "igor.sukhinskii";
  homeDirectory = /Users/igor.sukhinskii;
  stateVersion = "25.05";
in
{ lib, ... }:
{
  options.host = {
    username = lib.mkOption { type = lib.types.str; };
    homeDirectory = lib.mkOption { type = lib.types.path; };
    stateVersion = lib.mkOption { type = lib.types.str; };
  };

  config = {
    host = { inherit username homeDirectory stateVersion; };

    home-manager.users.${username} =
      { pkgs, ... }:
      let
        # GCM's `store` for Azure Repos OAuth only re-binds the account to the org in the global
        # git config (every time), which nix keeps read-only; tokens live in GCM's MSAL cache in
        # the keychain. So skip `store` and declare the binding below instead.
        gcm = toString (
          pkgs.writeShellScript "git-credential-azure" ''
            if [ "$1" = store ]; then cat >/dev/null; exit 0; fi
            exec ${pkgs.git-credential-manager}/bin/git-credential-manager "$@"
          ''
        );
      in
      {
        home.username = username;
        home.homeDirectory = homeDirectory;
        home.stateVersion = stateVersion;
        programs.home-manager.enable = true;

        # Azure DevOps over HTTPS with Git Credential Manager signing in through Entra ID:
        # no SSH key or PAT to rotate, tokens refresh on use and live in the login keychain.
        # Scoped to the two Azure DevOps hosts; GitHub stays with gh.
        home.packages = [ pkgs.git-credential-manager ];
        programs.git.settings.credential = {
          azreposCredentialType = "oauth";
          credentialStore = "keychain";
          # The account bound to the org (GCM would write this itself; see gcm above).
          "azrepos:org/mirasys".username = "igor.sukhinskii@mirasys.com";
          "https://dev.azure.com" = {
            helper = [
              ""
              gcm
            ];
            useHttpPath = true;
          };
          "https://mirasys.visualstudio.com".helper = [
            ""
            gcm
          ];
        };
      };
  };
}
