{ config, lib, pkgs, ... }:

# ROCKNIX Kernel/Firmware Compatibility Module
# This module handles chain-booting NixOS from ROCKNIX
# ROCKNIX provides: kernel, initrd, firmware, kernel modules
# NixOS provides: userspace, systemd, services

{
  options.rp5.rocknix = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;  # Enabled by default when module is imported
      description = "Enable ROCKNIX compatibility layer";
    };

    modulesPath = lib.mkOption {
      type = lib.types.path;
      default = "/lib/modules";
      description = "Path where ROCKNIX kernel modules are bind-mounted";
    };

    firmwarePath = lib.mkOption {
      type = lib.types.path;
      default = "/lib/firmware";
      description = "Path where ROCKNIX firmware is bind-mounted";
    };

    storagePath = lib.mkOption {
      type = lib.types.path;
      default = "/rocknix/storage";
      description = "Path to ROCKNIX storage partition";
    };
  };

  config = lib.mkIf config.rp5.rocknix.enable {
    # ==========================================================================
    # CRITICAL: Chain-boot configuration for ROCKNIX
    # We DON'T use boot.isContainer because we need the init wrapper for switch_root
    # Instead, we manually disable the boot components we don't need
    # ==========================================================================

    # Disable kernel building - we use ROCKNIX kernel via bind-mount
    boot.kernel.enable = false;

    # Disable modprobe config generation - modules come from ROCKNIX
    boot.modprobeConfig.enable = false;

    # Disable initrd - we chain-boot via switch_root from ROCKNIX init
    boot.initrd.enable = false;
    boot.initrd.systemd.enable = lib.mkForce false;

    # Disable all bootloaders - ROCKNIX GRUB handles booting
    boot.loader = {
      grub.enable = lib.mkForce false;
      systemd-boot.enable = lib.mkForce false;
      generic-extlinux-compatible.enable = lib.mkForce false;
    };

    # ==========================================================================
    # STUBS: Provide dummy derivations for attributes the system builder expects
    # These won't actually be used - ROCKNIX provides the real kernel/initrd
    # ==========================================================================

    system.build.installBootLoader = lib.mkForce "${pkgs.coreutils}/bin/true";

    system.build.initialRamdisk = lib.mkForce (
      pkgs.runCommand "rocknix-dummy-initrd" {} ''
        mkdir -p $out
        echo "# Dummy initrd - NixOS chain-boots from ROCKNIX" > $out/initrd
      ''
    );

    system.build.kernel = lib.mkForce (
      pkgs.runCommand "rocknix-dummy-kernel" {} ''
        mkdir -p $out
        touch $out/Image
        touch $out/bzImage
      ''
    );

    # ==========================================================================
    # ROCKNIX Integration
    # ==========================================================================

    # System activation should not try to build kernel modules
    system.activationScripts.setupKernelModules = lib.mkForce "";

    # Tag for identification
    system.nixos.tags = [ "rocknix-compat" ];

    # Environment for ROCKNIX compatibility
    environment.variables = {
      FIRMWARE_PATH = config.rp5.rocknix.firmwarePath or "/lib/firmware";
    };

    # Systemd service to verify ROCKNIX mounts on boot
    systemd.services.rocknix-verify = {
      description = "Verify ROCKNIX bind mounts";
      wantedBy = [ "multi-user.target" ];
      before = [ "display-manager.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        echo "Verifying ROCKNIX compatibility layer..."

        # Check kernel modules
        KVER=$(uname -r)
        if [ ! -d "/lib/modules/$KVER" ]; then
          echo "WARNING: Kernel modules not found at /lib/modules/$KVER"
          echo "Boot may have failed to bind-mount ROCKNIX modules"
        else
          echo "Kernel modules: OK (/lib/modules/$KVER)"
          ls /lib/modules/$KVER/ | head -5
        fi

        # Check firmware
        if [ ! -d "/lib/firmware" ] || [ -z "$(ls -A /lib/firmware 2>/dev/null)" ]; then
          echo "WARNING: Firmware not found at /lib/firmware"
        else
          echo "Firmware: OK (/lib/firmware)"
          ls /lib/firmware/ | head -5
        fi

        # Check ROCKNIX resources
        if [ -d "/rocknix/sysroot" ]; then
          echo "ROCKNIX sysroot: OK"
        else
          echo "WARNING: ROCKNIX sysroot not mounted"
        fi

        if [ -d "/rocknix/storage" ]; then
          echo "ROCKNIX storage: OK"
        else
          echo "WARNING: ROCKNIX storage not mounted"
        fi

        echo "ROCKNIX verification complete"
      '';
    };

    # Symlinks for firmware compatibility
    environment.etc = {
      "firmware".source = "/lib/firmware";
    };
  };
}
