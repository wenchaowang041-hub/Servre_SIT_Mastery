# NVMe FIO 自动测试脚本使用手册

Windows PowerShell 下建议使用 `nvme_fio_auto_test.ps1` 启动，或者先执行 `chcp 65001` 再运行 Bash 脚本，以避免中文提示乱码。


适用脚本：[nvme_fio_auto_test.sh](/C:/Users/王文超/Desktop/Servre_SIT_Mastery/practice/scripts-练手脚本/legacy/nvme_fio_auto_test.sh)

## 1. 脚本用途

该脚本用于服务器 Linux OS 下的 NVMe 盘自动化性能测试，适合整机 bring-up、在位确认、单盘性能抽检和多盘批量对比。

脚本默认能力：

- 自动识别系统中的 NVMe 盘
- 自动识别并排除系统盘
- 默认只执行读测试
- 可选执行写测试和随机混合读写测试
- 自动保存测试前后的 `nvme` 信息和 `smart-log`
- 自动生成性能汇总表

## 2. 风险说明

必须先明确一点：

- 默认执行的是读测试，风险较低
- 带 `--include-write` 时会执行写测试
- 写测试会破坏目标盘上的原有数据

因此：

- 系统盘禁止参与写测试
- 已有业务数据的盘不要执行写测试
- 不确认盘用途时，先只跑读测试

## 3. 环境要求

服务器 OS 需要具备以下命令：

```bash
lsblk
fio
```

建议同时具备：

```bash
nvme
```

如果缺少 `nvme` 命令，脚本仍可运行，但不会采集 `nvme list`、`id-ctrl`、`smart-log`。

## 4. 脚本测试内容

默认测试项：

- `seq_read`
- `rand_read`

启用 `--include-write` 后增加：

- `seq_write`
- `rand_rw`

如果需要精确控制测试项，可使用：

```bash
--tests seq_read,seq_write,rand_rw
```

当前测试参数：

- 顺序读：`1M` 块大小，`numjobs=1`
- 随机读：`4k` 块大小，`numjobs=4`
- 顺序写：`1M` 块大小，`numjobs=1`
- 随机混合读写：`4k`，`numjobs=4`，`rwmixread=70`

## 5. 系统盘保护逻辑

该脚本会通过以下方式识别系统盘：

1. 读取 `/` 的挂载源
2. 如果根分区挂在 `LVM/mapper` 上，则继续反查到底层物理盘
3. 如果底层盘是 `nvmeXn1`，则视为系统盘
4. 在 `--all` 模式下自动剔除系统盘
5. 如果目标列表里仍出现系统盘，脚本会直接退出

因此，正常情况下：

- `--all` 不会把系统盘加入测试
- `--include-write` 不会对系统盘执行写压测

## 6. 基本使用方法

### 6.1 查看帮助

```bash
bash nvme_fio_auto_test.sh --help
```

### 6.2 测试全部非系统盘，只跑读测试

```bash
bash nvme_fio_auto_test.sh --all --runtime 60 --size 10G
```

这是一线现场最推荐的起步方式。

### 6.3 测试单盘

```bash
bash nvme_fio_auto_test.sh --disk nvme0n1 --runtime 60 --size 10G
```

适用于：

- 单盘抽检
- 指定某块 NVMe 做对比验证
- 怀疑某块盘性能异常时单独拉出来测

### 6.4 执行带写测试的全盘压测

```bash
bash nvme_fio_auto_test.sh --all --include-write --runtime 60 --size 10G
```

执行时脚本会提示：

```text
警告: 已开启写测试，目标盘上的原有数据可能被破坏。
本次计划执行的测试项: seq_read,seq_write,rand_rw
如确认继续，请输入大写 YES:
```

必须输入大写：

```text
YES
```

否则脚本会取消执行。

### 6.5 只跑指定测试项

例如只跑顺序读、顺序写、随机读写混合，不跑随机读：

```bash
bash nvme_fio_auto_test.sh --all --tests seq_read,seq_write,rand_rw --include-write --runtime 60 --size 10G
```

例如只跑单盘顺序读：

```bash
bash nvme_fio_auto_test.sh --disk nvme0n1 --tests seq_read --runtime 60 --size 10G
```

## 7. 建议的现场使用流程

### 场景 A：新机上电后先确认 NVMe 基础状态

先执行：

```bash
lsblk
nvme list
```

确认：

- 在位数量是否正确
- 系统盘是哪一块
- 是否存在缺盘、掉盘、容量异常

然后执行安全读测：

```bash
bash nvme_fio_auto_test.sh --all --runtime 60 --size 10G
```

### 场景 B：单盘性能验证

```bash
bash nvme_fio_auto_test.sh --disk nvme0n1 --runtime 60 --size 10G
```

适合与规格值、样机之间、不同批次盘之间进行横向对比。

### 场景 C：空盘环境下做完整读写验证

确认目标盘不是系统盘且无业务数据后，执行：

```bash
bash nvme_fio_auto_test.sh --all --include-write --runtime 60 --size 10G
```

## 8. 输出结果说明

脚本每次执行会生成一个结果目录，类似：

```bash
fio-results-2026-04-02-130857
```

目录中常见文件如下：

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

- `lsblk.txt`
- `id-ctrl-before.txt`
- `smart-log-before.txt`
- `seq_read.txt`
- `rand_read.txt`
- `seq_write.txt`
- `rand_rw.txt`
- `smart-log-after.txt`

## 9. 如何看汇总结果

优先看：

```bash
cat fio-results-*/summary.md
```

或者：

```bash
column -t -s $'\t' fio-results-*/summary.tsv
```

汇总表包括：

- 磁盘名
- 测试类型（中文）
- 带宽
- IOPS
- 平均时延

现场快速判断时可重点关注：

- 同型号盘之间带宽是否明显偏低
- 同型号盘之间 IOPS 是否偏离明显
- 时延是否异常抬高
- 某块盘是否只在写测试下表现异常

## 10. 如何看原始结果

例如查看 `nvme0n1` 的顺序读结果：

```bash
cat fio-results-*/nvme0n1/seq_read.txt
```

例如查看 `nvme0n1` 的随机读结果：

```bash
cat fio-results-*/nvme0n1/rand_read.txt
```

如果需要核对健康状态变化，可对比：

```bash
cat fio-results-*/nvme0n1/smart-log-before.txt
cat fio-results-*/nvme0n1/smart-log-after.txt
```

## 11. 常见问题

### 11.1 输入了 `yes`，脚本直接取消

这是脚本设计使然。  
当前只有输入大写 `YES` 才继续写测试。

### 11.2 `root_disk=unknown`

说明当前环境下系统盘反查失败。  
此时不要直接使用 `--all --include-write`，应先手动核对：

```bash
lsblk
findmnt -no SOURCE /
```

确认系统盘后，再用 `--disk` 模式测试非系统盘。

### 11.3 报错 `Missing command: fio`

说明未安装 `fio`。  
需要先安装相关工具包。

### 11.4 只想测试某一块盘

使用：

```bash
bash nvme_fio_auto_test.sh --disk nvme0n1
```

### 11.5 为什么默认不跑写测试

因为写测试具备破坏性。  
在服务器整合测试场景里，误写系统盘或业务盘代价很高，所以默认只读。

## 12. 建议的测试记录方式

建议每次执行后至少保留以下内容：

- `summary.md`
- `test-meta.txt`
- `nvme-list-before.txt`
- 问题盘对应的 `smart-log-before.txt`
- 问题盘对应的 `smart-log-after.txt`

如果需要输出测试结论，建议记录：

- 测试时间
- 测试机型
- NVMe 数量
- 系统盘盘号
- 测试命令
- 是否包含写测试
- 异常盘号
- 异常现象

## 13. 推荐命令示例

安全版整机读测：

```bash
bash nvme_fio_auto_test.sh --all --runtime 60 --size 10G
```

单盘读测：

```bash
bash nvme_fio_auto_test.sh --disk nvme0n1 --runtime 60 --size 10G
```

空盘环境下整机读写测试：

```bash
bash nvme_fio_auto_test.sh --all --include-write --runtime 60 --size 10G
```

长时间压测：

```bash
bash nvme_fio_auto_test.sh --all --include-write --runtime 300 --size 20G
```

只跑顺序读、顺序写、随机读写混合：

```bash
bash nvme_fio_auto_test.sh --all --tests seq_read,seq_write,rand_rw --include-write --runtime 60 --size 10G
```


