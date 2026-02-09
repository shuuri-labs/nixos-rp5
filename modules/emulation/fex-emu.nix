{ config, lib, pkgs, ... }:

# FEX-Emu module for x86_64 emulation on aarch64
# Uses FEX from nixpkgs-unstable (FEX 2601+)
#
# Key insight: FEX's rootfs overlay works by intercepting syscalls inside the
# emulator and prepending the rootfs path. It does NOT use FUSE or kernel
# overlayfs. Config.json must have an absolute rootfs path for reliable
# resolution on NixOS.

let
  fex = pkgs.unstable.fex;

  # Default rootfs name (can be overridden)
  defaultRootFSName = "Ubuntu_24_04";

  # Helper script that wraps FEXRootFSFetcher and ensures config is correct
  fex-rootfs-setup = pkgs.writeShellScriptBin "fex-rootfs-setup" ''
    set -e

    echo "FEX-Emu RootFS Setup"
    echo "===================="

    if ! command -v FEXRootFSFetcher &>/dev/null; then
      echo "ERROR: FEXRootFSFetcher not found on PATH"
      exit 1
    fi

    echo "Launching FEXRootFSFetcher..."
    echo "This will download an x86_64 rootfs image."
    echo ""
    FEXRootFSFetcher "$@"

    # After fetching, fix up the config to use absolute path
    echo ""
    echo "Configuring FEX rootfs path..."
    fex-config-setup
  '';

  # Script to ensure FEX Config.json uses an absolute rootfs path.
  # FEX searches for rootfs by name in data directories, but on NixOS the
  # resolution can fail due to directory layout differences. Using an absolute
  # path bypasses name resolution entirely.
  fex-config-setup = pkgs.writeShellScriptBin "fex-config-setup" ''
    set -e

    # Locate the rootfs directory — check both legacy and XDG paths
    ROOTFS_DIR=""
    for dir in \
      "$HOME/.fex-emu/RootFS" \
      "''${XDG_DATA_HOME:-$HOME/.local/share}/fex-emu/RootFS"; do
      if [ -d "$dir" ]; then
        ROOTFS_DIR="$dir"
        break
      fi
    done

    if [ -z "$ROOTFS_DIR" ]; then
      echo "ERROR: No FEX rootfs directory found."
      echo "Run 'fex-rootfs-setup' to download one."
      exit 1
    fi

    # Find the first rootfs (or use the specified name)
    ROOTFS_NAME="''${1:-}"
    if [ -z "$ROOTFS_NAME" ]; then
      # Auto-detect: pick the first subdirectory in RootFS/
      ROOTFS_NAME=$(ls -1 "$ROOTFS_DIR" 2>/dev/null | head -1)
    fi

    if [ -z "$ROOTFS_NAME" ] || [ ! -d "$ROOTFS_DIR/$ROOTFS_NAME" ]; then
      echo "ERROR: No rootfs found in $ROOTFS_DIR"
      echo "Available: $(ls -1 "$ROOTFS_DIR" 2>/dev/null || echo '(none)')"
      exit 1
    fi

    ROOTFS_PATH="$ROOTFS_DIR/$ROOTFS_NAME"

    # Verify the rootfs has essential files
    if [ ! -f "$ROOTFS_PATH/bin/bash" ] && [ ! -L "$ROOTFS_PATH/bin/bash" ]; then
      echo "ERROR: $ROOTFS_PATH/bin/bash not found — rootfs may be incomplete"
      exit 1
    fi

    echo "RootFS: $ROOTFS_PATH"

    # Write config with ABSOLUTE path to both legacy and XDG locations
    # FEX checks these in order; having both ensures it works regardless
    # of which path FEX resolves first.
    CONFIG_CONTENT="{\"Config\":{\"RootFS\":\"$ROOTFS_PATH\"}}"

    mkdir -p "$HOME/.fex-emu"
    echo "$CONFIG_CONTENT" > "$HOME/.fex-emu/Config.json"
    echo "Wrote: $HOME/.fex-emu/Config.json"

    mkdir -p "''${XDG_CONFIG_HOME:-$HOME/.config}/fex-emu"
    echo "$CONFIG_CONTENT" > "''${XDG_CONFIG_HOME:-$HOME/.config}/fex-emu/Config.json"
    echo "Wrote: ''${XDG_CONFIG_HOME:-$HOME/.config}/fex-emu/Config.json"

    echo ""
    echo "FEX rootfs configured with absolute path."
  '';

  # Diagnostic script for debugging FEX issues on the device
  fex-check = pkgs.writeShellScriptBin "fex-check" ''
    echo "FEX-Emu Diagnostics"
    echo "==================="
    echo ""

    # 1. FEX binary
    echo "── FEX Binary ──"
    FEX_BIN="${fex}/bin/FEXInterpreter"
    if [ -f "$FEX_BIN" ]; then
      echo "  FEXInterpreter: $FEX_BIN"
      file "$FEX_BIN" 2>/dev/null || echo "  (file command not available)"
    else
      echo "  ERROR: FEXInterpreter not found at $FEX_BIN"
    fi
    echo ""

    # 2. binfmt registration
    echo "── binfmt ──"
    if [ -f /proc/sys/fs/binfmt_misc/FEX-x86_64 ]; then
      echo "  FEX-x86_64: registered"
      cat /proc/sys/fs/binfmt_misc/FEX-x86_64 2>/dev/null | head -3
    else
      echo "  FEX-x86_64: NOT registered"
    fi
    echo ""

    # 3. Config files
    echo "── Config ──"
    for cfg in \
      "$HOME/.fex-emu/Config.json" \
      "$HOME/.config/fex-emu/Config.json" \
      "''${XDG_CONFIG_HOME:-$HOME/.config}/fex-emu/Config.json"; do
      if [ -f "$cfg" ]; then
        echo "  $cfg:"
        echo "    $(cat "$cfg")"
      fi
    done
    echo ""

    # 4. RootFS
    echo "── RootFS ──"
    for dir in \
      "$HOME/.fex-emu/RootFS" \
      "''${XDG_DATA_HOME:-$HOME/.local/share}/fex-emu/RootFS"; do
      if [ -d "$dir" ]; then
        echo "  $dir:"
        for rf in "$dir"/*/; do
          [ -d "$rf" ] || continue
          RF_NAME=$(basename "$rf")
          echo "    $RF_NAME/"
          if [ -f "$rf/bin/bash" ] || [ -L "$rf/bin/bash" ]; then
            echo "      bin/bash: $(file "$rf/bin/bash" 2>/dev/null || echo 'exists')"
          else
            echo "      bin/bash: MISSING"
          fi
          if [ -d "$rf/usr/lib/x86_64-linux-gnu" ]; then
            LIB_COUNT=$(ls "$rf/usr/lib/x86_64-linux-gnu/" 2>/dev/null | wc -l)
            echo "      usr/lib/x86_64-linux-gnu/: $LIB_COUNT files"
          else
            echo "      usr/lib/x86_64-linux-gnu/: MISSING"
          fi
          if [ -f "$rf/etc/os-release" ]; then
            echo "      os-release: $(grep PRETTY_NAME "$rf/etc/os-release" 2>/dev/null | cut -d= -f2)"
          fi
        done
      fi
    done
    echo ""

    # 5. Thunks
    echo "── Thunks ──"
    GUEST_THUNKS="${fex}/share/fex-emu/GuestThunks"
    HOST_THUNKS="${fex}/lib/fex-emu/HostThunks"
    if [ -d "$GUEST_THUNKS" ]; then
      echo "  GuestThunks: $(ls "$GUEST_THUNKS" 2>/dev/null | wc -l) files"
    else
      echo "  GuestThunks: not found at $GUEST_THUNKS"
    fi
    if [ -d "$HOST_THUNKS" ]; then
      echo "  HostThunks: $(ls "$HOST_THUNKS" 2>/dev/null | wc -l) files"
    else
      echo "  HostThunks: not found at $HOST_THUNKS"
    fi
    echo ""

    # 6. Host /bin/bash
    echo "── /bin/bash ──"
    if [ -e /bin/bash ]; then
      echo "  /bin/bash exists: $(file /bin/bash 2>/dev/null || ls -la /bin/bash)"
    else
      echo "  /bin/bash: not present on host"
    fi
    echo ""

    # 7. Quick emulation test
    echo "── Emulation Test ──"
    # Resolve rootfs path from config
    ROOTFS_PATH=""
    for cfg in "$HOME/.fex-emu/Config.json" "$HOME/.config/fex-emu/Config.json"; do
      if [ -f "$cfg" ]; then
        # Extract RootFS value (simple grep, no jq dependency)
        ROOTFS_PATH=$(grep -o '"RootFS":"[^"]*"' "$cfg" 2>/dev/null | cut -d'"' -f4)
        break
      fi
    done

    if [ -n "$ROOTFS_PATH" ] && [ -f "$ROOTFS_PATH/bin/bash" ]; then
      echo "  Testing: FEX $ROOTFS_PATH/bin/bash -c 'uname -m'"
      RESULT=$(${fex}/bin/FEXInterpreter "$ROOTFS_PATH/bin/bash" -c 'uname -m' 2>/dev/null) || RESULT="FAILED"
      echo "  Result: $RESULT"
      if [ "$RESULT" = "x86_64" ]; then
        echo "  STATUS: EMULATION WORKING"
      else
        echo "  STATUS: EMULATION BROKEN — expected x86_64, got $RESULT"
      fi
    else
      echo "  Cannot test — rootfs bash not found at: $ROOTFS_PATH/bin/bash"
    fi
    echo ""

    # 8. Kernel support
    echo "── Kernel ──"
    echo "  Version: $(uname -r)"
    echo "  Arch: $(uname -m)"
    echo ""
  '';

in {
  # Install FEX and helpers
  environment.systemPackages = [
    fex
    fex-rootfs-setup
    fex-config-setup
    fex-check
    pkgs.squashfsTools  # for rootfs images
    pkgs.file           # for fex-check diagnostics
  ];

  # Register binfmt handlers so x86_64/i386 ELFs run through FEX automatically.
  # NixOS wraps the interpreter in a shell script at /run/binfmt/. We must NOT
  # use openBinary (O flag) because the kernel-opened fd doesn't survive the
  # shell wrapper. FEXInterpreter opens the binary by path instead.
  boot.binfmt.registrations = {
    FEX-x86_64 = {
      magicOrExtension = ''\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00'';
      mask = ''\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff'';
      interpreter = "${fex}/bin/FEXInterpreter";
      preserveArgvZero = true;
      openBinary = false;
      fixBinary = false;
    };

    FEX-i386 = {
      magicOrExtension = ''\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x03\x00'';
      mask = ''\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff'';
      interpreter = "${fex}/bin/FEXInterpreter";
      preserveArgvZero = true;
      openBinary = false;
      fixBinary = false;
    };
  };
}
