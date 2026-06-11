# Keychain + Touch ID helpers for private-vm host-side scripts.
# Imported by modules/nix-dev.nix as:
#   keychainHelper = import ./keychain-helper.nix { inherit pkgs vmUser; };
#
# Exports:
#   touchIdPrompt       — nix store path to keychain-helper.swift, passed as an
#                         arg to /usr/bin/swift in shell scripts that need Touch ID
#   privateVmKeychainSet — one-time setup: stores the LUKS passphrase in macOS
#                          Keychain (service=private-vm-luks). Requires no prior
#                          Touch ID auth; the Keychain item is protected by the
#                          login keychain. Touch ID is enforced at *read* time by
#                          the scripts that call /usr/bin/swift touchIdPrompt.
{ pkgs, vmUser }:
let
  touchIdPrompt = pkgs.writeText "private-vm-touchid.swift" (
    builtins.readFile ./keychain-helper.swift
  );

  privateVmKeychainSet = pkgs.writeShellScriptBin "private-vm-keychain-set" ''
    # One-time setup: store the LUKS passphrase in Keychain.
    # Touch ID is NOT required here — this is the setup step where you
    # deliberately create the entry. Reads are gated by Touch ID at unlock time.
    set -euo pipefail

    if security find-generic-password -a "${vmUser}" -s private-vm-luks >/dev/null 2>&1; then
      echo "error: Keychain entry already exists. To replace it:" >&2
      echo "  security delete-generic-password -a ${vmUser} -s private-vm-luks" >&2
      exit 1
    fi

    echo "Enter the LUKS passphrase (blank = generate random 32-byte hex):" >&2
    IFS= read -rs pw
    echo >&2
    if [[ -z "$pw" ]]; then
      pw=$(${pkgs.openssl}/bin/openssl rand -hex 32)
      echo "Generated passphrase — save this to your password manager now:" >&2
      printf '%s\n\n' "$pw" >&2
      echo "Press Enter when saved..." >&2
      read -r
    fi

    security add-generic-password -a "${vmUser}" -s private-vm-luks -w "$pw"
    echo "Stored in Keychain (service=private-vm-luks, account=${vmUser})." >&2
  '';
in
{
  inherit touchIdPrompt privateVmKeychainSet;
}
