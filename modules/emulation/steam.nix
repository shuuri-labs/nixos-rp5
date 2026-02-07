{ config, lib, pkgs, ... }:

# Steam integration for RP5 via FEX-Emu
# Steam is x86_64-only, runs through FEX binfmt emulation

let
  # Steam installation helper script
  install-steam = pkgs.writeShellScriptBin "install-steam" ''
    set -e

    STEAM_DIR="$HOME/.local/share/Steam"
    STEAM_DEB="/tmp/steam_installer.deb"

    echo "Steam Installer for ARM64 (via FEX-Emu)"
    echo "========================================="
    echo ""

    # Check binfmt is set up
    if [ ! -f /proc/sys/fs/binfmt_misc/FEX-x86_64 ]; then
      echo "ERROR: x86_64 binfmt handler not registered."
      echo "FEX-Emu binfmt must be active before installing Steam."
      exit 1
    fi

    # Check FEX rootfs is available
    FEX_DATA="''${XDG_DATA_HOME:-$HOME/.local/share}/fex-emu"
    if [ ! -d "$FEX_DATA/RootFS" ] && [ ! -f "$FEX_DATA/RootFS.sqsh" ]; then
      echo "WARNING: No FEX rootfs found at $FEX_DATA/RootFS"
      echo "Run 'fex-rootfs-setup' first if you haven't already."
      echo ""
    fi

    # Check if Steam is already installed
    if [ -f "$STEAM_DIR/steam.sh" ]; then
      echo "Steam already installed at $STEAM_DIR"
      read -p "Reinstall? [y/N] " -n 1 -r
      echo
      [[ $REPLY =~ ^[Yy]$ ]] || exit 0
    fi

    echo "Downloading Steam installer..."
    ${pkgs.curl}/bin/curl -L -o "$STEAM_DEB" \
      "https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb"

    echo "Extracting Steam..."
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    ${pkgs.binutils}/bin/ar x "$STEAM_DEB"
    ${pkgs.gnutar}/bin/tar xf data.tar.xz

    mkdir -p "$STEAM_DIR"
    mkdir -p "$HOME/.steam"

    if [ -d usr/lib/steam ]; then
      cp -r usr/lib/steam/* "$STEAM_DIR/"
    fi

    # Extract the bootstrap tarball — this creates steam.sh and the rest of the client
    BOOTSTRAP="$STEAM_DIR/bootstraplinux_ubuntu12_32.tar.xz"
    if [ -f "$BOOTSTRAP" ]; then
      echo "Extracting Steam bootstrap..."
      ${pkgs.gnutar}/bin/tar xf "$BOOTSTRAP" -C "$STEAM_DIR"
    else
      echo "WARNING: Bootstrap tarball not found in .deb"
      echo "Steam may not have installed correctly."
    fi

    # Clean up
    cd /
    rm -rf "$TEMP_DIR"
    rm -f "$STEAM_DEB"

    echo ""
    echo "Steam installed to $STEAM_DIR"
    echo "Run 'steam' to launch."
  '';

  # Steam launch wrapper
  steam-wrapper = pkgs.writeShellScriptBin "steam" ''
    STEAM_DIR="$HOME/.local/share/Steam"

    # steam.sh exists after first successful bootstrap; bin_steam.sh is the
    # initial entry point shipped in the .deb that performs the bootstrap
    if [ -f "$STEAM_DIR/steam.sh" ]; then
      LAUNCH="$STEAM_DIR/steam.sh"
    elif [ -f "$STEAM_DIR/bin_steam.sh" ]; then
      LAUNCH="$STEAM_DIR/bin_steam.sh"
    else
      echo "Steam not found. Run 'install-steam' first."
      exit 1
    fi

    # Steam environment
    export STEAMOS=1
    export STEAM_RUNTIME=1

    # Vulkan — point to the host ARM64 Turnip driver
    export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/freedreno_icd.aarch64.json

    # Expose NixOS paths into Steam's pressure-vessel container
    export PRESSURE_VESSEL_FILESYSTEMS_RO="/nix/store:/run/opengl-driver:/run/current-system/sw"

    # Don't load aarch64 MangoHud layer inside x86_64 container
    export DISABLE_MANGOHUD=1

    # DXVK async for Proton
    export DXVK_ASYNC=1

    # Shader cache
    export MESA_SHADER_CACHE_DIR="$HOME/.cache/mesa_shader_cache"
    mkdir -p "$MESA_SHADER_CACHE_DIR"

    cd "$STEAM_DIR"
    exec "$LAUNCH" "$@"
  '';

  # Gamepad UI wrapper
  steam-gamepadui = pkgs.writeShellScriptBin "steam-gamepadui" ''
    exec steam -gamepadui -steamos -steamdeck "$@"
  '';

in {
  # Steam scripts use #!/bin/bash shebangs — NixOS doesn't have /bin/bash by default
  systemd.tmpfiles.rules = [
    "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
    "d /usr/lib -"  # pressure-vessel/bwrap expects /usr/lib to exist
  ];

  environment.systemPackages = [
    install-steam
    steam-wrapper
    steam-gamepadui

    pkgs.curl
    pkgs.xdg-utils
  ];

  # Gamemode for better gaming performance
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

  # bwrap security wrapper for Steam sandbox
  security.wrappers.bwrap = {
    owner = "root";
    group = "root";
    capabilities = "cap_sys_admin+ep";
    source = "${pkgs.bubblewrap}/bin/bwrap";
  };
}
