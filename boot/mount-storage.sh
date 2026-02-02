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

  # Find NixOS systemd and switch root
  NIXOS_INIT=$(find /nixos/nix/var/nix/profiles/system -name "systemd" -path "*/lib/systemd/*" -type f 2>/dev/null | head -1)
  if [ -z "$NIXOS_INIT" ]; then
    NIXOS_INIT=$(find /nixos/nix/store -maxdepth 4 -name "systemd" -path "*/lib/systemd/*" -type f 2>/dev/null | head -1)
  fi

  exec /usr/bin/busybox switch_root /nixos $NIXOS_INIT --show-status=1 --unit=default.target
fi
