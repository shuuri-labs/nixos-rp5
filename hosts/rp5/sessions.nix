{ config, lib, pkgs, ... }:

let
  # Gamescope Steam session launch script
  gamescopeSteamSession = pkgs.writeShellScript "gamescope-steam-session" ''
    #!/bin/bash
    set -e

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

    # MangoHud (optional, uncomment to enable)
    # export MANGOHUD=1
    # export MANGOHUD_CONFIG="fps,frametime,cpu_temp,gpu_temp,ram"

    # Create control FIFO for FPS adjustment
    CONTROL_FIFO="/run/user/$(id -u)/gamescope-control"
    rm -f "$CONTROL_FIFO"
    mkfifo "$CONTROL_FIFO" 2>/dev/null || true

    # Default FPS limit
    FPS_LIMIT=''${GAMESCOPE_FPS_LIMIT:-60}

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

  # Plasma Wayland session script
  plasmaSession = pkgs.writeShellScript "plasma-wayland-session" ''
    #!/bin/bash
    set -e

    # Environment
    export XDG_SESSION_TYPE=wayland
    export QT_QPA_PLATFORM=wayland

    # Vulkan settings
    export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/freedreno_icd.aarch64.json

    # Start Plasma Wayland
    exec ${pkgs.plasma-workspace}/libexec/plasma-dbus-run-session-if-needed \
      ${pkgs.plasma-workspace}/bin/startplasma-wayland
  '';

in {
  # greetd display manager
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --sessions /etc/greetd/sessions";
        user = "greeter";
      };

      # Auto-login option (enable for dedicated gaming device)
      # Uncomment to auto-start Steam session on boot
      # initial_session = {
      #   command = "${gamescopeSteamSession}";
      #   user = "gamer";
      # };
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

  # Session user services
  systemd.user.services = {
    # Gamescope Steam as a user service (for session switching)
    gamescope-steam = {
      description = "Gamescope Steam Session";
      wantedBy = [ ];  # Started on demand
      serviceConfig = {
        ExecStart = "${gamescopeSteamSession}";
        Restart = "on-failure";
        RestartSec = 3;
      };
      environment = {
        XDG_RUNTIME_DIR = "/run/user/%U";
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
