{ ... }:
{
  flake.darwinModules.defender =
    { config, lib, ... }:
    let
      home = toString config.host.homeDirectory;
      folders = [
        "/nix/store"
        "/nix/var"
        "/var/lib/linux-builder"
        "/opt/homebrew"
        "${home}/.cache/nix"
        "${home}/.local/state/private-vm"
        "${home}/Library/Caches"
      ];
      extensions = [ "qcow2" ];
      shellArray = items: lib.concatStringsSep " " (map lib.escapeShellArg items);
    in
    {
      system.activationScripts.postActivation.text = ''
        if [ ! -x /usr/local/bin/mdatp ]; then
          echo "[defender] mdatp not installed, skipping exclusion sync"
        else
          echo "[defender] syncing exclusions"
          declared_folders=(${shellArray folders})
          declared_exts=(${shellArray extensions})

          parsed=$(/usr/local/bin/mdatp exclusion list 2>/dev/null | /usr/bin/awk '
            /^Excluded folder/    { mode="folder"; next }
            /^Excluded extension/ { mode="ext";    next }
            /^====/               { mode="" }
            mode=="folder" && /^Path:/      { sub(/^Path: *"/, ""); sub(/"$/, "");      print "FOLDER:" $0 }
            mode=="ext"    && /^Extension:/ { sub(/^Extension: *\.?/, "");              print "EXT:" $0 }
          ')
          current_folders=$(printf '%s\n' "$parsed" | /usr/bin/sed -n 's/^FOLDER://p')
          current_exts=$(printf '%s\n'    "$parsed" | /usr/bin/sed -n 's/^EXT://p')

          in_array() {
            local needle=$1; shift
            for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
            return 1
          }

          while IFS= read -r p; do
            [ -z "$p" ] && continue
            if ! in_array "$p" "''${declared_folders[@]}"; then
              echo "[defender] - folder $p"
              /usr/local/bin/mdatp exclusion folder remove --path "$p" >/dev/null
            fi
          done <<< "$current_folders"

          for d in "''${declared_folders[@]}"; do
            if ! printf '%s\n' "$current_folders" | /usr/bin/grep -qxF "$d"; then
              echo "[defender] + folder $d"
              /usr/local/bin/mdatp exclusion folder add --path "$d" >/dev/null
            fi
          done

          while IFS= read -r e; do
            [ -z "$e" ] && continue
            if ! in_array "$e" "''${declared_exts[@]}"; then
              echo "[defender] - ext $e"
              /usr/local/bin/mdatp exclusion extension remove --name "$e" >/dev/null
            fi
          done <<< "$current_exts"

          for d in "''${declared_exts[@]}"; do
            if ! printf '%s\n' "$current_exts" | /usr/bin/grep -qxF "$d"; then
              echo "[defender] + ext $d"
              /usr/local/bin/mdatp exclusion extension add --name "$d" >/dev/null
            fi
          done
        fi
      '';
    };
}
