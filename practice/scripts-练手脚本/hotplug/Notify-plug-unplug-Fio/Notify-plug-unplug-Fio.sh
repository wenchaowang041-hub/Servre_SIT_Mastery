#!/bin/bash
#===============================================================================
# 通知式 NVMe 热插拔测试（PCI 插槽电源控制）
# 流程：
#   分区 → UUID → 预采集日志 → MD5源文件
#   循环N轮：FIO→提示拔盘→等待→提示插回→检测识别→MD5校验→清FIO
#   最终日志采集
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYCLES="${CYCLES:-10}"
PULL_WAIT_SECONDS="${PULL_WAIT_SECONDS:-30}"
DISK_DETECT_TIMEOUT="${DISK_DETECT_TIMEOUT:-30}"
ROUND_NAME="${1:-$(date '+%F_%H%M%S')}"
LOG_ROOT="${LOG_ROOT:-${SCRIPT_DIR}/runs}"
ROUND_DIR="${LOG_ROOT}/${ROUND_NAME}"

# 系统盘（排除）
SYSTEM_DISK="/dev/nvme5n1"

mkdir -p "$ROUND_DIR"
cd "$ROUND_DIR"

step_run() {
    local title="$1"
    local script_path="$2"
    local log_file="$3"
    echo
    echo "===== ${title} ====="
    echo "script: ${script_path}"
    bash "$script_path" 2>&1 | tee -a "$log_file"
}

record_manual_state() {
    local note="$1"
    printf '[%s] %s\n' "$(date '+%F %T')" "$note" | tee -a loop-record.txt
}

# 获取所有非系统盘的 DUT NVMe 设备
get_dut_disks() {
    for dev in /dev/nvme*n1; do
        [ -b "$dev" ] || continue
        [[ "$dev" == "$SYSTEM_DISK" ]] && continue
        echo "$dev"
    done
}

# 等待系统识别到 NVMe 设备（轮询检测，超时兜底）
wait_for_disk() {
    local disk="$1"
    local timeout="${2:-$DISK_DETECT_TIMEOUT}"
    local elapsed=0

    while (( elapsed < timeout )); do
        if [ -b "${disk}" ] && [ -b "${disk}p1" ] && [ -b "${disk}p2" ]; then
            if (( elapsed <= 1 )); then
                echo "[OK] ${disk} 已识别"
            else
                echo "[OK] ${disk} 已识别，耗时 ${elapsed}s"
            fi
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    echo "[FAIL] ${disk} 在 ${timeout}s 内未被系统识别"
    return 1
}

# 注：软件断电功能已跳过，不同平台 slot address 匹配逻辑不同不可靠
# 纯靠物理拔插 + 设备检测
slot_of_disk() {
    echo ""
}

echo "round_name=${ROUND_NAME}" > round-meta.txt
echo "cycles=${CYCLES}" >> round-meta.txt
echo "pull_wait_seconds=${PULL_WAIT_SECONDS}" >> round-meta.txt
echo "system_disk=${SYSTEM_DISK}" >> round-meta.txt

echo "=== 通知式 NVMe 热插拔测试 ==="
echo "Round directory: ${ROUND_DIR}"
echo ""

# 获取所有 DUT 盘
mapfile -t dut_disks < <(get_dut_disks)
echo "DUT disks: ${dut_disks[*]}"
echo ""

# Step 1: 分区
step_run "Step 1: partition disks" "${SCRIPT_DIR}/1-fenqu.sh" "01-fenqu.log"

# Step 2: UUID 绑定
step_run "Step 2: bind UUID" "${SCRIPT_DIR}/UUID.sh" "02-uuid.log"

echo "Running mount -a to verify /etc/fstab..."
mount -a | tee -a "02-uuid.log"

# Step 3: 预采集日志
step_run "Step 3: collect start logs" "${SCRIPT_DIR}/2-check-start.sh" "03-check-start.log"

# Step 4: MD5 源文件
step_run "Step 4: create md5 source files" "${SCRIPT_DIR}/3-md5.sh" "04-md5-create.log"

for ((loop=1; loop<=CYCLES; loop++)); do
    echo
    echo "===== 热插拔循环 ${loop}/${CYCLES} ====="

    # 1. 启动 FIO 压力测试
    FIO_RUNTIME=$(( PULL_WAIT_SECONDS + ${#dut_disks[@]} * 30 + 60 ))
    echo "[FIO] 启动压力测试，预计运行 ${FIO_RUNTIME}s"
    export FIO_RUNTIME
    bash "${SCRIPT_DIR}/fio.sh" > "05-fio-loop${loop}.log" 2>&1 &
    sleep 5

    # 2. 提示拔出所有盘
    echo "[提示] 请拔出所有硬盘，按 Enter 确认..."
    read -r -p "" _
    record_manual_state "loop ${loop} batch pull done"

    # 3. 等待
    seconds=$PULL_WAIT_SECONDS
    while (( seconds > 0 )); do
        printf '\r等待: %2ds ' "$seconds"
        sleep 1
        ((seconds--))
    done
    printf '\r等待: done   \n'

    # 4. 提示插回
    echo "[提示] 请插入所有硬盘，按 Enter 确认..."
    read -r -p "" _
    record_manual_state "loop ${loop} physical reinsert done"

    # 5. 轮询检测所有盘已识别
    echo "[检测] 等待所有盘被系统识别..."
    all_detected=true
    for disk in "${dut_disks[@]}"; do
        if ! wait_for_disk "${disk}"; then
            all_detected=false
        fi
    done
    if ! $all_detected; then
        echo "[警告] 部分盘未被识别，但继续执行后续步骤"
    fi

    # 6. MD5 校验
    step_run "Step 6: md5 check (loop ${loop})" "${SCRIPT_DIR}/4-check-md5.sh" "06-check-md5-loop${loop}.log"
    record_manual_state "loop ${loop} all disks md5 check finished"

    # 7. 清理 FIO 进程
    echo "[FIO] 清理本轮 FIO 进程..."
    pkill -f "fio.*seq_mixed" 2>/dev/null || true
    sleep 2
    echo "[FIO] 本轮 FIO 已结束"
done

# Step 7: 最终日志采集
step_run "Step 7: final log check" "${SCRIPT_DIR}/5-check-log.sh" "07-check-log.log"

echo
echo "所有循环执行完毕。"
echo "Round logs saved in: ${ROUND_DIR}"
