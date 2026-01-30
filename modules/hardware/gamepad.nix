{ config, lib, pkgs, ... }:

# Gamepad/Controller configuration for Retroid Pocket 5
# The RP5 has a built-in gamepad that appears as an evdev input device

{
  options.rp5.hardware.gamepad = {
    enable = lib.mkEnableOption "RP5 built-in gamepad configuration";
  };

  config = lib.mkIf (config.rp5.hardware.gamepad.enable or true) {
    # udev rules for gamepad devices
    services.udev.extraRules = ''
      # RP5 built-in gamepad - allow input group access
      SUBSYSTEM=="input", ATTRS{name}=="*joypad*", MODE="0666", TAG+="uaccess"
      SUBSYSTEM=="input", ATTRS{name}=="*Gamepad*", MODE="0666", TAG+="uaccess"
      SUBSYSTEM=="input", ATTRS{name}=="*gamepad*", MODE="0666", TAG+="uaccess"
      SUBSYSTEM=="input", ATTRS{name}=="*Controller*", MODE="0666", TAG+="uaccess"

      # Retroid specific device names (may vary)
      SUBSYSTEM=="input", ATTRS{name}=="Retroid*", MODE="0666", TAG+="uaccess"
      SUBSYSTEM=="input", ATTRS{name}=="retroid*", MODE="0666", TAG+="uaccess"

      # Generic gamepad rules
      SUBSYSTEM=="input", ENV{ID_INPUT_JOYSTICK}=="1", MODE="0666", TAG+="uaccess"

      # Force feedback support
      SUBSYSTEM=="input", ATTR{capabilities/ff}!="0", MODE="0666"

      # Allow access to event devices for the input group
      KERNEL=="event[0-9]*", SUBSYSTEM=="input", MODE="0666", GROUP="input"

      # USB gamepads (for external controllers)
      SUBSYSTEM=="usb", ATTR{bInterfaceClass}=="03", ATTR{bInterfaceSubClass}=="00", ATTR{bInterfaceProtocol}=="00", MODE="0666"

      # Steam Controller (if connected via USB/dongle)
      SUBSYSTEM=="usb", ATTR{idVendor}=="28de", MODE="0666"
      KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
    '';

    # Packages for gamepad support
    environment.systemPackages = with pkgs; [
      # Input testing/configuration
      evtest      # Test input devices
      jstest-gtk  # Joystick testing GUI (if you have a desktop)
      linuxConsoleTools  # jstest, jscal

      # SDL gamepad mapping
      sdl2
    ];

    # uinput module for virtual input device creation (needed by some apps)
    boot.kernelModules = [ "uinput" ];

    # Steam Input udev rules (for external controllers)
    hardware.steam-hardware.enable = true;

    # Environment for SDL controller support
    environment.variables = {
      # SDL will use evdev directly
      SDL_JOYSTICK_DEVICE = "/dev/input/event*";
    };

    # Ensure gamer user is in input group
    users.users.gamer.extraGroups = [ "input" ];
  };
}
