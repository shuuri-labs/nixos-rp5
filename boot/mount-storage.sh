#!/bin/sh
# =============================================================================
# NixOS Chain-Boot Hook for ROCKNIX
# =============================================================================
# Place this file on the ROCKNIX boot partition as mount-storage.sh
# This hooks into ROCKNIX's init script during the storage mounting phase.
#
# Boot trigger: Hold SELECT button during boot OR create /storage/.boot-nixos
#
# WARNING: This uses features not officially supported by ROCKNIX.
# USE AT YOUR OWN RISK!
#
# Based on arch-through-rocknix by Mash0Star
# Adapted for persistent NixOS root filesystem
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
BTN_SELECT=314                              # SELECT button key code
NIXOS_BOOT_FLAG="/storage/.boot-nixos"      # Persistent boot flag
BOOT_COUNTER="/storage/.nixos-boot-attempts"
MAX_BOOT_ATTEMPTS=3
DEBUG_MODE=0                                # Set to 1 for verbose logging

# NixOS image configuration
# NixOS lives in an image file on STORAGE - no partition modifications needed
NIXOS_IMAGE_PATH="/storage/nixos.img"       # Path to NixOS image file

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------
log() {
    echo "[nixos-boot] $*"
}

log_debug() {
    [ "$DEBUG_MODE" = "1" ] && echo "[nixos-boot:debug] $*"
}

log_error() {
    echo "[nixos-boot:ERROR] $*" >&2
}

# -----------------------------------------------------------------------------
# is_key_pressed - Check if a specific key is currently pressed
# Uses evtest to query input devices
# Returns 0 if pressed, 1 if not
# -----------------------------------------------------------------------------
is_key_pressed() {
    local keycode="$1"
    for evdev in /dev/input/event*; do
        [ -e "$evdev" ] || continue
        if evtest --query "$evdev" EV_KEY "$keycode" 2>/dev/null; then
            [ $? -eq 10 ] && return 0
        fi
    done
    return 1
}

# -----------------------------------------------------------------------------
# Load device-specific joypad module if needed (for button detection)
# This is required on some devices before input can be read
# -----------------------------------------------------------------------------
load_joypad_module() {
    local module_path

    # Try SM8250 (Snapdragon 865) specific module first
    module_path="/sysroot/usr/lib/kernel-overlays/base/lib/modules/*/rocknix-joypad/rocknix-singleadc-joypad.ko"

    for mod in $module_path; do
        if [ -f "$mod" ]; then
            log_debug "Loading joypad module: $mod"
            insmod "$mod" 2>/dev/null && return 0
        fi
    done

    # Module may already be loaded or not needed
    log_debug "No joypad module found or needed"
    return 0
}

# -----------------------------------------------------------------------------
# should_boot_nixos - Determine if we should chain-boot to NixOS
# Checks: 1) Button press, 2) Persistent flag file
# -----------------------------------------------------------------------------
should_boot_nixos() {
    # Method 1: Check for SELECT button held during boot
    if is_key_pressed "$BTN_SELECT"; then
        log "SELECT button detected - booting NixOS"
        return 0
    fi

    # Method 2: Check for persistent boot flag
    # We need to temporarily mount storage to check
    if [ -b "/dev/disk/by-label/STORAGE" ]; then
        mkdir -p /tmp/storage_check
        if mount -o ro /dev/disk/by-label/STORAGE /tmp/storage_check 2>/dev/null; then
            if [ -f "/tmp/storage_check/.boot-nixos" ]; then
                umount /tmp/storage_check
                rmdir /tmp/storage_check
                log "Boot flag detected - booting NixOS"
                return 0
            fi
            umount /tmp/storage_check
            rmdir /tmp/storage_check
        fi
    fi

    # Method 3: Check kernel command line
    if grep -q "nixos" /proc/cmdline 2>/dev/null; then
        log "Kernel cmdline 'nixos' detected - booting NixOS"
        return 0
    fi

    return 1
}

# -----------------------------------------------------------------------------
# check_boot_counter - Implement boot failsafe
# After MAX_BOOT_ATTEMPTS failed boots, fall back to ROCKNIX
# Returns 0 if OK to boot, 1 if should fall back
# -----------------------------------------------------------------------------
check_boot_counter() {
    local attempts=0

    # Need storage mounted to check counter
    mkdir -p /tmp/storage_check
    if ! mount -o rw /dev/disk/by-label/STORAGE /tmp/storage_check 2>/dev/null; then
        log_debug "Cannot mount storage for boot counter check"
        return 0  # Proceed anyway
    fi

    if [ -f "/tmp/storage_check/.nixos-boot-attempts" ]; then
        attempts=$(cat "/tmp/storage_check/.nixos-boot-attempts" 2>/dev/null || echo 0)
    fi

    if [ "$attempts" -ge "$MAX_BOOT_ATTEMPTS" ]; then
        log_error "NixOS failed to boot $MAX_BOOT_ATTEMPTS times!"
        log_error "Falling back to ROCKNIX. Remove $BOOT_COUNTER to retry."
        rm -f "/tmp/storage_check/.nixos-boot-attempts"
        umount /tmp/storage_check
        rmdir /tmp/storage_check
        return 1
    fi

    # Increment counter
    echo $((attempts + 1)) > "/tmp/storage_check/.nixos-boot-attempts"
    log_debug "Boot attempt $((attempts + 1)) of $MAX_BOOT_ATTEMPTS"

    umount /tmp/storage_check
    rmdir /tmp/storage_check
    return 0
}

# -----------------------------------------------------------------------------
# find_nixos_init - Locate NixOS systemd init
# NixOS stores systemd in /nix/store, we need to find the right path
# -----------------------------------------------------------------------------
find_nixos_init() {
    local nixroot="$1"
    local init_path

    # Method 1: Follow the current-system symlink (preferred)
    if [ -L "$nixroot/run/current-system/sw/bin/init" ]; then
        init_path=$(readlink -f "$nixroot/run/current-system/sw/bin/init" 2>/dev/null)
        if [ -x "$init_path" ]; then
            echo "$init_path"
            return 0
        fi
    fi

    # Method 2: Follow /nix/var/nix/profiles/system symlink
    if [ -L "$nixroot/nix/var/nix/profiles/system" ]; then
        local system_path=$(readlink -f "$nixroot/nix/var/nix/profiles/system")
        if [ -x "$system_path/sw/bin/init" ]; then
            init_path=$(readlink -f "$system_path/sw/bin/init")
            echo "$init_path"
            return 0
        fi
        # Try activate script as fallback
        if [ -x "$system_path/activate" ]; then
            # NixOS activate script can bootstrap
            echo "$system_path/activate"
            return 0
        fi
    fi

    # Method 3: Search /nix/store for systemd (last resort)
    init_path=$(find "$nixroot/nix/store" -maxdepth 3 -name "systemd" -path "*/lib/systemd/*" -type f 2>/dev/null | head -1)
    if [ -x "$init_path" ]; then
        echo "$init_path"
        return 0
    fi

    return 1
}

# -----------------------------------------------------------------------------
# setup_loop_device - Set up loop device for image file
# Returns the loop device path on stdout
# -----------------------------------------------------------------------------
setup_loop_device() {
    local image_path="$1"
    local loop_dev

    # Check if image exists
    if [ ! -f "$image_path" ]; then
        log_error "NixOS image not found: $image_path"
        return 1
    fi

    # Find a free loop device and set it up
    loop_dev=$(losetup -f 2>/dev/null)
    if [ -z "$loop_dev" ]; then
        log_error "No free loop device available"
        return 1
    fi

    log "Setting up loop device $loop_dev for $image_path"
    if ! losetup "$loop_dev" "$image_path"; then
        log_error "Failed to set up loop device"
        return 1
    fi

    echo "$loop_dev"
    return 0
}

# -----------------------------------------------------------------------------
# mount_nixos_root - Mount NixOS root filesystem from image
# Sets NIXOS_ROOT_DEV to the loop device used
# -----------------------------------------------------------------------------
mount_nixos_root() {
    local nixroot="$1"

    log "Mounting NixOS from image: $NIXOS_IMAGE_PATH"

    # First ensure STORAGE is mounted
    if ! mountpoint -q /storage 2>/dev/null; then
        log "Mounting STORAGE partition first..."
        mkdir -p /storage
        if ! mount /dev/disk/by-label/STORAGE /storage -o rw,noatime; then
            log_error "Failed to mount STORAGE partition"
            return 1
        fi
    fi

    # Set up loop device for the image
    NIXOS_ROOT_DEV=$(setup_loop_device "$NIXOS_IMAGE_PATH")
    if [ -z "$NIXOS_ROOT_DEV" ]; then
        return 1
    fi

    # Mount the loop device
    log "Mounting NixOS image..."
    if ! mount -t ext4 -o rw,noatime,nodiratime "$NIXOS_ROOT_DEV" "$nixroot"; then
        log_error "Failed to mount NixOS image"
        losetup -d "$NIXOS_ROOT_DEV"
        return 1
    fi

    return 0
}

# -----------------------------------------------------------------------------
# boot_nixos - Main NixOS boot sequence
# -----------------------------------------------------------------------------
boot_nixos() {
    local nixroot="/nixroot"
    local kver
    local nixos_init

    log "Starting NixOS chain-boot sequence..."

    # Create mount point
    mkdir -p "$nixroot"

    # Mount NixOS root (handles both image and partition modes)
    if ! mount_nixos_root "$nixroot"; then
        log_error "Failed to mount NixOS root"
        return 1
    fi

    # Verify it looks like a NixOS root
    if [ ! -d "$nixroot/nix" ]; then
        log_error "Mounted filesystem does not appear to be NixOS (missing /nix)"
        umount "$nixroot"
        [ -n "$NIXOS_ROOT_DEV" ] && losetup -d "$NIXOS_ROOT_DEV" 2>/dev/null
        return 1
    fi

    log "NixOS root mounted successfully"

    # Create directories for ROCKNIX resources
    mkdir -p "$nixroot/rocknix/flash"
    mkdir -p "$nixroot/rocknix/sysroot"

    # Move ROCKNIX flash and sysroot to preserve them
    log "Preserving ROCKNIX resources..."
    if [ -d "/flash" ] && mountpoint -q /flash 2>/dev/null; then
        mount --move /flash "$nixroot/rocknix/flash" || {
            log_error "Failed to move /flash"
            # Non-fatal, continue
        }
    fi

    if [ -d "/sysroot" ] && mountpoint -q /sysroot 2>/dev/null; then
        mount --move /sysroot "$nixroot/rocknix/sysroot" || {
            log_error "Failed to move /sysroot"
            # Non-fatal, continue
        }
    fi

    # Get kernel version
    kver=$(uname -r)
    log "Kernel version: $kver"

    # Set up kernel modules bind-mount
    log "Setting up kernel modules bind-mount..."
    mkdir -p "$nixroot/lib/modules/$kver"

    local modules_src="$nixroot/rocknix/sysroot/usr/lib/kernel-overlays/base/lib/modules/$kver"
    if [ -d "$modules_src" ]; then
        mount --bind "$modules_src" "$nixroot/lib/modules/$kver" || {
            log_error "Failed to bind-mount kernel modules"
            # Try alternative path
            modules_src="$nixroot/rocknix/sysroot/lib/modules/$kver"
            if [ -d "$modules_src" ]; then
                mount --bind "$modules_src" "$nixroot/lib/modules/$kver"
            fi
        }
        log "Kernel modules mounted from: $modules_src"
    else
        log_error "Kernel modules not found at expected path"
        log_error "Tried: $modules_src"
        # List available to help debug
        log_debug "Available in kernel-overlays:"
        ls -la "$nixroot/rocknix/sysroot/usr/lib/kernel-overlays/base/lib/modules/" 2>/dev/null || true
    fi

    # Set up firmware bind-mount
    log "Setting up firmware bind-mount..."
    mkdir -p "$nixroot/lib/firmware"

    local firmware_src="$nixroot/rocknix/sysroot/usr/lib/kernel-overlays/base/lib/firmware"
    if [ -d "$firmware_src" ]; then
        mount --bind "$firmware_src" "$nixroot/lib/firmware" || {
            log_error "Failed to bind-mount firmware"
            # Try alternative path
            firmware_src="$nixroot/rocknix/sysroot/lib/firmware"
            if [ -d "$firmware_src" ]; then
                mount --bind "$firmware_src" "$nixroot/lib/firmware"
            fi
        }
        log "Firmware mounted from: $firmware_src"
    else
        log_error "Firmware not found at expected path"
    fi

    # Move STORAGE into NixOS (already mounted for image access)
    mkdir -p "$nixroot/rocknix/storage"
    if mountpoint -q /storage 2>/dev/null; then
        mount --move /storage "$nixroot/rocknix/storage" || {
            log_error "Failed to move /storage"
            # Try bind mount as fallback
            mount --bind /storage "$nixroot/rocknix/storage"
        }
    fi

    # Move virtual filesystems to new root
    log "Moving virtual filesystems..."
    for fs in dev proc sys run; do
        if [ -d "/$fs" ] && mountpoint -q "/$fs" 2>/dev/null; then
            mkdir -p "$nixroot/$fs"
            /usr/bin/busybox mount --move "/$fs" "$nixroot/$fs" || {
                log_error "Failed to move /$fs"
                # Try bind mount as fallback
                mount --bind "/$fs" "$nixroot/$fs"
            }
            log_debug "Moved /$fs to $nixroot/$fs"
        fi
    done

    # Find NixOS init
    log "Locating NixOS init..."
    nixos_init=$(find_nixos_init "$nixroot")

    if [ -z "$nixos_init" ]; then
        log_error "Could not find NixOS init/systemd!"
        log_error "Dropping to debug shell. Type 'exit' to reboot."
        exec /bin/sh
        return 1
    fi

    # Adjust path relative to new root
    local init_relative="${nixos_init#$nixroot}"
    log "Found NixOS init: $init_relative"

    # Final checks before switch_root
    log "Performing final checks..."
    log_debug "Root contents: $(ls -la $nixroot/ 2>/dev/null | head -10)"
    log_debug "Nix store exists: $([ -d $nixroot/nix/store ] && echo yes || echo no)"

    # Execute switch_root
    log "Executing switch_root to NixOS..."
    log "=============================================="

    # Use busybox switch_root
    exec /usr/bin/busybox switch_root "$nixroot" "$init_relative" --show-status=1 --unit=default.target

    # If we get here, switch_root failed
    log_error "switch_root failed!"
    return 1
}

# -----------------------------------------------------------------------------
# Main execution
# -----------------------------------------------------------------------------
main() {
    log "NixOS chain-boot hook starting..."

    # Load joypad module for button detection
    load_joypad_module

    # Check if we should boot NixOS
    if ! should_boot_nixos; then
        log_debug "No NixOS boot trigger detected, continuing ROCKNIX boot"
        # Let ROCKNIX continue its normal boot
        # The calling init script will proceed
        return 0
    fi

    # Check boot failsafe counter
    if ! check_boot_counter; then
        log "Boot failsafe triggered, continuing ROCKNIX boot"
        return 0
    fi

    # Attempt to boot NixOS
    if ! boot_nixos; then
        log_error "NixOS boot failed!"
        log_error "Dropping to emergency shell..."
        exec /bin/sh
    fi

    # Should never reach here
    log_error "Unexpected return from boot_nixos"
    exec /bin/sh
}

# Run main
main "$@"
