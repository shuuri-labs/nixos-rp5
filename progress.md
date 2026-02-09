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
- [x] FEX-Emu binfmt registration for x86_64/i386 (openBinary=false for NixOS compat)
- [x] RootFS setup helper (`fex-rootfs-setup`)
- [x] Steam wrapper scripts (`install-steam`, `steam-setup`, `steam`, `steam-minimal`, `steam-gamepadui`)
- [x] FEXBash-based Steam launcher with NixOS environment sanitization
- [ ] **BLOCKED**: FEX rootfs overlay not providing x86_64 libraries (see Known Issues)

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
- [x] ~~Test Steam installation on actual hardware~~ — install-steam works
- [x] ~~Verify FEX-Emu binfmt registration works correctly~~ — binfmt registered, x86_64 ELFs run through FEXInterpreter
- [ ] **Test FEX rootfs overlay fix** — rewrote steam wrapper to bypass FEXBash (see Known Issues)
- [ ] Get Steam UI rendering — steamwebhelper needs x86_64 mesa/llvmpipe from rootfs (blocked on rootfs fix)
- [ ] Test Gamescope session launch and FPS limiting
- [x] ~~Verify KDE Plasma session starts properly~~ — Plasma 5.27.11 on Wayland confirmed working
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
- [x] `install-steam` downloads and extracts Steam
- [x] `steam-setup` removes conflicting runtime libraries
- [x] Steam client process starts via FEXBash
- [x] Steam connects to Valve servers, downloads manifests
- [ ] Steam UI renders (blocked on rootfs/mesa)
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

### FEX-Emu Rootfs Overlay Not Working on NixOS

**Status:** Fix implemented — needs on-device testing

**Summary:**
FEX-Emu can run x86_64 binaries (instruction translation works), but its rootfs filesystem overlay was not activating. The root cause was identified: FEXBash runs `FEX /bin/bash`, but on NixOS `/bin/bash` is an aarch64 binary (tmpfiles symlink). FEX finds the host's native bash instead of the rootfs's x86_64 bash, so emulation never starts. Additionally, Config.json used a rootfs name (`"Ubuntu_24_04"`) instead of an absolute path, causing name resolution failures due to NixOS's non-standard directory layout.

**Root cause analysis:** See `docs/fex-rootfs-fix.md` for full details.

**Diagnostic evidence:**
- `FEXBash -c "uname -m"` returns `aarch64` — proves FEX is NOT emulating (it intercepts uname to return x86_64)
- `FEXBash -c "cat /etc/os-release"` shows NixOS — rootfs overlay not active
- Config at `~/.config/fex-emu/Config.json`, rootfs at `~/.fex-emu/RootFS/` — directory mismatch
- Steam client starts via binfmt (individual x86_64 binaries get translated) but with no rootfs overlay

**Fix applied (2026-02-09):**
1. Steam wrapper now invokes `FEXInterpreter <rootfs>/bin/bash` directly instead of FEXBash
2. Added `fex-config-setup` to write Config.json with absolute rootfs path to both legacy and XDG locations
3. Added `fex-find-rootfs` helper to locate rootfs from Config.json or well-known paths
4. Added `fex-check` diagnostic script for on-device debugging
5. Kept `/bin/bash` tmpfiles symlink for host script compatibility (no longer affects FEX)

**Testing procedure (on device):**
1. Deploy updated NixOS config
2. Run `fex-config-setup` to fix Config.json paths
3. Run `fex-check` to verify emulation works (`uname -m` should show `x86_64`)
4. Run `steam` — should now launch with rootfs overlay active

**Fallback if fix doesn't work:**
- bubblewrap namespace approach — mount rootfs as real filesystem root, bypassing FEX's syscall-level overlay
- muvm micro-VM approach — see https://github.com/nrabulinski/nixos-muvm-fex

---

## Changelog

### 2026-02-09
- Root-caused FEX rootfs overlay failure: FEXBash finds host aarch64 `/bin/bash` instead of rootfs x86_64 bash
- Rewrote Steam wrapper to bypass FEXBash — invokes `FEXInterpreter <rootfs>/bin/bash` directly
- Added `fex-config-setup`: writes Config.json with absolute rootfs path (bypasses name resolution)
- Added `fex-find-rootfs`: locates rootfs from Config.json or well-known directories
- Added `fex-check`: comprehensive on-device diagnostic script
- Documented full analysis in `docs/fex-rootfs-fix.md`

### 2026-02-07
- Rewrote FEX-Emu module: uses `pkgs.unstable.fex`, proper binfmt with `openBinary=false`
- Rewrote Steam module: FEXBash-based launcher, install-steam, steam-setup, steam-minimal
- Fixed binfmt: NixOS wrapper breaks O flag, `openBinary=false` is required
- Fixed /bin/bash: NixOS doesn't have it, added tmpfiles symlink for Steam scripts
- Added NixOS env sanitization: unset GIO_EXTRA_MODULES, VK_LAYER_PATH, etc. before FEXBash
- Added LIBGL_ALWAYS_SOFTWARE=1 and -cef-disable-gpu flags for steamwebhelper
- Steam client starts and connects to Valve servers but UI doesn't render (rootfs overlay blocked)
- Identified root cause: FEX rootfs overlay not functioning on NixOS (see Known Issues)

### 2026-02-01
- Scaled back project to focus on core functionality
- Archived ES-DE implementation to `archive/esde/`
- Updated sessions to Steam and Plasma only
- Added comprehensive documentation (module READMEs)
- Created progress tracking document
