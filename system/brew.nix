{ ... }:
{
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "zap";
      upgrade = false;
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
