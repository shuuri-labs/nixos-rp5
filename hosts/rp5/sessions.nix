{ config, lib, pkgs, ... }:

let
  kdePackages = pkgs.kdePackages;

  # Gamescope Steam session launch script
  gamescopeSteamSession = pkgs.writeShellScript "gamescope-steam-session" ''
    #!/bin/bash
    set -ex

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
    set -ex

    # Vulkan settings
    export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/freedreno_icd.aarch64.json

    # Start Plasma Wayland
    exec ${kdePackages.plasma-workspace}/libexec/plasma-dbus-run-session-if-needed \
      ${kdePackages.plasma-workspace}/bin/startplasma-wayland
  '';

in {
  # Plasma 6 desktop (handles all KDE paths, plugins, env vars)
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = false;  # We use greetd

  # greetd display manager with autologin
  services.greetd = {
    enable = true;
    settings = {
      # Default session: text login (fallback if graphical session fails)
      default_session = {
        command = "${pkgs.greetd}/bin/agreety --cmd ${pkgs.bash}/bin/bash";
      };

      # Auto-start Plasma on first boot (runs once, won't loop if it crashes)
      initial_session = {
        command = "${plasmaSession}";
        user = "gamer";
      };
    };
  };

  # Ensure greetd waits for display to be ready
  systemd.services.greetd = {
    after = [ "multi-user.target" "plymouth-quit.service" ];
    wants = [ "plymouth-quit.service" ];
    serviceConfig = {
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
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

    # Disable screen locking (gaming handheld)
    "xdg/kscreenlockerrc".text = ''
      [Daemon]
      Autolock=false
      LockOnResume=false
    '';
    "xdg/kdeglobals".text = ''
      [KDE Action Restrictions]
      action/lock_screen=false
    '';

    # Virtual keyboard for touchscreen input
    "xdg/kwinrc".text = ''
      [Wayland]
      InputMethod=/run/current-system/sw/share/applications/org.kde.plasma.keyboard.desktop
    '';
  };

  # Additional packages (Plasma provided by the module)
  environment.systemPackages = with pkgs; [
    tuigreet

    # Extra Plasma apps
    kdePackages.konsole
    kdePackages.dolphin
    kdePackages.kate
    kdePackages.ark
    kdePackages.spectacle

    # Virtual keyboard for touchscreen
    kdePackages.plasma-keyboard
    kdePackages.qtvirtualkeyboard

    # Wayland utilities
    wl-clipboard
    xdg-utils
  ];

  # XDG portals for Wayland apps
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [
      kdePackages.xdg-desktop-portal-kde
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  # Fonts
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      liberation_ttf
      dejavu_fonts
    ];

    fontconfig.defaultFonts = {
      serif = [ "DejaVu Serif" ];
      sansSerif = [ "DejaVu Sans" ];
      monospace = [ "DejaVu Sans Mono" ];
    };
  };

  # Session user services (for session switching)
  systemd.user.services = {
    gamescope-steam = {
      description = "Gamescope Steam Session";
      wantedBy = [ ];
      conflicts = [ "plasma-session.service" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${gamescopeSteamSession}";
        Restart = "on-failure";
        RestartSec = 3;
        KillMode = "mixed";
        KillSignal = "SIGTERM";
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "gamescope-steam";
      };
      environment = {
        XDG_RUNTIME_DIR = "/run/user/%U";
        XDG_SESSION_TYPE = "wayland";
      };
    };

    plasma-session = {
      description = "KDE Plasma Wayland Session";
      wantedBy = [ ];
      conflicts = [ "gamescope-steam.service" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${plasmaSession}";
        Restart = "on-failure";
        RestartSec = 3;
        KillMode = "mixed";
        KillSignal = "SIGTERM";
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

  # Programs
  programs = {
    dconf.enable = true;
    xwayland.enable = true;
  };
}
