#!/bin/sh
# =============================================================================
# NixOS Setup Script - Run from ROCKNIX via SSH
# =============================================================================
# This script creates the NixOS image and installs the boot hook.
# Run this after ROCKNIX is booted and working.
#
# Usage: ssh root@<rocknix-ip> < scripts/rocknix-setup.sh
#    Or: Copy to ROCKNIX and run: sh rocknix-setup.sh
# =============================================================================

set -e

NIXOS_IMAGE="/storage/nixos.img"
NIXOS_SIZE_MB=65536  # 64GB
BOOT_HOOK_URL="https://raw.githubusercontent.com/shuuri-labs/nixos-rp5/scaled-back/boot/mount-storage.sh"

echo "=== NixOS Setup for ROCKNIX ==="
echo ""

# Check we're on ROCKNIX
if [ ! -d "/storage" ]; then
    echo "ERROR: /storage not found. Are you running this on ROCKNIX?"
    exit 1
fi

# Step 1: Create NixOS image
echo "[1/3] Creating NixOS image ($((NIXOS_SIZE_MB / 1024))GB)..."
if [ -f "$NIXOS_IMAGE" ]; then
    echo "      Image already exists at $NIXOS_IMAGE"
    echo "      Delete it first if you want to recreate: rm $NIXOS_IMAGE"
else
    echo "      This will take a few minutes..."
    dd if=/dev/zero of="$NIXOS_IMAGE" bs=1M count=$NIXOS_SIZE_MB
    echo "      Formatting as ext4..."
    mkfs.ext4 -L NIXOSROOT "$NIXOS_IMAGE"
    echo "      Done!"
fi
echo ""

# Step 2: Install boot hook
echo "[2/3] Installing boot hook..."
mount -o remount,rw /flash 2>/dev/null || true

if command -v curl >/dev/null 2>&1; then
    curl -o /flash/mount-storage.sh "$BOOT_HOOK_URL"
elif command -v wget >/dev/null 2>&1; then
    wget -O /flash/mount-storage.sh "$BOOT_HOOK_URL"
else
    echo "ERROR: Neither curl nor wget available"
    echo "Please manually copy mount-storage.sh to /flash/"
    exit 1
fi

chmod 755 /flash/mount-storage.sh
sync
mount -o remount,ro /flash 2>/dev/null || true
echo "      Boot hook installed!"
echo ""

# Step 3: Verify
echo "[3/3] Verifying setup..."
echo ""
echo "NixOS image:"
ls -lh "$NIXOS_IMAGE"
echo ""
echo "Boot hook:"
ls -l /flash/mount-storage.sh
echo ""

echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Power off ROCKNIX"
echo "2. Put SD card in Linux machine/VM"
echo "3. Run: scripts/vm-install.sh"
echo "4. Put SD card back in RP5"
echo "5. Hold SELECT during boot to start NixOS"
echo ""
