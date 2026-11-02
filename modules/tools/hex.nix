{ ... }:
{
  # Hex (github.com/anomalyco/hex): local dictation; replaced OpenWhispr on
  # 2026-11-02. Its flake packages Linux only, so this takes the signed macOS
  # release zip. The bundle keeps Anomaly's Developer ID signature (no ad-hoc
  # re-sign), so macOS permission grants survive version bumps. In-app updates
  # can't replace a store path; bump `version` and `hash` here instead.
  flake.homeManagerModules.hex =
    { pkgs, ... }:
    let
      hex = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "hex";
        version = "3.2.0";
        src = pkgs.fetchurl {
          url = "https://github.com/anomalyco/hex/releases/download/v${version}/hex-${version}-macos-arm64.zip";
          hash = "sha256-0pa5MbVzUHGaatzPSuJQ9bH70dVMN4WbzKio7w80Fu8=";
        };
        nativeBuildInputs = [ pkgs.unzip ];
        sourceRoot = ".";
        dontFixup = true; # fixup would rewrite files and break the signature
        installPhase = ''
          mkdir -p $out/Applications $out/bin
          cp -R Hex.app $out/Applications/
          /usr/bin/codesign --verify --deep --strict $out/Applications/Hex.app
          # The control CLI (`hex status`, `hex settings set ...`) is the app binary.
          cat > $out/bin/hex <<EOF
          #!/bin/sh
          exec "$out/Applications/Hex.app/Contents/MacOS/hex" "\$@"
          EOF
          chmod +x $out/bin/hex
        '';
      };
    in
    {
      home.packages = [ hex ];
    };
}
