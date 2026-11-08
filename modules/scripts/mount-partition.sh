#!/usr/bin/env bash
set -euo pipefail

: "${PARTITION_DEVICE:?PARTITION_DEVICE is required}"
: "${PARTITION_NAME:?PARTITION_NAME is required}"

# Optional values are passed as empty strings when not configured.
owner="${PARTITION_OWNER:-}"
group="${PARTITION_GROUP:-}"
permissions="${PARTITION_PERMISSIONS:-}"
explicit_path="${PARTITION_PATH:-}"
partition_name="$PARTITION_NAME"

device_name="$PARTITION_DEVICE"
state_file="/run/nixos-partition-${partition_name}.mountpoint"

case "$device_name" in
  /dev/*)
    device="$device_name"
    ;;
  *)
    device="/dev/$device_name"
    ;;
esac

# Resolve the default mountpoint at runtime so that an owner's actual home
# directory is used, rather than assuming /home/<name>.
if [[ -n "$explicit_path" ]]; then
  mountpoint_path="$explicit_path"
elif [[ -n "$owner" ]]; then
  home="$(getent passwd "$owner" | cut -d: -f6 || true)"

  if [[ -z "$home" ]]; then
    echo "Could not find the home directory for user: $owner" >&2
    exit 1
  fi

  mountpoint_path="$home/Partitions/$partition_name"
else
  mountpoint_path="/mnt/$partition_name"
fi

mkdir -p "$mountpoint_path"

# Do not try to mount over an already-mounted filesystem.
if mountpoint -q "$mountpoint_path"; then
  echo "Partition mountpoint already mounted: $mountpoint_path"
  exit 0
fi

# Wait briefly for the device to appear.
attempt=0
while [[ ! -b "$device" && "$attempt" -lt 10 ]]; do
  sleep 1
  attempt=$((attempt + 1))
done

if [[ ! -b "$device" ]]; then
  echo "Partition device is unavailable: $device" >&2
  exit 1
fi

# Discover filesystem metadata at runtime.
fs_type="$(blkid -p -s TYPE -o value "$device" 2>/dev/null || true)"
uuid="$(blkid -p -s UUID -o value "$device" 2>/dev/null || true)"

if [[ -z "$fs_type" ]]; then
  echo "Could not determine filesystem type for $device" >&2
  exit 1
fi

if [[ -n "$uuid" ]]; then
  echo "Detected filesystem type $fs_type and UUID $uuid on $device"
  source="UUID=$uuid"
else
  echo "Detected filesystem type $fs_type on $device (no UUID found)"
  source="$device"
fi

mount_options="rw"
synthetic_ownership=0

# These filesystems commonly represent ownership through mount options
# instead of storing normal Unix owner/group metadata.
case "$fs_type" in
  vfat|msdos|fat|exfat|ntfs|ntfs3|ntfs-3g|fuseblk)
    synthetic_ownership=1

    # Resolve the actual UID/GID at mount time, including automatically
    # allocated NixOS IDs.
    if [[ -n "$owner" ]]; then
      uid="$(id -u "$owner")"
      mount_options="$mount_options,uid=$uid"
    fi

    if [[ -n "$group" ]]; then
      group_entry="$(getent group "$group" || true)"
      gid="$(printf '%s' "$group_entry" | cut -d: -f3)"

      if [[ -z "$gid" ]]; then
        echo "Could not resolve GID for group: $group" >&2
        exit 1
      fi

      mount_options="$mount_options,gid=$gid"
    fi

    # FAT-family and NTFS-style filesystems use masks rather than chmod
    # for their directory permissions.
    if [[ -n "$permissions" ]]; then
      mode=$((8#$permissions))
      mask=$((0777 & ~mode))
      printf -v dmask '%03o' "$mask"
      mount_options="$mount_options,dmask=$dmask"
    fi
    ;;
esac

mounted=0

# NTFS is often identified by blkid as "ntfs", although the available
# mount implementation may be ntfs3 or ntfs-3g.
if [[ "$fs_type" == "ntfs" ]]; then
  if mount -t ntfs3 -o "$mount_options" "$source" "$mountpoint_path"; then
    mounted=1
  elif mount -t ntfs-3g -o "$mount_options" "$source" "$mountpoint_path"; then
    mounted=1
  fi
else
  if mount -t "$fs_type" -o "$mount_options" "$source" "$mountpoint_path"; then
    mounted=1
  fi
fi

if [[ "$mounted" -ne 1 ]]; then
  echo "Failed to mount $device at $mountpoint_path" >&2
  exit 1
fi

# Remember the actual mountpoint so the service can unmount it cleanly
# when it stops during shutdown.
printf '%s\n' "$mountpoint_path" > "$state_file"

metadata_failure() {
  echo "$1" >&2
  umount "$mountpoint_path" || true
  rm -f "$state_file" || true
  exit 1
}

if [[ "$synthetic_ownership" -eq 0 ]]; then
  # Native Linux filesystems store ownership in filesystem metadata.
  # Change only the attributes explicitly requested in the config.
  if [[ -n "$owner" && -n "$group" ]]; then
    chown "$owner:$group" "$mountpoint_path" \
      || metadata_failure "Could not set owner and group on $mountpoint_path"
  elif [[ -n "$owner" ]]; then
    chown "$owner" "$mountpoint_path" \
      || metadata_failure "Could not set owner on $mountpoint_path"
  elif [[ -n "$group" ]]; then
    chgrp "$group" "$mountpoint_path" \
      || metadata_failure "Could not set group on $mountpoint_path"
  fi

  if [[ -n "$permissions" ]]; then
    chmod "$permissions" "$mountpoint_path" \
      || metadata_failure "Could not set permissions on $mountpoint_path"
  fi
fi

echo "Mounted $device at $mountpoint_path successfully"
