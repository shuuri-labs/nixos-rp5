{ config, lib, pkgs, ... }:

# Steam integration for RP5 via FEX-Emu
#
# IMPORTANT: We do NOT use FEXBash to launch Steam. FEXBash runs
# `FEX /bin/bash`, but on NixOS /bin/bash is an aarch64 binary (tmpfiles
# symlink) and FEX either can't emulate its own architecture or finds it
# before checking the rootfs. Instead, we invoke FEXInterpreter directly
# with the rootfs's x86_64 bash, which:
#   1. Guarantees FEX loads an x86_64 binary for emulation
#   2. Activates FEX's syscall-level rootfs overlay for all child processes
#   3. Bypasses the name-resolution issues with FEXBash
#
# See docs/fex-rootfs-fix.md for full analysis.

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
    ROOTFS_PATH=$(fex-find-rootfs 2>/dev/null) || true
    if [ -z "$ROOTFS_PATH" ]; then
      echo "WARNING: No FEX rootfs found."
      echo "Run 'fex-rootfs-setup' first if you haven't already."
      echo ""
    else
      echo "Using rootfs: $ROOTFS_PATH"
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

    # ── Patch rootfs for FHS files that bwrap/pressure-vessel expects ──
    echo ""
    echo "Patching rootfs for Steam compatibility..."

    ROOTFS_PATH=$(fex-find-rootfs 2>/dev/null) || true
    if [ -n "$ROOTFS_PATH" ] && [ -d "$ROOTFS_PATH" ]; then
      # /etc/host.conf — bwrap bind-mounts this into the container
      if [ ! -f "$ROOTFS_PATH/etc/host.conf" ]; then
        echo "  Creating /etc/host.conf in rootfs"
        echo "multi on" > "$ROOTFS_PATH/etc/host.conf"
      fi

      # /etc/hosts — needed for network resolution inside container
      if [ ! -f "$ROOTFS_PATH/etc/hosts" ]; then
        echo "  Creating /etc/hosts in rootfs"
        cat > "$ROOTFS_PATH/etc/hosts" << 'HOSTS'
127.0.0.1 localhost
::1 localhost
HOSTS
      fi

      # /etc/resolv.conf — DNS resolution (copy from host)
      if [ ! -f "$ROOTFS_PATH/etc/resolv.conf" ] && [ -f /etc/resolv.conf ]; then
        echo "  Copying /etc/resolv.conf to rootfs"
        cp /etc/resolv.conf "$ROOTFS_PATH/etc/resolv.conf"
      fi

      # /etc/machine-id — needed by dbus
      if [ ! -f "$ROOTFS_PATH/etc/machine-id" ] && [ -f /etc/machine-id ]; then
        echo "  Copying /etc/machine-id to rootfs"
        cp /etc/machine-id "$ROOTFS_PATH/etc/machine-id"
      fi

      # /etc/passwd and /etc/group — needed for user lookups inside container
      if [ ! -f "$ROOTFS_PATH/etc/passwd" ]; then
        echo "  Creating /etc/passwd in rootfs"
        grep "^$(whoami):" /etc/passwd > "$ROOTFS_PATH/etc/passwd" 2>/dev/null || true
        grep "^root:" /etc/passwd >> "$ROOTFS_PATH/etc/passwd" 2>/dev/null || true
      fi

      echo "  Rootfs patching complete."

      # ── Ensure mesa/libGL is installed in rootfs ──
      # steamwebhelper needs x86_64 mesa (llvmpipe for software rendering).
      # pressure-vessel's bwrap container gets libraries from the "host" (rootfs).
      # If the rootfs doesn't have mesa, steamwebhelper can't create GL contexts.
      echo ""
      echo "Checking rootfs mesa libraries..."
      if [ ! -f "$ROOTFS_PATH/usr/lib/x86_64-linux-gnu/libGL.so.1" ] && \
         [ ! -L "$ROOTFS_PATH/usr/lib/x86_64-linux-gnu/libGL.so.1" ]; then
        echo "  Mesa/libGL not found in rootfs — installing..."
        echo "  (This requires network access and may take a minute)"
        # Copy resolv.conf for DNS inside FEX
        cp /etc/resolv.conf "$ROOTFS_PATH/etc/resolv.conf" 2>/dev/null || true
        fex-rootfs-run "apt-get update -qq && apt-get install -y --no-install-recommends \
          libgl1-mesa-dri libgl1-mesa-glx libegl-mesa0 libgles2-mesa mesa-utils \
          libvulkan1 libx11-6 libxext6 libxcb1 2>&1" || \
          echo "  WARNING: apt-get failed — install mesa manually: fex-rootfs-run apt-get install -y libgl1-mesa-dri"
      else
        echo "  Mesa/libGL found in rootfs."
        # Check for DRI drivers (llvmpipe for software rendering)
        if [ -d "$ROOTFS_PATH/usr/lib/x86_64-linux-gnu/dri" ]; then
          DRI_COUNT=$(ls "$ROOTFS_PATH/usr/lib/x86_64-linux-gnu/dri/" 2>/dev/null | wc -l)
          echo "  DRI drivers: $DRI_COUNT files"
        else
          echo "  WARNING: No DRI drivers directory — llvmpipe may be missing"
          echo "  Try: fex-rootfs-run apt-get install -y libgl1-mesa-dri"
        fi
      fi
    else
      echo "  WARNING: Could not find rootfs — skipping patches."
      echo "  Run 'fex-rootfs-setup' and 'fex-config-setup' first."
    fi

    echo ""
    echo "Setup complete. Run 'steam' to launch."
    echo "NOTE: First launch takes several minutes on FEX — be patient!"
  '';

  # Helper: find the rootfs path from Config.json or well-known locations.
  # Used by steam wrapper and diagnostics. Returns absolute path on stdout.
  fex-find-rootfs = pkgs.writeShellScriptBin "fex-find-rootfs" ''
    # 1. Try Config.json (absolute path)
    for cfg in \
      "$HOME/.fex-emu/Config.json" \
      "''${XDG_CONFIG_HOME:-$HOME/.config}/fex-emu/Config.json"; do
      if [ -f "$cfg" ]; then
        # Extract RootFS value — handles both absolute paths and names
        RF=$(grep -o '"RootFS":"[^"]*"' "$cfg" 2>/dev/null | cut -d'"' -f4)
        if [ -n "$RF" ]; then
          # If it's an absolute path and exists, use it directly
          if [ "''${RF:0:1}" = "/" ] && [ -d "$RF" ]; then
            echo "$RF"
            exit 0
          fi
          # If it's a name, search for it
          for dir in \
            "$HOME/.fex-emu/RootFS/$RF" \
            "''${XDG_DATA_HOME:-$HOME/.local/share}/fex-emu/RootFS/$RF"; do
            if [ -d "$dir" ]; then
              echo "$dir"
              exit 0
            fi
          done
        fi
      fi
    done

    # 2. Fallback: find any rootfs directory
    for dir in \
      "$HOME/.fex-emu/RootFS" \
      "''${XDG_DATA_HOME:-$HOME/.local/share}/fex-emu/RootFS"; do
      if [ -d "$dir" ]; then
        FIRST=$(ls -1 "$dir" 2>/dev/null | head -1)
        if [ -n "$FIRST" ] && [ -d "$dir/$FIRST" ]; then
          echo "$dir/$FIRST"
          exit 0
        fi
      fi
    done

    exit 1
  '';

  # Steam launch wrapper — invokes FEXInterpreter directly with rootfs bash.
  # This bypasses FEXBash which has issues finding the correct bash on NixOS.
  steam-wrapper = pkgs.writeShellScriptBin "steam" ''
    STEAM_DIR="$HOME/.local/share/Steam"

    # Check Steam is installed
    if [ ! -f "$STEAM_DIR/steam.sh" ] && [ ! -f "$STEAM_DIR/bin_steam.sh" ]; then
      echo "Steam not found. Run 'install-steam' first."
      exit 1
    fi

    # ── Locate FEX rootfs ──
    ROOTFS_PATH=$(fex-find-rootfs 2>/dev/null) || true
    if [ -z "$ROOTFS_PATH" ]; then
      echo "ERROR: FEX rootfs not found."
      echo "Run 'fex-rootfs-setup' and then 'fex-config-setup' first."
      exit 1
    fi

    ROOTFS_BASH="$ROOTFS_PATH/bin/bash"
    if [ ! -f "$ROOTFS_BASH" ] && [ ! -L "$ROOTFS_BASH" ]; then
      echo "ERROR: x86_64 bash not found at $ROOTFS_BASH"
      echo "Rootfs may be incomplete. Re-run 'fex-rootfs-setup'."
      exit 1
    fi

    echo "Launching Steam via FEX..."
    echo "  Rootfs: $ROOTFS_PATH"
    echo "  (First launch takes several minutes — be patient!)"
    echo ""

    # ── Preserve display environment ──
    # Steam/steamwebhelper (CEF/Chromium) needs a display connection to create
    # GL contexts — even for "offscreen" rendering. Capture these BEFORE we
    # modify any environment variables.
    SAVE_DISPLAY="''${DISPLAY:-}"
    SAVE_WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-}"
    SAVE_XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    SAVE_XDG_SESSION_TYPE="''${XDG_SESSION_TYPE:-}"
    SAVE_DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-}"

    # If no DISPLAY is set, try XWayland default (:0)
    if [ -z "$SAVE_DISPLAY" ]; then
      # Check if XWayland is running
      if [ -e "/tmp/.X11-unix/X0" ]; then
        SAVE_DISPLAY=":0"
      elif [ -e "/tmp/.X11-unix/X1" ]; then
        SAVE_DISPLAY=":1"
      fi
    fi

    echo "  Display: DISPLAY=$SAVE_DISPLAY WAYLAND=$SAVE_WAYLAND_DISPLAY"
    echo "  Runtime: $SAVE_XDG_RUNTIME_DIR"
    echo ""

    # ── Sanitize NixOS environment ──
    # NixOS sets env vars pointing to /nix/store aarch64 libraries.
    # These leak into FEX and cause failures when x86_64 processes try to
    # load aarch64 .so files.

    # Graphics/Vulkan — aarch64 drivers can't be used by x86_64 processes
    unset VK_ICD_FILENAMES
    unset VK_LAYER_PATH
    unset VK_ADD_LAYER_PATH
    unset __EGL_VENDOR_LIBRARY_FILENAMES
    unset __EGL_VENDOR_LIBRARY_DIRS
    unset LIBGL_DRIVERS_PATH
    unset LIBVA_DRIVERS_PATH

    # GLib/GTK/dconf — NixOS paths reference aarch64 .so files
    unset GIO_EXTRA_MODULES
    unset GIO_MODULE_DIR
    unset GSETTINGS_SCHEMAS_PATH
    unset GI_TYPELIB_PATH
    unset GTK_PATH
    unset GTK_MODULES
    unset GTK_IM_MODULE

    # Reset XDG_DATA_DIRS to FHS defaults (NixOS version includes /nix paths)
    export XDG_DATA_DIRS="/usr/local/share:/usr/share"

    # MangoHud — disable completely (aarch64 layer can't load in x86_64)
    export DISABLE_MANGOHUD=1
    export MANGOHUD=0

    # Force software rendering — no x86_64 GPU driver on ARM64 without thunks.
    # steamwebhelper (Chromium) needs this to create its offscreen GL context.
    export LIBGL_ALWAYS_SOFTWARE=1

    # Shader cache
    export MESA_SHADER_CACHE_DIR="$HOME/.cache/mesa_shader_cache"
    mkdir -p "$MESA_SHADER_CACHE_DIR"

    # DXVK async for Proton
    export DXVK_ASYNC=1

    # ── pressure-vessel / bwrap sandbox workarounds ──
    # Steam uses pressure-vessel (bwrap) to sandbox steamwebhelper and games.
    # Inside FEX, bwrap creates a real kernel mount namespace. FEX's rootfs
    # overlay can't inject files into that namespace. So libraries (like mesa)
    # that the rootfs provides are invisible inside the bwrap container.
    #
    # The fix: tell pressure-vessel to prefer host libraries. In the FEX
    # context, "host" = rootfs overlay. pressure-vessel checks which libs
    # the host has (via FEX overlay → rootfs) and bind-mounts them in.
    export STEAM_RUNTIME_PREFER_HOST_LIBRARIES=1
    export STEAM_DISABLE_BROWSER_SANDBOX=1

    # Add rootfs library paths so pressure-vessel finds mesa/GL
    export PRESSURE_VESSEL_FILESYSTEMS_RO="/etc/host.conf:/etc/hosts:/etc/resolv.conf:/etc/machine-id"
    export PRESSURE_VESSEL_VARIABLE_DIR="$HOME/.local/share/Steam/steamrt64/var"
    mkdir -p "$HOME/.local/share/Steam/steamrt64/var" 2>/dev/null || true

    # ── Build Steam arguments ──
    # -cef-disable-gpu: tell steamwebhelper's Chromium not to use GPU
    # -cef-disable-sandbox: disable Chromium sandbox (conflicts with FEX/binfmt)
    # -no-browser: skip CEF entirely, use old VGUI (set via --no-browser flag)
    STEAM_ARGS="-cef-disable-gpu -cef-disable-sandbox"
    if [ "$1" = "--no-browser" ]; then
      STEAM_ARGS="-no-browser"
      shift
    fi

    STEAM_SCRIPT="steam.sh"
    if [ ! -f "$STEAM_DIR/steam.sh" ]; then
      STEAM_SCRIPT="bin_steam.sh"
    fi

    # ── Restore display environment ──
    # These must be set so steamwebhelper can connect to the display server
    # and create GL contexts. Without DISPLAY, CEF fails with
    # "Failed creating offscreen shared JS context".
    export DISPLAY="$SAVE_DISPLAY"
    export WAYLAND_DISPLAY="$SAVE_WAYLAND_DISPLAY"
    export XDG_RUNTIME_DIR="$SAVE_XDG_RUNTIME_DIR"
    export XDG_SESSION_TYPE="$SAVE_XDG_SESSION_TYPE"
    export DBUS_SESSION_BUS_ADDRESS="$SAVE_DBUS_SESSION_BUS_ADDRESS"

    # ── Reset PATH to FHS defaults ──
    # CRITICAL: NixOS PATH contains /run/current-system/sw/bin, /nix/store/...,
    # etc. When the emulated x86_64 bash searches for commands (uname, cat, ls),
    # it finds them at NixOS paths. FEX's rootfs overlay checks if these paths
    # exist in the rootfs — they DON'T (the rootfs is Ubuntu, not NixOS).
    # So FEX falls through to the host, which runs the aarch64 native binary,
    # completely escaping emulation.
    #
    # By resetting PATH to standard FHS paths, the emulated bash finds commands
    # at /usr/bin/uname, /bin/cat, etc. FEX's overlay redirects these to the
    # rootfs's x86_64 versions. All child processes stay under emulation.
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

    # ── Launch via FEXInterpreter with rootfs bash ──
    # We invoke FEXInterpreter directly with the rootfs's x86_64 bash
    # (bypassing FEXBash which has issues on NixOS). This guarantees:
    #   - FEX loads an x86_64 ELF for emulation
    #   - Rootfs overlay redirects FHS paths to rootfs x86_64 binaries
    #   - All child processes stay under emulation (not escaping to host)
    exec ${fex}/bin/FEXInterpreter "$ROOTFS_BASH" -c \
      "cd \"$STEAM_DIR\" && STEAMOS=1 STEAM_RUNTIME=1 LIBGL_ALWAYS_SOFTWARE=1 ./$STEAM_SCRIPT $STEAM_ARGS $*"
  '';

  # Minimal mode — skip the web browser entirely (old VGUI interface)
  steam-minimal = pkgs.writeShellScriptBin "steam-minimal" ''
    exec steam --no-browser "$@"
  '';

  # Gamepad UI wrapper
  steam-gamepadui = pkgs.writeShellScriptBin "steam-gamepadui" ''
    exec steam -gamepadui -steamos -steamdeck "$@"
  '';

in {
  # /bin/bash symlink — needed for Steam's #!/bin/bash shebangs when scripts
  # are executed outside FEX (e.g. by the native aarch64 shell wrapper above).
  # Inside FEX with rootfs overlay, /bin/bash resolves to the rootfs's x86_64 bash.
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
    steam-minimal
    steam-gamepadui
    fex-find-rootfs

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
