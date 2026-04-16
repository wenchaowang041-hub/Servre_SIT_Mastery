#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
cd "$SCRIPT_DIR"

CYCLES="${CYCLES:-10}"
PULL_WAIT_SECONDS="${PULL_WAIT_SECONDS:-30}"
INSERT_WAIT_SECONDS="${INSERT_WAIT_SECONDS:-6}"
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

    # 每轮启动 FIO 压力测试（后台运行，覆盖整轮拔插时间）
    # 单盘耗时 = 人工拔/插等待 + INSERT_WAIT + md5校验 + 交互缓冲 ~40s
    # FIO 需覆盖该轮所有盘的操作时间，额外留 60s 余量
    FIO_RUNTIME=$(( ${#dut_disks[@]} * (PULL_WAIT_SECONDS + INSERT_WAIT_SECONDS + 40) + 60 ))
    echo "[FIO] 本轮 FIO 压力测试启动，预计运行 ${FIO_RUNTIME}s"
    export FIO_RUNTIME
    bash "${SCRIPT_DIR}/fio-safe.sh" > "05-fio-loop${loop}.log" 2>&1 &
    sleep 5  # 等 FIO 进程稳定启动

    for disk in "${dut_disks[@]}"; do
        record_manual_state "loop ${loop} disk ${disk} start"

        pause_enter "Now you may PULL OUT ${disk}."
        record_manual_state "loop ${loop} operator pulled ${disk}"
        countdown "${PULL_WAIT_SECONDS}" "Pull wait"

        pause_enter "Now you may INSERT ${disk} slowly."
        record_manual_state "loop ${loop} operator inserted ${disk}"
        countdown "${INSERT_WAIT_SECONDS}" "Insert settle"

        step_run "Step 6: md5 check after reinsert (loop ${loop}, ${disk})" "${SCRIPT_DIR}/4-check-md5-safe.sh" "06-check-md5-loop${loop}-$(basename "${disk}").log"
        record_manual_state "loop ${loop} disk ${disk} md5 check finished"
    done

    # 本轮所有盘拔插完成，清理残留 FIO 进程
    echo "[FIO] 清理本轮 FIO 进程..."
    pkill -f "fio.*seq_mixed" 2>/dev/null || true
    sleep 2
    echo "[FIO] 本轮 FIO 已结束"
done

step_run "Step 7: final log check" "${SCRIPT_DIR}/5-check-log-safe.sh" "07-check-log.log"

echo
echo "All loops finished."
echo "Round logs saved in: ${ROUND_DIR}"
