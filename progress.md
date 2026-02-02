# NixOS RP5 Project Progress

This document tracks the implementation progress and to-do items for the NixOS Retroid Pocket 5 project.

## Current Features (Implemented)

### Core System
- [x] NixOS flake configuration for aarch64-linux
- [x] ROCKNIX chain-boot hook (`boot/mount-storage.sh`)
- [x] ROCKNIX kernel/firmware bind-mount compatibility
- [x] Boot failsafe (3 failed boots returns to ROCKNIX)
- [x] Multiple boot triggers (SELECT button, `.boot-nixos` flag, kernel cmdline)

### Hardware Support
- [x] Snapdragon 865 (SM8250) configuration
- [x] CPU frequency scaling with schedutil governor
- [x] GPU support via Mesa/Turnip (Adreno 650)
- [x] Built-in gamepad configuration and udev rules
- [x] External controller support (USB, Bluetooth)

### Graphics
- [x] Vulkan via Mesa Turnip driver
- [x] OpenGL ES 3.2 via Freedreno
- [x] 32-bit graphics libraries for Wine/Proton
- [x] Gamescope compositor with FPS limiting

### Sessions
- [x] greetd display manager with TUI greeter
- [x] Steam Gamescope session (Big Picture mode)
- [x] KDE Plasma Wayland session
- [x] Session switching via `rp5-session-switch`

### Emulation Layer
- [x] FEX-Emu/Box64 binfmt registration for x86_64
- [x] RootFS setup helper (`fex-rootfs-setup`)
- [x] Steam wrapper scripts (`install-steam`, `steam`, `steam-gamepadui`)

### System Overlay
- [x] HOME button long-press detection (800ms)
- [x] Quick settings menu (brightness, volume, WiFi, Bluetooth)
- [x] Session switching from overlay
- [x] Input monitoring daemon

### Utility Commands
- [x] `rp5-session-switch` - Switch between Steam/Plasma
- [x] `rp5-fps` - Control Gamescope FPS limit
- [x] `rp5-brightness` - Adjust screen brightness
- [x] `rp5-volume` - Control audio volume
- [x] `rp5-wifi` - WiFi toggle and connection
- [x] `rp5-bluetooth` - Bluetooth control

---

## To-Do List

### High Priority
- [ ] Test Steam installation on actual hardware
- [ ] Verify FEX-Emu/Box64 binfmt registration works correctly
- [ ] Test Gamescope session launch and FPS limiting
- [ ] Verify KDE Plasma session starts properly
- [ ] Run Netbird in desktop mode (Plasma session)

### Medium Priority
- [ ] Test overlay daemon HOME button detection on hardware
- [ ] Verify WiFi and Bluetooth control scripts work
- [ ] Test session switching (Steam <-> Plasma)
- [ ] Validate gamepad input in Gamescope sessions
- [ ] Configure audio output (speaker/headphone routing)

### Low Priority
- [ ] Add performance profiles (battery saver, balanced, performance)
- [ ] Implement OTA updates from ROCKNIX
- [ ] Add MangoHud overlay configuration options
- [ ] Create backup/restore scripts for user data
- [ ] Add network file sharing (SMB/NFS)

---

## Future Features

### Planned for Later Implementation
- [ ] **ES-DE (EmulationStation)** - Archived in `archive/esde/`, re-integrate when core is stable
- [ ] **RetroArch integration** - Standalone emulator support
- [ ] **Moonlight streaming** - Game streaming from PC
- [ ] **Chiaki** - PS Remote Play

### Ideas Under Consideration
- [ ] Custom boot splash screen
- [ ] Power management profiles
- [ ] Automatic sleep/wake handling
- [ ] SD card hot-swap support

---

## Archived Features

| Feature | Location | Reason |
|---------|----------|--------|
| ES-DE Session | `archive/esde/` | Scaled back to focus on core functionality |

---

## Testing Checklist

### Boot Tests
- [ ] SELECT button triggers NixOS boot
- [ ] `.boot-nixos` flag triggers NixOS boot
- [ ] Boot failsafe triggers after 3 failed boots
- [ ] ROCKNIX boots normally when no trigger present
- [ ] Kernel modules load correctly from bind-mount
- [ ] Firmware loads correctly from bind-mount

### Session Tests
- [ ] greetd displays session list correctly
- [ ] Steam Gamescope session launches
- [ ] KDE Plasma session launches
- [ ] Session switching works via `rp5-session-switch`
- [ ] Auto-login works (when configured)

### Steam Tests
- [ ] `install-steam` downloads and extracts Steam
- [ ] Steam launches via Box64/FEX-Emu
- [ ] Steam recognizes gamepad input
- [ ] Games launch in Gamescope
- [ ] Proton/Wine games work

### Overlay Tests
- [ ] HOME long-press opens overlay
- [ ] Brightness control works
- [ ] Volume control works
- [ ] WiFi toggle works
- [ ] Bluetooth toggle works
- [ ] Session switch from overlay works

### Hardware Tests
- [ ] GPU renders correctly (Vulkan, OpenGL ES)
- [ ] Touchscreen input works
- [ ] Built-in speakers work
- [ ] Headphone jack works
- [ ] USB devices recognized
- [ ] Bluetooth pairing works
- [ ] WiFi connects to networks

---

## Known Issues

### ROCKNIX /storage Read-Only After Partition Resize

**Status:** Investigating

**Symptoms:**
After resizing the STORAGE partition to make room for NIXOSROOT, ROCKNIX boots with `/storage` mounted read-only, causing cascading failures:

```
Failed to start storage-log.service
Dependency failed for var-log.mount
Dependency failed for systemd-update-utmp.service
Dependency failed for systemd-update-utmp-runlevel.service
Dependency failed for systemd-journal-flush.service
Failed to start swap.service
userconfig-setup[455]: mkdir: can't create directory '/storage/.config/': Read-only file system
Failed to mount tmp-cores.mount
Failed to mount tmp-database.mount
Failed to mount tmp-joypads.mount
Failed to mount tmp-overlays.mount
Failed to mount tmp-shaders.mount
userconfig-setup[523]: ln: /storage/.config/emulationstation/locale: No such file or directory
```

**What we've tried:**
- Verified partition label is "STORAGE" (correct)
- Ran `e2fsck -fy /dev/sda2` (passes clean)
- Reformatted STORAGE with `mkfs.ext4 -L STORAGE`
- Created expected directories (.config, .cache, .update)
- Reflashed ROCKNIX boot partition from fresh image

**Suspected causes:**
- ROCKNIX may detect partition table changes and mount read-only as safety measure
- ROCKNIX init scripts may have hardcoded expectations about partition layout
- UUID change after reformat may confuse ROCKNIX
- Filesystem features (journal, 64bit) may differ from ROCKNIX expectations

**Root cause (likely):**
Modern Ubuntu's `mkfs.ext4` creates filesystems with features like `metadata_csum` and `64bit` that the ROCKNIX kernel (based on LibreELEC/JELOS) may not fully support. When the kernel encounters incompatible features, it mounts read-only as a safety measure.

**Solution: Dedicated Partition**
NixOS now lives on a dedicated NIXOSROOT partition created during installation:

```bash
# From Linux VM with SD card attached:
# The vm-install.sh script partitions the SD card:
# - Partition 1: ROCKNIX boot (unchanged)
# - Partition 2: STORAGE (largest, ext4 without metadata_csum/64bit) - ROCKNIX expects this on p2
# - Partition 3: NIXOSROOT (64GB, ext4)
```

STORAGE is formatted with `-O ^metadata_csum,^64bit` flags to ensure ROCKNIX's kernel can mount it read-write without issues.

This provides better performance than image-based boot and cleanly separates ROCKNIX and NixOS. See INSTALL.md for full instructions.

---

## Changelog

### 2026-02-01
- Scaled back project to focus on core functionality
- Archived ES-DE implementation to `archive/esde/`
- Updated sessions to Steam and Plasma only
- Added comprehensive documentation (module READMEs)
- Created progress tracking document
