# ROCKNIX Compatibility Module

Handles compatibility with ROCKNIX kernel and firmware via bind-mounts.

## File

| File | Description |
|------|-------------|
| `kernel-modules.nix` | Kernel/firmware bind-mount configuration |

---

## kernel-modules.nix - ROCKNIX Compatibility Layer

### Purpose
Enables NixOS to run with ROCKNIX's kernel and firmware instead of building its own.

### Why This Is Needed

NixOS normally requires a kernel and generates an initrd for booting. Since we chain-boot from ROCKNIX:

1. **No kernel building** - We use ROCKNIX's kernel (already running)
2. **No initrd** - We use switch_root from ROCKNIX init
3. **No bootloader** - ROCKNIX GRUB handles booting
4. **Kernel modules** - Bind-mounted from ROCKNIX rootfs
5. **Firmware** - Bind-mounted from ROCKNIX rootfs

### How It Works

```
ROCKNIX boots with its kernel
         ↓
mount-storage.sh hook runs
         ↓
NixOS root mounted at /nixroot
         ↓
Kernel modules bind-mounted:
  /rocknix/sysroot/.../modules/$KVER → /nixroot/lib/modules/$KVER
         ↓
Firmware bind-mounted:
  /rocknix/sysroot/.../firmware → /nixroot/lib/firmware
         ↓
switch_root to NixOS
         ↓
NixOS systemd starts with ROCKNIX kernel/modules
```

### Key Configuration

**Boot Overrides:**
```nix
boot = {
  kernelPackages = lib.mkForce ...;  # Minimal, not actually used
  initrd.enable = lib.mkForce false;
  loader.grub.enable = lib.mkForce false;
};
```

**Module Loading:**
The following modules are loaded from the ROCKNIX bind-mount:
- `msm_drm` - Qualcomm DRM driver
- `evdev`, `uinput` - Input
- `cfg80211`, `mac80211` - WiFi
- `bluetooth`, `btusb` - Bluetooth
- `ext4`, `vfat` - Filesystems
- `snd`, `snd_pcm` - Audio

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rp5.rocknix.enable` | bool | true | Enable ROCKNIX compatibility |
| `rp5.rocknix.modulesPath` | path | /lib/modules | Modules mount point |
| `rp5.rocknix.firmwarePath` | path | /lib/firmware | Firmware mount point |
| `rp5.rocknix.storagePath` | path | /rocknix/storage | ROCKNIX storage |

### Verification Service

The `rocknix-verify` systemd service runs at boot to check:
- Kernel modules are present at `/lib/modules/$KVER`
- Firmware is present at `/lib/firmware`
- ROCKNIX sysroot is mounted at `/rocknix/sysroot`
- ROCKNIX storage is mounted at `/rocknix/storage`

### Directory Structure After Boot

```
/
├── lib/
│   ├── modules/
│   │   └── 6.x.x/           ← Bind-mount from ROCKNIX
│   └── firmware/            ← Bind-mount from ROCKNIX
├── nix/                     ← NixOS store
├── rocknix/
│   ├── flash/               ← ROCKNIX boot partition
│   ├── sysroot/             ← ROCKNIX rootfs
│   └── storage/             ← ROCKNIX storage partition
└── etc/, home/, etc.        ← NixOS root
```

### Troubleshooting

**Modules not loading:**
```bash
# Check if modules are mounted
ls /lib/modules/$(uname -r)/

# Check rocknix-verify output
journalctl -u rocknix-verify

# Manually check bind-mount
mount | grep modules
```

**Firmware missing:**
```bash
# Check firmware directory
ls /lib/firmware/

# Check bind-mount
mount | grep firmware
```

**WiFi/Bluetooth not working:**
```bash
# Check module is loaded
lsmod | grep cfg80211

# Try loading manually
modprobe cfg80211

# Check dmesg for errors
dmesg | grep -i wifi
```

### Important Constraints

1. **Cannot update kernel** - We use ROCKNIX's kernel
2. **Module versions must match** - ROCKNIX kernel version = module version
3. **Firmware must be compatible** - ROCKNIX firmware for ROCKNIX kernel
4. **No initrd** - Boot happens via switch_root
