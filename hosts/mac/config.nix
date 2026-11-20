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
        gcm = "${pkgs.git-credential-manager}/bin/git-credential-manager";
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
          # GCM records which account signs in to an org in the global git config, which nix
          # keeps read-only, so declare the binding here.
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
