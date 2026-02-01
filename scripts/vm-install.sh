#!/usr/bin/env bash
# =============================================================================
# NixOS Install Script - Run from Linux VM with SD card attached
# =============================================================================
# This script mounts the NixOS image and runs nixos-install.
#
# Prerequisites:
# - SD card with ROCKNIX attached to VM
# - Nix installed in VM
# - nixos-rp5 repo cloned
#
# Usage: sudo ./scripts/vm-install.sh
# =============================================================================

set -e

# Configuration
STORAGE_DEV="/dev/disk/by-label/STORAGE"
STORAGE_MOUNT="/mnt/storage"
NIXOS_IMAGE="nixos.img"
NIXOS_MOUNT="/mnt/nixos"
FLAKE_REF=".#rp5"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root (use sudo)"
    exit 1
fi

# Check we're in the repo directory
if [ ! -f "flake.nix" ]; then
    error "Run this script from the nixos-rp5 repo root directory"
    exit 1
fi

# Check nix is available
if ! command -v nix &>/dev/null; then
    error "Nix not found. Install it first:"
    echo "  sh <(curl -L https://nixos.org/nix/install) --daemon"
    exit 1
fi

echo "=== NixOS Installation Script ==="
echo ""

# Step 1: Find and mount STORAGE
log "[1/5] Mounting STORAGE partition..."
if [ ! -b "$STORAGE_DEV" ]; then
    # Try to find it by scanning
    STORAGE_DEV=$(blkid -L STORAGE 2>/dev/null || true)
    if [ -z "$STORAGE_DEV" ]; then
        error "STORAGE partition not found. Is the SD card connected?"
        echo "Available disks:"
        lsblk
        exit 1
    fi
fi

mkdir -p "$STORAGE_MOUNT"
if mountpoint -q "$STORAGE_MOUNT"; then
    warn "STORAGE already mounted at $STORAGE_MOUNT"
else
    mount "$STORAGE_DEV" "$STORAGE_MOUNT"
    log "Mounted STORAGE at $STORAGE_MOUNT"
fi

# Step 2: Check for NixOS image
log "[2/5] Checking NixOS image..."
if [ ! -f "$STORAGE_MOUNT/$NIXOS_IMAGE" ]; then
    error "NixOS image not found at $STORAGE_MOUNT/$NIXOS_IMAGE"
    error "Run rocknix-setup.sh on ROCKNIX first!"
    umount "$STORAGE_MOUNT"
    exit 1
fi
log "Found: $STORAGE_MOUNT/$NIXOS_IMAGE ($(du -h "$STORAGE_MOUNT/$NIXOS_IMAGE" | cut -f1))"

# Step 3: Set up loop device
log "[3/5] Setting up loop device..."
LOOP_DEV=$(losetup -f)
losetup "$LOOP_DEV" "$STORAGE_MOUNT/$NIXOS_IMAGE"
log "Loop device: $LOOP_DEV"

# Step 4: Mount NixOS image
log "[4/5] Mounting NixOS image..."
mkdir -p "$NIXOS_MOUNT"
mount "$LOOP_DEV" "$NIXOS_MOUNT"
log "Mounted at $NIXOS_MOUNT"

# Step 5: Install NixOS
log "[5/5] Running nixos-install..."
echo ""
warn "This will take a while. Installing NixOS..."
echo ""

# Add repo to git safe directories (in case running as root)
git config --global --add safe.directory "$(pwd)" 2>/dev/null || true

# Run nixos-install
nixos-install --root "$NIXOS_MOUNT" --flake "$FLAKE_REF" --no-root-passwd

echo ""
log "=== Installation Complete ==="
echo ""

# Cleanup
log "Cleaning up..."
umount "$NIXOS_MOUNT"
losetup -d "$LOOP_DEV"
umount "$STORAGE_MOUNT"

echo ""
log "=== All Done ==="
echo ""
echo "Next steps:"
echo "1. Remove SD card from VM"
echo "2. Insert SD card into RP5"
echo "3. Boot while holding SELECT to start NixOS"
echo ""
echo "Default login:"
echo "  Username: gamer"
echo "  Password: gamer"
echo ""
