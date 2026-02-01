#!/usr/bin/env bash
# =============================================================================
# NixOS RP5 Installation Helper
# =============================================================================
# This script helps set up the NixOS partition on the Retroid Pocket 5.
# Run this from a Linux system with the RP5's SD card mounted.
#
# Prerequisites:
# - SD card with ROCKNIX already installed and working
# - Third partition created for NixOS (ext4, label: NIXOSROOT)
# - NixOS aarch64 tarball or nixos-install available
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
    cat << EOF
Usage: $0 [OPTIONS] <command>

Commands:
    prepare-partition <device>    Create and format NixOS partition
    install-hook <boot-mount>     Install mount-storage.sh to ROCKNIX boot partition
    bootstrap <nixos-mount>       Bootstrap minimal NixOS to partition
    check                         Verify installation prerequisites

Options:
    -h, --help    Show this help message

Examples:
    # Create partition on SD card (assuming /dev/sdb)
    sudo $0 prepare-partition /dev/sdb

    # Install boot hook (ROCKNIX boot partition mounted at /mnt/rocknix)
    sudo $0 install-hook /mnt/rocknix

    # Bootstrap NixOS (NixOS partition mounted at /mnt/nixos)
    sudo $0 bootstrap /mnt/nixos
EOF
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root"
        exit 1
    fi
}

# Prepare NixOS partition
cmd_prepare_partition() {
    local device="$1"

    if [ -z "$device" ]; then
        error "Device not specified"
        usage
        exit 1
    fi

    if [ ! -b "$device" ]; then
        error "Device not found: $device"
        exit 1
    fi

    warn "This will modify the partition table on $device"
    warn "Make sure ROCKNIX is already installed and you have a backup!"
    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Aborted"
        exit 0
    fi

    log "Current partition layout:"
    fdisk -l "$device"

    echo
    warn "You need to create a third partition for NixOS."
    warn "Recommended size: 32GB or more"
    warn "Please use fdisk, parted, or gparted to create the partition."
    echo
    log "After creating the partition, format it with:"
    echo "    mkfs.ext4 -L NIXOSROOT ${device}3"
    echo
    log "Then run: $0 install-hook <boot-mount>"
}

# Install boot hook
cmd_install_hook() {
    local boot_mount="$1"

    if [ -z "$boot_mount" ]; then
        error "Boot mount point not specified"
        usage
        exit 1
    fi

    if [ ! -d "$boot_mount" ]; then
        error "Boot mount point does not exist: $boot_mount"
        exit 1
    fi

    # Check if it looks like a ROCKNIX boot partition
    if [ ! -f "$boot_mount/KERNEL" ] && [ ! -f "$boot_mount/grub/grub.cfg" ]; then
        warn "This doesn't look like a ROCKNIX boot partition"
        warn "Expected to find KERNEL or grub/grub.cfg"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    # Backup existing mount-storage.sh if present
    if [ -f "$boot_mount/mount-storage.sh" ]; then
        log "Backing up existing mount-storage.sh"
        cp "$boot_mount/mount-storage.sh" "$boot_mount/mount-storage.sh.bak.$(date +%Y%m%d%H%M%S)"
    fi

    # Copy our mount-storage.sh
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local hook_src="$script_dir/../boot/mount-storage.sh"

    if [ ! -f "$hook_src" ]; then
        error "mount-storage.sh not found at: $hook_src"
        exit 1
    fi

    log "Installing mount-storage.sh to $boot_mount/"
    cp "$hook_src" "$boot_mount/mount-storage.sh"
    chmod 755 "$boot_mount/mount-storage.sh"

    log "Boot hook installed successfully!"
    echo
    log "To boot NixOS:"
    log "  - Hold SELECT button during boot, OR"
    log "  - Create /storage/.boot-nixos file on ROCKNIX storage partition"
}

# Bootstrap NixOS
cmd_bootstrap() {
    local nixos_mount="$1"

    if [ -z "$nixos_mount" ]; then
        error "NixOS mount point not specified"
        usage
        exit 1
    fi

    if [ ! -d "$nixos_mount" ]; then
        error "NixOS mount point does not exist: $nixos_mount"
        exit 1
    fi

    # Check if partition is mounted
    if ! mountpoint -q "$nixos_mount"; then
        error "NixOS partition not mounted at: $nixos_mount"
        log "Mount it first: mount /dev/disk/by-label/NIXOSROOT $nixos_mount"
        exit 1
    fi

    log "Creating basic NixOS directory structure..."

    # Create essential directories
    mkdir -p "$nixos_mount"/{nix/store,nix/var/nix/profiles,etc,var,run,tmp,home,root}
    mkdir -p "$nixos_mount"/{lib/modules,lib/firmware}
    mkdir -p "$nixos_mount"/rocknix/{flash,sysroot,storage}

    # Set permissions
    chmod 1777 "$nixos_mount/tmp"
    chmod 755 "$nixos_mount"/{nix,etc,var,run,home,root,lib}

    log "Directory structure created"
    echo
    log "Next steps:"
    log "1. Build NixOS configuration: nix build .#nixosConfigurations.rp5.config.system.build.toplevel"
    log "2. Copy the closure to $nixos_mount/nix/store"
    log "3. Create system profile: nix-env --store $nixos_mount -p $nixos_mount/nix/var/nix/profiles/system --set <path-to-toplevel>"
    log "4. Run activate: $nixos_mount/nix/var/nix/profiles/system/activate"
    echo
    log "Or use nixos-install if available:"
    log "    nixos-install --root $nixos_mount --flake .#rp5"
}

# Check prerequisites
cmd_check() {
    log "Checking prerequisites..."

    local ok=1

    # Check for required tools
    for cmd in fdisk mkfs.ext4 mount; do
        if command -v "$cmd" &>/dev/null; then
            log "  $cmd: found"
        else
            error "  $cmd: NOT FOUND"
            ok=0
        fi
    done

    # Check for nix
    if command -v nix &>/dev/null; then
        log "  nix: found ($(nix --version))"
    else
        warn "  nix: not found (optional, needed for building config)"
    fi

    # Check for nixos-install
    if command -v nixos-install &>/dev/null; then
        log "  nixos-install: found"
    else
        warn "  nixos-install: not found (optional)"
    fi

    if [ "$ok" -eq 1 ]; then
        log "All required tools available"
    else
        error "Some required tools are missing"
        exit 1
    fi
}

# Main
main() {
    case "${1:-}" in
        prepare-partition)
            check_root
            cmd_prepare_partition "$2"
            ;;
        install-hook)
            check_root
            cmd_install_hook "$2"
            ;;
        bootstrap)
            check_root
            cmd_bootstrap "$2"
            ;;
        check)
            cmd_check
            ;;
        -h|--help|"")
            usage
            ;;
        *)
            error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"
