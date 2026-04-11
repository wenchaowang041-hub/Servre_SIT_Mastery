# NVMe FIO 自动测试脚本使用说明

适用脚本：

- `practice/scripts-练手脚本/legacy/nvme_fio_auto_test.sh`

## 1. 用途

该脚本用于服务器 Linux OS 下的 NVMe 批量性能测试，适合：

- 新机 bring-up 后做 NVMe 基础性能确认
- 多盘一致性对比
- 单盘异常复测
- 在批量测试中自动排除系统盘

## 2. 核心特性

- 自动识别 NVMe 盘
- 自动识别并排除系统盘
- 默认只跑读测试
- 支持按测试项精确选择
- 自动保存 `nvme list`、`smart-log`、`id-ctrl`
- 自动生成中文汇总结果

## 3. 环境要求

必须具备：

```bash
lsblk
fio
```

建议具备：

```bash
nvme
```

## 4. 支持的测试项

- `seq_read`：顺序读
- `seq_write`：顺序写
- `rand_read`：随机读
- `rand_rw`：随机读写混合

默认行为：

- 默认执行 `seq_read + rand_read`
- 只要带 `--include-write`，默认额外执行 `seq_write + rand_rw`
- 如果显式指定 `--tests`，则按 `--tests` 为准

## 5. 常用命令

查看帮助：

```bash
bash nvme_fio_auto_test.sh --help
```

测试全部非系统盘，只跑读测试：

```bash
bash nvme_fio_auto_test.sh --all --runtime 60 --size 10G
```

测试单盘：

```bash
bash nvme_fio_auto_test.sh --disk nvme0n1 --runtime 60 --size 10G
```

只跑顺序读、顺序写、随机读写混合：

```bash
bash nvme_fio_auto_test.sh --all --tests seq_read,seq_write,rand_rw --include-write --runtime 60 --size 10G
```

只跑单盘顺序读：

```bash
bash nvme_fio_auto_test.sh --disk nvme0n1 --tests seq_read --runtime 60 --size 10G
```

## 6. 写测试风险

只要执行写类测试：

- `seq_write`
- `rand_rw`

脚本会提示二次确认：

```text
警告: 已开启写测试，目标盘上的原有数据可能被破坏。
本次计划执行的测试项: seq_read,seq_write,rand_rw
如确认继续，请输入大写 YES:
```

注意：

- 只有输入大写 `YES` 才继续
- 系统盘禁止执行写测试
- 已有业务数据的盘不要执行写测试

## 7. 输出结果

每次执行会生成一个目录，例如：

```bash
fio-results-2026-04-02-151843
```

其中常用文件包括：

- `test-meta.txt`
- `lsblk.txt`
- `nvme-list-before.txt`
- `nvme-list-after.txt`
- `summary.tsv`
- `summary.md`

每块盘还会生成独立子目录，例如：

```bash
fio-results-xxxxxx/nvme0n1/
```

其中包含：

- `id-ctrl-before.txt`
- `smart-log-before.txt`
- `seq_read.txt`
- `seq_write.txt`
- `rand_read.txt`
- `rand_rw.txt`
- `smart-log-after.txt`

## 8. 如何看结果

优先看：

```bash
cat fio-results-*/summary.md
```

汇总表中的测试类型已经改成中文：

- 顺序读
- 顺序写
- 随机读
- 随机读写混合

现场快速判断时重点关注：

- 同型号盘之间是否有明显掉队盘
- 顺序读是否存在明显低于大盘水平的异常盘
- 顺序写是否整体一致
- 随机混合场景下 IOPS 和时延是否出现第二档异常盘

## 9. 建议的现场流程

先确认在位和系统盘：

```bash
lsblk
nvme list
```

先跑安全读测：

```bash
bash nvme_fio_auto_test.sh --all --runtime 60 --size 10G
```

确认目标盘为空盘后，再执行写测试：

```bash
bash nvme_fio_auto_test.sh --all --tests seq_read,seq_write,rand_rw --include-write --runtime 60 --size 10G
```

异常盘后续补查：

```bash
nvme id-ctrl /dev/nvme0
nvme smart-log /dev/nvme0
lspci -vv -s <BDF>
```
