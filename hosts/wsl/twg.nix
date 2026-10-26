# Host-local: WSL calls the Windows twg.exe rather than holding a second login.
# DEV1's Windows side installs twg (setup-igor) and holds the OAuth login, its
# encrypted storage (root key in Credential Manager) and the upkeep task; this
# wrapper only hands the arguments over through interop. File-path arguments
# must be Windows paths (`wslpath -w`), and output may end lines with CRLF.
{ pkgs, ... }:
let
  twgExe = "/mnt/c/Users/igor.sukhinskii/AppData/Local/Programs/twg/bin/twg.exe";
in
{
  home.packages = [
    (pkgs.writeShellScriptBin "twg" ''
      if [ ! -x ${twgExe} ]; then
        echo "twg: ${twgExe} not found; install twg on the Windows side (setup-igor)" >&2
        exit 127
      fi
      exec ${twgExe} "$@"
    '')
  ];
}
