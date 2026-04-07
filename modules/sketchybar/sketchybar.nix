{ ... }:
{
  # ── darwin: hide the native menu bar ──────────────────────────────────────
  flake.darwinModules.sketchybar =
    { pkgs, ... }:
    {
      system.defaults.NSGlobalDomain._HIHideMenuBar = true;
      fonts.packages = [ pkgs.nerd-fonts.hack ]; # kept for non-apple icons
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
      c = config.themes.palette.dark;

      # sketchybar color format: "0xff" + 6-digit hex (no #)
      # Names follow the base24 spec — stable across all themes
      clrBg = "0xff${c.base00}"; # default background
      clrBgAlt = "0xff${c.base01}"; # lighter background
      clrDim = "0xff${c.base03}"; # comments / dimmed
      clrFg = "0xff${c.base05}"; # default foreground
      clrRed = "0xff${c.base08}"; # red   (errors/deleted)
      clrOrange = "0xff${c.base09}"; # orange (constants)
      clrYellow = "0xff${c.base0A}"; # yellow (warnings)
      clrGreen = "0xff${c.base0B}"; # green  (strings/success)
      clrCyan = "0xff${c.base0C}"; # cyan   (support)
      clrBlue = "0xff${c.base0D}"; # blue   (functions)
      clrViolet = "0xff${c.base0E}"; # violet (keywords)

      # ── fonts ──────────────────────────────────────────────────────────────
      fontIcon = "SF Pro Display:Regular";
      fontLabel = "SF Pro Text:Regular";
      fontSys = ".SF NS:Regular";
      fontNF = "Hack Nerd Font:Regular";

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
        text = ''
          VOL=$(osascript -e "output volume of (get volume settings)")
          MUTED=$(osascript -e "output muted of (get volume settings)")

          if [ "$MUTED" = "true" ]; then
            ICON=${icoVolOff}
            COLOR="${clrDim}"
          elif [ "$VOL" -gt 66 ]; then
            ICON=${icoVolHi}
            COLOR="${clrBlue}"
          elif [ "$VOL" -gt 33 ]; then
            ICON=${icoVolMed}
            COLOR="${clrBlue}"
          else
            ICON=${icoVolOff}
            COLOR="${clrBlue}"
          fi

          sketchybar --set "$NAME" \
            icon="$ICON" \
            icon.color="$COLOR" \
            label="$VOL%"
        '';
      };

      pluginWifi = pkgs.writeShellApplication {
        name = "sketchybar-wifi";
        runtimeInputs = [ pkgs.sketchybar ];
        text = ''
          ADDR=$(ipconfig getifaddr en0 2>/dev/null)

          if [ -z "$ADDR" ]; then
            COLOR="${clrDim}"
            LABEL="off"
          else
            COLOR="${clrCyan}"
            LABEL="on"
          fi

          sketchybar --set "$NAME" \
            icon=${icoWifi} \
            icon.color="$COLOR" \
            label="$LABEL"
        '';
      };

      pluginBluetooth = pkgs.writeShellApplication {
        name = "sketchybar-bluetooth";
        runtimeInputs = [
          pkgs.sketchybar
          pkgs.blueutil
          pkgs.switchaudio-osx
        ];
        text = ''
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
            COLOR="${clrDim}"
            LABEL="off"
          elif [ "$CONNECTED" -gt 0 ] && [ "$BT_AUDIO" = "true" ]; then
            COLOR="${clrGreen}"
            LABEL="$CONNECTED"
          elif [ "$CONNECTED" -gt 0 ]; then
            COLOR="${clrViolet}"
            LABEL="$CONNECTED"
          else
            COLOR="${clrViolet}"
            LABEL="on"
          fi

          sketchybar --set "$NAME" \
            icon=${icoBt} \
            icon.color="$COLOR" \
            label="$LABEL"
        '';
      };

      pluginBattery = pkgs.writeShellApplication {
        name = "sketchybar-battery";
        runtimeInputs = [ pkgs.sketchybar ];
        text = ''
          BATT_INFO=$(pmset -g batt)
          PERCENT=$(echo "$BATT_INFO" | grep -o '[0-9]*%' | head -1 | tr -d '%')
          PLUGGED=$(echo "$BATT_INFO" | grep -c 'AC Power' || true)
          CHARGING=$(echo "$BATT_INFO" | grep -c 'charging' || true)

          if [ "$PLUGGED" -gt 0 ] && [ "$CHARGING" -gt 0 ]; then
            ICON=${icoPlug}
            COLOR="${clrGreen}"
          elif [ "$PERCENT" -ge 75 ]; then
            ICON=${icoBatF}
            COLOR="${clrGreen}"
          elif [ "$PERCENT" -ge 50 ]; then
            ICON=${icoBat34}
            COLOR="${clrGreen}"
          elif [ "$PERCENT" -ge 25 ]; then
            ICON=${icoBatH}
            COLOR="${clrOrange}"
          elif [ "$PERCENT" -ge 10 ]; then
            ICON=${icoBat14}
            COLOR="${clrRed}"
          else
            ICON=${icoBatE}
            COLOR="${clrRed}"
          fi

          sketchybar --set "$NAME" \
            icon="$ICON" \
            icon.color="$COLOR" \
            label="$PERCENT%"
        '';
      };

      pluginClock = pkgs.writeShellApplication {
        name = "sketchybar-clock";
        runtimeInputs = [ pkgs.sketchybar ];
        text = ''
          sketchybar --set "$NAME" \
            icon=${icoClock} \
            icon.color="${clrYellow}" \
            label="$(date '+%H:%M  %a %d %b')"
        '';
      };

    in
    {
      programs.sketchybar = {
        enable = true;
        extraPackages = [
          pluginVolume
          pluginWifi
          pluginBluetooth
          pluginBattery
          pluginClock
        ];
        config = /* bash */ ''
          #!${pkgs.bash}/bin/bash

          # ── hot-reload on config file change ────────────────────────────────
          sketchybar --hotload true

          # ── bar geometry & appearance ───────────────────────────────────────
          sketchybar --bar \
            height=32 \
            position=top \
            sticky=on \
            padding_left=12 \
            padding_right=12 \
            color=${clrBg} \
            border_width=0 \
            corner_radius=0 \
            blur_radius=0 \
            notch_width=188

          # ── global item defaults ────────────────────────────────────────────
          sketchybar --default \
            icon.font="${fontNF}:16.0" \
            icon.color=${clrFg} \
            label.font="${fontNF}:13.0" \
            label.color=${clrFg} \
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
              icon.color=${clrViolet} \
              # icon.font="${fontSys}:18.0" \
              icon.padding_left=4 \
              icon.padding_right=4 \
              label.drawing=off \
              background.drawing=off \
              click_script="open -a 'System Settings'"

          # ── RIGHT: clock ────────────────────────────────────────────────────
          sketchybar --add item clock right \
            --set clock \
              update_freq=10 \
              script="sketchybar-clock" \
              background.color=${clrBgAlt} \
              background.drawing=on \
              icon.color=${clrYellow} \
              label.color=${clrFg}

          # ── RIGHT: battery ──────────────────────────────────────────────────
          sketchybar --add item battery right \
            --set battery \
              update_freq=60 \
              script="sketchybar-battery" \
              label.width=32 \
              label.align=right \
              background.color=${clrBgAlt} \
              background.drawing=on

          # ── RIGHT: system group bracket (battery + clock) ───────────────────
          sketchybar --add bracket sys_group battery clock \
            --set sys_group \
              background.color=${clrBgAlt} \
              background.corner_radius=12 \
              background.height=24 \
              background.drawing=on

          # ── RIGHT: bluetooth ────────────────────────────────────────────────
          sketchybar --add item bluetooth right \
            --set bluetooth \
              update_freq=30 \
              script="sketchybar-bluetooth" \
              label.width=28 \
              label.align=right \
              click_script="sketchybar --set \$NAME popup.drawing=toggle" \
              background.color=${clrBgAlt} \
              background.drawing=on

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
              label.width=28 \
              label.align=right \
              background.color=${clrBgAlt} \
              background.drawing=on

          # ── RIGHT: volume ───────────────────────────────────────────────────
          sketchybar --add item volume right \
            --set volume \
              script="sketchybar-volume" \
              label.width=32 \
              label.align=right \
              background.color=${clrBgAlt} \
              background.drawing=on

          # Volume updates on system audio change events (no polling needed)
          sketchybar --subscribe volume volume_change

          # ── RIGHT: network group bracket (volume + wifi + bluetooth) ────────
          sketchybar --add bracket net_group volume wifi bluetooth \
            --set net_group \
              background.color=${clrBgAlt} \
              background.corner_radius=12 \
              background.height=24 \
              background.drawing=on

          # ── trigger initial run of all scripts ──────────────────────────────
          sketchybar --update
        '';
      };

      home.activation.reloadSketchybar = lib.hm.dag.entryAfter [ "linkGeneration" ] /* bash */ ''
        if launchctl list org.nix-community.home.sketchybar &>/dev/null; then
          ${pkgs.sketchybar}/bin/sketchybar --reload
        fi
      '';
    };
}
