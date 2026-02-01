{ config, lib, pkgs, ... }:

# Mesa with Turnip Vulkan driver for Adreno 650 GPU
# Turnip is the open-source Vulkan driver for Qualcomm Adreno GPUs

{
  options.rp5.graphics = {
    enable = lib.mkEnableOption "RP5 graphics configuration (Mesa/Turnip)";

    enableVulkan = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Vulkan support via Turnip driver";
    };

    enable32Bit = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable 32-bit graphics libraries (for Wine/Proton)";
    };
  };

  config = lib.mkIf (config.rp5.graphics.enable or true) {
    # Graphics/OpenGL
    hardware.opengl = {
      enable = true;
      driSupport = true;
      driSupport32Bit = config.rp5.graphics.enable32Bit or true;

      extraPackages = with pkgs; [
        # Mesa with Freedreno/Turnip
        mesa

        # Vulkan
        vulkan-loader
        vulkan-tools
        vulkan-validation-layers
        vulkan-extension-layer

        # VA-API (video acceleration)
        # Note: VA-API on Adreno may have limited support
      ];

      extraPackages32 = lib.mkIf (config.rp5.graphics.enable32Bit or true) (with pkgs.pkgsi686Linux; [
        mesa
        vulkan-loader
      ]);
    };

    # Environment variables for Turnip/Freedreno
    environment.variables = {
      # Vulkan ICD (Installable Client Driver)
      VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/freedreno_icd.aarch64.json";

      # Mesa settings for better compatibility
      MESA_VK_WSI_PRESENT_MODE = "fifo";  # VSync mode

      # Debug options (uncomment for troubleshooting)
      # TU_DEBUG = "startup";  # Turnip debug output
      # MESA_DEBUG = "1";
      # LIBGL_DEBUG = "verbose";

      # Force Turnip as the Vulkan driver
      # AMD_VULKAN_ICD = "RADV";  # Not applicable, but shows pattern

      # OpenGL ES settings
      MESA_GLES_VERSION_OVERRIDE = "3.2";
      MESA_GLSL_VERSION_OVERRIDE = "320";
    };

    # Vulkan layers configuration
    environment.etc."vulkan/explicit_layer.d/VkLayer_khronos_validation.json".source =
      "${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d/VkLayer_khronos_validation.json";

    # Graphics packages
    environment.systemPackages = with pkgs; [
      # Vulkan tools
      vulkan-tools       # vulkaninfo, vkcube
      vulkan-caps-viewer # GUI Vulkan info (if desktop available)

      # OpenGL tools
      glxinfo            # glxinfo (via mesa-demos)
      mesa-demos         # glxgears, es2gears, etc.

      # GPU monitoring (if available for ARM)
      # radeontop  # AMD only
      # nvtop      # NVIDIA/AMD/Intel

      # Debug tools
      apitrace           # OpenGL/Vulkan call tracing
    ];

    # DRM (Direct Rendering Manager) configuration
    services.udev.extraRules = ''
      # Allow video group access to GPU devices
      SUBSYSTEM=="drm", KERNEL=="card*", MODE="0666", GROUP="video"
      SUBSYSTEM=="drm", KERNEL=="renderD*", MODE="0666", GROUP="video"

      # Qualcomm KGSL (GPU) device
      SUBSYSTEM=="kgsl", MODE="0666", GROUP="video"
      KERNEL=="kgsl-3d0", MODE="0666", GROUP="video"
    '';

    # Ensure gamer is in video group
    users.users.gamer.extraGroups = [ "video" "render" ];
  };
}
