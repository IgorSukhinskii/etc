{ ... }:
{
  flake.homeManagerModules.openwhispr =
    { pkgs, lib, ... }:
    lib.mkIf pkgs.stdenv.isDarwin {
      home.activation.openwhispr = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        /usr/bin/xattr -cr "$HOME/Applications/Home Manager Apps/OpenWhispr.app" 2>/dev/null || true
      '';

      home.packages = [
        (pkgs.stdenvNoCC.mkDerivation {
          pname = "openwhispr";
          version = "1.6.5";
          src = pkgs.fetchurl {
            url = "https://github.com/OpenWhispr/openwhispr/releases/download/v1.6.5/OpenWhispr-1.6.5-arm64.dmg";
            hash = "sha256-qPT/pftSixffB2ULIureiiu9YodvxKTSiWg7IlfMmNM=";
          };
          nativeBuildInputs = [ pkgs.undmg ];
          sourceRoot = ".";
          installPhase = ''
            mkdir -p $out/Applications
            cp -r *.app $out/Applications/
            /usr/bin/codesign --force --deep --sign - $out/Applications/*.app
          '';
        })
      ];
    };
}
