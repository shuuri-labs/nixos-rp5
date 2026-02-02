BTN_SELECT=314

# Load joypad module for button detection
insmod /sysroot/usr/lib/kernel-overlays/base/lib/modules/*/rocknix-joypad/rocknix-singleadc-joypad.ko

# REQUIRED: Mount storage (we replace ROCKNIX's default mount behavior)
mount_part "$disk" "/storage" "rw,noatime"

# SELECT for NixOS
if is_key_pressed $BTN_SELECT; then
  echo "[nixos] Setting up NixOS boot..."

  # Verify storage is mounted
  echo "[nixos] Checking /storage mount..."
  mount | grep storage
  echo "[nixos] Contents of /storage:"
  ls -la /storage/ | head -20

  # Check if image exists
  if [ ! -f /storage/nixos.img ]; then
    echo "[nixos] ERROR: /storage/nixos.img not found!"
    echo "[nixos] Full /storage listing:"
    ls -la /storage/
    echo "[nixos] Waiting 60 seconds..."
    sleep 60
  else
    echo "[nixos] Found image: $(ls -lh /storage/nixos.img)"
  fi

  # Set up loop device - use loop1 since loop0 is used by ROCKNIX SYSTEM
  echo "[nixos] Setting up loop device (loop1)..."
  if ! losetup /dev/loop1 /storage/nixos.img; then
    echo "[nixos] ERROR: losetup loop1 failed, trying loop2..."
    if ! losetup /dev/loop2 /storage/nixos.img; then
      echo "[nixos] ERROR: losetup failed on loop1 and loop2!"
      losetup -a
      sleep 60
    fi
    LOOP_DEV=/dev/loop2
  else
    LOOP_DEV=/dev/loop1
  fi
  echo "[nixos] Using loop device: $LOOP_DEV"

  # Mount with error checking
  mkdir -p /nixos
  echo "[nixos] Mounting NixOS image..."
  mount -t ext4 $LOOP_DEV /nixos
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
    echo "[nixos] Loop devices:"
    losetup -a
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
  SYSTEM_PATH=$(readlink -f /nixos/nix/var/nix/profiles/system)
  echo "[nixos] System profile: $SYSTEM_PATH"

  if [ -z "$SYSTEM_PATH" ] || [ ! -d "$SYSTEM_PATH" ]; then
    echo "[nixos] ERROR: System profile not found!"
    echo "[nixos] Profiles dir:"
    ls -la /nixos/nix/var/nix/profiles/ 2>/dev/null || echo "no profiles dir"
    sleep 60
  fi

  # Use the init wrapper
  INIT_PATH="/nix/var/nix/profiles/system/init"
  echo "[nixos] Using init: $INIT_PATH"
  echo "[nixos] Init exists check:"
  ls -la /nixos$INIT_PATH 2>/dev/null || echo "init not found at $INIT_PATH"

  echo "[nixos] Executing switch_root in 5 seconds..."
  sleep 5

  exec /usr/bin/busybox switch_root /nixos $INIT_PATH
fi
