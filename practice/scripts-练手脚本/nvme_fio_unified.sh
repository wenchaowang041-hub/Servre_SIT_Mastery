#!/usr/bin/env bash
export LANG=${LANG:-C.UTF-8}
export LC_ALL=${LC_ALL:-C.UTF-8}
export PYTHONIOENCODING=${PYTHONIOENCODING:-UTF-8}

set -euo pipefail

RUNTIME=60
SIZE="10G"
RESULT_DIR="./fio-unified-results-$(date +%F-%H%M%S)"
TARGET_MODE="all"
TARGET_DISK=""
DEVICES_ARG=""
MODES_ARG="seq_read,seq_write,rand_read,rand_write,seq_mix,rand_mix"
MIX_READ=70
DIRECT=1
IOENGINE="libaio"
VERIFY_ONLY=0
BS_OVERRIDE=""
NUMJOBS_OVERRIDE=""
IODEPTH_OVERRIDE=""

usage() {
  cat <<'EOF'
用法:
  bash nvme_fio_unified.sh [选项]

选盘方式:
  --all                          测试全部非系统 NVMe 盘，默认模式
  --disk nvme0n1                 仅测试单盘
  --devices nvme0n1,nvme1n1      指定多块盘，逗号分隔

通用选项:
  --modes A,B,C                  指定测试模式，默认全量六项
  --runtime 60                   fio 运行时长，单位秒
  --size 10G                     每项测试的数据量
  --mix-read 70                  混合读比例，默认 70
  --bs-override 4k               覆盖默认块大小
  --numjobs-override 8           覆盖默认 numjobs
  --iodepth-override 1           覆盖默认 iodepth
  --result-dir DIR               指定结果目录
  --verify-only                  只做盘位识别与风险检查，不执行 fio
  -h, --help                     显示帮助

支持模式:
  seq_read    顺序读
  seq_write   顺序写
  rand_read   随机读
  rand_write  随机写
  seq_mix     顺序混合读写
  rand_mix    随机混合读写

示例:
  bash nvme_fio_unified.sh --all
  bash nvme_fio_unified.sh --disk nvme0n1 --modes seq_read,rand_read
  bash nvme_fio_unified.sh --disk nvme0n1 --modes rand_mix --mix-read 70 --runtime 43200 --size 50G --bs-override 4k --numjobs-override 8 --iodepth-override 1
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

normalize_disk_name() {
  local raw="$1"
  raw="${raw#/dev/}"
  echo "$raw"
}

translate_mode_name() {
  case "$1" in
    seq_read) echo "顺序读" ;;
    seq_write) echo "顺序写" ;;
    rand_read) echo "随机读" ;;
    rand_write) echo "随机写" ;;
    seq_mix) echo "顺序混合读写" ;;
    rand_mix) echo "随机混合读写" ;;
    *) echo "$1" ;;
  esac
}

mode_rw() {
  case "$1" in
    seq_read) echo "read" ;;
    seq_write) echo "write" ;;
    rand_read) echo "randread" ;;
    rand_write) echo "randwrite" ;;
    seq_mix) echo "rw" ;;
    rand_mix) echo "randrw" ;;
    *) return 1 ;;
  esac
}

mode_bs() {
  case "$1" in
    seq_read|seq_write) echo "1M" ;;
    rand_read|rand_write|rand_mix) echo "4k" ;;
    seq_mix) echo "128k" ;;
    *) return 1 ;;
  esac
}

mode_numjobs() {
  case "$1" in
    seq_read|seq_write|seq_mix) echo "1" ;;
    rand_read|rand_write|rand_mix) echo "4" ;;
    *) return 1 ;;
  esac
}

mode_iodepth() {
  echo "32"
}

resolved_bs() {
  if [[ -n "$BS_OVERRIDE" ]]; then
    echo "$BS_OVERRIDE"
  else
    mode_bs "$1"
  fi
}

resolved_numjobs() {
  if [[ -n "$NUMJOBS_OVERRIDE" ]]; then
    echo "$NUMJOBS_OVERRIDE"
  else
    mode_numjobs "$1"
  fi
}

resolved_iodepth() {
  if [[ -n "$IODEPTH_OVERRIDE" ]]; then
    echo "$IODEPTH_OVERRIDE"
  else
    mode_iodepth "$1"
  fi
}

mode_needs_write_confirmation() {
  case "$1" in
    seq_write|rand_write|seq_mix|rand_mix)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

mode_uses_mix_ratio() {
  case "$1" in
    seq_mix|rand_mix)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

extract_metric_token() {
  local file="$1"
  local pattern="$2"
  grep -Eo "$pattern" "$file" 2>/dev/null | head -n1 || true
}

extract_direction_metric_token() {
  local file="$1"
  local direction="$2"
  local pattern="$3"
  awk -v direction="$direction" -v pattern="$pattern" '
    $0 ~ "^[[:space:]]*" direction ":" {
      if (match($0, pattern)) {
        print substr($0, RSTART, RLENGTH)
      }
      exit
    }
  ' "$file" 2>/dev/null || true
}

extract_latency_avg() {
  local file="$1"
  awk '
    /^[[:space:]]*lat[[:space:]]+\(/ {
      unit = ""
      if (match($0, /\((nsec|usec|msec)\)/, unit_match)) {
        unit = unit_match[1]
      }
      if (match($0, /avg=[0-9.]+/)) {
        print substr($0, RSTART, RLENGTH) unit
        exit
      }
    }
    /^[[:space:]]*clat[[:space:]]+\(/ {
      unit = ""
      if (match($0, /\((nsec|usec|msec)\)/, unit_match)) {
        unit = unit_match[1]
      }
      if (match($0, /avg=[0-9.]+/)) {
        print substr($0, RSTART, RLENGTH) unit
        exit
      }
    }
  ' "$file" 2>/dev/null || true
}

extract_direction_latency_avg() {
  local file="$1"
  local direction="$2"
  awk -v direction="$direction" '
    $0 ~ "^[[:space:]]*" direction ":" {
      in_block = 1
      next
    }
    in_block && $0 ~ "^[[:space:]]*(read|write):" {
      exit
    }
    in_block && /^[[:space:]]*lat[[:space:]]+\(/ {
      unit = ""
      if (match($0, /\((nsec|usec|msec)\)/, unit_match)) {
        unit = unit_match[1]
      }
      if (match($0, /avg=[0-9.]+/)) {
        print substr($0, RSTART, RLENGTH) unit
        exit
      }
    }
    in_block && /^[[:space:]]*clat[[:space:]]+\(/ && fallback == "" {
      unit = ""
      if (match($0, /\((nsec|usec|msec)\)/, unit_match)) {
        unit = unit_match[1]
      }
      if (match($0, /avg=[0-9.]+/)) {
        fallback = substr($0, RSTART, RLENGTH) unit
      }
    }
    END {
      if (fallback != "") {
        print fallback
      }
    }
  ' "$file" 2>/dev/null || true
}

mode_primary_direction() {
  case "$1" in
    seq_read|rand_read) echo "read" ;;
    seq_write|rand_write) echo "write" ;;
    *) return 1 ;;
  esac
}

mode_is_mixed() {
  case "$1" in
    seq_mix|rand_mix) return 0 ;;
    *) return 1 ;;
  esac
}

append_summary() {
  local disk="$1"
  local mode="$2"
  local file="$3"
  local bw iops lat mode_cn direction
  local read_bw write_bw read_iops write_iops read_lat write_lat

  if mode_is_mixed "$mode"; then
    read_bw="$(extract_direction_metric_token "$file" 'read' '(BW|bw)=[^,[:space:]]+')"
    write_bw="$(extract_direction_metric_token "$file" 'write' '(BW|bw)=[^,[:space:]]+')"
    read_iops="$(extract_direction_metric_token "$file" 'read' '(IOPS|iops)=[^,[:space:]]+')"
    write_iops="$(extract_direction_metric_token "$file" 'write' '(IOPS|iops)=[^,[:space:]]+')"
    read_lat="$(extract_direction_latency_avg "$file" 'read')"
    write_lat="$(extract_direction_latency_avg "$file" 'write')"

    bw="R:${read_bw:-N/A} / W:${write_bw:-N/A}"
    iops="R:${read_iops:-N/A} / W:${write_iops:-N/A}"
    lat="R:${read_lat:-N/A} / W:${write_lat:-N/A}"
  else
    direction="$(mode_primary_direction "$mode" || true)"
    if [[ -n "$direction" ]]; then
      bw="$(extract_direction_metric_token "$file" "$direction" '(BW|bw)=[^,[:space:]]+')"
      iops="$(extract_direction_metric_token "$file" "$direction" '(IOPS|iops)=[^,[:space:]]+')"
      lat="$(extract_direction_latency_avg "$file" "$direction")"
    else
      bw="$(extract_metric_token "$file" '(BW|bw)=[^,[:space:]]+')"
      iops="$(extract_metric_token "$file" '(IOPS|iops)=[^,[:space:]]+')"
      lat="$(extract_latency_avg "$file")"
    fi
  fi
  mode_cn="$(translate_mode_name "$mode")"

  [[ -n "$bw" ]] || bw="N/A"
  [[ -n "$iops" ]] || iops="N/A"
  [[ -n "$lat" ]] || lat="N/A"

  printf "%s\t%s\t%s\t%s\t%s\n" "$disk" "$mode_cn" "$bw" "$iops" "$lat" >> "$SUMMARY_TSV"
  printf "| %s | %s | %s | %s | %s |\n" "$disk" "$mode_cn" "$bw" "$iops" "$lat" >> "$SUMMARY_MD"
}

resolve_base_disk() {
  local dev="$1"
  local pkname disk_name

  [[ -n "$dev" ]] || return 0

  pkname="$(lsblk -no PKNAME "$dev" 2>/dev/null | head -n1 || true)"
  if [[ -n "$pkname" && "$pkname" =~ ^nvme[0-9]+n[0-9]+$ ]]; then
    echo "$pkname"
    return 0
  fi

  disk_name="$(lsblk -sno NAME,TYPE "$dev" 2>/dev/null | awk '$2=="disk" {print $1; exit}' || true)"
  if [[ -n "$disk_name" ]]; then
    echo "$disk_name"
    return 0
  fi

  basename "$dev"
}

find_system_nvme_disk() {
  local source root_disk boot_disk

  source="$(findmnt -no SOURCE / 2>/dev/null || true)"
  if [[ -n "$source" ]]; then
    root_disk="$(resolve_base_disk "$source")"
    if [[ "$root_disk" =~ ^nvme[0-9]+n[0-9]+$ ]]; then
      echo "$root_disk"
      return 0
    fi
  fi

  source="$(findmnt -no SOURCE /boot 2>/dev/null || true)"
  if [[ -n "$source" ]]; then
    boot_disk="$(resolve_base_disk "$source")"
    if [[ "$boot_disk" =~ ^nvme[0-9]+n[0-9]+$ ]]; then
      echo "$boot_disk"
      return 0
    fi
  fi

  return 1
}

collect_target_disks() {
  local system_disk item normalized
  local -a disks=()
  local -a all_nvmes=()
  local -a raw_devices=()

  case "$TARGET_MODE" in
    single)
      normalized="$(normalize_disk_name "$TARGET_DISK")"
      disks=("$normalized")
      ;;
    devices)
      IFS=',' read -r -a raw_devices <<< "$DEVICES_ARG"
      for item in "${raw_devices[@]}"; do
        normalized="$(normalize_disk_name "$item")"
        [[ -n "$normalized" ]] && disks+=("$normalized")
      done
      ;;
    all)
      mapfile -t all_nvmes < <(lsblk -dn -o NAME,TYPE | awk '$2=="disk" && $1 ~ /^nvme/ {print $1}')
      system_disk="$(find_system_nvme_disk || true)"
      for item in "${all_nvmes[@]}"; do
        [[ "$item" == "$system_disk" ]] && continue
        disks+=("$item")
      done
      ;;
    *)
      echo "未知目标模式: $TARGET_MODE" >&2
      exit 1
      ;;
  esac

  if [[ "${#disks[@]}" -eq 0 ]]; then
    echo "未找到可测试的 NVMe 目标盘" >&2
    exit 1
  fi

  printf '%s\n' "${disks[@]}"
}

validate_modes() {
  local item
  local -a mode_array=()

  IFS=',' read -r -a mode_array <<< "$MODES_ARG"
  VALIDATED_MODES=()
  for item in "${mode_array[@]}"; do
    item="$(echo "$item" | xargs)"
    [[ -z "$item" ]] && continue
    case "$item" in
      seq_read|seq_write|rand_read|rand_write|seq_mix|rand_mix)
        VALIDATED_MODES+=("$item")
        ;;
      *)
        echo "不支持的模式: $item" >&2
        echo "可选值: seq_read, seq_write, rand_read, rand_write, seq_mix, rand_mix" >&2
        exit 1
        ;;
    esac
  done

  if [[ "${#VALIDATED_MODES[@]}" -eq 0 ]]; then
    echo "未选择任何有效模式" >&2
    exit 1
  fi
}

validate_overrides() {
  if [[ -n "$NUMJOBS_OVERRIDE" && ! "$NUMJOBS_OVERRIDE" =~ ^[0-9]+$ ]]; then
    echo "--numjobs-override 必须是正整数" >&2
    exit 1
  fi

  if [[ -n "$IODEPTH_OVERRIDE" && ! "$IODEPTH_OVERRIDE" =~ ^[0-9]+$ ]]; then
    echo "--iodepth-override 必须是正整数" >&2
    exit 1
  fi
}

confirm_write_risk_if_needed() {
  local mode item need_confirm=0 system_disk

  system_disk="$(find_system_nvme_disk || true)"
  for mode in "${VALIDATED_MODES[@]}"; do
    if mode_needs_write_confirmation "$mode"; then
      need_confirm=1
      break
    fi
  done

  [[ "$need_confirm" -eq 1 ]] || return 0

  for item in "${TARGET_DISKS[@]}"; do
    if [[ -n "$system_disk" && "$item" == "$system_disk" ]]; then
      echo "禁止对系统盘执行写类测试: $item" >&2
      exit 1
    fi
  done

  echo "警告: 已选择写类或混合写测试，目标盘原有数据可能被破坏。" >&2
  echo "目标盘: ${TARGET_DISKS[*]}" >&2
  echo "测试模式: ${VALIDATED_MODES[*]}" >&2
  read -r -p "如确认继续，请输入大写 YES: " CONFIRM
  if [[ "$CONFIRM" != "YES" ]]; then
    echo "已取消执行。" >&2
    exit 1
  fi
}

collect_pre_info() {
  local disk disk_dir ctrl_dev

  lsblk > "$RESULT_DIR/lsblk-before.txt"
  dmesg -T > "$RESULT_DIR/dmesg-before.txt" 2>&1 || true
  if command -v nvme >/dev/null 2>&1; then
    nvme list > "$RESULT_DIR/nvme-list-before.txt" 2>&1 || true
  fi

  for disk in "${TARGET_DISKS[@]}"; do
    disk_dir="$RESULT_DIR/$disk"
    mkdir -p "$disk_dir"
    lsblk "/dev/$disk" > "$disk_dir/lsblk-before.txt" 2>&1 || true
    if command -v nvme >/dev/null 2>&1; then
      ctrl_dev="/dev/${disk%n*}"
      nvme id-ctrl "$ctrl_dev" > "$disk_dir/id-ctrl-before.txt" 2>&1 || true
      nvme smart-log "$ctrl_dev" > "$disk_dir/smart-log-before.txt" 2>&1 || true
    fi
  done
}

collect_post_info() {
  local disk disk_dir ctrl_dev

  lsblk > "$RESULT_DIR/lsblk-after.txt"
  dmesg -T > "$RESULT_DIR/dmesg-after.txt" 2>&1 || true
  if command -v nvme >/dev/null 2>&1; then
    nvme list > "$RESULT_DIR/nvme-list-after.txt" 2>&1 || true
  fi

  for disk in "${TARGET_DISKS[@]}"; do
    disk_dir="$RESULT_DIR/$disk"
    lsblk "/dev/$disk" > "$disk_dir/lsblk-after.txt" 2>&1 || true
    if command -v nvme >/dev/null 2>&1; then
      ctrl_dev="/dev/${disk%n*}"
      nvme smart-log "$ctrl_dev" > "$disk_dir/smart-log-after.txt" 2>&1 || true
    fi
  done

  if command -v diff >/dev/null 2>&1; then
    diff -u "$RESULT_DIR/dmesg-before.txt" "$RESULT_DIR/dmesg-after.txt" > "$RESULT_DIR/dmesg-diff.txt" || true
    if [[ -f "$RESULT_DIR/nvme-list-before.txt" && -f "$RESULT_DIR/nvme-list-after.txt" ]]; then
      diff -u "$RESULT_DIR/nvme-list-before.txt" "$RESULT_DIR/nvme-list-after.txt" > "$RESULT_DIR/nvme-list-diff.txt" || true
    fi
  fi
}

run_mode_on_disk() {
  local disk="$1"
  local mode="$2"
  local disk_dir job_name rw bs numjobs iodepth output_file
  local -a fio_cmd

  disk_dir="$RESULT_DIR/$disk"
  job_name="${mode}_${disk}"
  rw="$(mode_rw "$mode")"
  bs="$(resolved_bs "$mode")"
  numjobs="$(resolved_numjobs "$mode")"
  iodepth="$(resolved_iodepth "$mode")"
  output_file="$disk_dir/${mode}.txt"

  fio_cmd=(
    fio
    --name="$job_name"
    --filename="/dev/$disk"
    --direct="$DIRECT"
    --ioengine="$IOENGINE"
    --rw="$rw"
    --bs="$bs"
    --iodepth="$iodepth"
    --runtime="$RUNTIME"
    --time_based
    --numjobs="$numjobs"
    --size="$SIZE"
    --group_reporting
    --output="$output_file"
  )

  if mode_uses_mix_ratio "$mode"; then
    fio_cmd+=(--rwmixread="$MIX_READ")
  fi

  log "开始测试: disk=$disk mode=$mode rw=$rw bs=$bs numjobs=$numjobs iodepth=$iodepth"
  printf 'command=' >> "$RESULT_DIR/test-meta.txt"
  printf '%q ' "${fio_cmd[@]}" >> "$RESULT_DIR/test-meta.txt"
  printf '\n' >> "$RESULT_DIR/test-meta.txt"

  "${fio_cmd[@]}"
  append_summary "$disk" "$mode" "$output_file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      TARGET_MODE="all"
      shift
      ;;
    --disk)
      TARGET_MODE="single"
      TARGET_DISK="${2:-}"
      shift 2
      ;;
    --devices)
      TARGET_MODE="devices"
      DEVICES_ARG="${2:-}"
      shift 2
      ;;
    --modes)
      MODES_ARG="${2:-}"
      shift 2
      ;;
    --runtime)
      RUNTIME="${2:-60}"
      shift 2
      ;;
    --size)
      SIZE="${2:-10G}"
      shift 2
      ;;
    --mix-read)
      MIX_READ="${2:-70}"
      shift 2
      ;;
    --bs-override)
      BS_OVERRIDE="${2:-}"
      shift 2
      ;;
    --numjobs-override)
      NUMJOBS_OVERRIDE="${2:-}"
      shift 2
      ;;
    --iodepth-override)
      IODEPTH_OVERRIDE="${2:-}"
      shift 2
      ;;
    --result-dir)
      RESULT_DIR="${2:-}"
      shift 2
      ;;
    --verify-only)
      VERIFY_ONLY=1
      shift
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
require_cmd findmnt

mkdir -p "$RESULT_DIR"
SUMMARY_TSV="$RESULT_DIR/summary.tsv"
SUMMARY_MD="$RESULT_DIR/summary.md"

validate_modes
validate_overrides
mapfile -t TARGET_DISKS < <(collect_target_disks)
confirm_write_risk_if_needed

{
  echo "date=$(date '+%F %T')"
  echo "target_mode=$TARGET_MODE"
  echo "target_disks=${TARGET_DISKS[*]}"
  echo "modes=${VALIDATED_MODES[*]}"
  echo "runtime=$RUNTIME"
  echo "size=$SIZE"
  echo "mix_read=$MIX_READ"
  echo "ioengine=$IOENGINE"
  echo "direct=$DIRECT"
  echo "bs_override=$BS_OVERRIDE"
  echo "numjobs_override=$NUMJOBS_OVERRIDE"
  echo "iodepth_override=$IODEPTH_OVERRIDE"
  echo "verify_only=$VERIFY_ONLY"
} > "$RESULT_DIR/test-meta.txt"

printf "disk\tmode\tbw\tiops\tlat_avg\n" > "$SUMMARY_TSV"
{
  echo "# FIO 测试汇总"
  echo
  echo "| 盘符 | 模式 | 带宽 | IOPS | 平均时延 |"
  echo "| --- | --- | --- | --- | --- |"
} > "$SUMMARY_MD"

log "目标盘: ${TARGET_DISKS[*]}"
log "测试模式: ${VALIDATED_MODES[*]}"

collect_pre_info

if [[ "$VERIFY_ONLY" -eq 1 ]]; then
  log "已完成盘位识别与风险检查，未执行 fio。"
  collect_post_info
  exit 0
fi

for disk in "${TARGET_DISKS[@]}"; do
  for mode in "${VALIDATED_MODES[@]}"; do
    run_mode_on_disk "$disk" "$mode"
  done
done

collect_post_info
log "测试完成，结果目录: $RESULT_DIR"
