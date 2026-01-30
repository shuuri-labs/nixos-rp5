{ config, lib, pkgs, ... }:

# Steam integration for RP5 via FEX-Emu/Box64
# Steam is x86_64-only, so we run it through the emulation layer

let
  # Steam installation helper script
  steam-installer = pkgs.writeShellScriptBin "install-steam" ''
    #!/bin/bash
    # Steam installer for ARM64 via FEX-Emu/Box64
    set -e

    STEAM_DIR="$HOME/.local/share/Steam"
    STEAM_INSTALLER="/tmp/steam_installer.deb"

    echo "Steam Installer for ARM64"
    echo "========================="
    echo ""

    # Check for binfmt x86_64 support
    if [ ! -f /proc/sys/fs/binfmt_misc/FEX-x86_64 ]; then
      echo "WARNING: x86_64 binfmt handler not registered!"
      echo "Steam may not run properly."
      echo "Ensure FEX-Emu or Box64 is properly configured."
      read -p "Continue anyway? [y/N] " -n 1 -r
      echo
      [[ $REPLY =~ ^[Yy]$ ]] || exit 1
    fi

    # Check if Steam is already installed
    if [ -f "$STEAM_DIR/steam.sh" ]; then
      echo "Steam appears to be already installed at $STEAM_DIR"
      read -p "Reinstall? [y/N] " -n 1 -r
      echo
      [[ $REPLY =~ ^[Yy]$ ]] || exit 0
    fi

    echo "Downloading Steam installer..."
    ${pkgs.curl}/bin/curl -L -o "$STEAM_INSTALLER" \
      "https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb"

    echo "Extracting Steam..."
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    ${pkgs.binutils}/bin/ar x "$STEAM_INSTALLER"
    ${pkgs.gnutar}/bin/tar xf data.tar.xz

    # Create Steam directory
    mkdir -p "$STEAM_DIR"
    mkdir -p "$HOME/.steam"

    # Copy Steam files
    if [ -d usr/lib/steam ]; then
      cp -r usr/lib/steam/* "$STEAM_DIR/"
    fi
    if [ -d usr/share/applications ]; then
      mkdir -p "$HOME/.local/share/applications"
      cp -r usr/share/applications/* "$HOME/.local/share/applications/"
    fi

    # Clean up
    cd /
    rm -rf "$TEMP_DIR"
    rm -f "$STEAM_INSTALLER"

    echo ""
    echo "Steam installed to $STEAM_DIR"
    echo "Run 'steam' to start Steam and complete setup."
    echo ""
    echo "NOTE: First launch may take a while as Steam updates itself."
  '';

  # Steam launch wrapper
  steam-wrapper = pkgs.writeShellScriptBin "steam" ''
    #!/bin/bash
    # Steam wrapper for ARM64

    STEAM_DIR="$HOME/.local/share/Steam"
    STEAM_SCRIPT="$STEAM_DIR/steam.sh"

    # Check if Steam is installed
    if [ ! -f "$STEAM_SCRIPT" ]; then
      echo "Steam not found at $STEAM_DIR"
      echo "Run 'install-steam' to install Steam first."
      exit 1
    fi

    # Environment setup
    export STEAM_RUNTIME=1
    export STEAM_RUNTIME_PREFER_HOST_LIBRARIES=0

    # FEX/Box64 environment
    export BOX64_LOG=1
    export BOX64_DYNAREC_BIGBLOCK=0

    # Vulkan driver
    export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/freedreno_icd.aarch64.json

    # DXVK async (if using Proton)
    export DXVK_ASYNC=1

    # Mesa shader cache
    export MESA_SHADER_CACHE_DIR="$HOME/.cache/mesa_shader_cache"
    mkdir -p "$MESA_SHADER_CACHE_DIR"

    # Better controller support
    export SDL_GAMECONTROLLERCONFIG=""

    # Start Steam
    cd "$STEAM_DIR"
    exec "$STEAM_SCRIPT" "$@"
  '';

  # Steam with specific flags
  steam-gamepadui = pkgs.writeShellScriptBin "steam-gamepadui" ''
    #!/bin/bash
    # Launch Steam in Big Picture / Gamepad UI mode
    exec steam -gamepadui -steamos -steamdeck "$@"
  '';

in {
  options.rp5.steam = {
    enable = lib.mkEnableOption "Steam gaming support via FEX-Emu/Box64";
  };

  config = lib.mkIf (config.rp5.steam.enable or true) {
    # Steam packages
    environment.systemPackages = [
      steam-installer
      steam-wrapper
      steam-gamepadui

      # Dependencies that Steam might need
      pkgs.curl
      pkgs.xdg-utils
      pkgs.xdg-user-dirs
    ];

    # Enable FEX-Emu (required for Steam)
    rp5.fex-emu.enable = true;

    # Steam udev rules for controllers
    hardware.steam-hardware.enable = true;

    # Environment for Steam
    environment.variables = {
      # Steam paths
      STEAM_EXTRA_COMPAT_TOOLS_PATHS = "$HOME/.steam/root/compatibilitytools.d";

      # Proton settings
      PROTON_USE_WINED3D = "0";      # Use DXVK by default
      PROTON_NO_ESYNC = "0";          # Enable esync
      PROTON_NO_FSYNC = "0";          # Enable fsync if available

      # Better game compatibility
      WINEDEBUG = "-all";             # Reduce Wine debug spam
      DXVK_HUD = "fps,memory";        # DXVK overlay
    };

    # Create Steam directories on activation
    system.activationScripts.steamDirs = lib.stringAfter [ "users" ] ''
      # Create Steam directories for gamer user
      mkdir -p /home/gamer/.local/share/Steam
      mkdir -p /home/gamer/.steam
      mkdir -p /home/gamer/.cache/mesa_shader_cache
      chown -R gamer:users /home/gamer/.local/share/Steam
      chown -R gamer:users /home/gamer/.steam
      chown -R gamer:users /home/gamer/.cache/mesa_shader_cache
    '';

    # Gamemode for better performance
    programs.gamemode = {
      enable = true;
      settings = {
        general = {
          renice = 10;
        };
        gpu = {
          apply_gpu_optimisations = "accept-responsibility";
          gpu_device = 0;
        };
      };
    };

    # Required for Steam's sandbox
    security.wrappers = {
      # bwrap for Steam's sandbox
      bwrap = {
        owner = "root";
        group = "root";
        capabilities = "cap_sys_admin+ep";
        source = "${pkgs.bubblewrap}/bin/bwrap";
      };
    };

    # Filesystem access for Steam
    programs.firejail.enable = false;  # Don't use firejail with Steam
  };
}
