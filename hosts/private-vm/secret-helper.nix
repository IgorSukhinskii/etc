# LUKS-passphrase store for private-vm.
#
# Exports a single command, `private-vm-secret`, with subcommands:
#
#   private-vm-secret set [--replace]
#   private-vm-secret get
#   private-vm-secret delete
#
# Storage model: an age-encrypted file with a Secure Enclave-backed age
# identity. `age-plugin-se` (from Homebrew, with the codesigning context
# preserved enough for SE access) creates a P-256 key inside the Secure
# Enclave with `any-biometry-or-passcode` access control. Touch ID is
# enforced at the hardware level on every decrypt; the private key never
# leaves the SE.
#
# Files (under $XDG_CONFIG_HOME/private-vm):
#   identity.txt   — handle to the SE key (useless without this Mac)
#   luks.age       — age-encrypted LUKS passphrase
#
# The `age` binary itself comes from nixpkgs; `age-plugin-se` must be on
# PATH and is provided by the Homebrew formula installed via
# `homebrew.brews` in the darwin module. A nix-built copy of the plugin
# would not work — its Secure Enclave access depends on the build's
# codesigning context which the nix sandbox does not preserve.
{ pkgs, vmUser }:
let
  privateVmSecret = pkgs.writeShellScriptBin "private-vm-secret" ''
    set -euo pipefail

    # Locate age-plugin-se. `age` discovers plugins by name on PATH.
    export PATH="/opt/homebrew/bin:$PATH"
    if ! command -v age-plugin-se >/dev/null 2>&1; then
      echo "error: age-plugin-se not on PATH. Install with: brew install age-plugin-se" >&2
      exit 1
    fi

    age="${pkgs.age}/bin/age"
    cfg_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/private-vm"
    identity="$cfg_dir/identity.txt"
    secret="$cfg_dir/luks.age"

    cmd="''${1:-}"
    shift || true

    case "$cmd" in
      set)
        replace=0
        if [[ "''${1:-}" == "--replace" ]]; then
          replace=1
        fi

        if [[ -e "$secret" && "$replace" != 1 ]]; then
          echo "error: $secret already exists. Re-run with --replace to overwrite." >&2
          exit 1
        fi

        mkdir -p "$cfg_dir"
        chmod 700 "$cfg_dir"

        if [[ ! -e "$identity" ]]; then
          # First-time setup. Creating the SE key does not prompt Touch ID;
          # the prompt fires on first decrypt (`get`). The chosen policy
          # (any-biometry-or-passcode) means losing/changing your fingerprint
          # falls back to the device passcode rather than locking you out.
          echo "Creating Secure Enclave identity at $identity..." >&2
          age-plugin-se keygen \
            --access-control any-biometry-or-passcode \
            -o "$identity" >&2
          chmod 600 "$identity"
        fi
        recipient=$(age-plugin-se recipients -i "$identity")

        echo "Enter LUKS passphrase (blank = generate random 32-byte hex): " >&2
        IFS= read -rs pw
        echo >&2
        if [[ -z "$pw" ]]; then
          pw=$(${pkgs.openssl}/bin/openssl rand -hex 32)
          printf '\nGenerated passphrase — save it to a password manager NOW.\nIt will not be shown again:\n\n%s\n\nPress Enter when saved... ' "$pw" >&2
          read -r _
        fi

        # Encrypt the raw passphrase bytes with NO trailing newline.
        # cryptsetup's `--key-file=-` treats stdin as raw bytes when piped
        # (newlines become part of the key), so any newline we append here
        # would mismatch the bytes used at `luksFormat` time. Consumers that
        # need a clean line on the guest side must use `cat`, not `read`.
        tmp=$(mktemp "$cfg_dir/.luks.age.XXXXXX")
        trap 'rm -f "$tmp"' EXIT
        printf '%s' "$pw" | "$age" -r "$recipient" -o "$tmp"
        chmod 600 "$tmp"
        mv "$tmp" "$secret"
        trap - EXIT
        unset pw

        echo "Stored at $secret (Touch ID required for read)." >&2
        ;;

      get)
        if [[ ! -e "$secret" || ! -e "$identity" ]]; then
          echo "error: secret store not initialized. Run: vm secret-set" >&2
          exit 1
        fi
        # Triggers a Touch ID prompt owned by `age-plugin-se`.
        exec "$age" -d -i "$identity" "$secret"
        ;;

      delete)
        rm -f "$secret" "$identity"
        echo "Removed $secret and $identity." >&2
        echo "Note: the underlying Secure Enclave key remains in the SE but is" >&2
        echo "unreachable without the identity file." >&2
        ;;

      *)
        echo "usage: private-vm-secret <set [--replace] | get | delete>" >&2
        exit 2 ;;
    esac
  '';
in
{
  inherit privateVmSecret;
}
