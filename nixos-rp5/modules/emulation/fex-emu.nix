{ config, lib, pkgs, inputs, ... }:

# FEX-Emu module for x86_64 emulation on aarch64
# FEX-Emu allows running x86_64 Linux binaries on ARM64, including Steam

let
  # FEX-Emu package
  # Note: This is a simplified derivation. For full functionality,
  # you may need to build from source with specific options.
  fex-emu = pkgs.stdenv.mkDerivation rec {
    pname = "fex-emu";
    version = "2401";  # Update to latest stable

    src = inputs.fex-emu-src or (pkgs.fetchFromGitHub {
      owner = "FEX-Emu";
      repo = "FEX";
      rev = "FEX-${version}";
      sha256 = lib.fakeSha256;  # Replace with actual hash
      fetchSubmodules = true;
    });

    nativeBuildInputs = with pkgs; [
      cmake
      ninja
      pkg-config
      python3
      git
    ];

    buildInputs = with pkgs; [
      SDL2
      libepoxy
      libdrm
      xorg.libX11
      xorg.libXrandr
      openssl
      zlib
      lz4
      zstd
      fmt
      nlohmann_json
    ];

    cmakeFlags = [
      "-DENABLE_LTO=ON"
      "-DBUILD_TESTS=OFF"
      "-DBUILD_THUNKS=ON"
      "-DCMAKE_BUILD_TYPE=Release"
      "-GNinja"
    ];

    # FEX needs write access to some cache directories
    postInstall = ''
      mkdir -p $out/share/fex-emu
      # Install wrapper scripts
      cat > $out/bin/FEXRun <<'EOF'
#!/bin/sh
exec $out/bin/FEXInterpreter "$@"
EOF
      chmod +x $out/bin/FEXRun
    '';

    meta = with lib; {
      description = "Fast x86 emulation frontend for running x86 and x86-64 applications on AArch64 Linux";
      homepage = "https://fex-emu.com/";
      license = licenses.mit;
      platforms = [ "aarch64-linux" ];
    };
  };

  # RootFS fetcher script
  fex-rootfs-fetcher = pkgs.writeShellScriptBin "fex-rootfs-setup" ''
    #!/bin/bash
    # FEX-Emu RootFS setup script
    # Downloads and configures the x86_64 rootfs for FEX

    set -e

    ROOTFS_PATH="''${FEX_ROOTFS:-/var/lib/fex-emu/rootfs}"
    ROOTFS_URL="https://rootfs.fex-emu.org/Ubuntu_22_04.sqsh"  # Example URL

    echo "FEX-Emu RootFS Setup"
    echo "===================="
    echo "RootFS path: $ROOTFS_PATH"

    if [ -d "$ROOTFS_PATH" ] && [ -n "$(ls -A $ROOTFS_PATH 2>/dev/null)" ]; then
      echo "RootFS already exists at $ROOTFS_PATH"
      echo "Delete it first if you want to reinstall"
      exit 0
    fi

    mkdir -p "$ROOTFS_PATH"
    mkdir -p /var/lib/fex-emu

    echo "Downloading RootFS..."
    echo "This may take a while depending on your internet connection."

    # Use FEX's built-in rootfs fetcher if available
    if command -v FEXRootFSFetcher &>/dev/null; then
      FEXRootFSFetcher -x "$ROOTFS_PATH"
    else
      echo "FEXRootFSFetcher not available."
      echo "Please manually download a rootfs from https://rootfs.fex-emu.org/"
      echo "And extract it to: $ROOTFS_PATH"
      exit 1
    fi

    echo "RootFS setup complete!"
    echo "You can now run x86_64 binaries with FEX"
  '';

in {
  options.rp5.fex-emu = {
    enable = lib.mkEnableOption "FEX-Emu x86_64 emulation";

    rootfsPath = lib.mkOption {
      type = lib.types.path;
      default = /var/lib/fex-emu/rootfs;
      description = "Path to FEX-Emu x86_64 rootfs";
    };

    enableBinfmt = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Register FEX as binfmt handler for x86_64/i386 binaries";
    };
  };

  config = lib.mkIf (config.rp5.fex-emu.enable or false) {
    # Install FEX-Emu packages
    environment.systemPackages = [
      # Note: Using a placeholder since the actual FEX package needs to be built
      # For now, provide the helper scripts
      fex-rootfs-fetcher

      # Box64 as an alternative/fallback
      pkgs.box64

      # For unpacking rootfs
      pkgs.squashfsTools
    ];

    # FEX-Emu environment
    environment.variables = {
      FEX_ROOTFS = toString config.rp5.fex-emu.rootfsPath;
    };

    # binfmt registration for x86_64 binaries
    # This allows running x86_64 ELF files directly
    boot.binfmt.registrations = lib.mkIf (config.rp5.fex-emu.enableBinfmt or true) {
      # x86_64 ELF binaries
      FEX-x86_64 = {
        # ELF magic for x86_64
        magicOrExtension = ''\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00'';
        mask = ''\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff'';
        # Use Box64 for now (more readily available)
        # Replace with FEX-Emu path when properly packaged
        interpreter = "${pkgs.box64}/bin/box64";
        preserveArgvZero = true;
        openBinary = true;
        fixBinary = false;  # Allow different binaries
      };

      # i386 (32-bit x86) ELF binaries
      FEX-i386 = {
        magicOrExtension = ''\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x03\x00'';
        mask = ''\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff'';
        # Box86 for 32-bit
        interpreter = "${pkgs.box86 or pkgs.box64}/bin/box86";
        preserveArgvZero = true;
        openBinary = true;
        fixBinary = false;
      };
    };

    # Systemd service to set up FEX rootfs on first boot
    systemd.services.fex-emu-setup = {
      description = "FEX-Emu RootFS Setup";
      wantedBy = [ "multi-user.target" ];
      before = [ "display-manager.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.writeShellScript "fex-setup-check" ''
          ROOTFS_PATH="${toString config.rp5.fex-emu.rootfsPath}"

          if [ -d "$ROOTFS_PATH" ] && [ -n "$(ls -A $ROOTFS_PATH 2>/dev/null)" ]; then
            echo "FEX RootFS already present at $ROOTFS_PATH"
            exit 0
          fi

          echo "FEX RootFS not found at $ROOTFS_PATH"
          echo "Run 'fex-rootfs-setup' to download and configure it"
          echo "Or manually extract a rootfs to $ROOTFS_PATH"

          # Create directory structure
          mkdir -p "$ROOTFS_PATH"
          mkdir -p /var/lib/fex-emu

          exit 0
        ''}";
      };
    };

    # Allow users to modify FEX config
    environment.etc."fex-emu/Config.json".text = builtins.toJSON {
      RootFS = toString config.rp5.fex-emu.rootfsPath;
      ThunkHostLibs = "/usr/lib/fex-emu/HostThunks/";
      ThunkGuestLibs = "/usr/lib/fex-emu/GuestThunks/";
    };
  };
}
