# 第三章 BIOS/UEFI 设置与优化

## 1. 模块概述与重要性

BIOS/UEFI 是服务器硬件整合测试里最容易被低估、但最影响结果上限的模块之一。

很多工程现场的“性能问题”“稳定性问题”“兼容性问题”，根因都不是 OS、驱动或应用，而是 BIOS/UEFI 设置不合理。最典型的场景包括：

- CPU 没开高性能模式，导致频率拉不上去
- NUMA/SNC/NPS 配置不对，导致跨节点访问变多
- PCIe 链路策略保守，导致 GPU/NPU/NIC 没跑满
- 内存模式和 RAS 设置不合理，导致带宽下降或时延上升
- C-state、P-state、ASPM、SR-IOV、IOMMU、Above 4G Decoding 等选项没配好，导致性能或兼容性异常
- BMC 与 BIOS 联动策略保守，导致整机散热与功耗控制异常

你要记住一句非常重要的话：

在服务器测试里，BIOS/UEFI 不是“开机菜单”，而是整机行为的第一层控制平面。

高级工程师看 BIOS/UEFI，不是靠“记菜单”，而是靠理解下面三件事：

1. 哪些选项影响功能识别
2. 哪些选项影响性能上限
3. 哪些选项影响稳定性和兼容性

如果你能把这三件事建立成系统方法，你在 CPU、内存、网络、存储、GPU/NPU 的测试结论会明显更稳。

## 2. 2026年厂商与主流产品信息对比表

> 本章对比表只聚焦 BIOS/UEFI 与固件生态，不列无关器件。服务器厂商最终呈现的菜单名称可能不同，但底层能力大多来自以下 BIOS/UEFI 生态。

| 厂商/项目 | 2026主流 BIOS/UEFI 方向 | 典型产品/平台 | 核心能力 | 典型服务器场景 | 测试关注重点 |
|---|---|---|---|---|---|
| AMI | Aptio V / MegaRAC 生态 | 大量 x86/ARM 服务器采用 | UEFI、Secure Boot、Redfish/BMC 协同、OEM 定制能力强 | 通用服务器、AI 服务器、OEM/ODM 平台 | 功耗策略、PCIe、Secure Boot、BMC 联动 |
| Insyde | InsydeH2O UEFI | 部分服务器、嵌入式与行业平台 | UEFI、OEM 定制、安全启动与平台适配 | 行业服务器、定制平台 | 兼容性、启动流程、固件升级回归 |
| Phoenix | SecureCore UEFI | 工控/行业设备及部分服务器场景 | 安全启动、平台初始化、OEM 集成 | 定制服务器与行业平台 | 启动链、设备枚举、安全选项 |
| Tianocore | EDK II 开源 UEFI 生态 | 开源/参考平台，部分厂商定制基础 | UEFI 参考实现、可扩展、社区活跃 | ARM/开放平台、研发验证 | 启动链、模块裁剪、驱动兼容 |
| 华为服务器平台固件 | 华为服务器 BIOS + BMC 协同 | Kunpeng / TaiShan / Ascend 服务器 | 平台化电源策略、RAS、BMC 管理联动 | 鲲鹏/昇腾服务器 | 功耗模式、RAS、NPU/整机协同 |
| Dell / HPE / Lenovo / Inspur / xFusion 等 OEM | OEM 定制 BIOS/UEFI | PowerEdge、ProLiant、ThinkSystem 等 | 在 AMI/Insyde 等底层上做 OEM 定制 | 企业/云/AI 服务器 | 菜单映射、默认值、批量配置一致性 |

## 3. 基础原理讲解（通俗易懂）

### 3.1 BIOS 和 UEFI 到底是什么

传统说法里，很多人把它统称为 BIOS。更准确地说：

- BIOS 是更老一代的固件启动模式
- UEFI 是现代服务器主流固件接口和启动架构

工程现场你仍然会听到“BIOS 设置”这个说法，但 2026 年主流服务器几乎都是 UEFI 体系下的服务器 BIOS 菜单。

你可以把 BIOS/UEFI 理解成：

- 上电后最先控制硬件初始化的固件层
- 操作系统启动前，对 CPU、内存、PCIe、启动设备、安全策略、虚拟化能力进行配置的入口
- 和 BMC 一起定义整机运行边界的核心平面

### 3.2 为什么 BIOS/UEFI 会显著影响测试结果

因为很多系统行为在 OS 启动之前就已经被决定了。

例如：

#### CPU 相关

- 是否启用 SMT / Hyper-Threading
- 是否启用高性能功耗模式
- 是否启用 C-state 深度节能
- 是否启用 SNC / NPS

#### 内存相关

- 内存运行频率
- Patrol Scrub / Demand Scrub
- ECC / RAS / 镜像 / Sparing
- CXL memory 配置

#### PCIe / 加速器相关

- PCIe Gen 速率上限
- Lane bifurcation
- Above 4G Decoding
- SR-IOV
- IOMMU / VT-d / SMMU

#### 启动与安全相关

- UEFI / Legacy 启动模式
- Secure Boot
- TPM / TCM
- Boot Order

也就是说，BIOS/UEFI 不是“调优附属品”，而是决定整机测试起跑线的配置层。

### 3.3 BIOS/UEFI 常见设置的逻辑分组

为了后续排查更高效，建议你把 BIOS 选项按下面几类理解：

#### 3.3.1 启动与安全类

- Boot Mode
- Secure Boot
- TPM / TCM
- PXE Boot
- Boot Order

重点看：机器能否稳定引导、能否满足安全合规要求。

#### 3.3.2 CPU 与功耗类

- Hyper-Threading / SMT
- C-state
- P-state
- Performance Profile
- Determinism
- Turbo / Boost

重点看：性能能否跑满，时延是否稳定。

#### 3.3.3 NUMA 与内存类

- SNC / NPS
- Memory Interleaving
- Patrol Scrub
- ECC / RAS
- Memory Frequency
- CXL Memory

重点看：内存带宽、时延、可靠性和 NUMA 行为。

#### 3.3.4 PCIe 与虚拟化类

- PCIe Speed
- ASPM
- SR-IOV
- VT-d / IOMMU / SMMU
- Above 4G Decoding
- ACS / ATS / PASID

重点看：网卡、NVMe、GPU/NPU/DPU 是否能正确枚举并达到性能设计值。

### 3.4 BIOS/UEFI 和 BMC 的关系

很多测试人员把 BIOS 和 BMC 分开看，这不够。服务器平台里，它们经常是联动的。

例如：

- BMC 负责风扇策略，BIOS 决定 CPU 功耗模式
- BMC 负责固件升级管控，BIOS 决定设备初始化策略
- BMC 提供传感器和 SEL 日志，BIOS 改变 RAS 和功耗边界

所以做 BIOS 测试时，一定要同时记录：

- BIOS 版本
- BMC 版本
- BIOS 设置变更项
- 改动前后传感器与性能变化

### 3.5 三种最常见的 BIOS 测试错误

#### 错误 1：改了 BIOS，但没留基线

后果：性能变了也不知道是哪个选项导致的。

#### 错误 2：一次改太多项

后果：问题出现后无法定位根因。

#### 错误 3：只看性能，不看稳定性和兼容性

后果：短期跑分提高了，长稳和量产却翻车。

## 4. 详细测试用例

### 用例 1：BIOS/UEFI 版本与当前设置基线采集

#### 测试目的

采集 BIOS/UEFI 当前版本、发布日期、启动模式和关键固件设置基线，作为后续调优和回归的依据。

#### 前置条件

- 服务器已可进入操作系统
- 有权限读取 BIOS 信息

#### 所需工具

- `dmidecode`
- `efibootmgr`
- `mokutil`
- `ipmitool`

#### 测试步骤

1. 采集 BIOS 版本和发布日期。
2. 确认当前是否为 UEFI 启动。
3. 检查 Secure Boot 状态。
4. 记录当前 BootOrder。
5. 结合 BMC 记录当前固件基线。

#### 完整测试命令

```bash
TS=$(date +%F_%H%M%S)
OUT=/tmp/bios_baseline_${TS}
mkdir -p "${OUT}"

dmidecode -t bios > "${OUT}/01_dmidecode_bios.txt"
test -d /sys/firmware/efi && echo "UEFI" || echo "Legacy" > "${OUT}/02_boot_mode.txt"
efibootmgr -v > "${OUT}/03_efibootmgr.txt" 2>/dev/null || true
mokutil --sb-state > "${OUT}/04_secure_boot.txt" 2>/dev/null || true
ipmitool mc info > "${OUT}/05_bmc_info.txt"

echo "bios baseline saved to ${OUT}"
```

#### 关键参数解析

| 参数/命令 | 含义 | 作用 |
|---|---|---|
| `dmidecode -t bios` | BIOS 信息 | 看 BIOS 版本、厂商、发布日期 |
| `/sys/firmware/efi` | EFI 固件目录 | 判断是否在 UEFI 模式启动 |
| `efibootmgr -v` | UEFI 启动项 | 看启动顺序与设备路径 |
| `mokutil --sb-state` | Secure Boot 状态 | 看安全启动是否开启 |
| `ipmitool mc info` | BMC 版本 | 做 BIOS/BMC 联动基线 |

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `Version` | BIOS 版本 | 在项目支持矩阵内 | 过旧：先升级再测试 |
| `Release Date` | BIOS 发布时间 | 应可追溯 | 过旧版本需评估已知问题 |
| `UEFI/Legacy` | 启动模式 | 现代服务器通常建议 UEFI | Legacy：核对项目要求 |
| `Secure Boot` | 安全启动状态 | 视项目策略而定 | 不符安全要求：调整后重测 |
| `BootOrder` | 启动顺序 | 与测试计划一致 | 顺序错误：易导致误启动或 PXE 干扰 |

### 用例 2：高性能模式 BIOS 设置验证

#### 测试目的

验证 BIOS 是否已切换到适合性能测试的模式，避免 CPU 频率、内存、PCIe 因省电策略受限。

#### 前置条件

- 可进入 BIOS 配置界面或已通过带外工具批量下发设置
- OS 已安装 CPU 频率检查工具

#### 所需工具

- BIOS Setup 界面
- `cpupower`
- `lscpu`
- `turbostat`

#### 测试步骤

1. 进入 BIOS，记录默认功耗配置。
2. 切换到 `Performance` 或等效高性能模式。
3. 关闭不必要的深度节能策略，如过深 C-state。
4. 保存退出并重启。
5. 进 OS 后验证 governor、实际频率和性能变化。

#### 完整测试命令

```bash
cpupower frequency-info
lscpu | egrep "Model name|CPU\\(s\\)|Thread\\(s\\) per core|Socket\\(s\\)"
turbostat --Summary --show Busy%,Bzy_MHz,TSC_MHz,PkgWatt -i 5 -n 6 2>/dev/null || true
```

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `governor` | 调频模式 | 压测场景常为 `performance` | `powersave`：查 BIOS/OS 双侧设置 |
| `Bzy_MHz` | 忙碌频率 | 应接近场景预期 | 偏低：查功耗模式、温度、功耗墙 |
| `PkgWatt` | 包功耗 | 满载时应合理上升 | 过低：可能未进入高性能模式 |

### 用例 3：NUMA / SNC / NPS 设置验证

#### 测试目的

验证 BIOS 中 NUMA 相关设置是否符合测试目标，并确认操作系统中实际生效。

#### 前置条件

- 双路或多路平台
- 支持 SNC（Intel）或 NPS（AMD）或同类 NUMA 分区能力

#### 所需工具

- BIOS Setup
- `lscpu`
- `numactl`

#### 测试步骤

1. 在 BIOS 中记录当前 SNC / NPS 设置。
2. 保存当前模式，进入 OS。
3. 采集 `lscpu` 与 `numactl -H`。
4. 修改为另一种模式后重启。
5. 对比 NUMA 节点数量和内存分布差异。

#### 完整测试命令

```bash
lscpu
numactl -H
lscpu -e=cpu,node,socket,core,online
```

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `NUMA node(s)` | NUMA 节点总数 | 与 BIOS 模式一致 | 不一致：设置未生效或固件问题 |
| `nodeX cpus` | 节点 CPU 列表 | 应分配合理 | 分布异常：查固件和 CPU 枚举 |
| `nodeX size` | 节点内存容量 | 应接近设计目标 | 偏差大：查 DIMM 插法和模式 |

### 用例 4：PCIe 相关 BIOS 设置验证

#### 测试目的

验证 PCIe 速率、Above 4G Decoding、SR-IOV、IOMMU 等 BIOS 设置是否满足 GPU/NPU/NIC/NVMe 测试要求。

#### 前置条件

- 平台已安装关键 PCIe 设备

#### 所需工具

- BIOS Setup
- `lspci`
- `dmesg`

#### 测试步骤

1. 在 BIOS 中检查 PCIe Speed 是否为 Auto 或目标代际。
2. 检查 Above 4G Decoding 是否开启。
3. 检查 SR-IOV、IOMMU/VT-d/SMMU 是否按场景开启。
4. 进入 OS 后检查关键设备枚举和链路状态。
5. 对比设置前后设备数量和链路宽度/速率。

#### 完整测试命令

```bash
lspci
lspci -vv
dmesg -T | egrep -i "pci|pcie|iommu|vfio|sriov"
```

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `LnkCap` | PCIe 最大能力 | 与设备设计一致 | 仅用于对比 |
| `LnkSta` | 当前链路状态 | 接近设计值 | 降宽/降速：查 BIOS、插槽、riser |
| `SR-IOV` 相关日志 | 虚拟功能能力 | 按场景正常出现 | 无法启用：查 BIOS 与驱动 |
| `IOMMU` 日志 | DMA 映射能力 | 按需求启用 | 关闭导致虚拟化/DPU 场景受限 |

### 用例 5：启动模式与安全启动回归测试

#### 测试目的

验证 UEFI 启动、Secure Boot、PXE 启动、Boot Order 调整后，服务器仍可稳定引导并满足安全要求。

#### 前置条件

- 已有可用系统盘和可选 PXE 环境

#### 所需工具

- BIOS Setup
- `efibootmgr`
- `mokutil`
- `journalctl`

#### 测试步骤

1. 记录当前 BootOrder。
2. 修改 BootOrder 或切换 PXE 优先级。
3. 切换 Secure Boot 开关。
4. 反复重启，检查系统能否稳定进入 OS。
5. 检查内核日志中是否出现启动链相关异常。

#### 完整测试命令

```bash
efibootmgr -v
mokutil --sb-state 2>/dev/null || true
journalctl -b | egrep -i "secure boot|efi|tpm|shim|grub"
```

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `BootCurrent` | 当前启动项 | 应与预期一致 | 偏离：查 BootOrder 和设备路径 |
| `BootOrder` | 启动顺序 | 与测试目标一致 | 顺序错误：调整 BIOS 启动项 |
| `SecureBoot` | 安全启动状态 | 与项目要求一致 | 不符：补签名或调整策略 |

### 用例 6：BIOS 改动前后性能回归验证

#### 测试目的

验证 BIOS 设置变更是否真正带来性能收益，且没有引入稳定性和兼容性回退。

#### 前置条件

- 已保存改动前 BIOS 关键配置
- 有可复现的 CPU/内存/网络/存储基线测试

#### 所需工具

- `sysbench`
- `fio`
- `iperf3`
- `ipmitool`

#### 测试步骤

1. 在改动 BIOS 前先执行一轮基线测试。
2. 修改目标 BIOS 选项。
3. 重启并确认 BIOS 设置已经生效。
4. 重新执行相同测试。
5. 对比性能、温度、日志、稳定性是否一起变化。

#### 完整测试命令

```bash
sysbench cpu --cpu-max-prime=20000 --threads=$(nproc) run
fio --name=randread --filename=/data/fio.test --size=10G --rw=randread --bs=4k --iodepth=64 --ioengine=libaio --direct=1 --runtime=60 --time_based --group_reporting
iperf3 -c <server_ip> -P 8 -t 60
ipmitool sensor
```

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `events per second` | CPU 吞吐 | 调优后应符合预期 | 无变化：设置可能未生效 |
| `BW/IOPS` | 存储吞吐/IOPS | 不应异常下降 | 下降：查 PCIe、IOMMU、NUMA |
| `iperf3 bitrate` | 网络带宽 | 不应下降 | 下降：查中断和 PCIe 策略 |
| `sensor` | 温度与功耗 | 不应出现新的告警 | 告警增加：性能提升可能不可持续 |

### 用例 7：BIOS 出厂恢复与最小改动法验证

#### 测试目的

验证 BIOS 设置异常时，能否通过恢复默认值和最小改动法快速定位问题根因。

#### 前置条件

- 允许维护窗口内重启

#### 所需工具

- BIOS Setup
- 配置记录表
- 基线采集脚本

#### 测试步骤

1. 导出或拍照记录当前 BIOS 设置。
2. 恢复 BIOS 默认值。
3. 进入系统，验证基础识别是否恢复正常。
4. 按“每次只改 1 到 2 项”的原则逐步恢复目标设置。
5. 每轮都做最小基线验证。

#### 完整测试命令

```bash
lscpu
numactl -H
lspci | egrep -i "ethernet|non-volatile|vga|3d|processing accelerators"
ipmitool sensor
```

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `CPU(s)` | CPU 识别情况 | 与规格一致 | 恢复默认后仍异常：偏向硬件问题 |
| `NUMA node(s)` | NUMA 情况 | 与默认设计一致 | 默认仍异常：查固件或硬件 |
| `关键 PCIe 设备数量` | 设备枚举情况 | 与实配一致 | 默认仍漏卡：查插槽/供电/固件 |

## 5. 结果分析与问题诊断方法

### 5.1 BIOS 问题的分析总思路

不要一看到性能问题就盲改 BIOS。正确顺序是：

1. 先确认当前 BIOS 版本和关键设置
2. 再明确你的测试目标是性能、稳定性还是兼容性
3. 每次只改少量设置
4. 每次改完都做最小回归
5. 保留变更前后日志

### 5.2 常见异常一：改完 BIOS 后性能没提升

常见原因：

- 设置根本没生效
- OS governor 把 BIOS 的高性能设置抵消了
- 热设计不足，性能提升后反而更快降频
- 负载根本不是 CPU 瓶颈

排查顺序：

1. 查 BIOS 设置是否保存成功
2. 查 OS 中频率和 governor
3. 查温度和包功耗
4. 查专项负载是否真的受该设置影响

### 5.3 常见异常二：改完 BIOS 后设备丢失或系统不稳定

常见原因：

- PCIe 代际强制过高
- SR-IOV / IOMMU / Above 4G Decoding 组合不合理
- Legacy/UEFI 启动切换导致引导项失效
- 内存 RAS 或频率设置过于激进

排查顺序：

1. 先恢复到上一个可用配置
2. 查 `dmesg`、BMC SEL
3. 检查关键设备枚举和启动项
4. 用最小改动法逐项回放

### 5.4 常见异常三：不同批次机器 BIOS 默认值不一致

这在量产导入或多机房交付中非常常见。

风险：

- 同型号机器性能不一致
- 同样的脚本结果波动大
- 问题难以批量复现

建议：

1. 固化 BIOS 版本
2. 固化关键选项模板
3. 上线前做批量抽检
4. 记录 BIOS profile 或带外配置文件

## 6. 最佳实践与注意事项

1. BIOS 改动前必须先做基线采集。
2. 每次只改 1 到 2 个关键选项，不要一次改一屏菜单。
3. 性能调优必须同时观察温度、功耗和稳定性。
4. Intel 平台重点关注 SNC、HT、C-state、Power Profile、VT-d。
5. AMD 平台重点关注 NPS、SMT、Determinism、IOMMU。
6. 华为 Kunpeng / Ascend 平台重点关注平台固件版本、功耗模式、RAS 和整机联动设置。
7. GPU/NPU/DPU 平台必须特别关注 PCIe、Above 4G Decoding、SR-IOV/IOMMU 和启动兼容性。
8. 任何 BIOS 优化结果都必须通过 OS 层和业务层验证，不能只凭菜单判断。

## 7. 进阶内容（高阶测试技巧、自动化思路、多厂商混配测试等）

### 7.1 BIOS 批量一致性管理

在真实项目里，最值钱的不是“单台机器调优成功”，而是“100 台机器调成一致”。

建议你后续沉淀这几样东西：

- BIOS 关键配置基线表
- BIOS 版本矩阵
- 带外批量下发流程
- BIOS 变更后的最小回归脚本

### 7.2 建议建立 BIOS 风险分级

可以把 BIOS 选项分成三类：

- A 类：高风险
  - 启动模式、PCIe、IOMMU、内存 RAS
- B 类：中风险
  - C-state、SMT、NUMA/SNC/NPS
- C 类：低风险
  - BootOrder、非关键外设开关

这样可以指导测试顺序和回滚优先级。

### 7.3 高级工程师的标准输出方式

完成 BIOS/UEFI 测试后，你应该能输出类似这样的结论：

“当前平台 BIOS 版本处于项目支持范围，已完成启动模式、CPU 功耗模式、NUMA 分区、PCIe 关键选项和安全启动状态核查。经对比验证，开启高性能模式后 CPU 吞吐提升明显，但在满载长稳阶段出现温度边界收紧现象；开启 Above 4G Decoding 与 IOMMU 后 GPU/NPU 枚举恢复正常。建议将当前配置固化为项目基线，并在批量导入前做多机一致性抽检。”

## 参考来源

- [AMI Aptio V / Firmware Solutions](https://www.ami.com/aptio/)
- [AMI MegaRAC](https://www.ami.com/megatrac/)
- [InsydeH2O UEFI Firmware](https://www.insyde.com/products)
- [Phoenix SecureCore](https://www.phoenix.com/phoenix-securecore/)
- [EDK II / Tianocore](https://www.tianocore.org/edk2/)
