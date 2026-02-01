# Package overlays for NixOS RP5
# This file defines custom packages and modifications to nixpkgs

final: prev: {
  # Custom packages for RP5

  # Session switcher utility
  rp5-session-switch = final.writeShellScriptBin "rp5-session-switch" ''
    #!/bin/bash
    # Session switcher for RP5
    # Usage: rp5-session-switch {steam|esde|plasma}

    case "$1" in
      steam)
        echo "Switching to Steam session..."
        systemctl --user stop plasma-session.service 2>/dev/null || true
        systemctl --user start gamescope-steam.service
        ;;
      plasma)
        echo "Switching to Plasma session..."
        systemctl --user stop gamescope-steam.service 2>/dev/null || true
        systemctl --user start plasma-session.service
        ;;
      *)
        echo "Usage: rp5-session-switch {steam|plasma}"
        exit 1
        ;;
    esac
  '';

  # FPS control utility for gamescope
  rp5-fps = final.writeShellScriptBin "rp5-fps" ''
    #!/bin/bash
    # Gamescope FPS limiter control
    # Usage: rp5-fps {30|40|60}

    FIFO="/run/user/$(id -u)/gamescope-control"

    case "$1" in
      30|40|60)
        if [ -p "$FIFO" ]; then
          echo "fps:$1" > "$FIFO"
          echo "FPS limit set to $1"
        else
          echo "Gamescope control FIFO not found"
          echo "Is gamescope-steam session running?"
          exit 1
        fi
        ;;
      *)
        echo "Usage: rp5-fps {30|40|60}"
        exit 1
        ;;
    esac
  '';

  # Brightness control utility
  rp5-brightness = final.writeShellScriptBin "rp5-brightness" ''
    #!/bin/bash
    # Brightness control for RP5
    # Usage: rp5-brightness {get|set <value>|up|down}

    BACKLIGHT_PATH=$(find /sys/class/backlight -mindepth 1 -maxdepth 1 -type l | head -1)

    if [ -z "$BACKLIGHT_PATH" ]; then
      echo "No backlight device found"
      exit 1
    fi

    MAX=$(cat "$BACKLIGHT_PATH/max_brightness")
    CURRENT=$(cat "$BACKLIGHT_PATH/brightness")
    STEP=$((MAX / 20))  # 5% steps

    case "$1" in
      get)
        PERCENT=$((CURRENT * 100 / MAX))
        echo "$PERCENT%"
        ;;
      set)
        if [ -z "$2" ]; then
          echo "Usage: rp5-brightness set <0-100>"
          exit 1
        fi
        VALUE=$((MAX * $2 / 100))
        echo "$VALUE" > "$BACKLIGHT_PATH/brightness"
        echo "Brightness set to $2%"
        ;;
      up)
        NEW=$((CURRENT + STEP))
        [ $NEW -gt $MAX ] && NEW=$MAX
        echo "$NEW" > "$BACKLIGHT_PATH/brightness"
        echo "Brightness: $((NEW * 100 / MAX))%"
        ;;
      down)
        NEW=$((CURRENT - STEP))
        [ $NEW -lt 0 ] && NEW=0
        echo "$NEW" > "$BACKLIGHT_PATH/brightness"
        echo "Brightness: $((NEW * 100 / MAX))%"
        ;;
      *)
        echo "Usage: rp5-brightness {get|set <value>|up|down}"
        exit 1
        ;;
    esac
  '';

  # Volume control utility
  rp5-volume = final.writeShellScriptBin "rp5-volume" ''
    #!/bin/bash
    # Volume control for RP5 (PipeWire/WirePlumber)
    # Usage: rp5-volume {get|set <value>|up|down|mute|unmute}

    case "$1" in
      get)
        ${final.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@
        ;;
      set)
        if [ -z "$2" ]; then
          echo "Usage: rp5-volume set <0-100>"
          exit 1
        fi
        ${final.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ "$2%"
        echo "Volume set to $2%"
        ;;
      up)
        ${final.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
        ${final.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@
        ;;
      down)
        ${final.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
        ${final.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@
        ;;
      mute)
        ${final.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ 1
        echo "Muted"
        ;;
      unmute)
        ${final.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
        echo "Unmuted"
        ;;
      toggle)
        ${final.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        ;;
      *)
        echo "Usage: rp5-volume {get|set <value>|up|down|mute|unmute|toggle}"
        exit 1
        ;;
    esac
  '';

  # WiFi control utility
  rp5-wifi = final.writeShellScriptBin "rp5-wifi" ''
    #!/bin/bash
    # WiFi control for RP5
    # Usage: rp5-wifi {on|off|status|scan|connect <ssid>}

    case "$1" in
      on)
        ${final.networkmanager}/bin/nmcli radio wifi on
        echo "WiFi enabled"
        ;;
      off)
        ${final.networkmanager}/bin/nmcli radio wifi off
        echo "WiFi disabled"
        ;;
      status)
        ${final.networkmanager}/bin/nmcli radio wifi
        echo "---"
        ${final.networkmanager}/bin/nmcli connection show --active | grep wifi
        ;;
      scan)
        ${final.networkmanager}/bin/nmcli device wifi rescan 2>/dev/null
        ${final.networkmanager}/bin/nmcli device wifi list
        ;;
      connect)
        if [ -z "$2" ]; then
          echo "Usage: rp5-wifi connect <ssid> [password]"
          exit 1
        fi
        if [ -n "$3" ]; then
          ${final.networkmanager}/bin/nmcli device wifi connect "$2" password "$3"
        else
          ${final.networkmanager}/bin/nmcli device wifi connect "$2"
        fi
        ;;
      *)
        echo "Usage: rp5-wifi {on|off|status|scan|connect <ssid> [password]}"
        exit 1
        ;;
    esac
  '';

  # Bluetooth control utility
  rp5-bluetooth = final.writeShellScriptBin "rp5-bluetooth" ''
    #!/bin/bash
    # Bluetooth control for RP5
    # Usage: rp5-bluetooth {on|off|status|scan|pair <mac>}

    case "$1" in
      on)
        ${final.util-linux}/bin/rfkill unblock bluetooth
        ${final.bluez}/bin/bluetoothctl power on
        echo "Bluetooth enabled"
        ;;
      off)
        ${final.bluez}/bin/bluetoothctl power off
        echo "Bluetooth disabled"
        ;;
      status)
        ${final.bluez}/bin/bluetoothctl show | grep -E "Powered|Name"
        echo "---"
        ${final.bluez}/bin/bluetoothctl devices Connected
        ;;
      scan)
        echo "Scanning for 10 seconds..."
        ${final.bluez}/bin/bluetoothctl --timeout 10 scan on
        ${final.bluez}/bin/bluetoothctl devices
        ;;
      pair)
        if [ -z "$2" ]; then
          echo "Usage: rp5-bluetooth pair <mac-address>"
          exit 1
        fi
        ${final.bluez}/bin/bluetoothctl pair "$2"
        ${final.bluez}/bin/bluetoothctl connect "$2"
        ${final.bluez}/bin/bluetoothctl trust "$2"
        ;;
      *)
        echo "Usage: rp5-bluetooth {on|off|status|scan|pair <mac>}"
        exit 1
        ;;
    esac
  '';
}
