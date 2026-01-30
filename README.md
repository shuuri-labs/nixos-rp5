# NixOS for Retroid Pocket 5

Run NixOS on your Retroid Pocket 5 with three session modes: Steam gaming, retro gaming (ES-DE), and full desktop (KDE Plasma).

## Features

- **Gamescope Steam Mode** - Steam Big Picture via FEX-Emu in Gamescope compositor
- **Gamescope ES-DE Mode** - EmulationStation Desktop Edition for retro gaming
- **Plasma Desktop Mode** - Full KDE Plasma Wayland desktop
- **System Overlay** - Quick settings via HOME button long-press
- **Persistent NixOS** - Full NixOS with generations, rollback, etc.

## Prerequisites

- Retroid Pocket 5 with ROCKNIX installed and working
- SD card with at least 64GB (32GB+ for NixOS partition)
- Another Linux machine for initial setup
- Basic familiarity with NixOS and flakes

## Quick Start

### 1. Prepare the SD Card

On your Linux machine with the RP5's SD card:

```bash
# Create NixOS partition (after existing ROCKNIX partitions)
# Using fdisk, parted, or gparted, create a ~32GB+ partition

# Format with label
sudo mkfs.ext4 -L NIXOSROOT /dev/sdX3  # Replace X3 with your partition
```

### 2. Install Boot Hook

```bash
# Mount ROCKNIX boot partition
sudo mount /dev/sdX1 /mnt/rocknix

# Install the boot hook
sudo cp boot/mount-storage.sh /mnt/rocknix/
sudo chmod 755 /mnt/rocknix/mount-storage.sh

sudo umount /mnt/rocknix
```

### 3. Build NixOS Configuration

```bash
# Build the system
nix build .#nixosConfigurations.rp5.config.system.build.toplevel

# Or if you have nixos-install
sudo mount /dev/disk/by-label/NIXOSROOT /mnt
sudo nixos-install --root /mnt --flake .#rp5
```

### 4. Boot into NixOS

Insert the SD card into your RP5, then:
- **Hold SELECT button during boot** to start NixOS
- Or create `/storage/.boot-nixos` file on ROCKNIX storage partition

## Session Modes

### Steam Mode (Gamescope)
- Launches Steam in Big Picture mode via FEX-Emu
- Optimized for gamepad input
- FPS limiting via `rp5-fps` command

### ES-DE Mode (Gamescope)
- EmulationStation Desktop Edition
- Full controller support
- Access to various emulators

### Plasma Mode
- Full KDE Plasma desktop
- Touch and mouse support
- Access to all desktop applications

## System Overlay

Hold the **HOME button for 800ms** to open the quick settings overlay:

- **Brightness** - Adjust screen brightness
- **Volume** - Adjust audio volume
- **WiFi** - Toggle wireless on/off
- **Bluetooth** - Toggle Bluetooth on/off
- **Session Switch** - Change between Steam/ES-DE/Plasma
- **FPS Limit** - Change framerate cap (in Steam mode)

## Utility Commands

```bash
# Session switching
rp5-session-switch steam   # Switch to Steam mode
rp5-session-switch esde    # Switch to ES-DE mode
rp5-session-switch plasma  # Switch to Plasma mode

# FPS control (in gamescope sessions)
rp5-fps 30   # Limit to 30 FPS
rp5-fps 60   # Limit to 60 FPS

# System controls
rp5-brightness get        # Show current brightness
rp5-brightness set 75     # Set to 75%
rp5-volume set 50         # Set volume to 50%
rp5-wifi on|off           # Toggle WiFi
rp5-bluetooth on|off      # Toggle Bluetooth
```

## Steam Setup

After booting into NixOS:

```bash
# Install Steam
install-steam

# Launch Steam
steam

# Or launch in Big Picture mode
steam-gamepadui
```

First launch will take time as Steam downloads updates.

## Configuration

### Default User
- Username: `gamer`
- Password: `gamer` (change on first login!)
- Has sudo without password

### Customization

Edit `hosts/rp5/default.nix` for system-wide changes:
- Timezone: `time.timeZone`
- Locale: `i18n.defaultLocale`
- Additional packages: `environment.systemPackages`

For auto-login to Steam, edit `hosts/rp5/sessions.nix` and uncomment the `initial_session` block.

## Troubleshooting

### Boot Issues

**NixOS won't start:**
- Ensure SELECT button is held during boot
- Check boot counter: After 3 failed boots, system falls back to ROCKNIX
- Clear failsafe: Delete `/storage/.nixos-boot-attempts` from ROCKNIX

**Kernel panic or no display:**
- Boot into ROCKNIX and verify partition labels
- Check mount-storage.sh is correct
- Verify NixOS was properly installed

### Graphics Issues

**Black screen or artifacts:**
```bash
# Check Vulkan driver
vulkaninfo | grep -i freedreno

# Check DRM devices
ls -la /dev/dri/

# Enable debug output
export TU_DEBUG=startup
```

### Steam/FEX Issues

**Steam won't run:**
```bash
# Check x86_64 binfmt
cat /proc/sys/fs/binfmt_misc/FEX-x86_64

# Verify Box64 is working
box64 --version

# Set up FEX rootfs
fex-rootfs-setup
```

### Audio Issues

```bash
# Check PipeWire
wpctl status

# Set default output
wpctl set-default <device-id>
```

## Architecture

```
ROCKNIX (boot partition)
├── GRUB
├── KERNEL (ROCKNIX kernel)
└── mount-storage.sh  ← Our boot hook

ROCKNIX (storage partition)
├── .boot-nixos       ← Optional: auto-boot NixOS
└── .nixos-boot-attempts  ← Failsafe counter

NIXOSROOT (NixOS partition)
├── nix/              ← Nix store
├── etc/
├── home/gamer/
├── lib/
│   ├── modules/      ← Bind-mounted from ROCKNIX
│   └── firmware/     ← Bind-mounted from ROCKNIX
└── rocknix/
    ├── flash/        ← ROCKNIX boot partition
    ├── sysroot/      ← ROCKNIX rootfs
    └── storage/      ← ROCKNIX storage
```

## Credits

- Based on [arch-through-rocknix](https://github.com/Mash0Star/arch-through-rocknix) by Mash0Star
- ROCKNIX team for the excellent handheld distribution
- FEX-Emu and Box64 teams for x86 emulation
- Valve for Gamescope

## License

MIT License - See LICENSE file
