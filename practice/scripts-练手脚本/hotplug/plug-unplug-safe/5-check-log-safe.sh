#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

lsblk | tee -a lsblk-Finish.log >> /dev/null

# 测试后拓扑快照（和开始时对比）
echo "=== lsscsi ===" > topology-after.log
command -v lsscsi >/dev/null 2>&1 && lsscsi >> topology-after.log 2>/dev/null || true

echo "" >> topology-after.log
echo "=== nvme list ===" >> topology-after.log
nvme list >> topology-after.log 2>/dev/null || true

echo "" >> topology-after.log
echo "=== lspci -tv ===" >> topology-after.log
lspci -tv >> topology-after.log 2>/dev/null || true

echo "" >> topology-after.log
echo "=== lsblk ===" >> topology-after.log
lsblk >> topology-after.log 2>/dev/null || true

echo "" >> topology-after.log
echo "=== mount points ===" >> topology-after.log
mount | grep nvme >> topology-after.log 2>/dev/null || true

# dmesg 采集 + 错误提取
dmesg > dmesg-Finish.log 2>/dev/null || true
echo "=== dmesg errors ==="
dmesg | grep -iE "error|fail|aer|fatal" || true

# SEL 采集 + 错误提取
echo "=== SEL errors ==="
ipmitool sel list | grep -iE "err|failed|fault|critical" || true
ipmitool sel list > bmc-Finish.log 2>/dev/null || true

for disk in $(list_dut_disks); do
    smartctl -a "$disk" | tee -a smartctl-Finish.log >> /dev/null
    smartctl -H "$disk" | tee -a smartctl-H-Finish.log >> /dev/null
    smartctl -H "$disk" | grep overall-health | grep -v "PASSED" || true
done

mount -a || true
rm -rf /mnt/nvme*/* 2>/dev/null || true
umount /mnt/nvme* 2>/dev/null || true
