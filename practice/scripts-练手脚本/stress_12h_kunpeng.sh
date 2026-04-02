#!/usr/bin/env bash

set -euo pipefail

DURATION_SECONDS=$((12 * 60 * 60))
CPU_WORKERS=256
VM_WORKERS=8
VM_BYTES="8G"
IO_WORKERS=0
HDD_WORKERS=0
LOG_DIR="./stress-ng-12h-$(date +%F-%H%M%S)"
SENSOR_INTERVAL=300

usage() {
  cat <<'EOF'
用法:
  bash stress_12h_kunpeng.sh [选项]

选项:
  --hours 12              压力测试时长，单位小时
  --minutes 10            压力测试时长，单位分钟
  --cpu 256               CPU 压力线程数
  --vm 8                  内存压力 worker 数
  --vm-bytes 8G           每个内存 worker 占用量
  --io 0                  IO worker 数
  --hdd 0                 HDD worker 数
  --sensor-interval 300   监控采样间隔，单位秒
  --log-dir DIR           日志目录
  -h, --help              显示帮助

说明:
  1. 依赖 stress-ng，不依赖 stress
  2. 默认适配 256 线程 Kunpeng 920 环境
  3. 默认 CPU 满载，内存压力总量为 8 * 8G = 64G
  4. 默认不跑磁盘 IO 压力，避免误伤业务盘
  5. 运行期间会采集 uptime、free、mpstat、top、ipmitool sensor
EOF
}

log() {
  echo "[$(date '+%F %T')] $*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令: $1" >&2
    exit 1
  fi
}

write_diff_file() {
  local before_file="$1"
  local after_file="$2"
  local out_file="$3"
  local title="$4"

  {
    echo "# $title"
    echo
    echo "before=$before_file"
    echo "after=$after_file"
    echo
    if [[ -f "$before_file" && -f "$after_file" ]]; then
      if command -v diff >/dev/null 2>&1; then
        diff -u "$before_file" "$after_file" || true
      else
        echo "系统缺少 diff 命令，无法生成标准差异。"
      fi
    else
      echo "缺少对比文件，无法生成差异。"
    fi
  } > "$out_file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hours)
      DURATION_SECONDS=$(("${2:-12}" * 60 * 60))
      shift 2
      ;;
    --minutes)
      DURATION_SECONDS=$(("${2:-10}" * 60))
      shift 2
      ;;
    --cpu)
      CPU_WORKERS="${2:-256}"
      shift 2
      ;;
    --vm)
      VM_WORKERS="${2:-8}"
      shift 2
      ;;
    --vm-bytes)
      VM_BYTES="${2:-8G}"
      shift 2
      ;;
    --io)
      IO_WORKERS="${2:-0}"
      shift 2
      ;;
    --hdd)
      HDD_WORKERS="${2:-0}"
      shift 2
      ;;
    --sensor-interval)
      SENSOR_INTERVAL="${2:-300}"
      shift 2
      ;;
    --log-dir)
      LOG_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd stress-ng
require_cmd lscpu
require_cmd free
require_cmd uptime
require_cmd date

mkdir -p "$LOG_DIR"

START_TIME="$(date '+%F %T')"
END_EPOCH=$(( $(date +%s) + DURATION_SECONDS ))

{
  echo "start_time=$START_TIME"
  echo "duration_seconds=$DURATION_SECONDS"
  echo "cpu_workers=$CPU_WORKERS"
  echo "vm_workers=$VM_WORKERS"
  echo "vm_bytes=$VM_BYTES"
  echo "io_workers=$IO_WORKERS"
  echo "hdd_workers=$HDD_WORKERS"
  echo "sensor_interval=$SENSOR_INTERVAL"
} | tee "$LOG_DIR/test-meta.txt"

lscpu > "$LOG_DIR/lscpu-before.txt"
free -h > "$LOG_DIR/free-before.txt"
uptime > "$LOG_DIR/uptime-before.txt"

if command -v ipmitool >/dev/null 2>&1; then
  ipmitool sensor list > "$LOG_DIR/ipmitool-sensor-before.txt" 2>&1 || true
  ipmitool sel list > "$LOG_DIR/ipmitool-sel-before.txt" 2>&1 || true
fi

if command -v dmesg >/dev/null 2>&1; then
  dmesg -T > "$LOG_DIR/dmesg-before.txt" 2>&1 || true
fi

monitor_loop() {
  while [[ "$(date +%s)" -lt "$END_EPOCH" ]]; do
    NOW_TAG="$(date +%F-%H%M%S)"

    {
      echo "===== $NOW_TAG ====="
      uptime
      free -h
      if command -v mpstat >/dev/null 2>&1; then
        mpstat -P ALL 1 1
      fi
      if command -v top >/dev/null 2>&1; then
        top -b -n 1 | head -n 40
      fi
    } >> "$LOG_DIR/runtime-status.log" 2>&1

    if command -v ipmitool >/dev/null 2>&1; then
      ipmitool sensor list > "$LOG_DIR/sensor-$NOW_TAG.txt" 2>&1 || true
    fi

    sleep "$SENSOR_INTERVAL"
  done
}

log "开始采集后台监控日志"
monitor_loop &
MONITOR_PID=$!

cleanup() {
  if kill -0 "$MONITOR_PID" >/dev/null 2>&1; then
    kill "$MONITOR_PID" >/dev/null 2>&1 || true
    wait "$MONITOR_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT

log "开始执行 12 小时 stress-ng 压力测试"
log "CPU worker=$CPU_WORKERS, VM worker=$VM_WORKERS, VM bytes=$VM_BYTES, IO worker=$IO_WORKERS, HDD worker=$HDD_WORKERS"

stress-ng \
  --cpu "$CPU_WORKERS" \
  --vm "$VM_WORKERS" \
  --vm-bytes "$VM_BYTES" \
  --io "$IO_WORKERS" \
  --hdd "$HDD_WORKERS" \
  --timeout "${DURATION_SECONDS}s" \
  --metrics-brief \
  --times \
  --tz \
  --verify 2>&1 | tee "$LOG_DIR/stress-ng.log"

log "压力测试执行完成，开始采集结束信息"

free -h > "$LOG_DIR/free-after.txt"
uptime > "$LOG_DIR/uptime-after.txt"

if command -v ipmitool >/dev/null 2>&1; then
  ipmitool sensor list > "$LOG_DIR/ipmitool-sensor-after.txt" 2>&1 || true
  ipmitool sel list > "$LOG_DIR/ipmitool-sel-after.txt" 2>&1 || true
fi

if command -v dmesg >/dev/null 2>&1; then
  dmesg -T > "$LOG_DIR/dmesg-after.txt" 2>&1 || true
fi

if command -v ipmitool >/dev/null 2>&1; then
  write_diff_file \
    "$LOG_DIR/ipmitool-sensor-before.txt" \
    "$LOG_DIR/ipmitool-sensor-after.txt" \
    "$LOG_DIR/ipmitool-sensor-diff.txt" \
    "ipmitool sensor 前后对比"

  write_diff_file \
    "$LOG_DIR/ipmitool-sel-before.txt" \
    "$LOG_DIR/ipmitool-sel-after.txt" \
    "$LOG_DIR/ipmitool-sel-diff.txt" \
    "ipmitool SEL 前后对比"
fi

if command -v dmesg >/dev/null 2>&1; then
  write_diff_file \
    "$LOG_DIR/dmesg-before.txt" \
    "$LOG_DIR/dmesg-after.txt" \
    "$LOG_DIR/dmesg-diff.txt" \
    "dmesg 前后对比"
fi

cleanup

log "测试完成，日志目录: $LOG_DIR"
