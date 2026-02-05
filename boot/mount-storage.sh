BTN_SELECT=314

# Load joypad module for button detection
insmod /sysroot/usr/lib/kernel-overlays/base/lib/modules/*/rocknix-joypad/rocknix-singleadc-joypad.ko

# REQUIRED: Mount storage (we replace ROCKNIX's default mount behavior)
mount_part "$disk" "/storage" "rw,noatime"

# SELECT for NixOS
if is_key_pressed $BTN_SELECT; then
  echo "[nixos] Setting up NixOS boot..."

  # Find NIXOSROOT partition (p3 - p2 is STORAGE which ROCKNIX expects)
  echo "[nixos] Looking for NIXOSROOT partition..."
  NIXOSROOT_DEV=""

  # Try by label first, then common device paths
  for part in /dev/disk/by-label/NIXOSROOT /dev/mmcblk0p3 /dev/sda3; do
    if [ -b "$part" ]; then
      NIXOSROOT_DEV="$part"
      echo "[nixos] Found NIXOSROOT at: $NIXOSROOT_DEV"
      break
    fi
  done

  if [ -z "$NIXOSROOT_DEV" ]; then
    echo "[nixos] ERROR: NIXOSROOT partition not found!"
    echo "[nixos] Available partitions:"
    ls -l /dev/mmcblk0* /dev/sda* 2>/dev/null || true
    echo "[nixos] Waiting 60 seconds..."
    sleep 60
  fi

  # Mount NIXOSROOT directly (no loop device needed)
  mkdir -p /nixos
  echo "[nixos] Mounting NIXOSROOT partition..."
  mount -t ext4 "$NIXOSROOT_DEV" /nixos
  MOUNT_RESULT=$?
  echo "[nixos] mount exit code: $MOUNT_RESULT"

  if [ $MOUNT_RESULT -ne 0 ]; then
    echo "[nixos] ERROR: mount failed with code $MOUNT_RESULT"
    echo "[nixos] dmesg tail:"
    dmesg | tail -20
    echo "[nixos] Waiting 60 seconds..."
    sleep 60
  fi

  # Verify mount worked
  echo "[nixos] Checking mount result..."
  echo "[nixos] /nixos contents:"
  ls -la /nixos/

  if [ ! -d /nixos/nix ]; then
    echo "[nixos] ERROR: /nixos/nix not found after mount!"
    echo "[nixos] Mount table:"
    mount
    echo "[nixos] Waiting 60 seconds to read output..."
    sleep 60
  else
    echo "[nixos] SUCCESS: /nixos/nix exists!"
    ls -la /nixos/nix/
  fi

  # Move ROCKNIX mounts to storage
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

  # Find and exec NixOS init
  echo "[nixos] Looking for NixOS init..."
  echo "[nixos] Checking profiles directory..."
  ls -la /nixos/nix/var/nix/ 2>/dev/null || echo "ERROR: /nixos/nix/var/nix doesn't exist!"
  echo ""
  echo "[nixos] Profiles directory contents:"
  ls -la /nixos/nix/var/nix/profiles/ 2>/dev/null || echo "ERROR: profiles directory doesn't exist!"
  echo ""

  # Try to find system profile
  SYSTEM_PATH=$(readlink -f /nixos/nix/var/nix/profiles/system 2>/dev/null)
  echo "[nixos] System profile symlink target: $SYSTEM_PATH"

  if [ -z "$SYSTEM_PATH" ] || [ ! -d "$SYSTEM_PATH" ]; then
    echo "[nixos] ERROR: System profile not found or invalid!"
    echo "[nixos] This means nixos-install did not complete successfully"
    echo ""
    echo "[nixos] Diagnostic information:"
    echo "[nixos] /nixos/nix structure:"
    find /nixos/nix -maxdepth 3 -type d 2>/dev/null | head -20
    echo ""
    echo "[nixos] Looking for system closures in /nixos/nix/store:"
    ls -d /nixos/nix/store/*nixos-system* 2>/dev/null | head -5 || echo "No system closures found!"
    echo ""
    echo "[nixos] BOOT FAILED - Dropping to emergency shell in 10 seconds..."
    sleep 10
    exec /bin/sh
  fi

  # Use the init wrapper
  INIT_PATH="/nix/var/nix/profiles/system/init"
  echo "[nixos] Using init: $INIT_PATH"

  if [ ! -f "/nixos$INIT_PATH" ]; then
    echo "[nixos] ERROR: Init not found at /nixos$INIT_PATH"
    echo "[nixos] System path contents:"
    ls -la "$SYSTEM_PATH/" 2>/dev/null
    echo ""
    echo "[nixos] BOOT FAILED - Dropping to emergency shell in 10 seconds..."
    sleep 10
    exec /bin/sh
  fi

  echo "[nixos] Init found! Executing switch_root in 3 seconds..."
  sleep 3

  exec /usr/bin/busybox switch_root /nixos $INIT_PATH
fi
