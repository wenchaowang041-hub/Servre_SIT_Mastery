#!/usr/bin/env bash

set -euo pipefail

RUNTIME=60
SIZE="10G"
RESULT_DIR="./fio-results-$(date +%F-%H%M%S)"
TARGET_MODE="all"
TARGET_DISK=""
INCLUDE_WRITE=0
JOBS_READ=1
JOBS_RAND=4
TESTS_ARG=""
RUN_SEQ_READ=1
RUN_SEQ_WRITE=0
RUN_RAND_READ=1
RUN_RAND_RW=0

usage() {
  cat <<'EOF'
用法:
  bash nvme_fio_auto_test.sh [选项]

选项:
  --disk nvme0n1                 只测试单盘
  --all                          测试全部非系统盘，默认启用
  --runtime 60                   fio 运行时长，单位秒
  --size 10G                     每项测试使用的数据量
  --include-write                开启写测试，具有破坏性
  --tests seq_read,seq_write     指定测试项
  --result-dir DIR               指定结果输出目录
  -h, --help                     显示帮助

可选测试项:
  seq_read     顺序读
  seq_write    顺序写
  rand_read    随机读
  rand_rw      随机读写混合

说明:
  1. 默认执行: 顺序读 + 随机读
  2. 仅加 --include-write 时，会额外执行: 顺序写 + 随机读写混合
  3. 如果显式指定 --tests，则按 --tests 为准
  4. 只要选择了写类测试，脚本都会要求二次确认

示例:
  bash nvme_fio_auto_test.sh
  bash nvme_fio_auto_test.sh --disk nvme0n1
  bash nvme_fio_auto_test.sh --tests seq_read,seq_write,rand_rw --include-write
  bash nvme_fio_auto_test.sh --all --include-write --runtime 120 --size 20G
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

resolve_base_disk() {
  local dev="$1"
  local disk_name pkname

  [[ -n "$dev" ]] || return 0

  pkname="$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1 || true)"
  if [[ -n "$pkname" ]]; then
    if [[ "$pkname" =~ ^nvme[0-9]+n1p[0-9]+$ ]]; then
      echo "${pkname%p*}"
      return 0
    fi
    if [[ "$pkname" =~ ^nvme[0-9]+n1$ ]]; then
      echo "$pkname"
      return 0
    fi
  fi

  disk_name="$(lsblk -sno NAME,TYPE "$dev" 2>/dev/null | awk '$2=="disk" {print $1; exit}' || true)"
  if [[ -n "$disk_name" ]]; then
    echo "$disk_name"
    return 0
  fi

  basename "$dev"
}

translate_test_name() {
  case "$1" in
    seq_read) echo "顺序读" ;;
    seq_write) echo "顺序写" ;;
    rand_read) echo "随机读" ;;
    rand_rw) echo "随机读写混合" ;;
    *) echo "$1" ;;
  esac
}

extract_metric_token() {
  local file="$1"
  local pattern="$2"
  grep -Eo "$pattern" "$file" 2>/dev/null | head -n1 || true
}

extract_latency_avg() {
  local file="$1"
  awk '
    /lat \(/ || /clat \(/ {
      if (match($0, /avg=[0-9.]+/)) {
        print substr($0, RSTART, RLENGTH)
        exit
      }
    }
  ' "$file" 2>/dev/null || true
}

append_summary() {
  local disk="$1"
  local test_name="$2"
  local file="$3"
  local bw iops lat test_name_cn

  bw="$(extract_metric_token "$file" '(BW|bw)=[^,[:space:]]+')"
  iops="$(extract_metric_token "$file" '(IOPS|iops)=[^,[:space:]]+')"
  lat="$(extract_latency_avg "$file")"
  test_name_cn="$(translate_test_name "$test_name")"

  [[ -n "$bw" ]] || bw="N/A"
  [[ -n "$iops" ]] || iops="N/A"
  [[ -n "$lat" ]] || lat="N/A"

  printf "%s\t%s\t%s\t%s\t%s\n" "$disk" "$test_name_cn" "$bw" "$iops" "$lat" >> "$SUMMARY_TSV"
  printf "| %s | %s | %s | %s | %s |\n" "$disk" "$test_name_cn" "$bw" "$iops" "$lat" >> "$SUMMARY_MD"
}

selected_tests_csv() {
  local selected=()
  [[ "$RUN_SEQ_READ" -eq 1 ]] && selected+=("seq_read")
  [[ "$RUN_SEQ_WRITE" -eq 1 ]] && selected+=("seq_write")
  [[ "$RUN_RAND_READ" -eq 1 ]] && selected+=("rand_read")
  [[ "$RUN_RAND_RW" -eq 1 ]] && selected+=("rand_rw")
  local joined=""
  local item
  for item in "${selected[@]}"; do
    if [[ -z "$joined" ]]; then
      joined="$item"
    else
      joined="$joined,$item"
    fi
  done
  echo "$joined"
}

enable_selected_tests() {
  local raw="$1"
  local item

  RUN_SEQ_READ=0
  RUN_SEQ_WRITE=0
  RUN_RAND_READ=0
  RUN_RAND_RW=0

  IFS=',' read -r -a SELECTED_TESTS <<< "$raw"
  for item in "${SELECTED_TESTS[@]}"; do
    case "$item" in
      seq_read) RUN_SEQ_READ=1 ;;
      seq_write) RUN_SEQ_WRITE=1 ;;
      rand_read) RUN_RAND_READ=1 ;;
      rand_rw) RUN_RAND_RW=1 ;;
      *)
        echo "不支持的测试项: $item" >&2
        echo "可选值: seq_read, seq_write, rand_read, rand_rw" >&2
        exit 1
        ;;
    esac
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk)
      TARGET_MODE="single"
      TARGET_DISK="${2:-}"
      shift 2
      ;;
    --all)
      TARGET_MODE="all"
      shift
      ;;
    --runtime)
      RUNTIME="${2:-}"
      shift 2
      ;;
    --size)
      SIZE="${2:-}"
      shift 2
      ;;
    --include-write)
      INCLUDE_WRITE=1
      shift
      ;;
    --tests)
      TESTS_ARG="${2:-}"
      shift 2
      ;;
    --result-dir)
      RESULT_DIR="${2:-}"
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

require_cmd lsblk
require_cmd fio

if command -v nvme >/dev/null 2>&1; then
  HAVE_NVME=1
else
  HAVE_NVME=0
fi

if [[ -n "$TESTS_ARG" ]]; then
  enable_selected_tests "$TESTS_ARG"
else
  if [[ "$INCLUDE_WRITE" -eq 1 ]]; then
    RUN_SEQ_WRITE=1
    RUN_RAND_RW=1
  fi
fi

if [[ "$RUN_SEQ_WRITE" -eq 1 || "$RUN_RAND_RW" -eq 1 ]]; then
  INCLUDE_WRITE=1
fi

if [[ "$RUN_SEQ_READ" -eq 0 && "$RUN_SEQ_WRITE" -eq 0 && "$RUN_RAND_READ" -eq 0 && "$RUN_RAND_RW" -eq 0 ]]; then
  echo "未选择任何测试项，脚本退出。" >&2
  exit 1
fi

mkdir -p "$RESULT_DIR"
SUMMARY_TSV="$RESULT_DIR/summary.tsv"
SUMMARY_MD="$RESULT_DIR/summary.md"

ROOT_SOURCE="$(findmnt -no SOURCE / || true)"
BOOT_SOURCE="$(findmnt -no SOURCE /boot 2>/dev/null || true)"
BOOT_EFI_SOURCE="$(findmnt -no SOURCE /boot/efi 2>/dev/null || true)"
ROOT_DISK=""

for candidate in "${BOOT_EFI_SOURCE:-}" "${BOOT_SOURCE:-}" "${ROOT_SOURCE:-}"; do
  if [[ -n "$candidate" ]]; then
    ROOT_DISK="$(resolve_base_disk "$candidate")"
    if [[ -n "${ROOT_DISK:-}" && "$ROOT_DISK" =~ ^nvme[0-9]+n1$ ]]; then
      break
    fi
    ROOT_DISK=""
  fi
done

mapfile -t ALL_NVME_DISKS < <(lsblk -dn -o NAME,TYPE | awk '$2=="disk" && $1 ~ /^nvme[0-9]+n1$/ {print $1}')

if [[ "${#ALL_NVME_DISKS[@]}" -eq 0 ]]; then
  echo "未发现 NVMe 盘。" >&2
  exit 1
fi

TARGETS=()

if [[ "$TARGET_MODE" == "single" ]]; then
  if [[ -z "$TARGET_DISK" ]]; then
    echo "--disk 需要指定盘符，例如: --disk nvme0n1" >&2
    exit 1
  fi
  if ! printf '%s\n' "${ALL_NVME_DISKS[@]}" | grep -qx "$TARGET_DISK"; then
    echo "目标盘不存在: $TARGET_DISK" >&2
    exit 1
  fi
  TARGETS=("$TARGET_DISK")
else
  for disk in "${ALL_NVME_DISKS[@]}"; do
    if [[ -n "${ROOT_DISK:-}" && "$disk" == "$ROOT_DISK" ]]; then
      continue
    fi
    TARGETS+=("$disk")
  done
fi

if [[ -n "${ROOT_DISK:-}" ]] && printf '%s\n' "${TARGETS[@]}" | grep -qx "$ROOT_DISK"; then
  echo "目标列表中包含系统盘，已拒绝执行: $ROOT_DISK" >&2
  exit 1
fi

if [[ "${#TARGETS[@]}" -eq 0 ]]; then
  echo "排除系统盘后，没有可测试的目标盘。" >&2
  exit 1
fi

if [[ "$INCLUDE_WRITE" -eq 1 ]]; then
  if [[ -n "${ROOT_DISK:-}" ]] && printf '%s\n' "${TARGETS[@]}" | grep -qx "$ROOT_DISK"; then
    echo "系统盘禁止执行写测试: $ROOT_DISK" >&2
    exit 1
  fi
  echo "警告: 已开启写测试，目标盘上的原有数据可能被破坏。"
  echo "本次计划执行的测试项: $(selected_tests_csv)"
  read -r -p "如确认继续，请输入大写 YES: " CONFIRM
  if [[ "$CONFIRM" != "YES" ]]; then
    echo "已取消执行。"
    exit 1
  fi
fi

{
  echo "date=$(date '+%F %T')"
  echo "runtime=$RUNTIME"
  echo "size=$SIZE"
  echo "include_write=$INCLUDE_WRITE"
  echo "root_source=${ROOT_SOURCE:-unknown}"
  echo "root_disk=${ROOT_DISK:-unknown}"
  echo "targets=${TARGETS[*]}"
  echo "selected_tests=$(selected_tests_csv)"
} | tee "$RESULT_DIR/test-meta.txt"

printf "disk\ttest\tbandwidth\tiops\tlatency_avg\n" > "$SUMMARY_TSV"
{
  echo "# FIO 测试汇总"
  echo
  echo "| 磁盘 | 测试类型 | 带宽 | IOPS | 平均时延 |"
  echo "| --- | --- | --- | --- | --- |"
} > "$SUMMARY_MD"

lsblk > "$RESULT_DIR/lsblk.txt"
if [[ "$HAVE_NVME" -eq 1 ]]; then
  nvme list > "$RESULT_DIR/nvme-list-before.txt" 2>&1 || true
fi

run_fio() {
  local disk="$1"
  local job_name="$2"
  local rw="$3"
  local bs="$4"
  local numjobs="$5"
  local outfile="$6"

  fio \
    --name="$job_name" \
    --filename="/dev/$disk" \
    --rw="$rw" \
    --bs="$bs" \
    --size="$SIZE" \
    --runtime="$RUNTIME" \
    --time_based \
    --numjobs="$numjobs" \
    --ioengine=libaio \
    --direct=1 \
    --group_reporting \
    --output="$outfile"
}

for disk in "${TARGETS[@]}"; do
  DISK_DIR="$RESULT_DIR/$disk"
  mkdir -p "$DISK_DIR"

  log "采集 $disk 的测试前信息"
  lsblk "/dev/$disk" > "$DISK_DIR/lsblk.txt" 2>&1 || true

  if [[ "$HAVE_NVME" -eq 1 ]]; then
    nvme id-ctrl "/dev/${disk%n1}" > "$DISK_DIR/id-ctrl-before.txt" 2>&1 || true
    nvme smart-log "/dev/${disk%n1}" > "$DISK_DIR/smart-log-before.txt" 2>&1 || true
  fi

  if [[ "$RUN_SEQ_READ" -eq 1 ]]; then
    log "开始执行 顺序读: $disk"
    run_fio "$disk" "seq_read_$disk" "read" "1M" "$JOBS_READ" "$DISK_DIR/seq_read.txt"
    append_summary "$disk" "seq_read" "$DISK_DIR/seq_read.txt"
  fi

  if [[ "$RUN_RAND_READ" -eq 1 ]]; then
    log "开始执行 随机读: $disk"
    run_fio "$disk" "rand_read_$disk" "randread" "4k" "$JOBS_RAND" "$DISK_DIR/rand_read.txt"
    append_summary "$disk" "rand_read" "$DISK_DIR/rand_read.txt"
  fi

  if [[ "$RUN_SEQ_WRITE" -eq 1 ]]; then
    log "开始执行 顺序写: $disk"
    run_fio "$disk" "seq_write_$disk" "write" "1M" "$JOBS_READ" "$DISK_DIR/seq_write.txt"
    append_summary "$disk" "seq_write" "$DISK_DIR/seq_write.txt"
  fi

  if [[ "$RUN_RAND_RW" -eq 1 ]]; then
    log "开始执行 随机读写混合: $disk"
    fio \
      --name="rand_rw_$disk" \
      --filename="/dev/$disk" \
      --rw=randrw \
      --rwmixread=70 \
      --bs=4k \
      --size="$SIZE" \
      --runtime="$RUNTIME" \
      --time_based \
      --numjobs="$JOBS_RAND" \
      --ioengine=libaio \
      --direct=1 \
      --group_reporting \
      --output="$DISK_DIR/rand_rw.txt"
    append_summary "$disk" "rand_rw" "$DISK_DIR/rand_rw.txt"
  fi

  if [[ "$HAVE_NVME" -eq 1 ]]; then
    nvme smart-log "/dev/${disk%n1}" > "$DISK_DIR/smart-log-after.txt" 2>&1 || true
  fi
done

if [[ "$HAVE_NVME" -eq 1 ]]; then
  nvme list > "$RESULT_DIR/nvme-list-after.txt" 2>&1 || true
fi

log "汇总表已生成: $SUMMARY_TSV"
log "汇总表已生成: $SUMMARY_MD"
log "测试完成，结果目录: $RESULT_DIR"
