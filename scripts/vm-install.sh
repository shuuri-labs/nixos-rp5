#!/usr/bin/env bash
# =============================================================================
# NixOS Install Script - Run from Linux VM with SD card attached
# =============================================================================
# This script creates a NIXOSROOT partition on the SD card and installs NixOS.
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
NIXOSROOT_SIZE="64G"
NIXOSROOT_LABEL="NIXOSROOT"
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

# Step 1: Find the SD card
log "[1/6] Finding SD card..."
ROCKNIX_DEV=$(blkid -L ROCKNIX 2>/dev/null || true)
STORAGE_DEV=$(blkid -L STORAGE 2>/dev/null || true)

if [ -z "$ROCKNIX_DEV" ] && [ -z "$STORAGE_DEV" ]; then
    error "ROCKNIX SD card not found. Is it connected to the VM?"
    echo "Available disks:"
    lsblk
    exit 1
fi

# Determine the base disk device from ROCKNIX or STORAGE partition
if [ -n "$ROCKNIX_DEV" ]; then
    DISK_DEV=$(echo "$ROCKNIX_DEV" | sed 's/p\?[0-9]*$//')
else
    DISK_DEV=$(echo "$STORAGE_DEV" | sed 's/p\?[0-9]*$//')
fi

log "Found SD card: $DISK_DEV"
log "Current partition layout:"
lsblk "$DISK_DEV"
echo ""

# Step 2: Check if NIXOSROOT partition exists
log "[2/6] Checking for NIXOSROOT partition..."
NIXOSROOT_DEV=$(blkid -L "$NIXOSROOT_LABEL" 2>/dev/null || true)

if [ -n "$NIXOSROOT_DEV" ]; then
    log "Found existing NIXOSROOT partition: $NIXOSROOT_DEV"
else
    warn "NIXOSROOT partition not found - will create it"
    echo ""
    warn "This will REPARTITION the SD card:"
    echo "  - Partition 1: ROCKNIX boot (unchanged)"
    echo "  - Partition 2: STORAGE (largest partition, recreated - DATA WILL BE LOST)"
    echo "  - Partition 3: NIXOSROOT (64GB, new)"
    echo ""
    warn "IMPORTANT: This will destroy existing data on STORAGE!"
    warn "Backup ROMs and saves from ROCKNIX before continuing!"
    echo ""
    echo "Press Ctrl+C now to cancel, or Enter to continue..."
    read -r
    echo ""

    # Step 3: Create NIXOSROOT partition
    log "[3/6] Creating NIXOSROOT partition..."

    # Get partition numbers
    ROCKNIX_PART_NUM=$(echo "$ROCKNIX_DEV" | grep -o '[0-9]*$')
    STORAGE_PART_NUM=$(echo "$STORAGE_DEV" | grep -o '[0-9]*$')

    log "ROCKNIX partition: ${DISK_DEV}p${ROCKNIX_PART_NUM}"
    log "STORAGE partition: ${DISK_DEV}p${STORAGE_PART_NUM}"

    # Unmount STORAGE partition if it's mounted anywhere
    log "Ensuring STORAGE partition is unmounted..."
    if mount | grep -q "$STORAGE_DEV"; then
        STORAGE_MOUNT_POINT=$(mount | grep "$STORAGE_DEV" | awk '{print $3}')
        log "STORAGE is mounted at $STORAGE_MOUNT_POINT, unmounting..."
        umount "$STORAGE_DEV" || {
            error "Failed to unmount STORAGE partition"
            error "Please manually unmount it first: sudo umount $STORAGE_DEV"
            exit 1
        }
        log "Unmounted successfully"
    else
        log "STORAGE not mounted, proceeding..."
    fi

    # Get the end position of ROCKNIX partition and total disk size
    # Use GB for better sector alignment (parted aligns better with round numbers)
    ROCKNIX_END=$(parted "$DISK_DEV" unit GB print | grep "^ *$ROCKNIX_PART_NUM" | awk '{print $3}' | sed 's/GB//')
    DISK_SIZE=$(parted "$DISK_DEV" unit GB print | grep "^Disk " | awk '{print $3}' | sed 's/GB//')

    # Calculate STORAGE end: leave 64GB for NIXOSROOT at the end
    # Use bc for floating point math and round down to avoid overlap
    STORAGE_END=$(echo "$DISK_SIZE - 64" | bc)
    STORAGE_START="${ROCKNIX_END}GB"
    STORAGE_END_STR="${STORAGE_END}GB"

    log "Partition layout:"
    log "  Disk size: ${DISK_SIZE}GB"
    log "  ROCKNIX ends at: ${ROCKNIX_END}GB (p1)"
    log "  STORAGE: ${STORAGE_START} to ${STORAGE_END_STR} (p2, largest partition)"
    log "  NIXOSROOT: ${STORAGE_END_STR} to 100% (p3, ~64GB)"

    # Delete old STORAGE partition and create new layout
    # Use 100% for NIXOSROOT end to let parted handle alignment automatically
    log "Repartitioning (this may take a moment)..."
    # Use yes to auto-confirm any prompts, and -s for script mode
    yes | parted ---pretend-input-tty -s "$DISK_DEV" -- \
        rm "$STORAGE_PART_NUM" \
        mkpart primary ext4 "$STORAGE_START" "$STORAGE_END_STR" \
        mkpart primary ext4 "$STORAGE_END_STR" 100% \
        2>/dev/null || true

    # Give parted a moment to complete
    sync
    sleep 1

    # Update partition table
    partprobe "$DISK_DEV"
    sleep 2

    # Determine new partition devices (p2 for STORAGE, p3 for NIXOSROOT)
    if [[ "$DISK_DEV" == *"nvme"* ]] || [[ "$DISK_DEV" == *"mmcblk"* ]]; then
        NEW_STORAGE_DEV="${DISK_DEV}p2"
        NIXOSROOT_DEV="${DISK_DEV}p3"
    else
        NEW_STORAGE_DEV="${DISK_DEV}2"
        NIXOSROOT_DEV="${DISK_DEV}3"
    fi

    log "Created STORAGE partition: $NEW_STORAGE_DEV"
    log "Created NIXOSROOT partition: $NIXOSROOT_DEV"

    # Format new STORAGE partition WITHOUT modern ext4 features that ROCKNIX kernel doesn't support
    # This prevents read-only mount issues (see progress.md for details)
    log "Formatting STORAGE partition (without metadata_csum,64bit for ROCKNIX compatibility)..."
    mkfs.ext4 -F -L STORAGE -O ^metadata_csum,^64bit "$NEW_STORAGE_DEV"
fi

# Step 4: Format NIXOSROOT partition
log "[4/6] Formatting NIXOSROOT partition..."
if blkid "$NIXOSROOT_DEV" | grep -q "TYPE="; then
    log "NIXOSROOT already formatted, skipping..."
else
    mkfs.ext4 -F -L "$NIXOSROOT_LABEL" "$NIXOSROOT_DEV"
    log "Formatted as ext4"
fi

# Step 5: Mount NIXOSROOT
log "[5/6] Mounting NIXOSROOT..."
mkdir -p "$NIXOS_MOUNT"
if mountpoint -q "$NIXOS_MOUNT"; then
    warn "Already mounted at $NIXOS_MOUNT"
else
    mount "$NIXOSROOT_DEV" "$NIXOS_MOUNT"
    log "Mounted at $NIXOS_MOUNT"
fi

# Step 6: Install NixOS
log "[6/6] Running nixos-install..."
echo ""
warn "This will take a while. Installing NixOS..."
echo ""

# Add repo to git safe directories (in case running as root)
git config --global --add safe.directory "$(pwd)" 2>/dev/null || true

# Run nixos-install
nixos-install --root "$NIXOS_MOUNT" --flake "$FLAKE_REF" --no-root-passwd
INSTALL_RESULT=$?

echo ""
if [ $INSTALL_RESULT -ne 0 ]; then
    error "nixos-install failed with exit code $INSTALL_RESULT"
    exit 1
fi

# Verify installation
log "Verifying installation..."
if [ ! -d "$NIXOS_MOUNT/nix/var/nix/profiles" ]; then
    error "Profiles directory not created!"
    error "Installation may have failed"
    exit 1
fi

if [ ! -L "$NIXOS_MOUNT/nix/var/nix/profiles/system" ]; then
    error "System profile symlink not created!"
    echo ""
    log "Profiles directory contents:"
    ls -la "$NIXOS_MOUNT/nix/var/nix/profiles/" || true
    error "Installation verification FAILED"
    exit 1
fi

# Follow the symlink chain: system -> system-N-link -> /nix/store/...
SYSTEM_LINK=$(readlink "$NIXOS_MOUNT/nix/var/nix/profiles/system")
log "system -> $SYSTEM_LINK"

SYSTEM_TARGET=$(readlink "$NIXOS_MOUNT/nix/var/nix/profiles/$SYSTEM_LINK")
log "$SYSTEM_LINK -> $SYSTEM_TARGET"

# Prepend mount point to the absolute /nix/store/... path
SYSTEM_PATH_ON_HOST="$NIXOS_MOUNT$SYSTEM_TARGET"
log "Checking on host at: $SYSTEM_PATH_ON_HOST"

if [ ! -d "$SYSTEM_PATH_ON_HOST" ]; then
    error "System profile directory not found at $SYSTEM_PATH_ON_HOST"
    echo ""
    log "Profiles directory contents:"
    ls -la "$NIXOS_MOUNT/nix/var/nix/profiles/" || true
    error "Installation verification FAILED"
    exit 1
fi

log "System profile contents:"
ls -la "$SYSTEM_PATH_ON_HOST/"

if [ ! -f "$SYSTEM_PATH_ON_HOST/init" ] && [ ! -L "$SYSTEM_PATH_ON_HOST/init" ]; then
    error "System init not found at $SYSTEM_PATH_ON_HOST/init"
    error "Installation verification FAILED"
    exit 1
fi

log "System profile verified"
log "Init found at: $SYSTEM_TARGET/init"

echo ""
log "=== Installation Complete and Verified ==="
echo ""

# Cleanup
log "Cleaning up..."
umount "$NIXOS_MOUNT"

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
