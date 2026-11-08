#!/usr/bin/env bash
set -euo pipefail

: "${PARTITION_NAME:?PARTITION_NAME is required}"

state_file="/run/nixos-partition-${PARTITION_NAME}.mountpoint"

if [[ ! -r "$state_file" ]]; then
  exit 0
fi

mountpoint_path="$(cat "$state_file")"

if [[ -n "$mountpoint_path" ]] && mountpoint -q "$mountpoint_path"; then
  if ! umount "$mountpoint_path"; then
    echo "Failed to unmount $mountpoint_path" >&2
    exit 1
  fi
fi

rm -f "$state_file"

echo "Partition ${PARTITION_NAME} unmounted successfully"
