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

  # Register binfmt handlers directly via systemd service.
  # NixOS boot.binfmt.registrations wraps the interpreter in a bash script,
  # which breaks the O (open-binary) flag — the kernel-opened fd doesn't
  # survive the shell wrapper correctly. We register FEXInterpreter directly
  # with the POCF flags that FEX expects.
  systemd.services.fex-binfmt = {
    description = "Register FEX-Emu binfmt handlers";
    after = [ "proc-sys-fs-binfmt_misc.mount" "systemd-binfmt.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "register-fex-binfmt" ''
        # Remove stale entries if they exist
        for entry in FEX-x86_64 FEX-i386; do
          [ -f "/proc/sys/fs/binfmt_misc/$entry" ] && echo -1 > "/proc/sys/fs/binfmt_misc/$entry"
        done

        # Register x86_64 (POCF = preserve-argv0, open-binary, credentials, fix-binary)
        echo ':FEX-x86_64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00:\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:${fex}/bin/FEXInterpreter:POCF' \
          > /proc/sys/fs/binfmt_misc/register

        # Register i386
        echo ':FEX-i386:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x03\x00:\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:${fex}/bin/FEXInterpreter:POCF' \
          > /proc/sys/fs/binfmt_misc/register

        # Verify
        for entry in FEX-x86_64 FEX-i386; do
          if [ -f "/proc/sys/fs/binfmt_misc/$entry" ]; then
            echo "fex-binfmt: $entry registered"
          else
            echo "fex-binfmt: WARNING - $entry failed to register"
          fi
        done
      '';
      ExecStop = pkgs.writeShellScript "unregister-fex-binfmt" ''
        for entry in FEX-x86_64 FEX-i386; do
          [ -f "/proc/sys/fs/binfmt_misc/$entry" ] && echo -1 > "/proc/sys/fs/binfmt_misc/$entry"
        done
      '';
    };
  };
}
