# Boot Hook

Chain-boot script that allows NixOS to boot from ROCKNIX.

## File

| File | Description |
|------|-------------|
| `mount-storage.sh` | ROCKNIX init hook for chain-booting NixOS |

---

## mount-storage.sh - NixOS Chain-Boot Hook

### Purpose
Hooks into ROCKNIX's init process to optionally chain-boot into NixOS.

### Installation

1. Copy to ROCKNIX boot partition:
```bash
# Mount ROCKNIX boot partition
sudo mount /dev/sdX1 /mnt/rocknix

# Install hook
sudo cp boot/mount-storage.sh /mnt/rocknix/
sudo chmod 755 /mnt/rocknix/mount-storage.sh

sudo umount /mnt/rocknix
```

2. ROCKNIX init will call this script during storage mounting phase.

### Boot Triggers

NixOS boot is triggered by any of:

| Trigger | How to Use |
|---------|------------|
| SELECT button | Hold SELECT during boot |
| Boot flag file | Create `/storage/.boot-nixos` on ROCKNIX storage |
| Kernel cmdline | Add `nixos` to GRUB cmdline |

### Boot Flow

```
ROCKNIX GRUB
     ↓
ROCKNIX Kernel
     ↓
ROCKNIX init
     ↓
mount-storage.sh (this hook)
     ↓
Check boot triggers ──→ No trigger ──→ Continue ROCKNIX boot
     ↓ (trigger found)
Check boot failsafe
     ↓
Mount NIXOSROOT partition
     ↓
Verify it's a NixOS root (/nix exists)
     ↓
Preserve ROCKNIX resources:
  - Move /flash to /nixroot/rocknix/flash
  - Move /sysroot to /nixroot/rocknix/sysroot
     ↓
Bind-mount kernel modules:
  ROCKNIX/lib/modules/$KVER → NixOS/lib/modules/$KVER
     ↓
Bind-mount firmware:
  ROCKNIX/lib/firmware → NixOS/lib/firmware
     ↓
Mount STORAGE partition (if exists)
     ↓
Move virtual filesystems (/dev, /proc, /sys, /run)
     ↓
Find NixOS init (systemd)
     ↓
switch_root to NixOS
     ↓
NixOS systemd takes over
```

### Boot Failsafe

Protects against boot loops:

1. Each NixOS boot attempt increments counter in `/storage/.nixos-boot-attempts`
2. After 3 failed boots, falls back to ROCKNIX
3. Counter is stored on ROCKNIX storage partition
4. Clear counter to retry: `rm /storage/.nixos-boot-attempts`

### Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BTN_SELECT` | 314 | SELECT button keycode |
| `NIXOS_PARTITION` | LABEL=NIXOSROOT | NixOS partition identifier |
| `MAX_BOOT_ATTEMPTS` | 3 | Failsafe threshold |
| `DEBUG_MODE` | 0 | Enable verbose logging |

### Key Functions

**is_key_pressed($keycode):**
Checks if a key is currently held using evtest.

**should_boot_nixos():**
Checks all boot triggers (button, flag file, cmdline).

**check_boot_counter():**
Implements boot failsafe counter.

**find_nixos_init($nixroot):**
Locates NixOS systemd init in the mounted root.

**boot_nixos():**
Main boot sequence - mounts, bind-mounts, and switch_root.

### Troubleshooting

**NixOS not booting:**
```bash
# Boot to ROCKNIX and check:

# 1. Is the partition accessible?
ls /dev/disk/by-label/NIXOSROOT

# 2. Check boot counter
cat /storage/.nixos-boot-attempts

# 3. Try manual boot
mount /dev/disk/by-label/NIXOSROOT /mnt
ls /mnt/nix  # Should exist
```

**Stuck at boot:**
```bash
# Enable debug mode (edit mount-storage.sh)
DEBUG_MODE=1

# Watch serial console or connect via ADB
```

**Boot loops:**
```bash
# Clear failsafe counter from ROCKNIX
rm /storage/.nixos-boot-attempts

# Or remove boot flag
rm /storage/.boot-nixos
```

### Debug Shell

If boot fails, the script drops to an emergency shell:
```
[nixos-boot:ERROR] NixOS boot failed!
[nixos-boot:ERROR] Dropping to emergency shell...
```

From this shell you can:
```bash
# Check mounts
mount

# Check NixOS partition
ls /nixroot

# Check logs
dmesg | tail -50

# Reboot
reboot
```
