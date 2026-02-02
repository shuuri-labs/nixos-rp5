BTN_SELECT=314

# Load joypad module for button detection
insmod /sysroot/usr/lib/kernel-overlays/base/lib/modules/*/rocknix-joypad/rocknix-singleadc-joypad.ko

# REQUIRED: Mount storage (we replace ROCKNIX's default mount behavior)
mount_part "$disk" "/storage" "rw,noatime"

# SELECT for NixOS
if is_key_pressed $BTN_SELECT; then
  echo "[nixos] Setting up NixOS boot..."

  # Check if image exists
  if [ ! -f /storage/nixos.img ]; then
    echo "[nixos] ERROR: /storage/nixos.img not found!"
    ls -la /storage/
    sleep 30
  fi

  # Set up loop device with error checking
  echo "[nixos] Setting up loop device..."
  if ! losetup /dev/loop0 /storage/nixos.img; then
    echo "[nixos] ERROR: losetup failed!"
    sleep 30
  fi

  # Mount with error checking
  mkdir -p /nixos
  echo "[nixos] Mounting NixOS image..."
  if ! mount -t ext4 /dev/loop0 /nixos; then
    echo "[nixos] ERROR: mount failed!"
    echo "[nixos] Trying without -t ext4..."
    mount /dev/loop0 /nixos || echo "[nixos] mount still failed!"
    sleep 30
  fi

  # Verify mount worked
  echo "[nixos] Checking mount..."
  ls -la /nixos/
  if [ ! -d /nixos/nix ]; then
    echo "[nixos] ERROR: /nixos/nix not found after mount!"
    echo "[nixos] Mount info:"
    mount | grep nixos
    sleep 30
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

  # Debug: show what we're working with
  echo "[nixos] NixOS root contents:"
  ls -la /nixos/
  echo "[nixos] Nix profiles:"
  ls -la /nixos/nix/var/nix/profiles/ 2>/dev/null || echo "profiles not found"
  echo "[nixos] System profile target:"
  readlink -f /nixos/nix/var/nix/profiles/system 2>/dev/null || echo "system profile not found"

  SYSTEM_PATH=$(readlink -f /nixos/nix/var/nix/profiles/system)
  echo "[nixos] SYSTEM_PATH: $SYSTEM_PATH"

  if [ -d "$SYSTEM_PATH" ]; then
    echo "[nixos] System path contents:"
    ls -la "$SYSTEM_PATH/"
  fi

  # Try to find init or systemd
  echo "[nixos] Looking for init..."
  ls -la "$SYSTEM_PATH/init" 2>/dev/null || echo "init not found"
  ls -la "$SYSTEM_PATH/systemd" 2>/dev/null || echo "systemd link not found"

  echo "[nixos] Attempting switch_root to /bin/sh for debug..."
  echo "[nixos] Press enter to continue or wait 10 seconds..."
  sleep 10

  # Try shell first to verify switch_root works
  exec /usr/bin/busybox switch_root /nixos /bin/sh
fi
