#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

ensure_root
require_tools
check_duts

log_header "fio start"

for disk in "${DUTS[@]}"; do
  name="$(disk_name "$disk")"
  fio --name="${name}_seq_mixed" \
    --filename="$(part2 "$disk")" \
    --ioengine=libaio \
    --direct=1 \
    --rw=readwrite \
    --bs="${FIO_BS}" \
    --numjobs=1 \
    --runtime="${FIO_RUNTIME}" \
    --time_based \
    --rwmixread="${FIO_RWMIXREAD}" \
    --group_reporting \
    --eta=never \
    --output="${LOG_DIR}/${name}-fio.log" &
done

sleep 10
jobs -l | tee -a "${LOG_DIR}/fio-pids.log" >/dev/null
