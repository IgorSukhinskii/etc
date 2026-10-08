# hosts/wsl

NixOS-WSL on a Windows work machine. Everything here is declared except what
can't be: the claude and codex logins, SSH keys, and t3's pairing.

## From scratch

Tested 2026-10-08 on a throwaway distro. On Windows, as the user (not
elevated), with no other NixOS-WSL distro running: distros share one kernel,
and a second systemd user manager for the same UID fails to start.

```powershell
wsl --unregister NixOS   # when replacing one
wsl --shutdown           # clears what it leaves behind
wsl --import NixOS $env:LOCALAPPDATA\WSL\NixOS nixos.wsl --version 2   # NixOS-WSL release
```

The fresh image boots as `nixos`; this config's user is `igor`. Build it from
GitHub (no git needed yet) and switch users the way NixOS-WSL documents it
(`boot`, not `switch`):

```powershell
wsl -d NixOS --user root --exec /run/current-system/sw/bin/bash -lc "NIX_CONFIG='experimental-features = nix-command flakes' nixos-rebuild boot --flake github:IgorSukhinskii/etc#wsl"
wsl -t NixOS
wsl -d NixOS --user root exit
wsl -t NixOS
```

The next start is `igor`. home-manager installs claude, codex and t3 and starts
t3's service ([t3.nix](t3.nix)). Then, inside:

```sh
git clone https://github.com/IgorSukhinskii/etc ~/etc   # nix-rebuild works from here
claude auth login
codex login
```

Then pair t3 again from the client: the server identity is new.
