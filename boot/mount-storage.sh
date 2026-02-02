BTN_SELECT=314

# Load joypad module for button detection
insmod /sysroot/usr/lib/kernel-overlays/base/lib/modules/*/rocknix-joypad/rocknix-singleadc-joypad.ko

# REQUIRED: Mount storage (we replace ROCKNIX's default mount behavior)
mount_part "$disk" "/storage" "rw,noatime"

# SELECT for NixOS
if is_key_pressed $BTN_SELECT; then
  # Set up NixOS image via loop device
  losetup /dev/loop0 /storage/nixos.img
  mkdir -p /nixos
  mount -t ext4 /dev/loop0 /nixos

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

  # Resolve the actual systemd binary path (follow symlinks before switch_root)
  SYSTEM_PATH=$(readlink -f /nixos/nix/var/nix/profiles/system)
  # Remove /nixos prefix to get path relative to new root
  SYSTEM_REL=${SYSTEM_PATH#/nixos}
  SYSTEMD_PATH="$SYSTEM_REL/systemd/lib/systemd/systemd"

  exec /usr/bin/busybox switch_root /nixos $SYSTEMD_PATH --system --show-status=1
fi
