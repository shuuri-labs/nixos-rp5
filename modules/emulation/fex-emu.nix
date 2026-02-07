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

  # Register binfmt handlers so x86_64/i386 ELFs run through FEX automatically
  boot.binfmt.registrations = {
    FEX-x86_64 = {
      magicOrExtension = ''\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00'';
      mask = ''\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff'';
      interpreter = "${fex}/bin/FEXInterpreter";
      preserveArgvZero = true;
      openBinary = true;
      fixBinary = false;
    };

    FEX-i386 = {
      magicOrExtension = ''\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x03\x00'';
      mask = ''\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff'';
      interpreter = "${fex}/bin/FEXInterpreter";
      preserveArgvZero = true;
      openBinary = true;
      fixBinary = false;
    };
  };

  # Oneshot service to verify binfmt registered correctly
  systemd.services.fex-binfmt-check = {
    description = "FEX-Emu binfmt registration check";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-binfmt.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "fex-binfmt-check" ''
        ok=true
        for handler in FEX-x86_64 FEX-i386; do
          if [ -f "/proc/sys/fs/binfmt_misc/$handler" ]; then
            echo "fex-binfmt: $handler registered"
          else
            echo "fex-binfmt: WARNING - $handler NOT registered"
            ok=false
          fi
        done
        if $ok; then
          echo "fex-binfmt: all handlers registered successfully"
        else
          echo "fex-binfmt: some handlers failed to register"
        fi
      '';
    };
  };
}
