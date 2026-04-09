#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

ensure_root
require_tools
check_duts

log_header "finish check"

lsblk | tee -a "${LOG_DIR}/lsblk-Finish.log" >/dev/null
command -v lsscsi >/dev/null 2>&1 && lsscsi | tee -a "${LOG_DIR}/lsscsi-Finish.log" >/dev/null
dmesg | tee -a "${LOG_DIR}/dmesg-Finish.log" >/dev/null
dmesg | grep -i "err\\|fail\\|abort\\|timeout" | tee -a "${LOG_DIR}/dmesg-Errors.log" >/dev/null || true
command -v ipmitool >/dev/null 2>&1 && ipmitool sel list | tee -a "${LOG_DIR}/bmc-Finish.log" >/dev/null
command -v ipmitool >/dev/null 2>&1 && ipmitool sel list | grep -i "err\\|fail\\|abort\\|timeout" | tee -a "${LOG_DIR}/bmc-Errors.log" >/dev/null || true

for disk in "${DUTS[@]}"; do
  name="$(disk_name "$disk")"
  {
    echo "disk: $disk"
    echo "bdf: $(bdf_of_disk "$disk")"
    echo "slot: $(slot_of_disk "$disk")"
    nvme smart-log "$disk" || true
    smartctl -a "$disk" || true
  } | tee -a "${LOG_DIR}/${name}-Finish.log" >/dev/null
done

mount -a
for disk in "${DUTS[@]}"; do
  mp="$(mount_point "$disk")"
  rm -f "${mp}"/*.bin "${mp}"/*.md5 2>/dev/null || true
done
umount "${MOUNT_ROOT}"/* || true
