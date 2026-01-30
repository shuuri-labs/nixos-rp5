{ config, lib, pkgs, ... }:

# Gamescope compositor configuration
# Gamescope is a SteamOS session compositor that provides:
# - Frame timing/limiting
# - Display scaling
# - HDR (on supported displays)
# - Overlay support

{
  options.rp5.gamescope = {
    enable = lib.mkEnableOption "Gamescope compositor";

    defaultFpsLimit = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Default framerate limit for gamescope sessions";
    };

    adaptiveSync = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable adaptive sync (VRR) if supported";
    };
  };

  config = lib.mkIf (config.rp5.gamescope.enable or true) {
    # Gamescope packages
    environment.systemPackages = with pkgs; [
      gamescope

      # MangoHud for FPS overlay
      mangohud

      # GPU monitoring
      # (add platform-specific tools if available)
    ];

    # Gamescope needs CAP_SYS_NICE for realtime scheduling
    security.wrappers.gamescope = {
      owner = "root";
      group = "root";
      capabilities = "cap_sys_nice+ep";
      source = "${pkgs.gamescope}/bin/gamescope";
    };

    # Environment for gamescope
    environment.variables = {
      # Default FPS limit (can be overridden per-session)
      GAMESCOPE_FPS_LIMIT = toString (config.rp5.gamescope.defaultFpsLimit or 60);

      # MangoHud configuration
      MANGOHUD_CONFIG = "fps,frametime,cpu_temp,gpu_temp,ram,position=top-left,font_size=18";
    };

    # Gamescope wrapper script with FPS control
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "gamescope-rp5" ''
        #!/bin/bash
        # Gamescope wrapper with runtime FPS control

        # Parse environment or use defaults
        FPS_LIMIT=''${GAMESCOPE_FPS_LIMIT:-60}
        REFRESH_RATE=''${GAMESCOPE_REFRESH_RATE:-60}
        ADAPTIVE_SYNC=${if config.rp5.gamescope.adaptiveSync or true then "true" else "false"}

        # Control FIFO for runtime adjustments
        CONTROL_FIFO="/run/user/$(id -u)/gamescope-control"
        rm -f "$CONTROL_FIFO"
        mkfifo "$CONTROL_FIFO" 2>/dev/null || true

        # Background process to handle control commands
        (
          while true; do
            if read -r cmd < "$CONTROL_FIFO" 2>/dev/null; then
              case "$cmd" in
                fps:*)
                  NEW_FPS="''${cmd#fps:}"
                  # Note: gamescope doesn't support runtime FPS changes yet
                  # This would require restarting the session
                  echo "FPS change requested to $NEW_FPS (requires session restart)" | logger -t gamescope-control
                  ;;
                quit)
                  break
                  ;;
              esac
            fi
          done
        ) &
        CONTROL_PID=$!

        # Build gamescope arguments
        ARGS=()
        ARGS+=(-e)  # Expose Wayland
        ARGS+=(-f)  # Fullscreen
        ARGS+=(--framerate-limit "$FPS_LIMIT")

        if [ "$ADAPTIVE_SYNC" = "true" ]; then
          ARGS+=(--adaptive-sync)
        fi

        # XWayland count (2 for Steam, 1 for simpler apps)
        ARGS+=(--xwayland-count 2)

        # Touch mode for handheld
        ARGS+=(--default-touch-mode 4)

        # Hide cursor when not moving
        ARGS+=(--hide-cursor-delay 3000)

        # Run gamescope
        cleanup() {
          kill $CONTROL_PID 2>/dev/null
          rm -f "$CONTROL_FIFO"
        }
        trap cleanup EXIT

        exec ${pkgs.gamescope}/bin/gamescope "''${ARGS[@]}" "$@"
      '')
    ];

    # Kernel parameters for better gaming performance
    boot.kernel.sysctl = {
      # More memory maps for games
      "vm.max_map_count" = 2147483642;

      # Better swap behavior for gaming
      "vm.swappiness" = 10;

      # Faster dirty page writeback
      "vm.dirty_ratio" = 10;
      "vm.dirty_background_ratio" = 5;
    };

    # Realtime scheduling for games
    security.pam.loginLimits = [
      {
        domain = "@games";
        item = "nice";
        type = "-";
        value = "-20";
      }
      {
        domain = "@games";
        item = "rtprio";
        type = "-";
        value = "99";
      }
      {
        domain = "@games";
        item = "memlock";
        type = "-";
        value = "unlimited";
      }
    ];

    # Create games group
    users.groups.games = {};
    users.users.gamer.extraGroups = [ "games" ];
  };
}
