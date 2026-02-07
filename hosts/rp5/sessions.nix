{ config, lib, pkgs, ... }:

let
  # Gamescope Steam session launch script with debug logging
  gamescopeSteamSession = pkgs.writeShellScript "gamescope-steam-session" ''
    #!/bin/bash
    set -ex  # Enable verbose output and exit on error

    echo "[gamescope-session] Starting Gamescope Steam session..."
    echo "[gamescope-session] Date: $(date)"
    echo "[gamescope-session] User: $(whoami)"
    echo "[gamescope-session] UID: $(id)"

    # Environment setup
    export XDG_SESSION_TYPE=wayland
    export SDL_VIDEODRIVER=wayland
    export QT_QPA_PLATFORM=wayland

    # Vulkan settings for Turnip
    export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/freedreno_icd.aarch64.json
    export MESA_VK_WSI_PRESENT_MODE=fifo

    # Steam settings
    export STEAM_RUNTIME=1
    export STEAM_RUNTIME_PREFER_HOST_LIBRARIES=0

    echo "[gamescope-session] Environment configured"
    echo "[gamescope-session] XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"

    # Check if required binaries exist
    echo "[gamescope-session] Checking for required binaries..."
    ls -la ${pkgs.gamescope}/bin/gamescope || echo "gamescope not found!"
    which steam || echo "steam not found!"

    # Create control FIFO for FPS adjustment
    CONTROL_FIFO="/run/user/$(id -u)/gamescope-control"
    rm -f "$CONTROL_FIFO"
    mkfifo "$CONTROL_FIFO" 2>/dev/null || true

    # Default FPS limit
    FPS_LIMIT=''${GAMESCOPE_FPS_LIMIT:-60}

    echo "[gamescope-session] Starting gamescope with FPS limit: $FPS_LIMIT"
    # Start gamescope with Steam in Big Picture mode
    exec ${pkgs.gamescope}/bin/gamescope \
      -e \
      -f \
      --adaptive-sync \
      --framerate-limit "$FPS_LIMIT" \
      --xwayland-count 2 \
      --default-touch-mode 4 \
      --hide-cursor-delay 3000 \
      -- \
      steam -gamepadui -steamos -steamdeck
  '';

  # Plasma Wayland session script with debug logging
  plasmaSession = pkgs.writeShellScript "plasma-wayland-session" ''
    #!/bin/bash
    set -ex  # Enable verbose output and exit on error

    echo "[plasma-session] Starting Plasma Wayland session..."
    echo "[plasma-session] Date: $(date)"
    echo "[plasma-session] User: $(whoami)"
    echo "[plasma-session] UID: $(id)"

    # Environment
    export XDG_SESSION_TYPE=wayland
    export QT_QPA_PLATFORM=wayland

    # Ensure kwin_wayland is in PATH
    export PATH="${pkgs.kwin}/bin:$PATH"

    # Vulkan settings
    export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/freedreno_icd.aarch64.json

    echo "[plasma-session] Environment configured"
    echo "[plasma-session] kwin_wayland: $(which kwin_wayland 2>/dev/null || echo NOT FOUND)"
    echo "[plasma-session] XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
    echo "[plasma-session] DISPLAY: $DISPLAY"
    echo "[plasma-session] WAYLAND_DISPLAY: $WAYLAND_DISPLAY"

    # Check if required binaries exist
    echo "[plasma-session] Checking for required binaries..."
    ls -la ${pkgs.plasma-workspace}/bin/startplasma-wayland || echo "startplasma-wayland not found!"
    ls -la ${pkgs.plasma-workspace}/libexec/plasma-dbus-run-session-if-needed || echo "plasma-dbus-run-session-if-needed not found!"

    echo "[plasma-session] Starting Plasma..."
    # Start Plasma Wayland
    exec ${pkgs.plasma-workspace}/libexec/plasma-dbus-run-session-if-needed \
      ${pkgs.plasma-workspace}/bin/startplasma-wayland
  '';

in {
  # greetd display manager with autologin
  services.greetd = {
    enable = true;
    settings = {
      # Default session: text login (fallback if graphical session fails)
      default_session = {
        command = "${pkgs.greetd.greetd}/bin/agreety --cmd ${pkgs.bash}/bin/bash";
      };

      # Auto-start Plasma on first boot (runs once, won't loop if it crashes)
      initial_session = {
        command = "${plasmaSession}";
        user = "gamer";
      };
    };
  };

  # Ensure greetd waits for display to be ready with detailed logging
  systemd.services.greetd = {
    after = [ "multi-user.target" "plymouth-quit.service" ];
    wants = [ "plymouth-quit.service" ];
    serviceConfig = {
      # Give system time to settle before starting session
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
      # Enable detailed logging
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
  };

  # Session desktop files for greetd
  environment.etc = {
    "greetd/sessions/gamescope-steam.desktop".text = ''
      [Desktop Entry]
      Name=Steam (Gamescope)
      Comment=Steam Big Picture in Gamescope compositor
      Exec=${gamescopeSteamSession}
      Type=Application
    '';

    "greetd/sessions/plasma-wayland.desktop".text = ''
      [Desktop Entry]
      Name=Plasma (Wayland)
      Comment=KDE Plasma Desktop on Wayland
      Exec=${plasmaSession}
      Type=Application
    '';
  };

  # Packages for sessions
  environment.systemPackages = with pkgs; [
    # greetd utilities
    greetd.tuigreet

    # Plasma desktop
    plasma-workspace
    plasma-desktop
    kwin                # Wayland compositor (required for startplasma-wayland)
    plasma-nm          # Network manager applet
    plasma-pa          # PulseAudio/PipeWire applet
    bluedevil          # Bluetooth applet
    powerdevil         # Power management
    kscreen            # Display configuration
    konsole            # Terminal
    dolphin            # File manager
    kate               # Text editor
    ark                # Archive manager
    spectacle          # Screenshots

    # Wayland utilities
    wl-clipboard
    xdg-utils

    # XWayland (for compatibility)
    xwayland
  ];

  # XDG portals for Wayland apps
  xdg.portal = {
    enable = true;
    wlr.enable = true;  # For gamescope/wlroots
    extraPortals = [
      pkgs.xdg-desktop-portal-kde  # For Plasma
      pkgs.xdg-desktop-portal-gtk  # Fallback
    ];
  };

  # Fonts
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-emoji
      liberation_ttf
      dejavu_fonts
    ];

    fontconfig.defaultFonts = {
      serif = [ "DejaVu Serif" ];
      sansSerif = [ "DejaVu Sans" ];
      monospace = [ "DejaVu Sans Mono" ];
    };
  };

  # Session user services (for session switching without login) with detailed logging
  systemd.user.services = {
    # Gamescope Steam session service
    gamescope-steam = {
      description = "Gamescope Steam Session";
      wantedBy = [ ];  # Started on demand via rp5-session-switch
      conflicts = [ "plasma-session.service" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${gamescopeSteamSession}";
        Restart = "on-failure";
        RestartSec = 3;
        KillMode = "mixed";
        KillSignal = "SIGTERM";
        # Detailed logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "gamescope-steam";
      };
      environment = {
        XDG_RUNTIME_DIR = "/run/user/%U";
        XDG_SESSION_TYPE = "wayland";
      };
    };

    # Plasma Wayland session service
    plasma-session = {
      description = "KDE Plasma Wayland Session";
      wantedBy = [ ];  # Started on demand via rp5-session-switch
      conflicts = [ "gamescope-steam.service" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${plasmaSession}";
        Restart = "on-failure";
        RestartSec = 3;
        KillMode = "mixed";
        KillSignal = "SIGTERM";
        # Detailed logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "plasma-session";
      };
      environment = {
        XDG_RUNTIME_DIR = "/run/user/%U";
        XDG_SESSION_TYPE = "wayland";
      };
    };
  };

  # Programs configuration
  programs = {
    # Enable dconf for GNOME/GTK settings
    dconf.enable = true;

    # XWayland for X11 app compatibility
    xwayland.enable = true;
  };

  # Qt theming
  qt = {
    enable = true;
    platformTheme = "kde";
    style = "breeze";
  };
}
