{ ... }:
{
  # ── darwin: auto-hide native menu bar (sketchybar replaces it visually) ────
  flake.darwinModules.sketchybar =
    { pkgs, ... }:
    {
      system.defaults.NSGlobalDomain._HIHideMenuBar = true;
      fonts.packages = [ pkgs.nerd-fonts.symbols-only ]; # kept for non-apple icons
      homebrew.casks = [
        "sf-symbols" # SF Symbols app
        "font-sf-pro" # installs "SF Pro Display" and "SF Pro Text" families
      ];
    };

  # ── home-manager: install + configure sketchybar ──────────────────────────
  flake.homeManagerModules.sketchybar =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      dc = config.themes.palette.dark;
      lc = config.themes.palette.light;

      mkClr = palette: key: "0xff${palette.${key}}";

      # Map semantic names → base24 keys (same key for both polarities)
      colorMap = {
        CLR_BG = "base00";
        CLR_BGALT = "base01";
        CLR_DIM = "base03";
        CLR_FG = "base05";
        CLR_RED = "base08";
        CLR_ORANGE = "base09";
        CLR_YELLOW = "base0A";
        CLR_GREEN = "base0B";
        CLR_CYAN = "base0C";
        CLR_BLUE = "base0D";
        CLR_VIOLET = "base0E";
      };

      # Render one palette branch as shell assignments
      mkBranch =
        palette:
        lib.concatStrings (lib.mapAttrsToList (name: key: "  ${name}=\"${mkClr palette key}\"\n") colorMap);

      # ── fonts ──────────────────────────────────────────────────────────────
      fontIcon = "SF Pro Display:Regular";
      fontLabel = "SF Pro Text:Regular";
      fontSys = ".SF NS:Regular";
      fontNF = "Symbols Nerd Font:Regular";

      # ── icons ──────────────────────────────────────────────────────────────
      # Nix regular strings: "$'\\uXXXX'" → bash $'\uXXXX' → glyph
      icoApple = "􀣺";
      icoVolHi = "$'\\uf028'"; # nf-fa-volume-up
      icoVolMed = "$'\\uf027'"; # nf-fa-volume-down
      icoVolOff = "$'\\uf026'"; # nf-fa-volume-off (muted + low)
      icoWifi = "$'\\uf1eb'"; # nf-fa-wifi
      icoBt = "$'\\uf294'"; # nf-fa-bluetooth-b
      icoBatF = "$'\\uf240'"; # nf-fa-battery-full
      icoBat34 = "$'\\uf241'"; # nf-fa-battery-three-quarters
      icoBatH = "$'\\uf242'"; # nf-fa-battery-half
      icoBat14 = "$'\\uf243'"; # nf-fa-battery-quarter
      icoBatE = "$'\\uf244'"; # nf-fa-battery-empty
      icoPlug = "$'\\uf1e6'"; # nf-fa-plug  (charging/AC)
      icoClock = "$'\\uf017'"; # nf-fa-clock-o

      # ── plugin scripts ─────────────────────────────────────────────────────
      pluginVolume = pkgs.writeShellApplication {
        name = "sketchybar-volume";
        runtimeInputs = [ pkgs.sketchybar ];
        excludeShellChecks = [ "SC1091" ];
        text = ''
          source "$HOME/.config/sketchybar/colors.sh"

          VOL=$(osascript -e "output volume of (get volume settings)")
          MUTED=$(osascript -e "output muted of (get volume settings)")

          if [ "$MUTED" = "true" ]; then
            ICON=${icoVolOff}
            COLOR="$CLR_DIM"
          elif [ "$VOL" -gt 66 ]; then
            ICON=${icoVolHi}
            COLOR="$CLR_BLUE"
          elif [ "$VOL" -gt 33 ]; then
            ICON=${icoVolMed}
            COLOR="$CLR_BLUE"
          else
            ICON=${icoVolOff}
            COLOR="$CLR_BLUE"
          fi

          sketchybar --set "$NAME" \
            icon="$ICON" \
            icon.color="$COLOR" \
            label="$VOL%" \
            label.color="$CLR_FG" \
            background.color="$CLR_BGALT"
        '';
      };

      pluginWifi = pkgs.writeShellApplication {
        name = "sketchybar-wifi";
        runtimeInputs = [ pkgs.sketchybar ];
        excludeShellChecks = [ "SC1091" ];
        text = ''
          source "$HOME/.config/sketchybar/colors.sh"

          ADDR=$(ipconfig getifaddr en0 2>/dev/null)

          if [ -z "$ADDR" ]; then
            COLOR="$CLR_DIM"
          else
            COLOR="$CLR_CYAN"
          fi

          sketchybar --set "$NAME" \
            icon=${icoWifi} \
            icon.color="$COLOR" \
            label.color="$CLR_FG" \
            background.color="$CLR_BGALT"
        '';
      };

      pluginBluetooth = pkgs.writeShellApplication {
        name = "sketchybar-bluetooth";
        runtimeInputs = [
          pkgs.sketchybar
          pkgs.blueutil
          pkgs.switchaudio-osx
        ];
        excludeShellChecks = [ "SC1091" ];
        text = ''
          source "$HOME/.config/sketchybar/colors.sh"

          POWER=$(blueutil --power)
          CONNECTED=$(blueutil --connected | wc -l | tr -d ' ')

          # Extract up to 3 device names from: address: ..., name: "Foo", ...
          DEV1=$(blueutil --connected | awk -F'"' 'NR==1{print $2}')
          DEV2=$(blueutil --connected | awk -F'"' 'NR==2{print $2}')
          DEV3=$(blueutil --connected | awk -F'"' 'NR==3{print $2}')

          # Update popup slots (show/hide each)
          for N in 1 2 3; do
            eval "DEV=\$DEV$N"
            if [ -n "$DEV" ]; then
              sketchybar --set "bt_dev$N" label="$DEV" label.drawing=on
            else
              sketchybar --set "bt_dev$N" label="" label.drawing=off
            fi
          done

          # Detect BT audio: current output device matches a connected BT device
          AUDIO=$(SwitchAudioSource -c 2>/dev/null || true)
          BT_AUDIO=false
          for DEV in "$DEV1" "$DEV2" "$DEV3"; do
            if [ -n "$DEV" ] && echo "$AUDIO" | grep -qi "$DEV"; then
              BT_AUDIO=true
              break
            fi
          done

          if [ "$POWER" = "0" ]; then
            COLOR="$CLR_DIM"
          elif [ "$CONNECTED" -gt 0 ] && [ "$BT_AUDIO" = "true" ]; then
            COLOR="$CLR_GREEN"
          elif [ "$CONNECTED" -gt 0 ]; then
            COLOR="$CLR_VIOLET"
          else
            COLOR="$CLR_VIOLET"
          fi

          sketchybar --set "$NAME" \
            icon=${icoBt} \
            icon.color="$COLOR" \
            background.color="$CLR_BGALT"
        '';
      };

      pluginBattery = pkgs.writeShellApplication {
        name = "sketchybar-battery";
        runtimeInputs = [ pkgs.sketchybar ];
        excludeShellChecks = [ "SC1091" ];
        text = ''
          source "$HOME/.config/sketchybar/colors.sh"

          BATT_INFO=$(pmset -g batt)
          PERCENT=$(echo "$BATT_INFO" | grep -o '[0-9]*%' | head -1 | tr -d '%')
          PLUGGED=$(echo "$BATT_INFO" | grep -c 'AC Power' || true)
          CHARGING=$(echo "$BATT_INFO" | grep -c 'charging' || true)

          if [ "$PLUGGED" -gt 0 ] && [ "$CHARGING" -gt 0 ]; then
            ICON=${icoPlug}
            COLOR="$CLR_GREEN"
          elif [ "$PERCENT" -ge 75 ]; then
            ICON=${icoBatF}
            COLOR="$CLR_GREEN"
          elif [ "$PERCENT" -ge 50 ]; then
            ICON=${icoBat34}
            COLOR="$CLR_GREEN"
          elif [ "$PERCENT" -ge 25 ]; then
            ICON=${icoBatH}
            COLOR="$CLR_ORANGE"
          elif [ "$PERCENT" -ge 10 ]; then
            ICON=${icoBat14}
            COLOR="$CLR_RED"
          else
            ICON=${icoBatE}
            COLOR="$CLR_RED"
          fi

          sketchybar --set "$NAME" \
            icon="$ICON" \
            icon.color="$COLOR" \
            label="$PERCENT%" \
            label.color="$CLR_FG" \
            background.color="$CLR_BGALT"
        '';
      };

      pluginClock = pkgs.writeShellApplication {
        name = "sketchybar-clock";
        runtimeInputs = [ pkgs.sketchybar ];
        excludeShellChecks = [ "SC1091" ];
        text = ''
          source "$HOME/.config/sketchybar/colors.sh"

          sketchybar --set "$NAME" \
            icon=${icoClock} \
            icon.color="$CLR_YELLOW" \
            label="$(date '+%H:%M  %a %d %b')" \
            label.color="$CLR_FG" \
            background.color="$CLR_BGALT"
        '';
      };

      pluginTheme = pkgs.writeShellApplication {
        name = "sketchybar-theme";
        runtimeInputs = [ pkgs.sketchybar ];
        excludeShellChecks = [ "SC1091" ];
        text = ''
          source "$HOME/.config/sketchybar/colors.sh"

          sketchybar --bar color=0x00000000 \
            --default icon.color="$CLR_FG" label.color="$CLR_FG" \
            --set '/.*/' background.color="$CLR_BGALT" label.color="$CLR_FG" \
            --set apple icon.color="$CLR_VIOLET" background.drawing=off \
            --set sys_group background.color="$CLR_BGALT" \
            --set net_group background.color="$CLR_BGALT"
        '';
      };

    in
    lib.mkIf pkgs.stdenv.isDarwin {
      programs.sketchybar = {
        enable = true;
        extraPackages = [
          pluginVolume
          pluginWifi
          pluginBluetooth
          pluginBattery
          pluginClock
          pluginTheme
        ];
        config = /* bash */ ''
          #!${pkgs.bash}/bin/bash

          source "$HOME/.config/sketchybar/colors.sh"

          # ── hot-reload on config file change ────────────────────────────────
          sketchybar --hotload true

          # ── theme: register event before any items subscribe to it ─────────
          sketchybar --add event theme_change AppleInterfaceThemeChangedNotification

          # ── bar geometry & appearance ───────────────────────────────────────
          sketchybar --bar \
            height=32 \
            position=top \
            sticky=on \
            padding_left=12 \
            padding_right=12 \
            color=0x00000000 \
            border_width=0 \
            corner_radius=0 \
            blur_radius=0 \
            notch_width=188

          # ── global item defaults ────────────────────────────────────────────
          sketchybar --default \
            icon.font="${fontNF}:24.0" \
            icon.color="$CLR_FG" \
            label.font="${fontLabel}:24.0" \
            label.color="$CLR_FG" \
            label.padding_left=4 \
            label.padding_right=6 \
            icon.padding_left=6 \
            icon.padding_right=2 \
            background.height=24 \
            background.corner_radius=12 \
            background.border_width=0 \
            update_freq=0

          # ── LEFT: Apple logo ────────────────────────────────────────────────
          sketchybar --add item apple left \
            --set apple \
              icon=${icoApple} \
              icon.color="$CLR_VIOLET" \
              icon.padding_left=4 \
              icon.padding_right=4 \
              label.drawing=off \
              label.color=0x00000000 \
              background.drawing=off \
              click_script="open -a 'System Settings'"

          # ── RIGHT: clock ────────────────────────────────────────────────────
          sketchybar --add item clock right \
            --set clock \
              update_freq=10 \
              script="sketchybar-clock" \
              background.color="$CLR_BGALT" \
              background.drawing=on \
              icon.color="$CLR_YELLOW" \
              label.color="$CLR_FG" \
            --subscribe clock theme_change

          # ── RIGHT: battery ──────────────────────────────────────────────────
          sketchybar --add item battery right \
            --set battery \
              update_freq=60 \
              script="sketchybar-battery" \
              label.width=60 \
              label.align=right \
              background.color="$CLR_BGALT" \
              background.drawing=on \
            --subscribe battery theme_change

          # ── RIGHT: system group bracket (battery + clock) ───────────────────
          sketchybar --add bracket sys_group battery clock \
            --set sys_group \
              background.color="$CLR_BGALT" \
              background.corner_radius=8 \
              background.height=32 \
              background.drawing=on

          # ── RIGHT: bluetooth ────────────────────────────────────────────────
          sketchybar --add item bluetooth right \
            --set bluetooth \
              update_freq=30 \
              script="sketchybar-bluetooth" \
              click_script="sketchybar --set \$NAME popup.drawing=toggle" \
              background.color="$CLR_BGALT" \
              background.drawing=on \
            --subscribe bluetooth theme_change

          # ── bluetooth popup: up to 3 connected device name slots ────────────
          sketchybar --add item bt_dev1 popup.bluetooth \
            --set bt_dev1 \
              label="" \
              label.drawing=off \
              background.drawing=off

          sketchybar --add item bt_dev2 popup.bluetooth \
            --set bt_dev2 \
              label="" \
              label.drawing=off \
              background.drawing=off

          sketchybar --add item bt_dev3 popup.bluetooth \
            --set bt_dev3 \
              label="" \
              label.drawing=off \
              background.drawing=off

          # ── RIGHT: wifi ─────────────────────────────────────────────────────
          sketchybar --add item wifi right \
            --set wifi \
              update_freq=30 \
              script="sketchybar-wifi" \
              label.drawing=off \
              background.color="$CLR_BGALT" \
              background.drawing=on \
            --subscribe wifi theme_change

          # ── RIGHT: volume ───────────────────────────────────────────────────
          sketchybar --add item volume right \
            --set volume \
              script="sketchybar-volume" \
              label.width=60 \
              label.align=right \
              background.color="$CLR_BGALT" \
              background.drawing=on \
            --subscribe volume volume_change theme_change

          # ── RIGHT: network group bracket (volume + wifi + bluetooth) ────────
          sketchybar --add bracket net_group volume wifi bluetooth \
            --set net_group \
              background.color="$CLR_BGALT" \
              background.corner_radius=8 \
              background.height=32 \
              background.drawing=on

          # ── theme: sentinel for static elements (bar, brackets, apple) ─────
          sketchybar --add item theme_sentinel left \
            --set theme_sentinel \
              drawing=off \
              script="sketchybar-theme" \
            --subscribe theme_sentinel theme_change

          # ── trigger initial run of all scripts ──────────────────────────────
          sketchybar --update
        '';
      };

      home.file.".config/sketchybar/colors.sh".text = ''
        if [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ]; then
        ${mkBranch dc}else
        ${mkBranch lc}fi
      '';
    };
}
