# Graphics Modules

Configuration for GPU and display compositor support.

## Files

| File | Description |
|------|-------------|
| `mesa-turnip.nix` | Mesa graphics stack with Turnip Vulkan driver |
| `gamescope.nix` | Gamescope compositor for gaming sessions |

---

## mesa-turnip.nix - Vulkan/OpenGL Support

### Purpose
Configures the Mesa graphics stack with the Turnip Vulkan driver for the Adreno 650 GPU.

### What It Does
- Enables hardware graphics with Mesa
- Configures Vulkan via Turnip driver
- Enables 32-bit graphics libraries (for Wine/Proton)
- Sets up DRM device permissions
- Installs Vulkan and OpenGL debugging tools

### How Turnip Works
Turnip is the open-source Vulkan driver for Qualcomm Adreno GPUs, part of Mesa. It provides:
- Full Vulkan 1.3 support
- Better performance than proprietary blob
- Works with Gamescope and DXVK/Proton

### Key Configuration

**Environment Variables:**
```bash
VK_ICD_FILENAMES      # Points to Turnip ICD
MESA_VK_WSI_PRESENT_MODE=fifo  # VSync mode
MESA_GLES_VERSION_OVERRIDE=3.2 # Force GLES 3.2
```

**Packages Installed:**
- `vulkan-tools` - vulkaninfo, vkcube
- `vulkan-validation-layers` - Debug layers
- `glxinfo` - OpenGL information
- `mesa-demos` - glxgears, es2gears
- `apitrace` - API call tracing

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rp5.graphics.enable` | bool | true | Enable graphics configuration |
| `rp5.graphics.enableVulkan` | bool | true | Enable Vulkan support |
| `rp5.graphics.enable32Bit` | bool | true | Enable 32-bit libraries |

### Testing Graphics

```bash
# Vulkan info
vulkaninfo | grep -i freedreno

# Vulkan test
vkcube

# OpenGL ES test
es2gears_wayland

# Check driver in use
MESA_DEBUG=1 vulkaninfo 2>&1 | head -20
```

### Troubleshooting

**Vulkan not working:**
```bash
# Check ICD file exists
ls /run/opengl-driver/share/vulkan/icd.d/

# Debug Turnip startup
TU_DEBUG=startup vkcube
```

**OpenGL issues:**
```bash
# Check GLES version
glxinfo -B | grep -i version
```

---

## gamescope.nix - Gaming Compositor

### Purpose
Configures Gamescope, the SteamOS session compositor for gaming.

### What It Does
- Installs Gamescope and MangoHud
- Sets up security capabilities for realtime scheduling
- Configures kernel parameters for gaming
- Creates `gamescope-rp5` wrapper script with FPS control
- Sets up PAM limits for the `games` group

### How Gamescope Works
Gamescope is a Wayland compositor that:
1. Runs games in a nested Wayland/XWayland session
2. Provides frame timing and FPS limiting
3. Handles display scaling and filtering
4. Supports HDR (on compatible displays)
5. Works with Steam's overlay system

### Key Configuration

**Default Settings:**
```bash
GAMESCOPE_FPS_LIMIT=60  # Default FPS limit
```

**Kernel Parameters:**
```bash
vm.max_map_count=2147483642  # For large games
vm.swappiness=10             # Less swap during gaming
```

**PAM Limits (games group):**
- Nice priority: -20
- Realtime priority: 99
- Memory lock: unlimited

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rp5.gamescope.enable` | bool | true | Enable Gamescope |
| `rp5.gamescope.defaultFpsLimit` | int | 60 | Default FPS limit |
| `rp5.gamescope.adaptiveSync` | bool | true | Enable VRR |

### Using Gamescope

```bash
# Launch app in Gamescope
gamescope -f --framerate-limit 60 -- your-app

# Use RP5 wrapper
gamescope-rp5 -- your-app

# Change FPS limit (in Steam session)
rp5-fps 30
rp5-fps 60
```

### Troubleshooting

**Gamescope won't start:**
```bash
# Check capabilities
getcap /run/wrappers/bin/gamescope

# Try without capabilities
/nix/store/.../bin/gamescope -f -- your-app
```

**FPS limiting not working:**
```bash
# MangoHud overlay to verify FPS
MANGOHUD=1 gamescope -f -- your-app
```
