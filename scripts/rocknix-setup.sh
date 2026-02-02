#!/bin/sh
# =============================================================================
# NixOS Setup Script - Run from ROCKNIX via SSH
# =============================================================================
# This script installs the boot hook for NixOS chain-booting.
# Run this after ROCKNIX is booted and working.
#
# NOTE: Partitioning and NixOS installation happens in the VM (vm-install.sh)
#       This script only sets up the boot hook.
#
# Usage: ssh root@<rocknix-ip> < scripts/rocknix-setup.sh
#    Or: Copy to ROCKNIX and run: sh rocknix-setup.sh
# =============================================================================

set -e

BOOT_HOOK_URL="https://raw.githubusercontent.com/shuuri-labs/nixos-rp5/scaled-back/boot/mount-storage.sh"

echo "=== NixOS Setup for ROCKNIX ==="
echo ""

# Check we're on ROCKNIX
if [ ! -d "/storage" ]; then
    echo "ERROR: /storage not found. Are you running this on ROCKNIX?"
    exit 1
fi

# Step 1: Install boot hook
echo "[1/2] Installing boot hook..."
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

# Step 2: Verify
echo "[2/2] Verifying setup..."
echo ""
echo "Boot hook:"
ls -l /flash/mount-storage.sh
echo ""

echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Power off ROCKNIX and remove SD card"
echo "2. Put SD card in Linux machine/VM"
echo "3. Run: sudo ./scripts/vm-install.sh"
echo "   (This will partition the SD card and install NixOS)"
echo "4. Put SD card back in RP5"
echo "5. Hold SELECT during boot to start NixOS"
echo ""
