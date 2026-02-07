{ config, lib, pkgs, ... }:

# Steam integration for RP5 via FEX-Emu
# Uses FEXBash to launch Steam inside the x86_64 rootfs environment,
# following the FEX Wiki's officially documented approach.
# https://wiki.fex-emu.com/index.php/Steam

let
  fex = pkgs.unstable.fex;

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
    echo ""
    echo "IMPORTANT: Run 'steam-setup' to delete conflicting runtime libraries"
    echo "before launching Steam for the first time."
    echo ""
    echo "Then run 'steam' to launch (first launch takes several minutes on FEX)."
  '';

  # Post-install setup: delete conflicting Steam runtime libraries
  # Per FEX Wiki: Steam bundles old x86_64 libs that conflict with the FEX rootfs.
  # These must be deleted so Steam uses the rootfs versions instead.
  steam-setup = pkgs.writeShellScriptBin "steam-setup" ''
    set -e

    STEAM_DIR="$HOME/.local/share/Steam"

    echo "Steam Setup for FEX-Emu"
    echo "========================"
    echo ""

    if [ ! -d "$STEAM_DIR" ]; then
      echo "ERROR: Steam not found at $STEAM_DIR"
      echo "Run 'install-steam' first."
      exit 1
    fi

    echo "Removing conflicting Steam runtime libraries..."
    echo "(These conflict with the FEX rootfs and must be deleted)"
    echo ""

    # Steam runtime libraries that conflict with the FEX rootfs
    # Per https://wiki.fex-emu.com/index.php/Steam
    RUNTIME_DIR="$STEAM_DIR/ubuntu12_32/steam-runtime"

    LIBS_TO_REMOVE=(
      # Graphics/driver libs that must come from rootfs
      "libgcc_s.so.1"
      "libstdc++.so.6"
      "libxcb.so.1"
      "libgpg-error.so.0"
      # Dbus — Steam bundles an old version
      "libdbus-1.so.3"
    )

    removed=0
    for lib in "''${LIBS_TO_REMOVE[@]}"; do
      # Search both i386 and amd64 runtime dirs
      while IFS= read -r -d "" file; do
        echo "  Removing: ''${file#$STEAM_DIR/}"
        rm -f "$file"
        removed=$((removed + 1))
      done < <(find "$RUNTIME_DIR" -name "$lib" -print0 2>/dev/null || true)
    done

    echo ""
    if [ "$removed" -gt 0 ]; then
      echo "Removed $removed conflicting libraries."
    else
      echo "No conflicting libraries found (already cleaned or different Steam version)."
    fi

    echo ""
    echo "Setup complete. Run 'steam' to launch."
    echo "NOTE: First launch takes several minutes on FEX — be patient!"
  '';

  # Steam launch wrapper using FEXBash
  # FEXBash runs commands inside the x86_64 rootfs with proper FEX environment.
  # This is the officially documented way to run Steam under FEX-Emu.
  steam-wrapper = pkgs.writeShellScriptBin "steam" ''
    STEAM_DIR="$HOME/.local/share/Steam"

    # Check Steam is installed
    if [ ! -f "$STEAM_DIR/steam.sh" ] && [ ! -f "$STEAM_DIR/bin_steam.sh" ]; then
      echo "Steam not found. Run 'install-steam' first."
      exit 1
    fi

    # Check FEXBash is available
    if ! command -v FEXBash &>/dev/null; then
      echo "ERROR: FEXBash not found on PATH."
      echo "FEX-Emu must be installed. Check your NixOS configuration."
      exit 1
    fi

    echo "Launching Steam via FEXBash..."
    echo "(First launch takes several minutes — be patient!)"
    echo ""

    # Shader cache
    export MESA_SHADER_CACHE_DIR="$HOME/.cache/mesa_shader_cache"
    mkdir -p "$MESA_SHADER_CACHE_DIR"

    # DXVK async for Proton
    export DXVK_ASYNC=1

    # Don't load aarch64 MangoHud layer inside x86_64 process
    export DISABLE_MANGOHUD=1
    export MANGOHUD=0

    # Launch Steam through FEXBash
    # FEXBash provides the x86_64 rootfs environment. Steam runs as an x86_64
    # process with FEX translating syscalls. binfmt_misc handles child processes.
    # steam.sh is preferred (full client); bin_steam.sh is the initial bootstrapper.
    if [ -f "$STEAM_DIR/steam.sh" ]; then
      exec ${fex}/bin/FEXBash -c "cd \"$STEAM_DIR\" && STEAMOS=1 STEAM_RUNTIME=1 ./steam.sh $*"
    else
      exec ${fex}/bin/FEXBash -c "cd \"$STEAM_DIR\" && STEAMOS=1 STEAM_RUNTIME=1 ./bin_steam.sh $*"
    fi
  '';

  # Gamepad UI wrapper
  steam-gamepadui = pkgs.writeShellScriptBin "steam-gamepadui" ''
    exec steam -gamepadui -steamos -steamdeck "$@"
  '';

in {
  # Steam scripts use #!/bin/bash shebangs — NixOS doesn't have /bin/bash by default
  systemd.tmpfiles.rules = [
    "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
    "d /usr/lib -"      # bwrap expects FHS paths
    "d /usr/share -"
  ];

  # /etc/host.conf — bwrap expects this for FHS compat
  environment.etc."host.conf".text = "multi on\n";

  environment.systemPackages = [
    install-steam
    steam-setup
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
