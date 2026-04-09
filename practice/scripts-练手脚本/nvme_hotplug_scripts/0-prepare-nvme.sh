#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

ensure_root
require_tools
check_duts

log_header "prepare start"

for disk in "${DUTS[@]}"; do
  name="$(disk_name "$disk")"
  mp="$(mount_point "$disk")"
  mkdir -p "$mp"

  if findmnt -rn -S "$disk" >/dev/null 2>&1; then
    echo "disk has mounted filesystem, stop and verify manually: $disk" >&2
    exit 1
  fi

  cat <<EOF | tee -a "${LOG_DIR}/prepare.log"
disk: $disk
bdf: $(bdf_of_disk "$disk")
slot: $(slot_of_disk "$disk")
EOF

  parted -s "$disk" mklabel gpt
  parted -s "$disk" mkpart primary ext4 1MiB 10GiB
  parted -s "$disk" mkpart primary 10GiB 100%
  mkfs.ext4 -F "$(part1 "$disk")"

  uuid="$(blkid -s UUID -o value "$(part1 "$disk")")"
  grep -vF "$uuid" /etc/fstab > /tmp/fstab.nvme_hotplug.$$ || true
  cat /tmp/fstab.nvme_hotplug.$$ > /etc/fstab
  rm -f /tmp/fstab.nvme_hotplug.$$
  echo "UUID=${uuid} ${mp} ext4 defaults,nofail 0 0" >> /etc/fstab
done

mount -a
df -h | tee -a "${LOG_DIR}/prepare.log" >/dev/null
umount "${MOUNT_ROOT}"/* || true

log_header "prepare finish"
