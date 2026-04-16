#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
cd "$SCRIPT_DIR"

CYCLES="${CYCLES:-10}"
PULL_WAIT_SECONDS="${PULL_WAIT_SECONDS:-10}"
INSERT_WAIT_SECONDS="${INSERT_WAIT_SECONDS:-30}"
ROUND_NAME="${1:-$(date '+%F_%H%M%S')}"
LOG_ROOT="${LOG_ROOT:-$SCRIPT_DIR/runs}"
ROUND_DIR="${LOG_ROOT}/${ROUND_NAME}"

mkdir -p "$ROUND_DIR"
cd "$ROUND_DIR"

step_run() {
    local title="$1"
    local script_path="$2"
    local log_file="$3"
    echo
    echo "===== ${title} ====="
    echo "script: ${script_path}"
    bash "$script_path" | tee -a "$log_file"
}

pause_enter() {
    local prompt="$1"
    echo
    echo "$prompt"
    read -r -p "Press Enter to continue... " _
}

countdown() {
    local seconds="$1"
    local label="$2"
    while (( seconds > 0 )); do
        printf '\r%s: %2ds ' "$label" "$seconds"
        sleep 1
        ((seconds--))
    done
    printf '\r%s: done   \n' "$label"
}

record_manual_state() {
    local note="$1"
    printf '[%s] %s\n' "$(date '+%F %T')" "$note" | tee -a loop-record.txt
}

echo "round_name=${ROUND_NAME}" > round-meta.txt
echo "cycles=${CYCLES}" >> round-meta.txt
echo "pull_wait_seconds=${PULL_WAIT_SECONDS}" >> round-meta.txt
echo "insert_wait_seconds=${INSERT_WAIT_SECONDS}" >> round-meta.txt
echo "system_disk=$(get_system_disk || true)" >> round-meta.txt
echo "dut_disks=$(list_dut_disks | xargs)" >> round-meta.txt
echo "other_nvme_disks=$(list_non_dut_nvmes | xargs)" >> round-meta.txt

echo "Round directory: ${ROUND_DIR}"
echo "System disk excluded: $(get_system_disk || true)"
echo "DUT disks: $(list_dut_disks | xargs)"
echo "Other NVMe disks: $(list_non_dut_nvmes | xargs)"

pause_enter "Confirm the test environment is ready and /etc/fstab does not contain stale DUT entries."

step_run "Step 1: partition disks" "${SCRIPT_DIR}/1-fenqu-safe.sh" "01-fenqu.log"
step_run "Step 2: bind UUID and prepare mount points" "${SCRIPT_DIR}/UUID-safe.sh" "02-uuid.log"

echo
echo "Running mount -a to verify /etc/fstab..."
mount -a | tee -a "02-uuid.log"

step_run "Step 3: collect start logs" "${SCRIPT_DIR}/2-check-start-safe.sh" "03-check-start.log"
step_run "Step 4: create md5 source files and copy to p1" "${SCRIPT_DIR}/3-md5-safe.sh" "04-md5-create.log"

mapfile -t dut_disks < <(list_dut_disks)

for ((loop=1; loop<=CYCLES; loop++)); do
    echo
    echo "===== Hotplug loop ${loop}/${CYCLES} ====="

    # 1. 启动 FIO 压力测试
    # FIO 需覆盖：拔盘等待 + 检测超时 + MD5校验时间 + 余量
    FIO_RUNTIME=$(( PULL_WAIT_SECONDS + ${#dut_disks[@]} * (30 + 30) + 60 ))
    echo "[FIO] 启动压力测试，预计运行 ${FIO_RUNTIME}s"
    export FIO_RUNTIME
    bash "${SCRIPT_DIR}/fio-safe.sh" > "05-fio-loop${loop}.log" 2>&1 &
    sleep 5  # 等 FIO 进程稳定启动

    # 2. 提示拔所有盘
    record_manual_state "loop ${loop} batch pull start"
    pause_enter "Now you may PULL OUT all DUT disks: ${dut_disks[*]}."
    record_manual_state "loop ${loop} batch pull done"

    # 3. 等待一段时间
    countdown "${PULL_WAIT_SECONDS}" "Pull wait"

    # 4. 提示插回所有盘
    pause_enter "Now you may INSERT all DUT disks slowly."
    record_manual_state "loop ${loop} batch insert done"

    # 5. 等待并逐个检测所有盘已识别
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

    # 6. 执行一次 MD5 校验（4-check-md5-safe.sh 内部会遍历所有盘）
    step_run "Step 6: md5 check (loop ${loop})" "${SCRIPT_DIR}/4-check-md5-safe.sh" "06-check-md5-loop${loop}.log"
    record_manual_state "loop ${loop} all disks md5 check finished"

    # 7. 清理 FIO 进程
    echo "[FIO] 清理本轮 FIO 进程..."
    pkill -f "fio.*seq_mixed" 2>/dev/null || true
    sleep 2
    echo "[FIO] 本轮 FIO 已结束"
done

step_run "Step 7: final log check" "${SCRIPT_DIR}/5-check-log-safe.sh" "07-check-log.log"

echo
echo "All loops finished."
echo "Round logs saved in: ${ROUND_DIR}"
