{ config, lib, pkgs, ... }:

# ROCKNIX Kernel/Firmware Compatibility Module
# This module handles the bind-mounted kernel modules and firmware from ROCKNIX
# The actual bind-mounts are done by mount-storage.sh during boot

{
  options.rp5.rocknix = {
    enable = lib.mkEnableOption "ROCKNIX compatibility layer";

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

  config = lib.mkIf (config.rp5.rocknix.enable or true) {
    # Treat as container to skip bootloader/initrd requirements
    # We chain-boot from ROCKNIX, so we don't need NixOS to manage boot
    boot.isContainer = true;

    # Override the container check for systemd (we're not actually a container)
    boot.enableContainers = lib.mkDefault true;

    # Still set these for documentation purposes
    boot.loader = {
      grub.enable = lib.mkForce false;
      systemd-boot.enable = lib.mkForce false;
      generic-extlinux-compatible.enable = lib.mkForce false;
    };

    # System activation should not try to build kernel modules
    system.activationScripts.setupKernelModules = lib.mkForce "";

    # Don't regenerate hardware config that depends on kernel
    system.nixos.tags = [ "rocknix-compat" ];

    # Environment for ROCKNIX compatibility
    environment.variables = {
      # Firmware path for drivers
      FIRMWARE_PATH = config.rp5.rocknix.firmwarePath or "/lib/firmware";
    };

    # Systemd service to verify ROCKNIX mounts
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
    # Some drivers look in different paths
    environment.etc = {
      # Alternative firmware paths that some drivers check
      "firmware".source = "/lib/firmware";
    };

    # Module loading configuration
    # These modules should be loaded from the ROCKNIX bind-mount
    boot.kernelModules = [
      # Graphics
      "msm_drm"         # Qualcomm DRM driver
      "gpu_sched"       # GPU scheduler

      # Input
      "evdev"
      "uinput"

      # USB
      "usbcore"
      "usbhid"
      "usb_storage"

      # Networking
      "cfg80211"        # Wireless configuration
      "mac80211"        # Wireless MAC layer
      # Qualcomm WiFi driver loaded by firmware

      # Bluetooth
      "bluetooth"
      "btusb"
      "rfkill"

      # Filesystem
      "ext4"
      "vfat"
      "nls_cp437"
      "nls_iso8859-1"

      # Audio
      "snd"
      "snd_pcm"
      "snd_timer"
    ];

    # Blacklisted modules (prevent loading problematic modules)
    boot.blacklistedKernelModules = [
      # Add any modules that cause issues
    ];
  };
}
