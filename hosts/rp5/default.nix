{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware.nix
    ./sessions.nix
    ../../modules/hardware/sm8250.nix
    ../../modules/hardware/gamepad.nix
    ../../modules/graphics/mesa-turnip.nix
    ../../modules/graphics/gamescope.nix
    ../../modules/rocknix-compat/kernel-modules.nix
    ../../modules/emulation/fex-emu.nix
    ../../modules/emulation/steam.nix
    ../../modules/overlay/overlay-daemon.nix
  ];

  # System identity
  networking.hostName = "rp5";
  system.stateVersion = "24.05";

  # Timezone and locale
  time.timeZone = "UTC";  # Change to your timezone
  i18n.defaultLocale = "en_US.UTF-8";

  # Boot configuration
  # We use ROCKNIX kernel via switch_root, so minimal boot config
  boot = {
    # No bootloader management - ROCKNIX handles this
    loader.grub.enable = false;

    # No initrd - we boot via switch_root from ROCKNIX
    initrd.enable = false;

    # Kernel parameters (passed via ROCKNIX kernel cmdline)
    kernelParams = [
      "quiet"
      "loglevel=3"
    ];

    # Required sysctl for Steam/games
    kernel.sysctl = {
      "vm.max_map_count" = 2147483642;
    };

    # Tmpfs for /tmp
    tmp.useTmpfs = true;
    tmp.tmpfsSize = "2G";
  };

  # Filesystems
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOSROOT";
      fsType = "ext4";
      options = [ "noatime" "nodiratime" ];
    };

    # ROCKNIX resources (mounted by switch_root script)
    "/rocknix/flash" = {
      device = "/dev/disk/by-label/ROCKNIX";
      fsType = "vfat";
      options = [ "ro" "noatime" "nofail" ];
    };

    "/rocknix/storage" = {
      device = "/dev/disk/by-label/STORAGE";
      fsType = "ext4";
      options = [ "rw" "noatime" "nofail" ];
    };
  };

  # Swap (zram-based, no swap partition needed)
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };

  # Networking
  networking = {
    networkmanager = {
      enable = true;
      wifi.powersave = false;  # Better responsiveness for gaming
    };

    # Firewall (disabled for gaming, enable if needed)
    firewall.enable = false;
  };

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
        Experimental = true;
      };
    };
  };

  # Audio via PipeWire
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = false;  # Not needed for gaming

    wireplumber.enable = true;
  };

  # Disable PulseAudio (using PipeWire)
  hardware.pulseaudio.enable = false;

  # Security / Realtime audio
  security.rtkit.enable = true;

  # User account
  users.users.gamer = {
    isNormalUser = true;
    description = "Gamer";
    extraGroups = [
      "wheel"        # sudo
      "video"        # GPU access
      "audio"        # Audio access
      "input"        # Input devices
      "networkmanager"
      "bluetooth"
    ];
    # Default password: "gamer" (change on first login!)
    initialPassword = "gamer";
  };

  # Sudo without password for gamer (handheld convenience)
  security.sudo.extraRules = [{
    users = [ "gamer" ];
    commands = [{
      command = "ALL";
      options = [ "NOPASSWD" ];
    }];
  }];

  # Auto-login to gamer user
  services.getty.autologinUser = "gamer";

  # System packages
  environment.systemPackages = with pkgs; [
    # Basic utilities
    vim
    htop
    btop
    neofetch
    wget
    curl
    git
    unzip
    p7zip

    # Hardware tools
    pciutils
    usbutils
    lshw

    # Graphics tools
    vulkan-tools
    glxinfo
    mesa-demos

    # Network tools
    iw
    wirelesstools

    # RP5 utilities (from overlay)
    rp5-session-switch
    rp5-fps
    rp5-brightness
    rp5-volume
    rp5-wifi
    rp5-bluetooth

    # Gaming
    mangohud

    # Development (optional, comment out to save space)
    # gcc
    # gnumake
  ];

  # Environment variables
  environment.variables = {
    # Vulkan driver for Turnip
    VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/freedreno_icd.aarch64.json";

    # Mesa settings
    MESA_VK_WSI_PRESENT_MODE = "fifo";

    # SDL settings for better controller support
    SDL_GAMECONTROLLERCONFIG = "";  # Will be populated if needed
  };

  # Nix settings
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      # Reduce store size
      min-free = 1073741824;  # 1GB
      max-free = 3221225472;  # 3GB
    };

    # Garbage collection
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  # Reduce journal size
  services.journald.extraConfig = ''
    SystemMaxUse=100M
    RuntimeMaxUse=50M
  '';

  # Power management
  services.power-profiles-daemon.enable = false;  # Using device-specific power management
  services.thermald.enable = false;  # SM8250 handles thermals

  # udev rule to allow gamer to access backlight
  services.udev.extraRules = ''
    # Backlight access for gamer user
    SUBSYSTEM=="backlight", ACTION=="add", RUN+="${pkgs.coreutils}/bin/chmod 666 %S%p/brightness"
  '';

  # Boot success service (clears failsafe counter)
  systemd.services.nixos-boot-success = {
    description = "NixOS Boot Success Handler";
    wantedBy = [ "graphical.target" ];
    after = [ "graphical.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'rm -f /rocknix/storage/.nixos-boot-attempts && logger -t boot-success \"NixOS boot successful\"'";
    };
  };

  # DBus for system control
  services.dbus.enable = true;

  # Polkit for privilege escalation
  security.polkit.enable = true;

  # Allow users to control network/bluetooth without password
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if ((action.id == "org.freedesktop.NetworkManager.enable-disable-wifi" ||
           action.id == "org.freedesktop.NetworkManager.network-control" ||
           action.id == "org.freedesktop.NetworkManager.settings.modify.system" ||
           action.id == "org.bluez.device.pair" ||
           action.id == "org.bluez.device.connect") &&
          subject.local && subject.active) {
        return polkit.Result.YES;
      }
    });
  '';
}
