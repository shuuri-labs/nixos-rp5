{ config, lib, pkgs, ... }:

# Snapdragon 865 (SM8250) specific configuration
# CPU: Kryo 585 (1x2.84 GHz Cortex-A77 + 3x2.42 GHz Cortex-A77 + 4x1.8 GHz Cortex-A55)
# GPU: Adreno 650

{
  options.rp5.hardware.sm8250 = {
    enable = lib.mkEnableOption "Snapdragon 865 (SM8250) hardware configuration";
  };

  config = lib.mkIf (config.rp5.hardware.sm8250.enable or true) {
    # CPU frequency scaling
    powerManagement = {
      enable = true;
      cpuFreqGovernor = "schedutil";  # Best for heterogeneous ARM cores
    };

    # Boot parameters for SM8250
    boot.kernelParams = [
      # Qualcomm-specific
      "clk_ignore_unused"      # Don't disable unused clocks (needed for some peripherals)
      "pd_ignore_unused"       # Don't disable unused power domains

      # Memory
      "cma=256M"               # Contiguous memory for GPU/media

      # Console
      "console=tty0"
    ];

    # Module parameters for Qualcomm hardware
    boot.extraModprobeConfig = ''
      # Adreno GPU options
      options adreno idle_timeout=50

      # WiFi power save (disable for lower latency)
      options cfg80211 ieee80211_regdom=US
    '';

    # udev rules for Qualcomm hardware
    services.udev.extraRules = ''
      # Adreno GPU - allow video group access
      SUBSYSTEM=="drm", KERNEL=="renderD*", MODE="0666"
      SUBSYSTEM=="drm", KERNEL=="card*", MODE="0666"

      # Qualcomm DSP
      SUBSYSTEM=="misc", KERNEL=="fastrpc-*", MODE="0666"

      # USB gadget mode
      SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666"

      # Battery/charging
      SUBSYSTEM=="power_supply", ATTR{type}=="Battery", MODE="0644"

      # Sensors
      SUBSYSTEM=="iio", MODE="0666"
    '';

    # Environment for Qualcomm hardware
    environment.variables = {
      # Adreno/Turnip Vulkan driver
      MESA_LOADER_DRIVER_OVERRIDE = "kgsl";  # Use KGSL backend for Mesa on Qualcomm

      # Better performance settings
      __GL_THREADED_OPTIMIZATIONS = "1";
    };

    # Qualcomm-specific packages
    environment.systemPackages = with pkgs; [
      # Power management
      # (qualcomm-specific tools would go here if packaged)
    ];

    # Thermal management - SM8250 handles this in firmware/kernel
    # Don't run thermald
    services.thermald.enable = false;
  };
}
