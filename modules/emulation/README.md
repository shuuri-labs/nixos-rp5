# Emulation Modules

Configuration for x86_64 emulation and Steam support on ARM64.

## Files

| File | Description |
|------|-------------|
| `fex-emu.nix` | FEX-Emu/Box64 for running x86_64 binaries |
| `steam.nix` | Steam client integration via emulation layer |

---

## fex-emu.nix - x86_64 Emulation

### Purpose
Enables running x86_64 Linux binaries on ARM64 using FEX-Emu and Box64.

### What It Does
- Registers binfmt handlers for x86_64 and i386 ELF binaries
- Provides `fex-rootfs-setup` script for downloading x86_64 rootfs
- Configures FEX-Emu environment and config file
- Creates systemd service for first-boot setup

### How It Works

```
x86_64 ELF binary → Linux kernel (binfmt_misc)
                         ↓
                    Box64/FEX-Emu
                         ↓
               Dynamic translation to ARM64
                         ↓
                   Native execution
```

**Box64** is the default interpreter because it's readily available in nixpkgs. FEX-Emu can be used as an alternative with better performance for some workloads.

### Key Configuration

**binfmt Registration:**
```nix
FEX-x86_64 = {
  magicOrExtension = "\x7fELF...";  # x86_64 ELF magic
  interpreter = "${pkgs.box64}/bin/box64";
};
```

**Environment Variables:**
```bash
FEX_ROOTFS=/var/lib/fex-emu/rootfs
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rp5.fex-emu.enable` | bool | false | Enable x86_64 emulation |
| `rp5.fex-emu.rootfsPath` | path | /var/lib/fex-emu/rootfs | RootFS location |
| `rp5.fex-emu.enableBinfmt` | bool | true | Register binfmt handlers |

### Setup

```bash
# Download and setup x86_64 rootfs
fex-rootfs-setup

# Verify binfmt registration
cat /proc/sys/fs/binfmt_misc/FEX-x86_64

# Test with x86_64 binary
file /path/to/x86_64/binary  # Should say "x86-64"
./path/to/x86_64/binary      # Should run via Box64
```

### Troubleshooting

**Binary won't run:**
```bash
# Check binfmt is registered
ls /proc/sys/fs/binfmt_misc/

# Run with debug output
BOX64_LOG=2 ./your-binary
```

**Missing libraries:**
```bash
# Check what's needed
BOX64_LOG=1 ./your-binary 2>&1 | grep -i library
```

---

## steam.nix - Steam Integration

### Purpose
Provides Steam client installation and configuration for ARM64.

### What It Does
- Installs Steam installer script (`install-steam`)
- Creates Steam wrapper with ARM64-specific settings
- Configures Proton/Wine environment variables
- Enables gamemode for better performance
- Sets up Steam's sandbox wrapper (bwrap)

### How Steam Works on ARM64

```
Steam (x86_64) → Box64 → ARM64
     ↓
Proton/Wine (x86_64) → Box64 → ARM64
     ↓
Windows game → Wine → x86_64 → Box64 → ARM64
```

### Key Scripts

**install-steam:**
- Downloads Steam from official CDN
- Extracts to `~/.local/share/Steam`
- Sets up directory structure

**steam:**
- Wrapper script with proper environment
- Configures Box64 and Vulkan settings
- Handles shader cache directory

**steam-gamepadui:**
- Launches Steam in Big Picture mode
- Uses `-gamepadui -steamos -steamdeck` flags

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rp5.steam.enable` | bool | true | Enable Steam support |

### Installation

```bash
# Install Steam
install-steam

# Launch Steam (first run will download updates)
steam

# Launch in Big Picture mode
steam-gamepadui
```

### Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `STEAM_RUNTIME` | 1 | Use Steam's bundled libraries |
| `BOX64_DYNAREC_BIGBLOCK` | 0 | Box64 optimization |
| `VK_ICD_FILENAMES` | freedreno_icd | Vulkan driver |
| `DXVK_ASYNC` | 1 | Async shader compilation |
| `PROTON_NO_ESYNC` | 0 | Enable esync |

### Troubleshooting

**Steam won't launch:**
```bash
# Check binfmt
cat /proc/sys/fs/binfmt_misc/FEX-x86_64

# Check Box64
box64 --version

# Run with debug
BOX64_LOG=2 steam
```

**Games crash:**
```bash
# Check Proton log
cat ~/.local/share/Steam/steamapps/compatdata/*/pfx/drive_c/users/steamuser/AppData/Local/Proton*/proton.log

# Try different Proton version
# In Steam: Right-click game → Properties → Compatibility
```

**Performance issues:**
```bash
# Enable gamemode
gamemoderun steam

# Check MangoHud
MANGOHUD=1 %command%  # Add to game launch options
```
