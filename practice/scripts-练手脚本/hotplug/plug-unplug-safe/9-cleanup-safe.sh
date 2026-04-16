#!/bin/bash
#===============================================================================
# 清理 NVMe 热插拔测试残留
# 功能：卸载所有测试盘 → 清除分区表 → 清理 fstab → 清理 udev 规则
#===============================================================================

set -euo pipefail

# 系统盘（不被清理）
SYSTEM_DISK="/dev/nvme5n1"

echo "=== NVMe 测试环境清理 ==="
echo "系统盘(跳过): $SYSTEM_DISK"
echo ""

# 1. 卸载所有 nvme 挂载点
echo "[1] 卸载挂载点..."
for mp in $(mount | awk '$1 ~ /nvme[0-9]+n1p[0-9]+/ {print $3}' | tac); do
    echo "  umount $mp"
    umount "$mp" 2>/dev/null || true
done

# 2. 清理 fstab 中的 nvme 条目
echo "[2] 清理 /etc/fstab..."
FSTAB_BACKUP="/etc/fstab.bak.$(date +%Y%m%d)"
if grep -q "nvme" /etc/fstab; then
    cp /etc/fstab "$FSTAB_BACKUP"
    echo "  备份: $FSTAB_BACKUP"
    sed -i '/nvme.*nvme/d' /etc/fstab
    sed -i '/nvme.*UUID/d' /etc/fstab
    sed -i '/nvme.*ext4/d' /etc/fstab
    echo "  已移除 fstab 中的 nvme 条目"
else
    echo "  fstab 无 nvme 条目"
fi

# 3. 清除所有非系统盘的分区表
echo "[3] 清除分区表..."
for dev in /dev/nvme*n1; do
    [ -b "$dev" ] || continue
    [[ "$dev" == "$SYSTEM_DISK" ]] && echo "  跳过系统盘: $dev" && continue

    echo "  清理: $dev"

    # 方法1: sgdisk (最干净)
    if command -v sgdisk >/dev/null 2>&1; then
        sgdisk --zap-all "$dev" 2>/dev/null || true
    fi

    # 方法2: wipefs (清除签名)
    if command -v wipefs >/dev/null 2>&1; then
        wipefs -a "$dev" 2>/dev/null || true
        wipefs -a "${dev}p1" 2>/dev/null || true
        wipefs -a "${dev}p2" 2>/dev/null || true
    fi

    # 方法3: dd 清零前 10MB (兜底)
    dd if=/dev/zero of="$dev" bs=1M count=10 status=none 2>/dev/null || true
done

# 4. 重新扫描 NVMe 设备
echo "[4] 重新扫描 NVMe 总线..."
for ctrl in /sys/class/nvme/nvme*/; do
    [ -d "$ctrl" ] || continue
    echo 1 > "${ctrl}rescan" 2>/dev/null || true
done
sleep 3

# 5. 验证
echo ""
echo "=== 清理结果 ==="
echo ""
echo "--- lsblk ---"
lsblk
echo ""
echo "--- fstab 中的 nvme 条目 ---"
grep nvme /etc/fstab 2>/dev/null || echo "  无 (已清空)"
echo ""
echo "清理完成！"
