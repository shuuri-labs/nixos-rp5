# Installation Guide

Complete guide for installing NixOS on the Retroid Pocket 5 alongside ROCKNIX.

## Prerequisites

- Retroid Pocket 5 with ROCKNIX installed and working
- SD card (512GB recommended, 128GB minimum)
- Computer with Linux (or Linux VM) for partitioning
- Basic familiarity with terminal commands

## Step 1: Partition the SD Card

You need three partitions:

| Partition | Label | Size | Purpose |
|-----------|-------|------|---------|
| 1 | (ROCKNIX) | 2GB | ROCKNIX boot |
| 2 | STORAGE | Remainder - 64GB | ROCKNIX data, ROMs, shared storage |
| 3 | NIXOSROOT | 64GB | NixOS root filesystem |

### If ROCKNIX is Already Installed

ROCKNIX expands STORAGE to fill the card on first boot. You need to shrink it.

**Option A: From Linux machine**

```bash
# Install tools
sudo apt update && sudo apt install -y parted e2fsprogs

# Identify your SD card (BE CAREFUL - wrong disk = data loss)
lsblk
# Usually /dev/sdX or /dev/mmcblkX

# Check current layout
sudo parted /dev/sdX print

# Shrink the ext4 filesystem first (adjust 417G based on your card size)
# Formula: (total card size) - 2GB (boot) - 64GB (nixos) = STORAGE size
sudo e2fsck -f /dev/sdX2
sudo resize2fs /dev/sdX2 417G

# Resize partition and create NIXOSROOT
sudo parted /dev/sdX
# In parted:
print
resizepart 2 419GB
mkpart primary ext4 419GB -1
print
quit

# Format new partition
sudo mkfs.ext4 -L NIXOSROOT /dev/sdX3

# Expand STORAGE filesystem to fill resized partition
sudo resize2fs /dev/sdX2

# Verify
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

## Step 2: Install the Boot Hook

The boot hook allows chain-booting from ROCKNIX to NixOS.

```bash
# Mount ROCKNIX boot partition
sudo mkdir -p /mnt/rocknix
sudo mount /dev/sdX1 /mnt/rocknix

# Copy boot hook
sudo cp boot/mount-storage.sh /mnt/rocknix/
sudo chmod 755 /mnt/rocknix/mount-storage.sh

sudo umount /mnt/rocknix
```

## Step 3: Build and Install NixOS

### On a NixOS Machine (or with Nix installed)

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

### Using the Install Script (if available)

```bash
# Mount NixOS partition
sudo mount /dev/disk/by-label/NIXOSROOT /mnt/nixos

# Run bootstrap
./scripts/install.sh bootstrap /mnt/nixos

# Install
sudo nixos-install --root /mnt/nixos --flake .#rp5
```

## Step 4: Boot into NixOS

Insert the SD card into your RP5, then use one of these methods:

### Method 1: Hold SELECT Button
Hold the **SELECT** button while the device boots.

### Method 2: Create Boot Flag
From ROCKNIX, create the boot flag file:
```bash
touch /storage/.boot-nixos
```
NixOS will boot automatically on next restart.

### Method 3: One-time Boot
From ROCKNIX terminal:
```bash
# Reboot and hold SELECT, or:
echo "nixos" >> /proc/cmdline  # Doesn't actually work, use SELECT
```

## Step 5: First Boot Setup

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
