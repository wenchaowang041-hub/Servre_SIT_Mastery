#!/usr/bin/env bash

set -euo pipefail

DEVICES=""
RUNTIME=60
RW_MODE="randrw"
RW_MODES=""
RW_MIX_READ=70
BS="4k"
IODEPTH=32
NUMJOBS=1
SIZE="10G"
LOG_DIR="./multi-nvme-fio-$(date +%F-%H%M%S)"

usage() {
  cat <<'EOF'
用法:
  bash nvme_multi_device_fio.sh --devices /dev/nvme0n1,/dev/nvme1n1 [选项]

选项:
  --devices DEV1,DEV2         指定多块 NVMe 设备，逗号分隔
  --runtime 60                运行时长，单位秒
  --rw randrw                 指定单个 fio rw 模式，默认 randrw
  --rw-modes A,B,C            指定多个 rw 模式，按顺序逐个执行
  --rwmixread 70              混合读比例，默认 70，仅混合模式生效
  --bs 4k                     块大小
  --iodepth 32                队列深度
  --numjobs 1                 每组 job 数
  --size 10G                  每个 job 的数据量
  --log-dir DIR               指定日志目录
  -h, --help                  显示帮助

常见 rw 模式:
  read, write, randread, randwrite, rw, randrw, readwrite, trim, randtrim

示例:
  bash nvme_multi_device_fio.sh --devices /dev/nvme0n1,/dev/nvme1n1
  bash nvme_multi_device_fio.sh --devices /dev/nvme0n1,/dev/nvme1n1 --rw randread --bs 4k
  bash nvme_multi_device_fio.sh --devices /dev/nvme0n1,/dev/nvme1n1 --rw-modes read,write,randread,randwrite,randrw
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

is_mixed_rw_mode() {
  case "$1" in
    rw|randrw|readwrite|randreadwrite)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --devices)
      DEVICES="${2:-}"
      shift 2
      ;;
    --runtime)
      RUNTIME="${2:-60}"
      shift 2
      ;;
    --rw)
      RW_MODE="${2:-randrw}"
      shift 2
      ;;
    --rw-modes)
      RW_MODES="${2:-}"
      shift 2
      ;;
    --rwmixread)
      RW_MIX_READ="${2:-70}"
      shift 2
      ;;
    --bs)
      BS="${2:-4k}"
      shift 2
      ;;
    --iodepth)
      IODEPTH="${2:-32}"
      shift 2
      ;;
    --numjobs)
      NUMJOBS="${2:-1}"
      shift 2
      ;;
    --size)
      SIZE="${2:-10G}"
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

require_cmd fio
require_cmd lsblk
require_cmd dmesg

if [[ -z "$DEVICES" ]]; then
  echo "必须指定 --devices，例如: --devices /dev/nvme0n1,/dev/nvme1n1" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"

DEVICE_LIST_COLON="$(echo "$DEVICES" | tr ',' ':')"
IFS=',' read -r -a DEVICE_ARRAY <<< "$DEVICES"

if [[ -n "$RW_MODES" ]]; then
  IFS=',' read -r -a RW_MODE_ARRAY <<< "$RW_MODES"
else
  RW_MODE_ARRAY=("$RW_MODE")
fi

{
  echo "date=$(date '+%F %T')"
  echo "devices=$DEVICES"
  echo "rw_modes=${RW_MODE_ARRAY[*]}"
  echo "rwmixread=$RW_MIX_READ"
  echo "bs=$BS"
  echo "iodepth=$IODEPTH"
  echo "numjobs=$NUMJOBS"
  echo "runtime=$RUNTIME"
  echo "size=$SIZE"
} | tee "$LOG_DIR/test-meta.txt"

log "采集测试前信息"
lsblk > "$LOG_DIR/lsblk-before.txt"
dmesg -T > "$LOG_DIR/dmesg-before.txt" 2>&1 || true

if command -v nvme >/dev/null 2>&1; then
  nvme list > "$LOG_DIR/nvme-list-before.txt" 2>&1 || true
fi

for dev in "${DEVICE_ARRAY[@]}"; do
  dev_name="$(basename "$dev")"
  lsblk "$dev" > "$LOG_DIR/${dev_name}-lsblk-before.txt" 2>&1 || true
  if command -v nvme >/dev/null 2>&1; then
    ctrl_dev="${dev%n1}"
    nvme id-ctrl "$ctrl_dev" > "$LOG_DIR/${dev_name}-id-ctrl-before.txt" 2>&1 || true
    nvme smart-log "$ctrl_dev" > "$LOG_DIR/${dev_name}-smart-log-before.txt" 2>&1 || true
  fi
done

for rw in "${RW_MODE_ARRAY[@]}"; do
  rw="$(echo "$rw" | xargs)"
  [[ -z "$rw" ]] && continue

  output_file="$LOG_DIR/fio-${rw}.txt"
  log "开始执行多设备并发 FIO 测试: rw=$rw"

  fio_cmd=(
    fio
    --name="multi_device_${rw}"
    --filename="$DEVICE_LIST_COLON"
    --direct=1
    --ioengine=libaio
    --rw="$rw"
    --bs="$BS"
    --iodepth="$IODEPTH"
    --runtime="$RUNTIME"
    --time_based
    --numjobs="$NUMJOBS"
    --size="$SIZE"
    --group_reporting
    --output="$output_file"
  )

  if is_mixed_rw_mode "$rw"; then
    fio_cmd+=(--rwmixread="$RW_MIX_READ")
  fi

  printf 'command=' >> "$LOG_DIR/test-meta.txt"
  printf '%q ' "${fio_cmd[@]}" >> "$LOG_DIR/test-meta.txt"
  printf '\n' >> "$LOG_DIR/test-meta.txt"

  "${fio_cmd[@]}"
done

log "采集测试后信息"
lsblk > "$LOG_DIR/lsblk-after.txt"
dmesg -T > "$LOG_DIR/dmesg-after.txt" 2>&1 || true

if command -v nvme >/dev/null 2>&1; then
  nvme list > "$LOG_DIR/nvme-list-after.txt" 2>&1 || true
fi

for dev in "${DEVICE_ARRAY[@]}"; do
  dev_name="$(basename "$dev")"
  lsblk "$dev" > "$LOG_DIR/${dev_name}-lsblk-after.txt" 2>&1 || true
  if command -v nvme >/dev/null 2>&1; then
    ctrl_dev="${dev%n1}"
    nvme smart-log "$ctrl_dev" > "$LOG_DIR/${dev_name}-smart-log-after.txt" 2>&1 || true
  fi
done

if command -v diff >/dev/null 2>&1; then
  diff -u "$LOG_DIR/dmesg-before.txt" "$LOG_DIR/dmesg-after.txt" > "$LOG_DIR/dmesg-diff.txt" || true
  if [[ -f "$LOG_DIR/nvme-list-before.txt" && -f "$LOG_DIR/nvme-list-after.txt" ]]; then
    diff -u "$LOG_DIR/nvme-list-before.txt" "$LOG_DIR/nvme-list-after.txt" > "$LOG_DIR/nvme-list-diff.txt" || true
  fi
fi

log "测试完成，结果目录: $LOG_DIR"
