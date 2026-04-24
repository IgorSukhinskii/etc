{ ... }:
{
  flake.homeManagerModules.ical =
    { pkgs, lib, ... }:
    lib.mkIf pkgs.stdenv.isDarwin {
      home.packages = [
        (pkgs.stdenvNoCC.mkDerivation {
          name = "ical-0.7.0";
          src = pkgs.fetchurl {
            url = "https://github.com/BRO3886/ical/releases/download/v0.7.0/ical-darwin-arm64.tar.gz";
            hash = "sha256-kNdH7NXWIjCZTDUneraOI6wsdnwwmq6UdcHqzSJmZcI=";
          };
          phases = [ "installPhase" ];
          installPhase = ''
            mkdir -p $out/bin
            tar -xzf $src -C "$TMPDIR"
            find "$TMPDIR" -name 'ical' -type f -exec install -m755 {} $out/bin/ical \;
          '';
        })
      ];
    };
}
