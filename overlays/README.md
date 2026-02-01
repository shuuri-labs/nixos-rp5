# Overlays (Utility Scripts)

Nix overlay providing RP5 utility commands.

## File

| File | Description |
|------|-------------|
| `default.nix` | Package overlay with utility scripts |

---

## default.nix - RP5 Utilities

### Purpose
Provides command-line utilities for controlling RP5 system functions.

### How Nix Overlays Work

This file is a Nix "overlay" - it extends nixpkgs with additional packages:

```nix
final: prev: {
  # final = modified nixpkgs (with our additions)
  # prev = original nixpkgs

  rp5-session-switch = final.writeShellScriptBin "rp5-session-switch" ''
    # Script content
  '';
}
```

The overlay is applied in `flake.nix` and the packages become available system-wide.

---

## Utilities Reference

### rp5-session-switch

Switch between session modes without logging out.

```bash
rp5-session-switch steam   # Gamescope + Steam
rp5-session-switch plasma  # KDE Plasma desktop
```

**How it works:**
1. Stops current session's systemd user service
2. Starts requested session's service

**Notes:**
- Requires appropriate services defined in sessions.nix
- Some state may not transfer between sessions

---

### rp5-fps

Control Gamescope FPS limiter (in Steam session).

```bash
rp5-fps 30    # Limit to 30 FPS (battery saver)
rp5-fps 40    # Limit to 40 FPS (balanced)
rp5-fps 60    # Limit to 60 FPS (performance)
```

**How it works:**
- Writes to Gamescope control FIFO at `/run/user/$UID/gamescope-control`
- Gamescope reads and applies new FPS limit

**Notes:**
- Only works when Gamescope is running
- Current Gamescope may require session restart for FPS changes

---

### rp5-brightness

Control screen brightness.

```bash
rp5-brightness get        # Show current brightness %
rp5-brightness set 75     # Set to 75%
rp5-brightness up         # Increase by 5%
rp5-brightness down       # Decrease by 5%
```

**How it works:**
- Reads/writes to sysfs backlight interface
- Automatically finds backlight device in `/sys/class/backlight/`
- Steps are 5% of max brightness

---

### rp5-volume

Control audio volume (via WirePlumber/PipeWire).

```bash
rp5-volume get            # Show current volume
rp5-volume set 50         # Set to 50%
rp5-volume up             # Increase by 5%
rp5-volume down           # Decrease by 5%
rp5-volume mute           # Mute audio
rp5-volume unmute         # Unmute audio
rp5-volume toggle         # Toggle mute
```

**How it works:**
- Uses `wpctl` (WirePlumber) to control default audio sink
- Works with PipeWire audio stack

---

### rp5-wifi

WiFi control via NetworkManager.

```bash
rp5-wifi on               # Enable WiFi radio
rp5-wifi off              # Disable WiFi radio
rp5-wifi status           # Show radio status and active connection
rp5-wifi scan             # Scan for networks
rp5-wifi connect SSID     # Connect to open network
rp5-wifi connect SSID pw  # Connect with password
```

**How it works:**
- Uses `nmcli` (NetworkManager CLI)
- Manages WiFi radio and connections

---

### rp5-bluetooth

Bluetooth control via BlueZ.

```bash
rp5-bluetooth on          # Power on Bluetooth
rp5-bluetooth off         # Power off Bluetooth
rp5-bluetooth status      # Show power state and connected devices
rp5-bluetooth scan        # Scan for devices (10 seconds)
rp5-bluetooth pair XX:XX  # Pair and connect to device
```

**How it works:**
- Uses `bluetoothctl` (BlueZ CLI)
- Uses `rfkill` to unblock Bluetooth hardware

---

## Adding New Utilities

To add a new utility:

1. Add to `overlays/default.nix`:
```nix
rp5-my-utility = final.writeShellScriptBin "rp5-my-utility" ''
  #!/bin/bash
  # Your script here
  case "$1" in
    action1)
      # Do something
      ;;
    *)
      echo "Usage: rp5-my-utility {action1|action2}"
      exit 1
      ;;
  esac
'';
```

2. Add to system packages (if not automatically included):
```nix
environment.systemPackages = with pkgs; [
  rp5-my-utility
];
```

3. Document in this README.
