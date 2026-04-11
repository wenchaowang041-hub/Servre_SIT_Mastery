# DC500cycles DC Cycle 硬件告警分析报告

## 基本信息

- 数据包：`E:\桌面\金丝雀\2SW\DC500cycles_Log.zip`
- 场景：`DC cycle 500圈`
- 关注点：`服务器系统下检查 dmesg 报 Hardware Error`
- 关联 BUG ID：`3461`
- 结论摘要：`500 圈稳定复现 recoverable APEI Hardware Error，未见 fatal / uncorrected / MCE`

## 汇报版结论

- `DC cycle 500圈` 已完整执行结束，但系统在每轮启动早期都稳定报出 `APEI recoverable Hardware Error`，问题具备稳定复现性。
- 除 `dmesg` 告警外，日志对比还显示 `ipmi_sdr` 存在全程一致性的 NPU 温度传感器状态差异，`pcie_details` 存在 `TransPend` 状态位间歇性变化，说明平台侧还存在附加异常信号。
- `ipmi_sel.log` 未提供明确的 FRU 级硬件故障定位，而且 SEL 在循环过程中持续被 `reset/cleared`，因此当前日志只能确认“平台/固件/硬件链路存在异常”，还不能直接锁定具体器件。
- 现阶段建议维持 BUG `3461` 打开状态，并继续沿 `APEI + PCIe + 传感器时序` 三条线并行定位。

## 建议动作

1. 补采一轮不清 SEL 的 `DC cycle`，保留完整 SEL 证据，确认是否存在被清空掩盖的器件级事件。
2. 对出现 `pcie_details` 差异的轮次做定点复查，重点关注对应设备 `DevSta` 中 `TransPend` 位变化前后的链路状态。
3. 对 NPU 温度传感器做开机后分时采样，确认 `ns -> ok` 是否只是初始化时序问题，而不是传感器丢失。
4. 结合同平台的 `warm reboot`、`AC cycle`、`OS cycle` 结果做横向比对，判断问题是否只出现在 `DC cycle` 上电路径。

## 问题现象

`DC500cycles_Log.zip` 中的 `log_reboot.txt` 显示本次 DC cycle 从 `DC 1` 跑到 `DC 500`，时间范围为 `2026-04-03 16:49:32` 到 `2026-04-05 04:14:29`，说明测试流程本身完整执行结束。

但在 `DC500cycles_Log/dmesg_error.log` 中，系统在启动早期就持续报出同一类硬件告警：

```text
[    0.674409] {1}[Hardware Error]: Hardware error from APEI Generic Hardware Error Source: 0
[    0.674415] {1}[Hardware Error]: event severity: recoverable
[    0.674418] {1}[Hardware Error]:  Error 0, type: recoverable
```

这类告警在整个 500 圈过程中反复出现，属于稳定复现，而不是单次偶发。

## 日志证据

### 1. dmesg 告警特征

从 `dmesg_error.log` 统计结果看：

- `APEI Generic Hardware Error Source: 0` 出现 `500` 次
- `recoverable` 出现 `1000` 次
- `fatal` 出现 `0` 次
- `uncorrected` 出现 `0` 次
- `MCE` 出现 `0` 次

说明当前问题的性质是：

- OS 已经感知到硬件层告警
- 告警类型是可恢复级别
- 没有升级成更严重的致命错误或不可纠正错误

### 2. SEL 侧证据

`DC500cycles_Log/ipmi_sel.log` 中没有检到对应的 `Hardware Error / MCE / DIMM` 关键字，说明这次异常更偏向 OS / APEI 侧告警，而不是 BMC SEL 已明确记录的器件级致命故障。

### 3. 时间特征

该硬件告警在启动极早期就出现，首批日志时间大约在 `0.664s ~ 0.674s` 左右，说明它不是运行很久之后才出现的性能抖动，而是开机阶段就已经存在的稳定告警。

## 结论

当前 `DC cycle` 的失败点可以整理为：

1. `DC cycle` 过程能完整跑完 500 圈，但每轮启动后都会出现同类 `APEI recoverable Hardware Error`。
2. 告警级别为 `recoverable`，目前没有看到 `fatal`、`uncorrected`、`MCE` 等更严重错误。
3. 由于 `ipmi_sel.log` 未同步给出更明确的 FRU / 器件定位信息，现阶段还不能仅凭这包日志直接锁定具体硬件部件。
4. 该问题与前面反馈的 `BUG ID: 3461` 现象一致，可视为同一类问题。

## 后续建议

- 优先继续追 `APEI` / 固件 / 平台硬件链路，确认告警来源到底是 BIOS、BMC、主板还是某个 PCIe / 扩展器件。
- 结合同一套机器的 `warm reboot`、`power cycle`、`冷启动` 差异，判断是否只在特定上电流程中复现。
- 如果后续能拿到更完整的 `rasdaemon`、`mcelog` 或更细的 `dmesg` 前后文，再进一步定位到具体模块或总线。
- 若要形成正式结论，建议把这类结果表述为：`系统在 DC cycle 启动过程中稳定报 recoverable APEI Hardware Error，需继续定位平台硬件/固件链路`。

## 补充检查发现

在进一步复查 `contrast/diff_fail.log`、`contrast/fail_details.log` 和 `ipmi_sel.log` 后，除 `dmesg_error.log` 中稳定复现的 `APEI recoverable Hardware Error` 外，还发现以下附加问题：

### 1. ipmi_sdr 基线差异贯穿整个 500 圈

`contrast/diff_fail.log` 中，`/root/log/base_round/ipmi_sdr.log` 在 `500` 圈中均出现差异记录，说明这不是个别轮次的偶发项，而是全程存在的基线不一致。

结合 `fail_details.log` 看，差异主要集中在多张 NPU 的 `CORE Temp` 传感器状态：

- 基线侧为 `ok`
- 对比侧为 `ns`

典型字段包括：`NPU1/2/3/4/5/8/10/11/12/13 CORE Temp`。

这类差异更像是传感器就绪时序或采集时点不一致，而不是明确的硬件故障，因为同一批设备的 `Power` 项保持 `ok`，且差异模式在各轮次基本一致。

### 2. pcie_details 存在间歇性状态位差异

`contrast/diff_fail.log` 中，`/root/log/base_round/pcie_details.log` 共出现 `36` 次差异，涉及轮次包括 `12`、`30`、`32`、`112`、`302`、`499` 等。

从 `fail_details.log` 的具体 diff 看，这些差异并不是设备枚举丢失，而是同一 PCIe 设备 `DevSta` 字段中的 `TransPend` 位发生变化：

```text
- DevSta: CorrErr+ NonFatalErr- FatalErr- UnsupReq+ AuxPwr- TransPend+
+ DevSta: CorrErr+ NonFatalErr- FatalErr- UnsupReq+ AuxPwr- TransPend-
```

这说明 PCIe 链路至少存在状态位抖动或采样窗口差异。现有日志不足以直接判定为致命故障，但它属于值得继续跟踪的平台侧异常信号。

### 3. 第 5 轮附近存在记录异常

`contrast/diff_fail.log` 与 `ipmi_sel.log` 都显示 `Round 5 / Reboot Count 5` 出现重复记录：

- `diff_fail.log` 中有两条 `Round 5 Ended`，时间分别为 `2026-04-03 17:10:55` 和 `2026-04-03 17:27:30`
- `ipmi_sel.log` 中 `Reboot Count: 5` 也出现重复，其中第二段只有 `Log area reset/cleared`

这说明第 5 轮附近可能发生过一次中断、重试，或日志采集链路不完整。它不一定是根因，但会影响单轮追溯的可信度。

### 4. SEL 在每轮都会被 reset/cleared

`ipmi_sel.log` 中每个 `Reboot Count` 的首条几乎都是：

- `Event Logging Disabled SEL Status | Log area reset/cleared | Asserted`

这意味着 SEL 在循环过程中持续被清空或重置，因此即便存在瞬时硬件事件，也可能无法通过最终 SEL 留存完整关联证据。换句话说，SEL 在这套日志里的取证价值有限，不能因为未见 FRU 级错误就完全排除底层器件或链路问题。

## 补充结论

因此，这包 `DC500cycles` 日志不能只下“APEI recoverable Hardware Error”这一条结论，还应补充说明：

1. `ipmi_sdr` 存在全程一致性的 NPU 温度传感器状态差异，更像传感器采集时序问题。
2. `pcie_details` 存在 `TransPend` 状态位间歇性变化，提示 PCIe 侧仍有波动信号。
3. 第 `5` 轮附近存在记录重复/不完整现象，说明日志链路本身也有异常点。
4. 由于 SEL 在循环中被重复清空，现有 SEL 结果只能作为弱佐证，不能作为“无硬件问题”的强证据。

## 对外汇报简版

本次 `DC cycle 500圈` 测试已完整执行结束，但服务器在每轮启动早期均稳定报出 `APEI recoverable Hardware Error`，问题具备稳定复现性。进一步复查发现，除 `dmesg` 告警外，`ipmi_sdr` 在 500 圈中均存在 NPU 温度传感器状态差异，`pcie_details` 在 36 个轮次出现 `TransPend` 状态位变化，且第 5 轮附近存在重复记录现象，说明平台侧仍存在附加异常信号。由于 `ipmi_sel.log` 在循环过程中持续被 `reset/cleared`，当前日志尚不足以直接锁定具体 FRU，但可以确认异常并非单次偶发，建议继续沿 `APEI`、`PCIe` 和传感器初始化时序三条方向并行定位，BUG `3461` 维持打开并继续跟踪。
