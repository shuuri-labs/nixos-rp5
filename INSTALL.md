# Installation Guide

Complete guide for installing NixOS on the Retroid Pocket 5 alongside ROCKNIX.

## Prerequisites

- Retroid Pocket 5 with ROCKNIX installed and working
- SD card (512GB recommended, 128GB minimum)
- Computer with Linux (or Linux VM) for installation
- Basic familiarity with terminal commands

## Installation Methods

There are two ways to install NixOS:

| Method | Pros | Cons |
|--------|------|------|
| **Image-based (Recommended)** | No partition changes, ROCKNIX stays stock, easy to remove | Slightly slower I/O |
| **Partition-based** | Native partition speed | Requires partition resizing, may cause ROCKNIX issues |

---

## Method A: Image-Based Installation (Recommended)

NixOS lives in an image file on the ROCKNIX STORAGE partition. No partition modifications needed.

### Step A1: Boot ROCKNIX and Create the Image

First, ensure ROCKNIX boots and works normally. Then SSH into ROCKNIX:

```bash
# SSH into ROCKNIX (find IP in ROCKNIX network settings)
ssh root@<rocknix-ip>

# Create the NixOS image file (64GB, adjust as needed)
cd /storage
dd if=/dev/zero of=nixos.img bs=1M count=65536 status=progress

# Format the image as ext4
mkfs.ext4 -L NIXOSROOT nixos.img

# Verify
ls -lh nixos.img
```

### Step A2: Install the Boot Hook

```bash
# Still in ROCKNIX SSH session
# Mount the boot partition
mkdir -p /tmp/boot
mount /dev/disk/by-label/ROCKNIX /tmp/boot 2>/dev/null || mount /dev/mmcblk0p1 /tmp/boot

# Download or copy mount-storage.sh to the boot partition
# Option 1: If you have the file accessible via network
curl -o /tmp/boot/mount-storage.sh https://raw.githubusercontent.com/yourusername/nixos-rp5/main/boot/mount-storage.sh

# Option 2: Create it manually (copy content from boot/mount-storage.sh)

chmod 755 /tmp/boot/mount-storage.sh
umount /tmp/boot
```

### Step A3: Install NixOS into the Image

From a Linux machine with Nix installed:

```bash
# Clone the repo
git clone https://github.com/yourusername/nixos-rp5.git
cd nixos-rp5

# Mount the image from the SD card
# First, mount STORAGE partition
sudo mkdir -p /mnt/storage
sudo mount /dev/disk/by-label/STORAGE /mnt/storage

# Set up loop device for the image
sudo losetup -fP /mnt/storage/nixos.img
# Find which loop device was assigned
LOOP_DEV=$(losetup -l | grep nixos.img | awk '{print $1}')
echo "Loop device: $LOOP_DEV"

# Mount the image
sudo mkdir -p /mnt/nixos
sudo mount $LOOP_DEV /mnt/nixos

# Install NixOS
sudo nixos-install --root /mnt/nixos --flake .#rp5

# Cleanup
sudo umount /mnt/nixos
sudo losetup -d $LOOP_DEV
sudo umount /mnt/storage
```

### Step A4: Boot into NixOS

- Hold **SELECT** button during boot, OR
- Create `/storage/.boot-nixos` file in ROCKNIX

---

## Method B: Partition-Based Installation

NixOS lives on a dedicated partition. Requires resizing ROCKNIX's STORAGE partition.

**⚠️ Warning:** This method may cause ROCKNIX to mount /storage as read-only due to ext4 feature incompatibilities. Use Method A if you encounter issues.

### Step B1: Partition the SD Card

You need three partitions (this modifies ROCKNIX's default layout):

| Partition | Label | Size | Purpose |
|-----------|-------|------|---------|
| 1 | (ROCKNIX) | 2GB | ROCKNIX boot |
| 2 | STORAGE | Remainder - 64GB | ROCKNIX data, ROMs, shared storage |
| 3 | NIXOSROOT | 64GB | NixOS root filesystem |

### If ROCKNIX is Already Installed

ROCKNIX expands STORAGE to fill the card on first boot. You need to shrink it.

**⚠️ CRITICAL: Always shrink the filesystem SMALLER than your target partition size BEFORE shrinking the partition. Failure to do this causes filesystem corruption.**

**Option A: From Linux machine**

```bash
# Install tools
sudo apt update && sudo apt install -y parted e2fsprogs

# Identify your SD card (BE CAREFUL - wrong disk = data loss)
lsblk
# Usually /dev/sdX or /dev/mmcblkX

# Check current layout
sudo parted /dev/sdX print

# =================================================================
# STEP 1: Shrink filesystem FIRST (to LESS than target partition)
# =================================================================
# For a 512GB card wanting 64GB for NixOS:
#   Target STORAGE partition: ~400GB
#   Shrink filesystem to: 350GB (50GB buffer for safety)
#
# Formula: (total card size) - 2GB (boot) - 64GB (nixos) - 50GB (buffer) = filesystem size

sudo e2fsck -f /dev/sdX2
sudo resize2fs /dev/sdX2 350G

# Verify filesystem shrink succeeded
sudo e2fsck -f /dev/sdX2

# =================================================================
# STEP 2: Shrink partition (to MORE than the filesystem)
# =================================================================
sudo parted /dev/sdX
# In parted:
print
resizepart 2 400GB
print
quit

# =================================================================
# STEP 3: Create NIXOSROOT partition
# =================================================================
sudo parted /dev/sdX mkpart primary ext4 400GB 100%

# Format new partition
sudo mkfs.ext4 -L NIXOSROOT /dev/sdX3

# =================================================================
# STEP 4: Expand STORAGE filesystem to fill its partition
# =================================================================
sudo resize2fs /dev/sdX2

# Final verification
sudo e2fsck -f /dev/sdX2
sudo e2fsck -f /dev/sdX3
sudo parted /dev/sdX print
sudo blkid /dev/sdX*
```

**Option B: From macOS (using UTM/VM)**

If you don't have a Linux machine:

1. Install [UTM](https://mac.getutm.app/) (free)
2. Download [Ubuntu Desktop ISO](https://ubuntu.com/download/desktop)
3. Create VM and boot into "Try Ubuntu" mode
4. Pass SD card reader to VM: **VM Settings → USB → Add SD card reader**
5. Open terminal and run the Linux commands above

**Option C: From ROCKNIX via SSH (if you can unmount storage)**

This only works if you can stop all services using /storage:

```bash
# SSH into ROCKNIX
ssh root@<rocknix-ip>

# Check what's using storage
fuser -m /storage

# Try to stop services and unmount (usually won't work while system is running)
# Better to use a separate Linux system
```

### Fresh SD Card (No ROCKNIX Yet)

```bash
# Create partition table
sudo parted /dev/sdX mklabel gpt

# Create partitions
sudo parted /dev/sdX mkpart primary fat32 1MiB 2GiB      # Boot
sudo parted /dev/sdX mkpart primary ext4 2GiB 419GiB    # STORAGE
sudo parted /dev/sdX mkpart primary ext4 419GiB 100%    # NIXOSROOT

# Format
sudo mkfs.vfat -F 32 /dev/sdX1
sudo mkfs.ext4 -L STORAGE /dev/sdX2
sudo mkfs.ext4 -L NIXOSROOT /dev/sdX3

# Then flash ROCKNIX to partition 1 (follow ROCKNIX instructions)
```

### Step B2: Install the Boot Hook

The boot hook allows chain-booting from ROCKNIX to NixOS.

**Important:** For partition mode, edit `mount-storage.sh` and change:
```bash
NIXOS_BOOT_MODE="partition"    # Change from "image" to "partition"
```

```bash
# Mount ROCKNIX boot partition
sudo mkdir -p /mnt/rocknix
sudo mount /dev/sdX1 /mnt/rocknix

# Copy boot hook
sudo cp boot/mount-storage.sh /mnt/rocknix/
sudo chmod 755 /mnt/rocknix/mount-storage.sh

sudo umount /mnt/rocknix
```

### Step B3: Build and Install NixOS

#### On a NixOS Machine (or with Nix installed)

```bash
# Clone this repo
git clone https://github.com/yourusername/nixos-rp5.git
cd nixos-rp5

# Build the system
nix build .#nixosConfigurations.rp5.config.system.build.toplevel

# Mount NixOS partition
sudo mkdir -p /mnt/nixos
sudo mount /dev/disk/by-label/NIXOSROOT /mnt/nixos

# Install
sudo nixos-install --root /mnt/nixos --flake .#rp5

# Unmount
sudo umount /mnt/nixos
```

#### Using the Install Script (if available)

```bash
# Mount NixOS partition
sudo mount /dev/disk/by-label/NIXOSROOT /mnt/nixos

# Run bootstrap
./scripts/install.sh bootstrap /mnt/nixos

# Install
sudo nixos-install --root /mnt/nixos --flake .#rp5
```

### Step B4: Boot into NixOS

Insert the SD card into your RP5, then use one of these methods:

#### Option 1: Hold SELECT Button
Hold the **SELECT** button while the device boots.

#### Option 2: Create Boot Flag
From ROCKNIX, create the boot flag file:
```bash
touch /storage/.boot-nixos
```
NixOS will boot automatically on next restart.

#### Option 3: One-time Boot
From ROCKNIX terminal:
```bash
# Reboot and hold SELECT, or:
echo "nixos" >> /proc/cmdline  # Doesn't actually work, use SELECT
```

---

## First Boot Setup (Both Methods)

On first NixOS boot:

1. Login with default credentials:
   - Username: `gamer`
   - Password: `gamer`

2. **Change your password immediately:**
   ```bash
   passwd
   ```

3. Connect to WiFi:
   ```bash
   rp5-wifi scan
   rp5-wifi connect "YourSSID" "YourPassword"
   ```

4. (Optional) Install Steam:
   ```bash
   install-steam
   ```

## Boot Failsafe

If NixOS fails to boot 3 times in a row, the system automatically falls back to ROCKNIX.

To reset the counter:
```bash
# From ROCKNIX
rm /storage/.nixos-boot-attempts
```

To always boot ROCKNIX (disable NixOS boot):
```bash
# From ROCKNIX
rm /storage/.boot-nixos
# And don't hold SELECT during boot
```

## Partition Layout Diagram

```
SD Card (512GB example)
┌─────────────────────────────────────────────────────────────────┐
│ sda1: ROCKNIX │        sda2: STORAGE        │  sda3: NIXOSROOT  │
│    (2GB)      │         (~446GB)            │      (64GB)       │
│   FAT32       │          ext4               │       ext4        │
│               │                             │                   │
│ - GRUB        │ - ROMs                      │ - /nix/store      │
│ - Kernel      │ - ROCKNIX saves             │ - /etc            │
│ - mount-      │ - .boot-nixos flag          │ - /home/gamer     │
│   storage.sh  │ - Steam games (optional)    │ - System config   │
└─────────────────────────────────────────────────────────────────┘
```

## Troubleshooting

### NixOS won't boot
- Ensure SELECT is held during the entire boot sequence
- Check that `mount-storage.sh` is on the boot partition
- Verify NIXOSROOT partition has label `NIXOSROOT`: `blkid /dev/sdX3`

### Boot loops to ROCKNIX
- Failsafe triggered after 3 failed boots
- Clear counter: `rm /storage/.nixos-boot-attempts`
- Check NixOS installation is complete

### Can't resize STORAGE from ROCKNIX
- Use a Linux machine or VM (UTM on Mac)
- Cannot resize mounted filesystem safely

### Partition not recognized
- Ensure partition has correct label: `e2label /dev/sdX3 NIXOSROOT`
- Check boot script expects `LABEL=NIXOSROOT`

### Filesystem corruption after resize
If you see "filesystem size doesn't match partition size" errors:

```bash
# This happens when partition was shrunk before filesystem was small enough

# Option 1: Expand partition to fit filesystem, then redo properly
sudo parted /dev/sdX rm 3                    # Remove NIXOSROOT
sudo parted /dev/sdX resizepart 2 100%       # Expand STORAGE to full disk
sudo e2fsck -f /dev/sdX2                     # Now fsck should work
sudo resize2fs /dev/sdX2 350G                # Shrink filesystem properly
# Then redo partition steps above

# Option 2: Force repair (may lose data at end of filesystem)
sudo e2fsck -fy /dev/sdX2
```

### ROCKNIX boots with read-only storage
If ROCKNIX shows `/storage` as read-only:
- The STORAGE filesystem may have errors
- Run `sudo e2fsck -fy /dev/sdX2` from Linux
- Ensure label is exactly "STORAGE": `sudo e2label /dev/sdX2 STORAGE`
- As last resort, reformat: `sudo mkfs.ext4 -L STORAGE /dev/sdX2`
