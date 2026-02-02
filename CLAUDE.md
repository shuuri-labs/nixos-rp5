# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NixOS configuration for chain-booting NixOS on the Retroid Pocket 5 (Snapdragon 865/SM8250) via ROCKNIX. The system provides two session modes:

1. **Gamescope Steam** - Steam Big Picture via FEX-Emu/Box64 in Gamescope compositor
2. **Plasma Wayland** - Full KDE Plasma desktop environment

See [progress.md](progress.md) for project status and to-do items.

## Architecture

### Boot Flow
```
ROCKNIX GRUB → ROCKNIX Kernel → init → mount-storage.sh hook
                                              ↓
                              [SELECT button or .boot-nixos flag]
                                              ↓
                              Mount NIXOSROOT → bind-mount modules/firmware
                                              ↓
                              switch_root → NixOS systemd
```

### Key Components
- **boot/mount-storage.sh** - ROCKNIX boot hook that chain-boots NixOS
- **flake.nix** - NixOS flake entry point (aarch64-linux)
- **hosts/rp5/** - Host-specific configuration
- **modules/** - Reusable NixOS modules

### Module Structure
```
modules/
├── hardware/
│   ├── sm8250.nix      # Snapdragon 865 config
│   └── gamepad.nix     # Built-in controller
├── graphics/
│   ├── mesa-turnip.nix # Vulkan via Turnip
│   └── gamescope.nix   # Gamescope compositor
├── emulation/
│   ├── fex-emu.nix     # x86_64 emulation
│   └── steam.nix       # Steam integration
├── sessions/           # (in hosts/rp5/sessions.nix)
├── overlay/
│   └── overlay-daemon.nix  # System overlay (HOME long-press)
└── rocknix-compat/
    └── kernel-modules.nix  # ROCKNIX kernel/firmware handling
```

## Build Commands

```bash
# Check flake
nix flake check

# Build system
nix build .#nixosConfigurations.rp5.config.system.build.toplevel

# Enter dev shell
nix develop

# Format nix files
nixpkgs-fmt **/*.nix
```

## Installation

See **[INSTALL.md](INSTALL.md)** for complete instructions. Summary:

1. **Partition SD card**: 2GB ROCKNIX boot (p1), largest STORAGE (p2), 64GB NIXOSROOT (p3)
2. **Install boot hook**: Copy `boot/mount-storage.sh` to ROCKNIX boot partition
3. **Build and deploy**: `nixos-install --root /mnt/nixos --flake .#rp5`
4. **Boot**: Hold SELECT during boot, or create `/storage/.boot-nixos`

## Key Files

| File | Purpose |
|------|---------|
| `INSTALL.md` | Complete installation guide |
| `progress.md` | Project status and to-do list |
| `boot/mount-storage.sh` | ROCKNIX chain-boot hook |
| `flake.nix` | Flake entry point |
| `hosts/rp5/default.nix` | Main host config |
| `hosts/rp5/sessions.nix` | greetd + session definitions |
| `modules/emulation/fex-emu.nix` | FEX-Emu/Box64 for x86_64 |
| `modules/overlay/overlay-daemon.nix` | System overlay daemon |
| `overlays/default.nix` | RP5 utility scripts |

## Session Management

Sessions are managed via greetd. Session selection at login or runtime switching:

```bash
# Switch sessions (from overlay or terminal)
rp5-session-switch steam   # Gamescope + Steam
rp5-session-switch plasma  # KDE Plasma

# Control FPS in gamescope
rp5-fps 30|40|60
```

## Overlay Controls

Hold HOME button for 800ms to open system overlay:
- Brightness control
- Volume control
- WiFi toggle
- Bluetooth toggle
- Session switching
- FPS limit (in Steam mode)

## Hardware Notes

### Snapdragon 865 (SM8250)
- GPU: Adreno 650 (Turnip Vulkan driver)
- CPU: Kryo 585 (1+3+4 core configuration)
- Kernel: ROCKNIX kernel via bind-mount
- Firmware: ROCKNIX firmware via bind-mount

### Graphics
- Vulkan via Mesa Turnip driver
- OpenGL ES 3.2 via Freedreno
- 32-bit libs enabled for Wine/Proton

## Troubleshooting

### Boot Issues
- Check boot counter: `cat /rocknix/storage/.nixos-boot-attempts`
- Clear failsafe: `rm /rocknix/storage/.nixos-boot-attempts`
- Boot to ROCKNIX: Don't hold SELECT, or wait for 3 failed boots

### Graphics Issues
- Check Vulkan: `vulkaninfo | grep -i freedreno`
- Check DRM: `ls /dev/dri/`
- Enable debug: `TU_DEBUG=startup`

### Steam/FEX Issues
- Check binfmt: `cat /proc/sys/fs/binfmt_misc/FEX-x86_64`
- Run setup: `fex-rootfs-setup`
- Check Box64: `box64 --version`

## Important Constraints

- **No kernel builds** - We use ROCKNIX kernel via bind-mount
- **No initrd** - Boot via switch_root from ROCKNIX init
- **No bootloader management** - ROCKNIX GRUB handles booting
- **ARM64 only** - Cross-compilation not supported in this config
