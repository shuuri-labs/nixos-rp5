#!/bin/sh
# NixOS Chain-Boot Hook for ROCKNIX
# Based on arch-through-rocknix by Mash0Star
#
# Place on ROCKNIX boot partition as mount-storage.sh
# Hold SELECT during boot to start NixOS

BTN_SELECT=314

# Load joypad module (needed for button detection on some devices)
insmod /sysroot/usr/lib/kernel-overlays/base/lib/modules/*/rocknix-joypad/rocknix-singleadc-joypad.ko 2>/dev/null

# SELECT for NixOS
if is_key_pressed $BTN_SELECT; then
  echo "[nixos] SELECT pressed - booting NixOS..."

  # Loop-mount NixOS image
  losetup /dev/loop0 /storage/nixos.img
  mkdir -p /nixos
  mount -t ext4 /dev/loop0 /nixos

  # Verify NixOS root
  if [ ! -d /nixos/nix ]; then
    echo "[nixos] ERROR: /nixos/nix not found, aborting"
    umount /nixos
    losetup -d /dev/loop0
  else
    # Move ROCKNIX flash and sysroot into storage
    for f in flash sysroot; do
      mkdir -p /storage/$f
      mount --move /$f /storage/$f
    done

    # Bind-mount kernel modules and firmware from ROCKNIX
    mkdir -p /nixos/lib/modules /nixos/lib/firmware
    mount --bind /storage/sysroot/usr/lib/kernel-overlays/base/lib/modules /nixos/lib/modules
    mount --bind /storage/sysroot/usr/lib/kernel-overlays/base/lib/firmware /nixos/lib/firmware

    # Move storage into NixOS
    mkdir -p /nixos/rocknix/storage
    mount --move /storage /nixos/rocknix/storage

    # Move virtual filesystems
    for f in run dev proc sys; do
      mkdir -p /nixos/$f
      /usr/bin/busybox mount --move /$f /nixos/$f
    done

    # Find and exec NixOS systemd
    NIXOS_INIT=$(find /nixos/nix/var/nix/profiles/system -name "systemd" -path "*/lib/systemd/*" -type f 2>/dev/null | head -1)
    if [ -z "$NIXOS_INIT" ]; then
      NIXOS_INIT=$(find /nixos/nix/store -maxdepth 4 -name "systemd" -path "*/lib/systemd/*" -type f 2>/dev/null | head -1)
    fi

    echo "[nixos] Starting: $NIXOS_INIT"
    exec /usr/bin/busybox switch_root /nixos $NIXOS_INIT --show-status=1 --unit=default.target
  fi
fi
