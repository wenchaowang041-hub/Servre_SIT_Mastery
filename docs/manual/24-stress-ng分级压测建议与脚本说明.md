# stress-ng 分级压测建议与脚本说明

适用场景：

- Kunpeng 920 / 7260Z 等 ARM 服务器
- 整机 bring-up 后稳定性确认
- CPU / 内存长稳压力测试
- 现场快速冒烟与正式 12H 稳定性测试

配套脚本：

- `practice/scripts-练手脚本/stress_12h_kunpeng.sh`

## 1. 为什么默认推荐 `stress-ng`

在服务器整合测试场景里，`stress-ng` 相比 `stress` 更适合做稳定性验证，原因包括：

- 测试项更丰富
- 输出更完整
- 更适合长时间压测
- 可配合 `--metrics-brief`、`--times` 做收尾分析

因此，当前默认建议使用 `stress-ng`，不再默认使用 `stress`。

## 2. 基本思路

对这类 `256` 线程、`2TiB` 内存的大机器，不建议一上来就直接跑最满的 12H。

更合理的方式是分级推进：

1. 先做冒烟测试，确认工具、系统、传感器、日志路径正常
2. 再做 30 分钟或 2 小时短中测
3. 最后做正式 12 小时长稳测试

## 3. 分级压测建议

### 3.1 冒烟测试

用途：

- 验证 `stress-ng` 工具可用
- 验证系统不会立刻报错或死机
- 快速看温度、风扇、告警、日志是否异常

推荐命令：

```bash
stress-ng --cpu 32 --vm 4 --vm-bytes 4G --timeout 300s --metrics-brief --times --tz
```

特点：

- 强度较低
- 5 分钟出结果
- 适合刚装机、刚换件、刚升级后做初步摸底

### 3.2 10 分钟短测

用途：

- 验证脚本、监控和日志采集逻辑是否正常
- 快速看 CPU、内存和温度变化
- 初步确认机器在较高负载下是否稳定

推荐命令：

```bash
stress-ng --cpu 128 --vm 8 --vm-bytes 8G --timeout 600s --metrics-brief --times --tz
```

特点：

- 中等压力
- 内存压力约 `64G`
- 适合现场快速验证

### 3.3 30 分钟短测

用途：

- 看基础稳定性
- 看 CPU / 内存路径是否存在明显异常
- 看温度和告警是否开始出现问题

推荐命令：

```bash
stress-ng --cpu 128 --vm 8 --vm-bytes 8G --timeout 1800s --metrics-brief --times --tz
```

### 3.4 2 小时中测

用途：

- 排查“短测没问题，跑久才出问题”的情况
- 观察温度、负载、传感器、SEL、`dmesg` 是否持续稳定

推荐命令：

```bash
stress-ng --cpu 256 --vm 8 --vm-bytes 8G --timeout 2h --metrics-brief --times --tz
```

### 3.5 12 小时正式稳定性测试

用途：

- 作为整机长稳测试
- 观察是否出现重启、卡死、掉核、告警或内核报错
- 适合作为阶段性验证或交付前验证

推荐命令：

```bash
stress-ng --cpu 256 --vm 8 --vm-bytes 8G --timeout 12h --metrics-brief --times --tz
```

## 4. 为什么不建议默认加 `--io` 和 `--hdd`

除非测试目标本身就是整机混合 IO 压力，否则不建议默认带：

```bash
--io
--hdd
```

原因：

- 会引入大量临时文件
- 会把测试目标从“CPU / 内存稳定性”变成“整机混合压力”
- 出现异常时不利于归因

所以，在 CPU / 内存稳定性验证场景里，默认建议只使用：

- `--cpu`
- `--vm`

## 5. 配套脚本说明

脚本：

- `practice/scripts-练手脚本/stress_12h_kunpeng.sh`

当前脚本能力：

- 基于 `stress-ng`
- 支持 `--hours`
- 支持 `--minutes`
- 默认采集 `lscpu`、`free`、`uptime`
- 运行期间采集 `mpstat`、`top`
- 如果环境存在 `ipmitool`，会采集 `sensor` 和 `SEL`
- 收尾时保留前后日志

## 6. 推荐脚本用法

10 分钟验证版：

```bash
bash stress_12h_kunpeng.sh --minutes 10 --cpu 128 --vm 8 --vm-bytes 8G
```

30 分钟短测：

```bash
bash stress_12h_kunpeng.sh --minutes 30 --cpu 128 --vm 8 --vm-bytes 8G
```

2 小时中测：

```bash
bash stress_12h_kunpeng.sh --hours 2 --cpu 256 --vm 8 --vm-bytes 8G
```

12 小时正式测试：

```bash
bash stress_12h_kunpeng.sh --hours 12 --cpu 256 --vm 8 --vm-bytes 8G
```

## 7. 结果查看建议

重点看以下文件：

- `stress-ng.log`
- `runtime-status.log`
- `ipmitool-sensor-before.txt`
- `ipmitool-sensor-after.txt`
- `ipmitool-sel-before.txt`
- `ipmitool-sel-after.txt`
- `dmesg-before.txt`
- `dmesg-after.txt`

如果脚本版本已支持差异文件，还可以优先看：

- `ipmitool-sensor-diff.txt`
- `ipmitool-sel-diff.txt`
- `dmesg-diff.txt`

## 8. 现场判定重点

测试完成后，重点关注：

- `stress-ng` 是否正常完成
- 是否有 `failed`、`error`、`killed`
- CPU 温度是否异常飙高
- SEL 是否新增告警
- `dmesg` 是否新增报错、reset、AER、I/O error
- `top` / `mpstat` 中 CPU 是否达到预期负载

## 9. 当前建议

对于你当前这台 `Kunpeng 920 7260Z / 256 线程 / 2TiB 内存` 的整机，推荐顺序为：

1. 先跑 10 分钟验证版
2. 再跑 30 分钟短测
3. 再跑 12 小时正式稳定性测试

这样能兼顾：

- 现场效率
- 风险控制
- 问题收敛速度
