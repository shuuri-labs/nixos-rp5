# Hardware Modules

Configuration for Retroid Pocket 5 hardware components.

## Files

| File | Description |
|------|-------------|
| `sm8250.nix` | Snapdragon 865 SoC configuration |
| `gamepad.nix` | Built-in gamepad and controller support |

---

## sm8250.nix - Snapdragon 865 Configuration

### Purpose
Configures the Qualcomm Snapdragon 865 (SM8250) system-on-chip for optimal operation.

### What It Does
- Sets CPU frequency governor to `schedutil` (best for heterogeneous ARM cores)
- Configures kernel parameters for Qualcomm hardware
- Sets up udev rules for GPU and DSP access
- Disables thermald (hardware handles thermal management)

### Key Configuration

**CPU Cores:**
- 1x Cortex-A77 @ 2.84 GHz (prime core)
- 3x Cortex-A77 @ 2.42 GHz (performance cores)
- 4x Cortex-A55 @ 1.8 GHz (efficiency cores)

**Kernel Parameters:**
```
clk_ignore_unused    # Keep clocks enabled for peripherals
pd_ignore_unused     # Keep power domains enabled
cma=256M             # Contiguous memory for GPU/media
console=tty0         # Console output
```

**udev Rules:**
- GPU devices (`/dev/dri/*`) accessible to video group
- Qualcomm DSP (fastrpc) accessible
- Battery and sensor access

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rp5.hardware.sm8250.enable` | bool | true | Enable SM8250 configuration |

### Troubleshooting

**GPU not accessible:**
```bash
# Check DRM devices
ls -la /dev/dri/

# Verify permissions
groups  # Should include 'video'
```

**Thermal throttling:**
```bash
# Check temperature
cat /sys/class/thermal/thermal_zone*/temp
```

---

## gamepad.nix - Controller Support

### Purpose
Configures the built-in gamepad and provides support for external controllers.

### What It Does
- Sets udev rules for gamepad device access
- Installs input testing tools (evtest, jstest-gtk)
- Configures SDL gamepad support
- Enables Steam hardware rules for external controllers

### Key Configuration

**udev Rules:**
- Built-in RP5 gamepad detected by name pattern
- Generic joystick devices (`ID_INPUT_JOYSTICK=1`)
- Force feedback support
- USB gamepad support
- Steam Controller support

**Packages Installed:**
- `evtest` - Command-line input tester
- `jstest-gtk` - GUI joystick tester
- `linuxConsoleTools` - jstest, jscal utilities
- `sdl2` - SDL library with gamepad support

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rp5.hardware.gamepad.enable` | bool | true | Enable gamepad configuration |

### Testing Gamepad

```bash
# List input devices
evtest

# Test specific device
evtest /dev/input/event0

# GUI test (in Plasma session)
jstest-gtk
```

### Troubleshooting

**Gamepad not detected:**
```bash
# List input devices
ls /dev/input/event*

# Check device info
cat /sys/class/input/event*/device/name
```

**Button mapping wrong:**
```bash
# Check SDL mapping
cat $SDL_GAMECONTROLLERCONFIG

# Remap with sdl2-gamecontroller-db
```
