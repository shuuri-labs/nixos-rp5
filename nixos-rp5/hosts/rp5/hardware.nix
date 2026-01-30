{ config, lib, pkgs, modulesPath, ... }:

{
  # Hardware configuration for Retroid Pocket 5
  # Snapdragon 865 (SM8250) with Adreno 650 GPU

  # CPU
  # Snapdragon 865: 1x Cortex-X1 @ 2.84GHz + 3x Cortex-A78 @ 2.42GHz + 4x Cortex-A55 @ 1.8GHz
  powerManagement.cpuFreqGovernor = lib.mkDefault "schedutil";

  # Hardware
  hardware = {
    # We use ROCKNIX kernel and firmware via bind-mounts
    # Don't try to load NixOS firmware
    enableRedistributableFirmware = false;
    enableAllFirmware = false;

    # Graphics - handled by mesa-turnip module
    graphics.enable = true;
  };

  # Console
  console = {
    font = "ter-v24n";
    packages = [ pkgs.terminus_font ];
    # Use framebuffer console
    earlySetup = false;
  };

  # Services specific to hardware
  services = {
    # Firmware updates (disabled - we use ROCKNIX firmware)
    fwupd.enable = false;
  };

  # Kernel modules to load (from ROCKNIX bind-mount)
  boot.kernelModules = [
    # These should be available from ROCKNIX kernel
    "snd_soc_sm8250"   # Audio codec
    "qcom_spmi_adc5"   # ADC for battery/thermals
  ];

  # Extra module packages (none - using ROCKNIX modules)
  boot.extraModulePackages = [ ];
}
