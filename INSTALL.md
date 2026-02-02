# Installation Guide

Complete guide for installing NixOS on the Retroid Pocket 5 alongside ROCKNIX.

## Overview

NixOS is installed on a dedicated NIXOSROOT partition alongside ROCKNIX. This approach:
- Provides better performance (no loop device overhead)
- Uses a proper partition layout
- Keeps ROCKNIX and NixOS cleanly separated

## Prerequisites

- Retroid Pocket 5 with ROCKNIX installed and working
- SD card (512GB recommended, 128GB minimum)
- Computer with Linux (or Linux VM) for installation
- Basic familiarity with terminal commands

---

## Quick Install (Scripts)

### Step 1: ROCKNIX Setup (Install Boot Hook)
Boot ROCKNIX, connect to WiFi, then from your computer:
```bash
# SSH and run setup script to install boot hook
ssh root@<rocknix-ip> 'sh -s' < scripts/rocknix-setup.sh
```

### Step 2: NixOS Install (Partition and Install)
Power off RP5, put SD card in Linux VM, then:
```bash
cd nixos-rp5
git pull
sudo ./scripts/vm-install.sh
# This will partition the SD card (creating NIXOSROOT) and install NixOS
```

### Step 3: Boot
Put SD card back in RP5, hold SELECT during boot.

---

## Manual Install (Step by Step)

### Step 1: Install the Boot Hook (from ROCKNIX)

First, ensure ROCKNIX boots and works normally. Then SSH into ROCKNIX:

```bash
# SSH into ROCKNIX (find IP in ROCKNIX network settings)
ssh root@<rocknix-ip>

# Remount boot partition as read-write
mount -o remount,rw /flash

# Download and install the boot hook
curl -o /flash/mount-storage.sh https://raw.githubusercontent.com/yourusername/nixos-rp5/scaled-back/boot/mount-storage.sh
# Or use wget if curl isn't available:
# wget -O /flash/mount-storage.sh https://raw.githubusercontent.com/yourusername/nixos-rp5/scaled-back/boot/mount-storage.sh

# Make it executable
chmod 755 /flash/mount-storage.sh

# Remount as read-only
sync
mount -o remount,ro /flash

# Power off to prepare for partitioning
poweroff
```

### Step 2: Partition SD Card and Install NixOS (from Linux VM)

Remove the SD card from RP5 and connect it to a Linux machine (or VM) with Nix installed:

```bash
# Clone the repo
git clone https://github.com/yourusername/nixos-rp5.git
cd nixos-rp5

# Run the install script (will partition SD card and install NixOS)
sudo ./scripts/vm-install.sh

# The script will:
# 1. Find the SD card
# 2. Recreate STORAGE partition (largest) on p2 (where ROCKNIX expects it)
# 3. Create NIXOSROOT partition (64GB) on p3
# 4. Format STORAGE (without metadata_csum/64bit for ROCKNIX compatibility)
# 5. Format NIXOSROOT as ext4
# 6. Install NixOS to NIXOSROOT
```

**IMPORTANT:** This will repartition the SD card and destroy existing data on STORAGE. Back up ROMs and saves from ROCKNIX before running this!

### Step 3: Boot into NixOS

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
┌───────────────────────────────────────────────────────────────────────────┐
│ Part 1: ROCKNIX │ Part 2: STORAGE              │ Part 3: NIXOSROOT       │
│     (2GB)       │     (~446GB)                 │      (64GB)             │
│     FAT32       │      ext4                    │       ext4              │
│                 │                              │                         │
│ - GRUB          │ - ROMs                       │ - NixOS system          │
│ - Kernel        │ - ROCKNIX saves              │ - /nix/store            │
│ - Boot hook     │ - .boot-nixos flag           │ - User files            │
│                 │ - Steam games (if using      │                         │
│                 │   NixOS Steam session)       │                         │
└───────────────────────────────────────────────────────────────────────────┘

Note: STORAGE stays on partition 2 where ROCKNIX expects it.
      STORAGE is formatted without metadata_csum/64bit for ROCKNIX compatibility.
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
- Verify NIXOSROOT partition exists: `lsblk | grep NIXOSROOT`

### Boot loops to ROCKNIX
- Failsafe triggered after 3 failed boots
- Clear counter: `rm /storage/.nixos-boot-attempts`
- Check NixOS installation is complete

### Partition not found error
```bash
# From Linux VM, verify partitions exist
lsblk /dev/mmcblk0  # or your SD card device
# Should show ROCKNIX (p1), STORAGE (p2), NIXOSROOT (p3)
```

### Removing NixOS
To completely remove NixOS and restore single STORAGE partition:

**WARNING:** This requires repartitioning and will destroy all data!

```bash
# From Linux VM (not ROCKNIX)
sudo parted /dev/mmcblk0
  rm 3          # Remove NIXOSROOT
  resizepart 2 100%  # Expand STORAGE to fill disk
  quit
```

To keep partitions but just disable NixOS boot:
```bash
# From ROCKNIX
rm /storage/.boot-nixos
# And don't hold SELECT during boot
```
