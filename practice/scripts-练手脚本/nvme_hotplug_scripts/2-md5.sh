#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

ensure_root
require_tools
check_duts

log_header "md5 create"

mount -a
sleep 3
df -h | tee -a "${LOG_DIR}/df-Before-MD5.log" >/dev/null

for disk in "${DUTS[@]}"; do
  name="$(disk_name "$disk")"
  mp="$(mount_point "$disk")"
  src="${MD5_SRC_DIR}/${name}.bin"

  mkdir -p "$mp"
  mountpoint -q "$mp" || mount "$(part1 "$disk")" "$mp"

  dd if=/dev/urandom of="$src" bs=1M count=1000 status=progress
  sync
  md5sum "$src" | tee "${LOG_DIR}/${name}.md5src"
  cp "$src" "${mp}/${name}.bin"
  md5sum "${mp}/${name}.bin" | tee "${LOG_DIR}/${name}.md5disk"
done

sync
umount "${MOUNT_ROOT}"/* || true
