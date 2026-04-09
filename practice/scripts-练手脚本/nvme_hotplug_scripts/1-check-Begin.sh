#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

ensure_root
require_tools
check_duts

log_header "begin check"

lsblk | tee -a "${LOG_DIR}/lsblk-Begin.log" >/dev/null
command -v lsscsi >/dev/null 2>&1 && lsscsi | tee -a "${LOG_DIR}/lsscsi-Begin.log" >/dev/null
dmesg -C
command -v ipmitool >/dev/null 2>&1 && ipmitool sel clear >/dev/null

for disk in "${DUTS[@]}"; do
  name="$(disk_name "$disk")"
  bdf="$(bdf_of_disk "$disk")"
  {
    echo "disk: $disk"
    echo "bdf: $bdf"
    echo "slot: $(slot_of_disk "$disk")"
    lspci -s "$bdf" -vvv | grep -i "LnkSta:\|Speed" || true
    nvme list | grep -F "$disk" || true
    nvme smart-log "$disk" || true
    smartctl -a "$disk" || true
  } | tee -a "${LOG_DIR}/${name}-Begin.log" >/dev/null
done
