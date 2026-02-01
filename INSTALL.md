# Installation Guide

Complete guide for installing NixOS on the Retroid Pocket 5 alongside ROCKNIX.

## Overview

NixOS lives in an image file on ROCKNIX's STORAGE partition. This approach:
- Requires no partition modifications
- Keeps ROCKNIX completely stock
- Makes NixOS easy to remove (just delete the image file)

## Prerequisites

- Retroid Pocket 5 with ROCKNIX installed and working
- SD card (512GB recommended, 128GB minimum)
- Computer with Linux (or Linux VM) for installation
- Basic familiarity with terminal commands

---

## Quick Install (Scripts)

### Step 1: ROCKNIX Setup
Boot ROCKNIX, connect to WiFi, then from your computer:
```bash
# SSH and run setup script
ssh root@<rocknix-ip> 'sh -s' < scripts/rocknix-setup.sh
```

### Step 2: NixOS Install
Power off RP5, put SD card in Linux VM, then:
```bash
cd nixos-rp5
git pull
sudo ./scripts/vm-install.sh
```

### Step 3: Boot
Put SD card back in RP5, hold SELECT during boot.

---

## Manual Install (Step by Step)

### Step 1: Boot ROCKNIX and Create the Image

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

## Step 2: Install the Boot Hook

```bash
# Still in ROCKNIX SSH session
# Mount the boot partition
mkdir -p /tmp/boot
mount /dev/disk/by-label/ROCKNIX /tmp/boot 2>/dev/null || mount /dev/mmcblk0p1 /tmp/boot

# Download mount-storage.sh to the boot partition
curl -o /tmp/boot/mount-storage.sh https://raw.githubusercontent.com/yourusername/nixos-rp5/main/boot/mount-storage.sh

# Or use wget if curl isn't available
# wget -O /tmp/boot/mount-storage.sh https://raw.githubusercontent.com/yourusername/nixos-rp5/main/boot/mount-storage.sh

chmod 755 /tmp/boot/mount-storage.sh
sync
umount /tmp/boot
```

## Step 3: Install NixOS into the Image

From a Linux machine (or VM) with Nix installed:

```bash
# Clone the repo
git clone https://github.com/yourusername/nixos-rp5.git
cd nixos-rp5

# Mount STORAGE partition from SD card
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

## Step 4: Boot into NixOS

Insert the SD card into your RP5, then:

- **Hold SELECT button** during boot, OR
- Create `/storage/.boot-nixos` file from ROCKNIX: `touch /storage/.boot-nixos`

---

## First Boot Setup

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

---

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

---

## Storage Layout

```
SD Card (512GB example)
┌─────────────────────────────────────────────────────────┐
│  Partition 1: ROCKNIX  │     Partition 2: STORAGE       │
│       (2GB)            │          (~510GB)              │
│       FAT32            │           ext4                 │
│                        │                                │
│  - GRUB                │  - nixos.img (64GB)  ← NixOS   │
│  - Kernel              │  - ROMs                        │
│  - mount-storage.sh    │  - ROCKNIX saves               │
│                        │  - .boot-nixos flag            │
│                        │  - Steam games                 │
└─────────────────────────────────────────────────────────┘
```

---

## macOS Users (UTM/VM)

If you don't have a Linux machine:

1. Install [UTM](https://mac.getutm.app/) (free)
2. Download [Ubuntu Desktop ISO](https://ubuntu.com/download/desktop)
3. Create VM and boot into "Try Ubuntu" mode
4. Pass SD card reader to VM: **VM Settings → USB → Add SD card reader**
5. Install Nix in the VM: `sh <(curl -L https://nixos.org/nix/install) --daemon`
6. Follow Step 3 above

---

## Troubleshooting

### NixOS won't boot
- Ensure SELECT is held during the entire boot sequence
- Check that `mount-storage.sh` is on the boot partition
- Verify the image exists: `ls -la /storage/nixos.img`

### Boot loops to ROCKNIX
- Failsafe triggered after 3 failed boots
- Clear counter: `rm /storage/.nixos-boot-attempts`
- Check NixOS installation is complete

### Image not found error
```bash
# From ROCKNIX, verify image exists and has correct permissions
ls -la /storage/nixos.img
# Should show ~64GB file
```

### Removing NixOS
To completely remove NixOS:
```bash
# From ROCKNIX
rm /storage/nixos.img
rm /storage/.boot-nixos
rm /storage/.nixos-boot-attempts

# Remove boot hook (optional)
mount /dev/mmcblk0p1 /tmp/boot
rm /tmp/boot/mount-storage.sh
umount /tmp/boot
```
