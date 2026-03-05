{ ... }:
{
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      upgrade = true;
    };
    taps = [ "mhaeuser/mhaeuser" ];
    casks = [
      "alt-tab"
      "raycast"
      "bitwarden"
      "battery-toolkit"
      "qmk-toolbox"
      "vial"
      "claude-code"
    ];
  };
}
