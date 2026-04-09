#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

ensure_root
require_tools
check_duts

log_header "md5 verify"

sleep 6
mount -a

for disk in "${DUTS[@]}"; do
  name="$(disk_name "$disk")"
  mp="$(mount_point "$disk")"
  mountpoint -q "$mp" || mount "$(part1 "$disk")" "$mp"

  {
    echo "disk: $disk"
    nvme list | grep -F "$disk" || true
    nvme smart-log "$disk" || true
    smartctl -a "$disk" || true
    diff -u "${LOG_DIR}/${name}.md5src" <(md5sum "${mp}/${name}.bin")
  } | tee -a "${LOG_DIR}/${name}-check-md5.log"
done

dmesg | tail -200 | tee -a "${LOG_DIR}/dmesg-After-Reinsert.log" >/dev/null
command -v ipmitool >/dev/null 2>&1 && ipmitool sel list | tee -a "${LOG_DIR}/bmc-After-Reinsert.log" >/dev/null

umount "${MOUNT_ROOT}"/* || true
