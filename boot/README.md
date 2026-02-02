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

NixOS lives on a dedicated NIXOSROOT partition (typically `/dev/mmcblk0p3`) alongside ROCKNIX and STORAGE partitions.

### Installation

1. Copy to ROCKNIX boot partition:
```bash
# From ROCKNIX SSH session
mkdir -p /tmp/boot
mount /dev/mmcblk0p1 /tmp/boot

# Download or copy the script
curl -o /tmp/boot/mount-storage.sh https://raw.githubusercontent.com/yourusername/nixos-rp5/main/boot/mount-storage.sh
chmod 755 /tmp/boot/mount-storage.sh

umount /tmp/boot
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
Find and mount NIXOSROOT partition
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
Move STORAGE into NixOS (/nixroot/rocknix/storage)
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

### How It Works

1. **Trigger Detection**: Checks if SELECT button is pressed during boot
2. **Find NIXOSROOT**: Looks for NIXOSROOT partition by label or device path
3. **Mount**: Directly mounts the NIXOSROOT partition (no loop device needed)
4. **Verify**: Checks that `/nix` directory exists
5. **Bind-mount Resources**: Makes ROCKNIX kernel modules and firmware available
6. **Switch Root**: Transfers control to NixOS systemd

### Troubleshooting

**NixOS not booting:**
```bash
# Boot to ROCKNIX and check:

# 1. Is the NIXOSROOT partition present?
lsblk | grep NIXOSROOT
blkid | grep NIXOSROOT

# 2. Check boot counter
cat /storage/.nixos-boot-attempts

# 3. Try manual mount
mkdir -p /tmp/nixos
mount /dev/mmcblk0p3 /tmp/nixos  # p3 is NIXOSROOT, p2 is STORAGE
ls /tmp/nixos/nix  # Should exist
```

**Stuck at boot:**
```bash
# Enable debug mode (edit mount-storage.sh on boot partition)
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

# Check NixOS root
ls /nixroot

# Check logs
dmesg | tail -50

# Reboot
reboot
```
