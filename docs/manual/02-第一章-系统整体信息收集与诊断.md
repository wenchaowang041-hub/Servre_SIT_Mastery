# 第一章 系统整体信息收集与诊断

## 1. 模块概述与重要性

系统整体信息收集与诊断，是整套服务器硬件整合测试的“起手式”。这一章决定两件事：

1. 你是否真的知道自己在测哪一台机器。
2. 你后续所有性能、稳定性、兼容性结论，是否有可信的环境基线。

很多工程现场的问题，不是出在“专项测试做得不够”，而是出在一开始没有把整机静态信息、运行状态、版本链和告警链收干净。典型后果包括：

- 把工程样机误当量产机，导致性能结论失真
- CPU / DIMM / SSD / NIC 实配与配置单不一致
- BIOS、BMC、CPLD、驱动版本混乱，问题无法复现
- PCIe 链路降速、降宽但无人发现
- 传感器或风扇策略异常，导致后续烧机中途降频
- GPU/NPU/DPU 已掉卡或跑在异常模式，却被误当作负载问题

高级工程师在这一章的核心能力，不是“会跑多少命令”，而是：

- 建立基线
- 识别偏差
- 做证据链
- 给出风险判断

你必须形成一个习惯：正式测试之前，先回答“当前平台的身份、版本、拓扑、健康状态和运行模式是什么”。如果这五件事答不清楚，后续所有测试都不具备交付价值。

## 2. 2026年厂商与主流产品信息对比表

> 说明：表格用于帮助测试工程师建立“整机平台认知基线”，不是替代官方 datasheet。规格优先采用 2025-2026 年厂商公开资料。

| 厂商 | 2026主流平台/器件 | 类型 | 关键规格 | 管理/互联特点 | 测试关注重点 | 典型场景 |
|---|---|---|---|---|---|---|
| 华为 | Kunpeng 950 | CPU | 96核192线程 / 192核384线程 | 面向 TaiShan 950 SuperPoD，支持四层隔离 | `lscpu`、`dmidecode`、NUMA、BMC、RAS | 通算、数据库、虚拟化 |
| 华为 | TaiShan 950 SuperPoD | 通算超节点 | 最多16节点、32处理器、48TB内存 | 支持 DPU/SSD/内存池化 | 多节点身份识别、拓扑一致性、BMC 批量管理 | 企业核心业务、主机替代 |
| 华为 | Ascend 950PR / 950DT | NPU | 950PR 面向推荐/Prefill；950DT 提供 144GB 和 4TB/s 访存带宽 | 统一互联，面向 Atlas 950 平台 | `npu-smi`、驱动/CANN、功耗温度、互联状态 | 训练、推理、推荐 |
| 华为 | Atlas 950 SuperPoD | AI 超节点 | 满配 8192 个 Ascend 950DT | 16PB/s 全光互联 | 多节点统一视图、BMC/NPU 管理、链路诊断 | 大模型训练 |
| Intel | Xeon 6 / Xeon 6980P | CPU | 最高 128 核，12 通道 DDR5，支持 MRDIMM | PCIe 5.0、UPI、CXL 能力依平台而定 | BIOS 模式、SNC、频率、UPI、PCIe 枚举 | 通算、AI Host |
| AMD | EPYC 9005 / EPYC 9965 | CPU | 最高 192 核，12 通道 DDR5-6400，160 条 PCIe 5.0 | 高 I/O 密度，支持 CXL 2.0 | NPS、IOMMU、PCIe lane、内存均衡 | 云、虚拟化、GPU Host |
| NVIDIA | DGX B200 | AI 服务器 | 8x Blackwell GPU，1440GB HBM3e，64TB/s，约14.3kW | NVLink 14.4TB/s，BlueField-3，ConnectX-7 | GPU/DPU/网卡/BMC/存储统一基线采集 | AI 工厂 |
| Dell / HPE / Lenovo 等 | 2026 主流 2U/4U AI 服务器 | 整机平台 | 普遍支持双路 CPU + 多 GPU/NPU + 多网卡 + 多 NVMe | Redfish/BMC、PCIe Gen5/CXL | DMI、FRU、BMC、链路与传感器检查 | 企业与云数据中心 |

## 3. 基础原理讲解（通俗易懂）

### 3.1 什么叫“系统整体信息”

“系统整体信息”不是一条 `lscpu` 就完事，而是五大类：

1. 身份信息
   - 机器型号、序列号、主板、BIOS、BMC、FRU、资产编号
2. 资源信息
   - CPU、内存、网卡、存储、PCIe 设备、GPU/NPU/DPU 数量与型号
3. 拓扑信息
   - NUMA、PCIe Root Port、链路宽度、链路速率、设备归属关系
4. 健康信息
   - 温度、电压、风扇、PSU、ECC/RAS、AER、告警计数
5. 软件信息
   - OS、Kernel、驱动、固件、工具链、服务状态

你可以把它理解成给服务器做一次“全身建档”。建档不完整，后面任何诊断都会变慢。

### 3.2 为什么信息收集不只是“记录”，而是“诊断”

很多新手工程师把这一章当成抄配置。真正的高级工程师，会在采集的同时做判断。

例如：

- `lscpu` 显示逻辑核数不对，意味着 BIOS、CPU 插槽、SMT、固件可能有问题
- `numactl -H` 显示节点不均衡，意味着 SNC/NPS 设置或 DIMM 插法可能异常
- `lspci -vv` 显示链路跑在 `x8`，意味着 riser、bifurcation、插卡或信号质量有问题
- `ipmitool sensor` 有 `cr` 或 `nr`，意味着散热、电源、传感器本身存在风险
- `dmidecode` 和配置单不一致，意味着样机、返修件、替换件、BOM 错误都可能存在

所以“采集”只是动作，“诊断”才是价值。

### 3.3 服务器信息源分层理解

建议把信息源按四层看待：

#### 第一层：固件层

来自 BIOS、BMC、CPLD、FRU、SMBIOS。

常用工具：

- `dmidecode`
- `ipmitool mc info`
- `ipmitool fru`
- `ipmitool sdr list full`

这层告诉你：机器是谁、板卡是什么、固件版本如何、传感器如何定义。

#### 第二层：内核枚举层

来自 Linux Kernel 对设备的识别。

常用工具：

- `lspci`
- `lsblk`
- `lscpu`
- `lshw`
- `dmesg`

这层告诉你：OS 实际看到了什么设备，链路状态怎样，有没有枚举错误。

#### 第三层：驱动层

来自驱动与设备交互状态。

常用工具：

- `ethtool -i`
- `modinfo`
- `smartctl`
- `nvme list`
- `nvidia-smi`
- `npu-smi`

这层告诉你：驱动是否匹配、固件是否对齐、设备是否处于健康可用状态。

#### 第四层：管理与遥测层

来自 BMC、Redfish、厂商平台工具、日志系统。

常用工具：

- `ipmitool sel list`
- Redfish API
- 厂商 OOB 管理界面

这层告诉你：有没有历史告警、掉电、过温、重启、风扇异常、PSU 抖动等问题。

高级工程师不会只看单一层。真正可靠的诊断，必须跨层验证。

### 3.4 为什么 2026 年这一章更重要

在 Kunpeng 950、Ascend 950、Xeon 6、EPYC 9005、DGX B200 这样的新一代平台上，单机复杂度已经大到以下程度：

- CPU 核数更高，NUMA 更敏感
- 内存代际升级到 DDR5 / MRDIMM / CXL，配置错误代价更大
- AI 服务器中 GPU/NPU/DPU/高速网卡共享 PCIe 资源，拓扑更复杂
- BMC/Redfish 已不只是管理入口，而是遥测、诊断和批量运维的数据源

因此，整机信息采集已经从“测试准备”升级为“平台验证第一步”。

## 4. 详细测试用例

### 用例 1：整机静态身份与资产信息采集

#### 测试目的

确认服务器型号、序列号、主板、BIOS、BMC、FRU、CPU、内存槽位和关键资产信息，建立静态基线。

#### 前置条件

- 服务器已正常开机
- 拥有 `root` 或 `sudo` 权限
- 已安装 `dmidecode`、`ipmitool`

#### 所需工具

- `dmidecode`
- `ipmitool`
- `hostnamectl`

#### 测试步骤

1. 登录服务器并确认当前主机名。
2. 采集 `hostnamectl` 输出，确认 OS 和主机身份。
3. 使用 `dmidecode` 采集 BIOS、系统、主板、内存信息。
4. 使用 `ipmitool mc info` 和 `ipmitool fru` 采集管理控制器和 FRU 信息。
5. 对照项目 BOM 或配置单，确认型号、序列号、部件标识一致。
6. 将结果保存为原始日志，不要手工改写原文。

#### 完整测试命令

```bash
TS=$(date +%F_%H%M%S)
OUT=/tmp/sit_identity_${TS}
mkdir -p "${OUT}"

hostnamectl > "${OUT}/01_hostnamectl.txt"
dmidecode -t bios > "${OUT}/02_dmidecode_bios.txt"
dmidecode -t system > "${OUT}/03_dmidecode_system.txt"
dmidecode -t baseboard > "${OUT}/04_dmidecode_baseboard.txt"
dmidecode -t processor > "${OUT}/05_dmidecode_processor.txt"
dmidecode -t memory > "${OUT}/06_dmidecode_memory.txt"
ipmitool mc info > "${OUT}/07_ipmi_mc_info.txt"
ipmitool fru > "${OUT}/08_ipmi_fru.txt"

echo "identity snapshot saved to ${OUT}"
```

#### 关键参数解析

| 参数/命令 | 含义 | 作用 |
|---|---|---|
| `dmidecode -t bios` | 只看 BIOS 类信息 | 聚焦 BIOS 版本、发布日期、厂商 |
| `dmidecode -t system` | 只看系统信息 | 看产品名、序列号、UUID |
| `dmidecode -t processor` | 只看 CPU 槽位信息 | 校验插槽是否完整识别 |
| `dmidecode -t memory` | 只看 DIMM 信息 | 看插槽、容量、速度、厂商 |
| `ipmitool mc info` | BMC 管理控制器信息 | 确认 BMC 固件与管理能力 |
| `ipmitool fru` | FRU 资产信息 | 核对板卡、部件、SN |

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `Vendor` | BIOS/部件厂商 | 与平台设计一致 | 厂商不符：排查工程样机或替换件 |
| `Version` | BIOS/BMC/FRU 版本 | 与项目版本矩阵一致 | 版本偏旧：先升级再测试 |
| `Serial Number` | 序列号 | 非空，和资产系统一致 | 缺失或重复：记录为资产管理缺陷 |
| `Part Number` | 部件号 | 与配置单一致 | 不一致：核对 BOM、返修记录 |
| `Configured Memory Speed` | 配置内存速率 | 与平台支持与 BIOS 策略相符 | 明显偏低：查 DIMM 混插、降频、BIOS 策略 |

### 用例 2：CPU、NUMA 与内存拓扑采集

#### 测试目的

确认 CPU 核数、线程数、Socket 数、NUMA 节点、内存分布是否与预期一致，为 CPU、内存、网络和 AI 测试建立绑定基础。

#### 前置条件

- 已安装 `lscpu`、`numactl`

#### 所需工具

- `lscpu`
- `numactl`
- `free`

#### 测试步骤

1. 采集 CPU 基本信息。
2. 采集 NUMA 节点分布。
3. 采集系统总内存和可用内存。
4. 检查逻辑核数、Socket、线程数是否与产品规格一致。
5. 检查 NUMA 节点的 CPU 和内存分配是否均衡。

#### 完整测试命令

```bash
TS=$(date +%F_%H%M%S)
OUT=/tmp/sit_topology_${TS}
mkdir -p "${OUT}"

lscpu > "${OUT}/01_lscpu.txt"
lscpu -e=cpu,node,socket,core,online > "${OUT}/02_lscpu_extended.txt"
numactl -H > "${OUT}/03_numactl_H.txt"
free -h > "${OUT}/04_free_h.txt"

echo "topology snapshot saved to ${OUT}"
```

#### 关键参数解析

| 参数/命令 | 含义 | 作用 |
|---|---|---|
| `lscpu` | CPU 总览 | 看架构、socket、core、thread、cache |
| `lscpu -e=...` | 扩展枚举表 | 做 CPU 到 NUMA / socket / core 的映射 |
| `numactl -H` | NUMA 详情 | 看各节点 CPU 列表和内存容量 |
| `free -h` | 内存总览 | 看操作系统可见内存是否合理 |

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `Socket(s)` | CPU 路数 | 与整机设计一致 | 少路：查 CPU、主板、BIOS 识别 |
| `Core(s) per socket` | 每路核心数 | 与 CPU SKU 一致 | 异常：查 SKU、BIOS 限制、故障 CPU |
| `Thread(s) per core` | 每核线程数 | 与 SMT/超线程配置一致 | 不一致：查 BIOS 是否关闭 SMT |
| `NUMA nodeX size` | 每个节点内存容量 | 理想状态接近均衡 | 某节点偏小：查 DIMM 插法和失效 |
| `online` | CPU 是否在线 | 应为 `yes` | 离线 CPU：查内核参数或硬件故障 |

### 用例 3：PCIe 设备与链路状态采集

#### 测试目的

确认网卡、RAID、NVMe、GPU、NPU、DPU 等 PCIe 设备被正常枚举，并检查链路速率、宽度、错误能力。

#### 前置条件

- 已安装 `pciutils`

#### 所需工具

- `lspci`
- `grep`
- `awk`

#### 测试步骤

1. 列出全部 PCIe 设备。
2. 分别筛选网络、存储、加速卡类设备。
3. 采集详细链路信息。
4. 检查 `LnkCap` 与 `LnkSta` 是否一致。
5. 检查是否存在 `AER`、`Correctable Error`、`Unsupported Request` 等异常。

#### 完整测试命令

```bash
TS=$(date +%F_%H%M%S)
OUT=/tmp/sit_pcie_${TS}
mkdir -p "${OUT}"

lspci > "${OUT}/01_lspci.txt"
lspci -nn > "${OUT}/02_lspci_nn.txt"
lspci -vv > "${OUT}/03_lspci_vv.txt"
lspci | egrep -i "ethernet|network|fibre|non-volatile|raid|vga|3d|processing accelerators" > "${OUT}/04_lspci_key_devices.txt"

echo "pcie snapshot saved to ${OUT}"
```

#### 关键参数解析

| 参数/命令 | 含义 | 作用 |
|---|---|---|
| `lspci` | 基础 PCIe 枚举 | 看设备是否被系统识别 |
| `lspci -nn` | 带厂商/设备 ID | 便于匹配驱动与型号 |
| `lspci -vv` | 详细寄存器与链路信息 | 查速率、宽度、错误状态 |
| `egrep ...` | 过滤关键设备 | 快速抽取 NIC/SSD/GPU/NPU/DPU |

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `LnkCap` | 设备支持的最大链路能力 | 由设备决定 | 用于对比当前链路是否跑满 |
| `LnkSta` | 当前链路状态 | 应接近设计目标 | 降速/降宽：查插槽、riser、BIOS、信号完整性 |
| `Kernel driver in use` | 当前驱动 | 与设备匹配 | 无驱动：安装驱动或查兼容性 |
| `AER` 相关字段 | PCIe 错误报告能力 | 无持续错误计数 | 有大量错误：查硬件接触或链路质量 |

### 用例 4：BMC 传感器、SEL 与健康状态诊断

#### 测试目的

检查 BMC 管理控制器是否工作正常，并获取温度、电压、风扇、PSU、历史事件日志等健康信息。

#### 前置条件

- BMC 通道可用
- 已安装 `ipmitool`

#### 所需工具

- `ipmitool`

#### 测试步骤

1. 采集管理控制器信息。
2. 采集全部传感器和 SDR 记录。
3. 采集 SEL 事件日志。
4. 分析是否有过温、掉电、风扇丢失、PSU 波动、重复重启等历史告警。
5. 对关键告警做时间关联分析。

#### 完整测试命令

```bash
TS=$(date +%F_%H%M%S)
OUT=/tmp/sit_bmc_${TS}
mkdir -p "${OUT}"

ipmitool mc info > "${OUT}/01_mc_info.txt"
ipmitool sensor > "${OUT}/02_sensor.txt"
ipmitool sdr list full > "${OUT}/03_sdr_full.txt"
ipmitool sel list > "${OUT}/04_sel_list.txt"
ipmitool fru > "${OUT}/05_fru.txt"

echo "bmc snapshot saved to ${OUT}"
```

#### 关键参数解析

| 参数/命令 | 含义 | 作用 |
|---|---|---|
| `ipmitool sensor` | 传感器摘要 | 快速看温度、电压、风扇、PSU 状态 |
| `ipmitool sdr list full` | 全量 SDR 信息 | 看阈值定义与状态细节 |
| `ipmitool sel list` | 事件日志 | 查历史异常和时间线 |
| `ipmitool mc info` | BMC 控制器信息 | 看 BMC 固件和能力 |

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `Status` | 传感器状态 | `ok` 或正常态 | `cr/nr/ns/na`：查传感器、风扇、PSU、线缆 |
| `Reading` | 当前读数 | 应在阈值范围内 | 温度高、电压漂移：查散热与供电 |
| `SEL Timestamp` | 告警时间 | 与事件时间线一致 | 集中爆发：查同一时刻掉电或热事件 |
| `Event Description` | 事件描述 | 无关键告警 | PSU lost / Fan fault / Temp high：先处理硬件 |

### 用例 5：操作系统与驱动基线采集

#### 测试目的

确认 OS、Kernel、驱动、常用工具链版本，建立软件栈基线。

#### 前置条件

- 已安装常用运维工具

#### 所需工具

- `uname`
- `cat`
- `modinfo`
- `ethtool`
- `lsmod`

#### 测试步骤

1. 检查 OS 和 Kernel 版本。
2. 记录关键驱动版本。
3. 记录关键模块加载状态。
4. 保存版本清单，用于后续问题复现。

#### 完整测试命令

```bash
TS=$(date +%F_%H%M%S)
OUT=/tmp/sit_sw_${TS}
mkdir -p "${OUT}"

cat /etc/os-release > "${OUT}/01_os_release.txt"
uname -a > "${OUT}/02_uname.txt"
lsmod > "${OUT}/03_lsmod.txt"
modinfo mlx5_core > "${OUT}/04_modinfo_mlx5_core.txt" 2>/dev/null || true
modinfo nvme > "${OUT}/05_modinfo_nvme.txt" 2>/dev/null || true
ethtool -i eth0 > "${OUT}/06_ethtool_i_eth0.txt" 2>/dev/null || true

echo "software snapshot saved to ${OUT}"
```

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `PRETTY_NAME` | 操作系统版本 | 在支持矩阵内 | 非支持版本：不做正式认证结论 |
| `Kernel` | 内核版本 | 与驱动兼容 | 内核过新/过旧：驱动不稳定 |
| `version` | 驱动版本 | 与固件配套 | 版本错配：升级或回退 |
| `firmware-version` | 设备固件版本 | 与厂商建议一致 | 性能波动：优先核对固件 |

### 用例 6：整机快速健康烟测脚本

#### 测试目的

用一组最小动作，在 5 到 10 分钟内判断服务器是否适合进入专项测试。

#### 前置条件

- 完成前述信息采集
- 已安装常用基础工具

#### 所需工具

- `lscpu`
- `numactl`
- `ipmitool`
- `lspci`
- `lsblk`

#### 测试步骤

1. 检查 CPU 和 NUMA 是否正常。
2. 检查关键 PCIe 设备是否全部枚举。
3. 检查传感器和 SEL 是否有明显告警。
4. 检查块设备与配置单是否一致。
5. 输出健康摘要，作为是否进入下一章的判定依据。

#### 完整测试命令

```bash
echo "===== CPU ====="
lscpu | egrep "Architecture|CPU\\(s\\)|Socket\\(s\\)|Core\\(s\\) per socket|Thread\\(s\\) per core|NUMA node\\(s\\)"

echo "===== NUMA ====="
numactl -H

echo "===== PCIe Key Devices ====="
lspci | egrep -i "ethernet|network|fibre|non-volatile|raid|vga|3d|processing accelerators"

echo "===== Storage ====="
lsblk -o NAME,MODEL,SIZE,TYPE,MOUNTPOINT

echo "===== BMC Sensors ====="
ipmitool sensor

echo "===== SEL Last 20 ====="
ipmitool sel list last 20
```

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `CPU(s)` | 逻辑 CPU 数 | 与规格一致 | 偏少：查 BIOS、故障 CPU、内核参数 |
| `NUMA node(s)` | NUMA 节点数 | 与平台匹配 | 异常：查 BIOS SNC/NPS |
| `processing accelerators` | AI 加速器枚举 | 应与实配一致 | 漏卡：查驱动、供电、PCIe |
| `SEL last 20` | 最近事件 | 不应有重复严重告警 | 重复过温/掉电：暂停专项测试 |

## 5. 结果分析与问题诊断方法

### 5.1 诊断总原则

看到异常时，不要直接跳到结论。请按下面顺序做：

1. 先确认异常是否真实存在
2. 再确认异常属于哪一层
3. 再做交叉验证
4. 最后才给原因判断

例如，某 GPU/NPU 没识别：

- `lspci` 没看到设备：优先看硬件层
- `lspci` 看到了，驱动没起来：优先看驱动层
- 驱动起来但工具不可见：优先看运行库/服务层
- 工具可见但性能异常：再看拓扑、温度、功耗和互联层

### 5.2 常见异常一：配置单和实际机器不一致

表现：

- CPU 型号不对
- DIMM 数量不对
- SSD 厂牌/固件不对
- 网卡速率不对
- FRU 部件号不对

诊断方法：

1. 用 `dmidecode`、`ipmitool fru` 采静态身份
2. 用 `lsblk`、`lspci` 采 OS 实际可见设备
3. 对照 BOM / 送测清单 / 资产系统
4. 查是否存在返修、借测、样机临时替换

结论模板：

“当前送测样机静态配置与计划配置存在差异，暂不建议直接输出性能与稳定性结论，应先校准送测配置。”

### 5.3 常见异常二：PCIe 设备降宽或降速

表现：

- GPU/NPU/NIC/SSD 可以识别，但性能明显偏低
- `LnkSta` 低于 `LnkCap`

诊断方法：

1. `lspci -vv` 看 `LnkCap` 和 `LnkSta`
2. 确认卡件插槽正确
3. 核对 riser、retimer、转接板、背板
4. 查 BIOS 中 PCIe speed / bifurcation / ASPM 相关设置
5. 排查接触不良和信号质量问题

典型结论：

“设备已被系统枚举，但当前链路仅以 PCIe Gen4 x8 运行，低于设计 Gen5 x16，预计会对带宽型工作负载造成明显影响。”

### 5.4 常见异常三：BMC 传感器或 SEL 告警频繁

表现：

- 反复出现过温
- 风扇缺失或转速异常
- PSU 输入丢失
- Watchdog reset

诊断方法：

1. `ipmitool sensor` 看当前状态
2. `ipmitool sdr list full` 看阈值
3. `ipmitool sel list` 做时间线分析
4. 结合机房温度、功率模式、盖板状态、风道、风扇策略判断

原则：

如果环境已经有明显过温或供电告警，不要直接开始烧机或 AI 训练负载。

### 5.5 常见异常四：NUMA 或内存分布不均衡

表现：

- 某个 NUMA 节点内存容量明显偏小
- 某路 CPU 核心数不完整
- AI 或网络压测结果抖动大

诊断方法：

1. `lscpu`
2. `lscpu -e=cpu,node,socket,core,online`
3. `numactl -H`
4. `dmidecode -t memory`

处理方向：

- 查 DIMM 插法是否遵循厂商白皮书
- 查 BIOS 是否开启特定分区模式
- 查是否存在坏条、降频或屏蔽

## 6. 最佳实践与注意事项

1. 所有正式测试前，先做一次全量基线采集。
2. 原始日志必须保留，不要只保留人工摘要。
3. 任何硬件异常都要同时看“固件层 + 内核层 + 驱动层”。
4. 多厂商混配环境中，更要重视 `lspci -nn`、驱动版本和固件版本绑定关系。
5. 对 AI 服务器，除了 CPU/内存/网卡/盘，还必须把 GPU/NPU/DPU 一并纳入整机基线。
6. `SEL` 日志要做时间线分析，不要只看最新一条。
7. 看到配置不一致、链路降级、严重传感器告警时，应暂停后续专项测试，先校准环境。
8. 测试结论必须包含“环境前提”，否则不具备复现价值。

## 7. 进阶内容（高阶测试技巧、自动化思路、多厂商混配测试等）

### 7.1 自动化采集框架建议

建议把本章沉淀成统一脚本框架，目录建议如下：

```bash
sit_collect/
├── collect_identity.sh
├── collect_topology.sh
├── collect_pcie.sh
├── collect_bmc.sh
├── collect_sw.sh
├── summary_report.sh
└── output/
```

输出建议统一分三层：

- `raw/`：原始命令输出
- `parsed/`：结构化 CSV / JSON
- `summary.md`：管理层与测试负责人摘要

### 7.2 建议增加结构化比对

同一批机器做整机信息采集时，真正高效的做法不是人工逐台看，而是把以下字段做成结构化比对：

- 机型
- BIOS 版本
- BMC 版本
- CPU 型号
- DIMM 数量 / 容量 / 速率
- PCIe 关键设备数量
- GPU/NPU/DPU 数量
- 关键固件版本
- 是否有 SEL 严重告警

这样你可以快速发现“批次异常机”和“离群机”。

### 7.3 多厂商平台上的特殊注意点

#### 华为平台

- 重点看 Kunpeng / Ascend 对应的软件栈匹配关系
- 重点看 BMC 管理信息、整机遥测、NPU 侧工具链版本

#### Intel 平台

- 重点看 SNC、功耗模式、UPI、MRDIMM 支持与 BIOS 策略

#### AMD 平台

- 重点看 NPS、SMT、IOMMU、PCIe lane 分配与 CXL 配置

#### NVIDIA AI 平台

- 重点把 GPU、DPU、ConnectX 网卡、BMC、NVMe 一起采
- 不要只看 `nvidia-smi`，还要看 `lspci`、BMC、网络和存储

### 7.4 高级工程师输出模板

做完本章，建议你输出一段标准化摘要：

1. 当前平台身份
2. 当前资源与拓扑
3. 当前健康状态
4. 当前版本基线
5. 当前风险项
6. 是否允许进入下一阶段专项测试

标准示例：

“当前样机已完成整机基线采集，CPU/内存/存储/网络/加速器枚举完整，BIOS 与 BMC 版本在项目支持范围内，未发现持续性关键传感器告警。存在 1 处 PCIe 链路降宽风险，建议在进入 GPU/NPU 专项测试前完成插槽与 BIOS 配置复核。”

## 参考来源

- [Huawei HUAWEI CONNECT 2025：Kunpeng 950 / Ascend 950 路标公开信息](https://www.huawei.com/cn/news/2025/9/hc-xu-keynote-speech)
- [Huawei MWC Barcelona 2026：Atlas 950 SuperPoD / TaiShan 950 SuperPoD](https://www.huawei.com/en/news/2026/3/mwc-superpod-computing)
- [Intel Xeon 6 Product Brief](https://www.intel.com/content/www/us/en/products/docs/xeon-6-product-brief.html)
- [AMD EPYC 9005 Series Datasheet](https://www.amd.com/content/dam/amd/en/documents/epyc-business-docs/datasheets/amd-epyc-9005-series-processor-datasheet.pdf)
- [NVIDIA DGX B200 官方规格](https://www.nvidia.com/zh-tw/data-center/dgx-b200/)
