# Overlay Module

System overlay daemon providing quick settings via HOME button long-press.

## File

| File | Description |
|------|-------------|
| `overlay-daemon.nix` | Input monitor and overlay UI |

---

## overlay-daemon.nix - System Overlay

### Purpose
Provides a quick-access system overlay triggered by holding the HOME button.

### What It Does
- Monitors gamepad input for HOME button press
- Triggers overlay after configurable hold time (default: 800ms)
- Displays quick settings menu (whiptail-based TUI)
- Allows control of brightness, volume, WiFi, Bluetooth
- Enables session switching without logging out

### How It Works

```
User holds HOME button
         ↓
rp5-input-monitor (evtest) detects key press
         ↓
Wait for 800ms hold threshold
         ↓
Toggle overlay state, signal rp5-overlay-ui
         ↓
Overlay shows quick settings menu
         ↓
User makes selection → execute action
```

### Components

**rp5-input-monitor:**
- Systemd user service started with graphical session
- Uses evtest to monitor input events
- Detects HOME button (KEY_HOMEPAGE or BTN_MODE)
- Measures hold duration
- Controls overlay visibility

**rp5-overlay-ui:**
- Whiptail-based menu interface
- Reads/writes system settings
- Calls utility scripts for actions

### Menu Options

| Option | Action |
|--------|--------|
| Brightness | Adjust screen brightness (0-100%) |
| Volume | Adjust audio volume (0-100%) |
| WiFi | Toggle wireless on/off |
| Bluetooth | Toggle Bluetooth on/off |
| Switch to Steam | Start Gamescope Steam session |
| Switch to Plasma | Start KDE Plasma session |
| Exit | Close overlay |

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rp5.overlay.enable` | bool | true | Enable overlay daemon |
| `rp5.overlay.holdMs` | int | 800 | HOME button hold time (ms) |

### Configuration

```nix
# Adjust hold time (make it longer)
rp5.overlay.holdMs = 1000;  # 1 second

# Disable overlay
rp5.overlay.enable = false;
```

### State Files

| Path | Purpose |
|------|---------|
| `/run/user/$UID/rp5-overlay/active` | Overlay visibility flag |
| `/run/user/$UID/rp5-overlay/overlay.sock` | Control FIFO |
| `/run/user/$UID/rp5-overlay/press_time` | Button press timestamp |

### Troubleshooting

**Overlay doesn't appear:**
```bash
# Check service status
systemctl --user status rp5-input-monitor

# Check for input device
evtest  # Select device and watch for KEY_HOMEPAGE

# Manual trigger
rp5-overlay-ui
```

**Wrong button detected:**
```bash
# Find the HOME button code
evtest /dev/input/event0
# Press HOME and note the key code
# Update BTN_SELECT in overlay-daemon.nix if needed
```

**Menu looks broken:**
```bash
# Check whiptail is installed
which whiptail

# Test whiptail directly
whiptail --msgbox "Test" 8 40
```

### Extending the Overlay

To add new menu options:

1. Add menu entry in the whiptail command:
```bash
"N" "New Option" \
```

2. Add case handler:
```bash
N)
  # Your action here
  show_menu
  ;;
```

3. Optionally add to fallback echo menu for non-whiptail systems.
