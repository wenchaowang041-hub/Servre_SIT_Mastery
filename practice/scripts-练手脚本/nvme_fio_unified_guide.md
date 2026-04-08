# NVMe FIO 统一复用脚本说明

适用脚本：[`nvme_fio_unified.sh`](/C:/Users/王文超/Desktop/Servre_SIT_Mastery/practice/scripts-练手脚本/nvme_fio_unified.sh)

Windows PowerShell 下建议优先使用 [`nvme_fio_unified.ps1`](/C:/Users/王文超/Desktop/Servre_SIT_Mastery/practice/scripts-练手脚本/nvme_fio_unified.ps1) 启动，避免中文提示乱码。

## 1. 脚本用途

这套脚本用于把常见 NVMe `fio` 模式统一收口成一个可复用入口，兼顾：

- 单盘验证
- 多盘指定测试
- 全部非系统盘批量测试
- 顺序 / 随机 / 混合读写模式统一执行
- 测试前后 `lsblk`、`dmesg`、`nvme list`、`smart-log` 自动留档
- 自动生成汇总表
- 支持用覆盖参数精确对齐现场 `fio` 命令

## 2. 支持的标准模式

| 模式 | 含义 | fio rw | 默认 bs | 默认 numjobs | 默认 iodepth | 备注 |
| --- | --- | --- | --- | ---: | ---: | --- |
| `seq_read` | 顺序读 | `read` | `1M` | 1 | 32 | 安全读测试 |
| `seq_write` | 顺序写 | `write` | `1M` | 1 | 32 | 破坏性 |
| `rand_read` | 随机读 | `randread` | `4k` | 4 | 32 | 安全读测试 |
| `rand_write` | 随机写 | `randwrite` | `4k` | 4 | 32 | 破坏性 |
| `seq_mix` | 顺序混合读写 | `rw` | `128k` | 1 | 32 | 默认 `mix-read=70` |
| `rand_mix` | 随机混合读写 | `randrw` | `4k` | 4 | 32 | 默认 `mix-read=70` |

## 3. 选盘方式

### 3.1 测全部非系统盘

```bash
bash nvme_fio_unified.sh --all
```

### 3.2 只测单盘

```bash
bash nvme_fio_unified.sh --disk nvme1n1
```

### 3.3 指定多块盘

```bash
bash nvme_fio_unified.sh --devices nvme1n1,nvme2n1,nvme3n1
```

## 4. 选择模式

默认会执行全量六项：

```text
seq_read,seq_write,rand_read,rand_write,seq_mix,rand_mix
```

如果只想跑部分模式，用 `--modes`：

```bash
bash nvme_fio_unified.sh --disk nvme1n1 --modes seq_read,rand_read
```

例如只跑写和混合：

```bash
bash nvme_fio_unified.sh --devices nvme1n1,nvme2n1 --modes seq_write,rand_write,seq_mix,rand_mix
```

## 5. 常用参数

```bash
--runtime 60
--size 10G
--mix-read 70
--bs-override 4k
--numjobs-override 8
--iodepth-override 1
--result-dir ./fio-results-custom
--verify-only
```

说明：

- `--runtime`：每个模式运行时长，单位秒。
- `--size`：每个模式的数据量。
- `--mix-read`：混合模式读占比，`seq_mix` / `rand_mix` 生效。
- `--bs-override`：覆盖脚本默认块大小。
- `--numjobs-override`：覆盖脚本默认 `numjobs`。
- `--iodepth-override`：覆盖脚本默认 `iodepth`。
- `--result-dir`：结果输出目录。
- `--verify-only`：只做目标盘识别和风险检查，不真正执行 `fio`。

## 6. 安全策略

这套脚本默认内置两层保护：

1. `--all` 模式会自动识别并跳过系统 NVMe 盘。
2. 只要你选择了 `seq_write`、`rand_write`、`seq_mix`、`rand_mix`，脚本就会强制二次确认，必须输入大写 `YES` 才继续。

因此建议现场先执行：

```bash
bash nvme_fio_unified.sh --all --verify-only
```

确认目标盘无误后，再执行实际压测。

## 7. 推荐使用方式

### 7.1 现场首次上电，先做安全读测试

```bash
bash nvme_fio_unified.sh --all --modes seq_read,rand_read --runtime 60 --size 10G
```

### 7.2 单盘做全量基线

```bash
bash nvme_fio_unified.sh --disk nvme1n1 --runtime 60 --size 10G
```

### 7.3 多盘并发做写压测

```bash
bash nvme_fio_unified.sh --devices nvme1n1,nvme2n1 --modes seq_write,rand_write,rand_mix --runtime 120 --size 20G
```

### 7.4 对齐现场 12H 混合读写命令

如果你原始想跑的是：

```bash
fio --name=mix_workload \
  --filename=/dev/nvme0n1 \
  --rw=randrw \
  --rwmixread=70 \
  --bs=4k \
  --size=50G \
  --numjobs=8 \
  --runtime=43200 \
  --iodepth=1 \
  --ioengine=libaio \
  --direct=1 \
  --time_based
```

对应统一脚本命令为：

```bash
bash nvme_fio_unified.sh \
  --disk nvme0n1 \
  --modes rand_mix \
  --mix-read 70 \
  --runtime 43200 \
  --size 50G \
  --bs-override 4k \
  --numjobs-override 8 \
  --iodepth-override 1
```

说明：

- 统一脚本会自动带上 `--ioengine=libaio`
- 统一脚本会自动带上 `--direct=1`
- 统一脚本会自动带上 `--time_based`

这里要特别注意：如果你自己直接写裸 `fio` 命令，只写 `--runtime=43200` 但不带 `--time_based`，`fio` 可能在写完 `size=50G` 后就提前结束，不一定真的跑满 12 小时。统一脚本已经把这个坑规避掉了。

### 7.5 Windows PowerShell 启动

```powershell
.\nvme_fio_unified.ps1 --disk nvme0n1 --modes rand_mix --mix-read 70 --runtime 43200 --size 50G --bs-override 4k --numjobs-override 8 --iodepth-override 1
```

## 8. 输出结果

每次执行会生成类似目录：

```text
fio-unified-results-2026-04-07-173000
```

目录中常见文件：

- `test-meta.txt`
- `summary.tsv`
- `summary.md`
- `lsblk-before.txt`
- `lsblk-after.txt`
- `dmesg-before.txt`
- `dmesg-after.txt`
- `dmesg-diff.txt`
- `nvme-list-before.txt`
- `nvme-list-after.txt`

每块盘还有独立子目录，例如：

```text
fio-unified-results-xxxxxx/nvme1n1/
```

其中包含：

- `seq_read.txt`
- `seq_write.txt`
- `rand_read.txt`
- `rand_write.txt`
- `seq_mix.txt`
- `rand_mix.txt`
- `lsblk-before.txt`
- `lsblk-after.txt`
- `id-ctrl-before.txt`
- `smart-log-before.txt`
- `smart-log-after.txt`

## 9. 与旧脚本的关系

这个脚本的定位是统一入口，优先覆盖原先两类场景：

- [`legacy/nvme_fio_auto_test.sh`](/C:/Users/王文超/Desktop/Servre_SIT_Mastery/practice/scripts-练手脚本/legacy/nvme_fio_auto_test.sh) 的单盘 / 全盘批量能力
- [`legacy/nvme_multi_device_fio.sh`](/C:/Users/王文超/Desktop/Servre_SIT_Mastery/practice/scripts-练手脚本/legacy/nvme_multi_device_fio.sh) 的多盘指定能力

后续建议优先使用 `nvme_fio_unified.sh`，旧脚本已归档到 `legacy/` 目录，仅保留作为历史版本参考。
