{ config, lib, pkgs, ... }:

# RP5 System Overlay Daemon
# Provides a quick-access overlay triggered by HOME button long-press
# Features: brightness, volume, WiFi, Bluetooth, session switching, FPS control

let
  # Input monitoring daemon
  # Watches for HOME button long-press and triggers overlay
  input-monitor = pkgs.writeShellScriptBin "rp5-input-monitor" ''
    #!/bin/bash
    # RP5 Input Monitor - watches for HOME button long-press

    # Configuration
    HOLD_MS=''${RP5_OVERLAY_HOLD_MS:-800}  # Hold time in milliseconds
    HOME_KEY="KEY_HOMEPAGE"                  # Or BTN_MODE (172) depending on device

    # State file for overlay
    STATE_DIR="/run/user/$(id -u)/rp5-overlay"
    mkdir -p "$STATE_DIR"

    OVERLAY_ACTIVE="$STATE_DIR/active"
    OVERLAY_SOCKET="$STATE_DIR/overlay.sock"

    log() {
      echo "[input-monitor] $*"
      logger -t rp5-input-monitor "$*"
    }

    toggle_overlay() {
      if [ -f "$OVERLAY_ACTIVE" ]; then
        log "Hiding overlay"
        rm -f "$OVERLAY_ACTIVE"
        # Send hide signal to overlay
        echo "hide" > "$OVERLAY_SOCKET" 2>/dev/null || true
      else
        log "Showing overlay"
        touch "$OVERLAY_ACTIVE"
        # Send show signal to overlay
        echo "show" > "$OVERLAY_SOCKET" 2>/dev/null || true

        # If overlay process isn't running, start it
        if ! pgrep -f "rp5-overlay-ui" > /dev/null; then
          log "Starting overlay UI"
          rp5-overlay-ui &
        fi
      fi
    }

    log "Starting input monitor (hold threshold: ''${HOLD_MS}ms)"

    # Find input device
    INPUT_DEVICE=""
    for dev in /dev/input/event*; do
      if ${pkgs.evtest}/bin/evtest --info "$dev" 2>/dev/null | grep -qi "gamepad\|joypad\|controller"; then
        INPUT_DEVICE="$dev"
        break
      fi
    done

    if [ -z "$INPUT_DEVICE" ]; then
      log "WARNING: No gamepad device found, trying event0"
      INPUT_DEVICE="/dev/input/event0"
    fi

    log "Monitoring device: $INPUT_DEVICE"

    # Monitor input events
    # Using evtest in a pipeline to detect key hold
    PRESS_TIME=0

    ${pkgs.evtest}/bin/evtest "$INPUT_DEVICE" 2>/dev/null | while read -r line; do
      # Look for HOME key events
      if echo "$line" | grep -q "KEY_HOMEPAGE\|BTN_MODE"; then
        if echo "$line" | grep -q "value 1"; then
          # Key pressed
          PRESS_TIME=$(date +%s%3N)
          echo "$PRESS_TIME" > "$STATE_DIR/press_time"
        elif echo "$line" | grep -q "value 0"; then
          # Key released
          if [ -f "$STATE_DIR/press_time" ]; then
            PRESS_TIME=$(cat "$STATE_DIR/press_time")
            NOW=$(date +%s%3N)
            HELD=$((NOW - PRESS_TIME))

            if [ "$HELD" -ge "$HOLD_MS" ]; then
              toggle_overlay
            fi
            rm -f "$STATE_DIR/press_time"
          fi
        fi
      fi
    done
  '';

  # Simple text-based overlay UI (placeholder until full GTK version)
  overlay-ui = pkgs.writeShellScriptBin "rp5-overlay-ui" ''
    #!/bin/bash
    # RP5 Overlay UI - Simple version using whiptail/dialog

    STATE_DIR="/run/user/$(id -u)/rp5-overlay"
    SOCKET="$STATE_DIR/overlay.sock"

    # Create named pipe for control
    rm -f "$SOCKET"
    mkfifo "$SOCKET"

    log() {
      logger -t rp5-overlay-ui "$*"
    }

    get_brightness() {
      BACKLIGHT=$(find /sys/class/backlight -mindepth 1 -maxdepth 1 -type l | head -1)
      if [ -n "$BACKLIGHT" ]; then
        MAX=$(cat "$BACKLIGHT/max_brightness")
        CUR=$(cat "$BACKLIGHT/brightness")
        echo $((CUR * 100 / MAX))
      else
        echo "N/A"
      fi
    }

    set_brightness() {
      BACKLIGHT=$(find /sys/class/backlight -mindepth 1 -maxdepth 1 -type l | head -1)
      if [ -n "$BACKLIGHT" ]; then
        MAX=$(cat "$BACKLIGHT/max_brightness")
        VAL=$((MAX * $1 / 100))
        echo "$VAL" > "$BACKLIGHT/brightness"
      fi
    }

    get_volume() {
      ${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}'
    }

    set_volume() {
      ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ "$1%"
    }

    get_wifi_status() {
      ${pkgs.networkmanager}/bin/nmcli radio wifi
    }

    toggle_wifi() {
      STATUS=$(get_wifi_status)
      if [ "$STATUS" = "enabled" ]; then
        ${pkgs.networkmanager}/bin/nmcli radio wifi off
      else
        ${pkgs.networkmanager}/bin/nmcli radio wifi on
      fi
    }

    get_bt_status() {
      ${pkgs.bluez}/bin/bluetoothctl show | grep -q "Powered: yes" && echo "on" || echo "off"
    }

    toggle_bluetooth() {
      STATUS=$(get_bt_status)
      if [ "$STATUS" = "on" ]; then
        ${pkgs.bluez}/bin/bluetoothctl power off
      else
        ${pkgs.bluez}/bin/bluetoothctl power on
      fi
    }

    show_menu() {
      BRIGHTNESS=$(get_brightness)
      VOLUME=$(get_volume)
      WIFI=$(get_wifi_status)
      BT=$(get_bt_status)

      # Use dialog/whiptail for menu
      if command -v whiptail &>/dev/null; then
        CHOICE=$(whiptail --title "RP5 Quick Settings" --menu "Select option:" 20 60 10 \
          "1" "Brightness: $BRIGHTNESS%" \
          "2" "Volume: $VOLUME%" \
          "3" "WiFi: $WIFI" \
          "4" "Bluetooth: $BT" \
          "5" "Switch to Steam" \
          "6" "Switch to ES-DE" \
          "7" "Switch to Plasma" \
          "8" "Exit" \
          3>&1 1>&2 2>&3)

        case "$CHOICE" in
          1)
            NEW_BRIGHT=$(whiptail --title "Brightness" --inputbox "Enter brightness (0-100):" 8 40 "$BRIGHTNESS" 3>&1 1>&2 2>&3)
            set_brightness "$NEW_BRIGHT"
            show_menu
            ;;
          2)
            NEW_VOL=$(whiptail --title "Volume" --inputbox "Enter volume (0-100):" 8 40 "$VOLUME" 3>&1 1>&2 2>&3)
            set_volume "$NEW_VOL"
            show_menu
            ;;
          3)
            toggle_wifi
            show_menu
            ;;
          4)
            toggle_bluetooth
            show_menu
            ;;
          5)
            rp5-session-switch steam
            ;;
          6)
            rp5-session-switch esde
            ;;
          7)
            rp5-session-switch plasma
            ;;
          8|"")
            exit 0
            ;;
        esac
      else
        # Fallback: simple echo menu
        echo "RP5 Quick Settings"
        echo "=================="
        echo "1) Brightness: $BRIGHTNESS%"
        echo "2) Volume: $VOLUME%"
        echo "3) WiFi: $WIFI"
        echo "4) Bluetooth: $BT"
        echo "5) Switch to Steam"
        echo "6) Switch to ES-DE"
        echo "7) Switch to Plasma"
        echo "8) Exit"
        read -p "Choice: " CHOICE
        # Handle choice...
      fi
    }

    # Main loop
    while true; do
      if read -r cmd < "$SOCKET" 2>/dev/null; then
        case "$cmd" in
          show)
            show_menu
            ;;
          hide)
            # Hide overlay
            ;;
          quit)
            exit 0
            ;;
        esac
      fi
      sleep 0.1
    done
  '';

in {
  options.rp5.overlay = {
    enable = lib.mkEnableOption "RP5 system overlay";

    holdMs = lib.mkOption {
      type = lib.types.int;
      default = 800;
      description = "Milliseconds to hold HOME button to trigger overlay";
    };
  };

  config = lib.mkIf (config.rp5.overlay.enable or true) {
    # Overlay packages
    environment.systemPackages = [
      input-monitor
      overlay-ui
      pkgs.whiptail  # For TUI menus
      pkgs.evtest    # For input monitoring
    ];

    # Environment
    environment.variables = {
      RP5_OVERLAY_HOLD_MS = toString (config.rp5.overlay.holdMs or 800);
    };

    # Systemd user service for input monitor
    systemd.user.services.rp5-input-monitor = {
      description = "RP5 Input Monitor (HOME button detection)";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];

      serviceConfig = {
        ExecStart = "${input-monitor}/bin/rp5-input-monitor";
        Restart = "on-failure";
        RestartSec = 3;
      };

      environment = {
        XDG_RUNTIME_DIR = "/run/user/%U";
        RP5_OVERLAY_HOLD_MS = toString (config.rp5.overlay.holdMs or 800);
      };
    };

    # udev rules for input device access
    services.udev.extraRules = ''
      # Allow input group to read input events
      SUBSYSTEM=="input", MODE="0666"
    '';
  };
}
