#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# 1. 保存并清空 dmesg（保留旧日志供参考，同时清空后续测试用）
dmesg > dmesg-before.log 2>/dev/null || true
dmesg -c &> /dev/null

# 2. 保存并清空 SEL
ipmitool sel list > sel-before.log 2>/dev/null || true
ipmitool sel clear &> /dev/null || true

# 3. 磁盘拓扑快照
echo "=== lsblk ===" > topology-before.log
lsblk >> topology-before.log 2>/dev/null || true

echo "" >> topology-before.log
echo "=== lsscsi ===" >> topology-before.log
lsscsi >> topology-before.log 2>/dev/null || true

echo "" >> topology-before.log
echo "=== nvme list ===" >> topology-before.log
nvme list >> topology-before.log 2>/dev/null || true

echo "" >> topology-before.log
echo "=== lspci -tv ===" >> topology-before.log
lspci -tv >> topology-before.log 2>/dev/null || true

echo "" >> topology-before.log
echo "=== fdisk -l ===" >> topology-before.log
fdisk -l >> topology-before.log 2>/dev/null || true

echo "" >> topology-before.log
echo "=== mount points ===" >> topology-before.log
mount | grep nvme >> topology-before.log 2>/dev/null || true

# 4. 盘 SMART 健康检查
for disk in $(list_dut_disks); do
    smartctl -a "$disk" | tee -a check-smart-start.txt
    smartctl -H "$disk" | tee -a check-smart-start.txt
done
