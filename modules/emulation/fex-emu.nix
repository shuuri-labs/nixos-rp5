{ config, lib, pkgs, ... }:

# FEX-Emu module for x86_64 emulation on aarch64
# Uses FEX from nixpkgs-unstable (FEX 2601+)

let
  fex = pkgs.unstable.fex;

  # Helper script that wraps FEXRootFSFetcher
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
    exec FEXRootFSFetcher "$@"
  '';

in {
  # Install FEX and helper
  environment.systemPackages = [
    fex
    fex-rootfs-setup
    pkgs.squashfsTools # for rootfs images
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
