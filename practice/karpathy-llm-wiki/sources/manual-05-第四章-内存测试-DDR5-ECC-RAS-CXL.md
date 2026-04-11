# 第四章 内存测试（DDR5、ECC、RAS、CXL 等）

## 1. 模块概述与重要性

如果说 CPU 决定服务器“会不会算”，那么内存决定服务器“算得顺不顺、稳不稳、能不能持续算”。

很多工程师对内存测试的理解仍停留在两个层面：

- 系统能识别出来多少内存
- 跑一个 `memtester` 没报错

这在 2026 年的服务器平台上远远不够。真正的服务器内存测试，至少要回答下面这些问题：

1. DIMM 是否全部被正确识别
2. 实际运行频率是否符合平台设计
3. 插法、拓扑、NUMA 分布是否均衡
4. 带宽和时延是否达到平台预期
5. ECC、EDAC、RAS 是否健康
6. 长时间高负载下是否会出现纠错增长、降频、报错、掉条
7. 新一代内存形态如 MRDIMM、MCRDIMM、CXL Memory 是否真的按预期生效

对高级工程师来说，内存测试的价值不只是“测内存本身”，而是它经常是整机瓶颈和隐性故障的根源：

- CPU 跑分低，可能不是 CPU 不行，而是 DIMM 降频
- AI 训练吞吐抖动，可能不是加速器问题，而是 NUMA 和内存带宽不稳
- 数据库时延高，可能不是盘慢，而是本地/远端内存访问分布异常
- 长稳测试中偶发重启，可能不是整机问题，而是 ECC 持续增长或 RAS 已经触发边界

所以这一章必须建立一个高级工程师视角：

- 把 DIMM 当作“平台资源”去测，而不是当作“条子”去测
- 把内存问题和 CPU、BIOS、NUMA、PCIe、AI 工作负载一起看
- 让结果既能指导现场排障，也能支撑项目汇报和量产导入

## 2. 2026年厂商与主流产品信息对比表

> 本章对比表只聚焦服务器内存方向，不再泛化到整机平台。规格优先采用厂商公开资料与公开新闻口径。

| 厂商 | 2026主流产品方向 | 公开规格/进展 | 典型亮点 | 典型应用 | 重点测试关注点 |
|---|---|---|---|---|---|
| SK hynix | DDR5 RDIMM / 高容量服务器 RDIMM | 2025 年底宣布基于 32Gb die 的 `256GB DDR5 RDIMM` 完成 Intel Xeon 6 平台认证 | 大容量服务器内存验证推进快 | 高容量数据库、AI Host、大内存节点 | 容量识别、兼容性、频率、热稳定性 |
| Samsung | DDR5 RDIMM / MCRDIMM / CXL Memory | 持续推进 CXL Memory 与高带宽服务器内存生态 | CXL 布局早，适合大内存扩展场景 | AI/HPC、内存池化、扩展内存平台 | CXL 可见性、容量扩展、带宽、互操作 |
| Micron | DDR5 RDIMM / MRDIMM | 公开 128GB DDR5 RDIMM 和新一代 MRDIMM 产品资料，覆盖 `5600/6400/7200/8000 MT/s` 路线 | 高容量、高速度、较低时延和能效优势 | AI 数据中心、数据库、通算节点 | 带宽、时延、功耗、平台兼容性 |
| 长鑫存储 CXMT | DDR5 颗粒与服务器内存方向 | 官网公开 DDR5 颗粒速率突破 `8000 Mbps`，面向服务器/工作站/PC 高端场景 | 国产化替代和供应链价值高 | 国产服务器、政企、行业平台 | 兼容性、批次一致性、稳定性 |
| Kingston / Smart / Apacer 等模组商 | 服务器 RDIMM/LRDIMM | 基于三星/海力士/美光颗粒构建企业模组 | 供应链灵活、适配面广 | OEM/ODM、行业平台 | SPD 信息、颗粒批次差异、兼容矩阵 |
| CXL 生态厂商 | CXL Type-3 Memory 扩展 | 依赖 CPU 与 BIOS/OS 支持 | 让系统容量扩展从“插 DIMM”走向“外接内存” | 内存池化、大模型 Host、内存密集型业务 | 枚举、带宽、时延、热插拔/错误恢复 |

## 3. 基础原理讲解（通俗易懂）

### 3.1 服务器内存测试到底在测什么

服务器内存测试不是只看“有多少 GB”，而是看下面六层能力：

1. 识别层
   - DIMM 是否全部识别
   - 槽位、容量、厂商、Part Number 是否正确
2. 运行层
   - 实际运行频率是否符合预期
   - Rank、通道、DPC（DIMM per Channel）配置是否合理
3. 拓扑层
   - NUMA 节点的内存分布是否均衡
   - 本地/远端访问路径是否合理
4. 性能层
   - 带宽、时延、并发下稳定性是否达标
5. 可靠性层
   - ECC、EDAC、RAS 是否正常
   - 是否出现 CE/UE、MCE、scrub 相关异常
6. 演进层
   - MRDIMM、MCRDIMM、CXL 内存是否生效
   - 是否对现有 CPU/BIOS/OS 形成兼容挑战

### 3.2 DDR5 相比 DDR4，测试重点为什么变了

到了 DDR5 时代，内存测试的复杂度明显增加，原因包括：

- 频率更高，信号完整性和兼容性问题更敏感
- 容量更大，大容量 RDIMM/MRDIMM 对平台的训练、功耗和热更敏感
- PMIC 下沉到模组侧，内存本身的电源管理更重要
- 平台开始引入 MRDIMM、MCRDIMM、CXL，传统 DIMM 测试思路不够用了

你可以简单理解：

- DDR4 时代，很多问题是“能不能跑起来”
- DDR5 时代，更多问题是“能不能满速稳定跑起来”

### 3.3 服务器内存的几个核心概念

#### 3.3.1 通道、Rank、DPC

- Channel：内存通道，决定并行带宽能力
- Rank：DIMM 内的逻辑结构，影响并发和控制复杂度
- DPC：每个通道插几条 DIMM

经验上：

- 插得越满，不代表一定越快
- 同一平台在 `1DPC` 和 `2DPC` 下，频率和时延表现可能差很多

#### 3.3.2 NUMA 和本地/远端访问

在双路服务器上，CPU 更喜欢访问“自己这路”的内存。

因此：

- 本地节点带宽通常更高
- 远端节点时延通常更高

如果你不做 NUMA 绑定，很多内存测试结果会出现“平均值看起来还行，真实业务很差”的问题。

#### 3.3.3 ECC、EDAC、RAS

这是高级工程师和普通工程师拉开差距的关键。

- ECC：纠错能力
- EDAC：Error Detection and Correction，Linux 侧常见内存错误统计入口
- RAS：Reliability, Availability, Serviceability，可靠性、可用性、可维护性

你要区分两类错误：

- 可纠错错误（CE）
  - 系统可能还能跑，但说明内存/IMC/环境已经不干净
- 不可纠错错误（UE）
  - 风险极高，通常必须停测

高级工程师不会只在“出 UE”时才重视，而会从 CE 的增长趋势中提前发现风险。

#### 3.3.4 MRDIMM / MCRDIMM / CXL Memory

这些是 2026 年必须补的概念。

- MRDIMM：Multiplexed Rank DIMM，目标是提升有效带宽
- MCRDIMM：Multiplexed Combined Rank DIMM，侧重更高带宽与平台协同
- CXL Memory：通过 CXL 总线接入的扩展内存，改变传统“内存只能插 DIMM”的思路

这意味着内存测试以后不只是测主板上那几条 DIMM，而是要测“整个内存层”。

### 3.4 内存问题为什么常常被误判

因为很多内存问题表面上看不像内存问题。

例如：

- CPU 跑分低，根因是 DIMM 频率从 6400 掉到了 4800
- 网卡吞吐波动，根因是中断绑在远端节点，导致跨 NUMA 访问内存
- AI 训练前段数据处理慢，根因是 CPU+内存带宽不足
- 长稳中偶发 crash，根因是 ECC 持续增长最终触发更严重的 RAS 行为

所以内存测试必须和 CPU、BIOS、NUMA 一起分析。

## 4. 详细测试用例

### 用例 1：DIMM 枚举、容量、槽位与频率核对

#### 测试目的

确认 DIMM 数量、容量、槽位、厂商、部件号、标称速率和实际配置速率是否符合送测配置与平台设计。

#### 前置条件

- 服务器已正常启动
- 已安装 `dmidecode`、`lshw`
- 具备 root 或 sudo 权限

#### 所需工具

- `dmidecode`
- `lshw`
- `lscpu`

#### 测试步骤

1. 采集 `dmidecode -t memory`。
2. 采集 `lshw -class memory`。
3. 核对 DIMM 槽位、容量和厂商。
4. 检查 `Speed` 与 `Configured Memory Speed`。
5. 核对是否有空槽、No Module Installed、Unknown 或降频。

#### 完整测试命令

```bash
TS=$(date +%F_%H%M%S)
OUT=/tmp/mem_inventory_${TS}
mkdir -p "${OUT}"

dmidecode -t memory > "${OUT}/01_dmidecode_memory.txt"
lshw -class memory > "${OUT}/02_lshw_memory.txt"
lscpu > "${OUT}/03_lscpu.txt"

echo "memory inventory saved to ${OUT}"
```

#### 关键参数解析

| 参数/命令 | 含义 | 作用 |
|---|---|---|
| `dmidecode -t memory` | 读取 SMBIOS 内存信息 | 看槽位、容量、厂商、部件号、速率 |
| `lshw -class memory` | 读取 OS 识别的内存层级 | 辅助看层级和总量 |
| `lscpu` | CPU 与 NUMA 概览 | 辅助判断内存与 CPU 拓扑关系 |

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `Locator` | DIMM 槽位 | 与主板丝印和配置单一致 | 槽位缺失：查插条或主板通道问题 |
| `Size` | 单条容量 | 与送测配置一致 | 容量异常：查坏条、识别失败、混插 |
| `Manufacturer` | 厂商 | 与项目允许清单一致 | 非预期厂商：核对替换件和批次 |
| `Part Number` | 料号 | 应可追溯 | 缺失：资产管理和质量追踪风险 |
| `Speed` | 模组标称速度 | 与产品规格一致 | 偏低：查 DIMM 规格是否一致 |
| `Configured Memory Speed` | 实际运行速度 | 接近平台当前支持上限 | 明显降频：查 BIOS、DPC、混插、CPU 平台限制 |

### 用例 2：NUMA 内存分布与节点均衡性检查

#### 测试目的

确认各 NUMA 节点的内存容量分布是否均衡，避免后续 CPU、网络、存储和 AI 测试因为内存拓扑失衡而失真。

#### 前置条件

- 双路或多路服务器更有意义
- 已安装 `numactl`

#### 所需工具

- `numactl`
- `lscpu`

#### 测试步骤

1. 采集 `numactl -H`。
2. 记录每个 NUMA 节点的 CPU 列表和内存容量。
3. 对比各节点容量是否接近。
4. 若存在明显偏差，反查 DIMM 插法和 BIOS NUMA 设置。

#### 完整测试命令

```bash
lscpu
numactl -H
lscpu -e=cpu,node,socket,core,online
```

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `NUMA node(s)` | 节点数量 | 与 BIOS 模式一致 | 异常：查 SNC/NPS/平台固件 |
| `nodeX size` | 节点容量 | 理想状态接近均衡 | 偏小：查 DIMM 插法、掉条、屏蔽 |
| `nodeX free` | 节点空闲内存 | 取决于业务状态 | 某节点异常紧张：查进程绑核绑内存 |

### 用例 3：内存带宽测试

#### 测试目的

验证本地节点、远端节点和全系统内存带宽是否达到平台预期。

#### 前置条件

- 已安装 Intel MLC 或 STREAM
- 尽量在空闲环境运行

#### 所需工具

- `mlc`
- `stream`
- `numactl`

#### 测试步骤

1. 先执行全局带宽矩阵测试。
2. 记录本地节点与远端节点带宽。
3. 再使用 `STREAM` 做简单带宽基线。
4. 对比历史基线或同平台结果。

#### 完整测试命令

```bash
./mlc --bandwidth_matrix
./mlc --peak_injection_bandwidth
./mlc --loaded_latency

numactl --cpunodebind=0 --membind=0 ./stream
numactl --cpunodebind=0 --membind=1 ./stream
```

#### 关键参数解析

| 参数 | 含义 | 作用 |
|---|---|---|
| `--bandwidth_matrix` | 节点间带宽矩阵 | 观察本地/远端带宽差异 |
| `--peak_injection_bandwidth` | 峰值注入带宽 | 看系统上限 |
| `--loaded_latency` | 负载下时延 | 观察高负载时访问时延 |
| `--cpunodebind` | 绑定执行 CPU 节点 | 固定计算位置 |
| `--membind` | 绑定内存节点 | 比较本地与远端访问 |

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `Bandwidth` | 带宽值 | 本地应明显高于远端 | 本地偏低：查频率、通道未满、NUMA 设置 |
| `Loaded Latency` | 负载时延 | 不同平台不同，但应稳定 | 波动大：查 BIOS、电源模式、背景干扰 |
| `Copy/Scale/Add/Triad` | STREAM 结果 | 同平台应相对稳定 | 某项偏低：查编译器和绑核 |

### 用例 4：内存时延与本地/远端访问差异测试

#### 测试目的

量化 NUMA 本地访问与跨节点访问的时延差异，为数据库、网络、AI Host 绑定优化提供依据。

#### 前置条件

- 已安装 `mlc` 或同类工具

#### 所需工具

- `mlc`
- `numactl`

#### 测试步骤

1. 采集各节点本地时延。
2. 采集跨节点远端时延。
3. 记录倍数差异。
4. 将结果反馈给 CPU 绑核、IRQ 亲和性和 AI Host 进程绑核策略。

#### 完整测试命令

```bash
./mlc --latency_matrix
./mlc --loaded_latency
```

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `Local Latency` | 本地节点访问时延 | 应低于远端 | 偏高：查频率、通道、BIOS |
| `Remote Latency` | 远端节点时延 | 高于本地属正常 | 过高：查互连、NUMA 设置、负载干扰 |

### 用例 5：内存稳定性压力测试

#### 测试目的

验证内存在高占用、长时间、高并发访问下是否稳定，是否触发 ECC、EDAC、MCE、系统错误或性能衰减。

#### 前置条件

- 已安装 `memtester`、`stress-ng`
- 系统空闲内存足够

#### 所需工具

- `memtester`
- `stress-ng`
- `dmesg`
- `journalctl`

#### 测试步骤

1. 记录测试前 `dmesg` 和 EDAC 基线。
2. 使用 `memtester` 做功能型覆盖。
3. 使用 `stress-ng --vm` 做长稳内存压力。
4. 测试后检查 `dmesg`、`journalctl`、`rasdaemon`。

#### 完整测试命令

```bash
TS=$(date +%F_%H%M%S)
OUT=/tmp/mem_stress_${TS}
mkdir -p "${OUT}"

dmesg -T > "${OUT}/01_dmesg_before.txt"
journalctl -k > "${OUT}/02_journal_before.txt"

memtester 64G 1 > "${OUT}/03_memtester.txt" 2>&1
stress-ng --vm 8 --vm-bytes 80% --vm-method all --timeout 2h --metrics-brief > "${OUT}/04_stressng_vm.txt" 2>&1

dmesg -T > "${OUT}/05_dmesg_after.txt"
journalctl -k > "${OUT}/06_journal_after.txt"
ras-mc-ctl --summary > "${OUT}/07_ras_summary.txt" 2>&1 || true

echo "memory stress logs saved to ${OUT}"
```

#### 关键参数解析

| 参数 | 含义 | 作用 |
|---|---|---|
| `memtester 64G 1` | 测试 64G 内存一轮 | 快速做功能覆盖 |
| `--vm 8` | 启动 8 个内存压力 worker | 增加并发访问压力 |
| `--vm-bytes 80%` | 使用 80% 可用内存 | 拉高真实内存负载 |
| `--vm-method all` | 多种访问模式 | 更容易触发边界问题 |
| `--timeout 2h` | 跑 2 小时 | 验证中期稳定性 |

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `FAILURE` | memtester 错误 | 不应出现 | 立即停测，查 DIMM/CPU IMC |
| `bogo ops/s` | 内存压力吞吐 | 同平台应稳定 | 后期明显下降：查热和频率 |
| `EDAC` | 可纠错错误 | 不应持续增长 | 增长：查 DIMM、槽位、环境 |
| `MCE` | 机器检查异常 | 不应出现致命错误 | 立即停测并做硬件定位 |

### 用例 6：ECC / EDAC / RAS 错误检查

#### 测试目的

检查内存是否出现可纠错错误、不可纠错错误、scrub 相关告警，判断平台可靠性是否达标。

#### 前置条件

- 系统支持 EDAC / rasdaemon / mcelog

#### 所需工具

- `dmesg`
- `journalctl`
- `ras-mc-ctl`
- `edac-util`

#### 测试步骤

1. 查看当前 EDAC 驱动和错误计数。
2. 查看内核日志中的内存和 ECC 记录。
3. 若有历史 CE，观察是否持续增长。
4. 若有 UE，立即升级为阻断问题。

#### 完整测试命令

```bash
dmesg -T | egrep -i "edac|ecc|mce|memory error|ras"
journalctl -k | egrep -i "edac|ecc|mce|memory error|ras"
edac-util -v 2>/dev/null || true
ras-mc-ctl --summary 2>/dev/null || true
```

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `CE` | Correctable Error | 可偶发，但不应持续增加 | 持续增长：查条子、槽位、温度、IMC |
| `UE` | Uncorrectable Error | 不应出现 | 阻断测试，优先换条/换槽/查 CPU |
| `Syndrome` | 错误签名 | 可辅助定位 | 同一槽位反复出现：优先怀疑 DIMM 或槽位 |

### 用例 7：内存降频与混插兼容性验证

#### 测试目的

验证不同容量、不同 Rank、不同厂商或不同批次 DIMM 混插时，是否出现全局降频、训练失败或稳定性风险。

#### 前置条件

- 允许维护窗口和重启
- 可更换 DIMM 组合

#### 所需工具

- `dmidecode`
- BIOS Setup
- `stress-ng`

#### 测试步骤

1. 记录单一规格 DIMM 的基线频率。
2. 更换为混插组合。
3. 重新启动并核对 `Configured Memory Speed`。
4. 跑带宽和稳定性测试。
5. 判断是否适合量产使用。

#### 完整测试命令

```bash
dmidecode -t memory | egrep -i "Locator|Manufacturer|Part Number|Speed|Configured Memory Speed|Size"
stress-ng --vm 8 --vm-bytes 70% --timeout 1h --metrics-brief
```

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `Configured Memory Speed` | 混插后的实际频率 | 应符合平台容忍范围 | 大幅降频：不建议量产 |
| `Manufacturer / Part Number` | 混插对象 | 应可追溯 | 无法追溯：质量与复现风险高 |

### 用例 8：CXL Memory 枚举与可用性验证

#### 测试目的

验证 CXL Type-3 Memory Device 是否被 BIOS 和 OS 正确识别，容量是否可见，是否可用于扩展内存场景。

#### 前置条件

- 平台支持 CXL
- BIOS 已开启相关选项
- OS 已安装 `cxl-cli`

#### 所需工具

- `lspci`
- `dmesg`
- `cxl`

#### 测试步骤

1. 检查 PCIe 侧是否识别到 CXL 设备。
2. 检查 `dmesg` 中 CXL 初始化日志。
3. 使用 `cxl list` 查看 memory device、decoder、region。
4. 如平台支持，验证 region 创建和容量可见性。

#### 完整测试命令

```bash
lspci | grep -i cxl
dmesg -T | grep -i cxl
cxl list -M -m -d -D -R 2>/dev/null || true
```

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `memdev` | CXL 内存设备 | 应被正确枚举 | 不可见：查 BIOS、固件、内核 |
| `decoder` | 地址解码器 | 应与平台设计匹配 | 缺失：查 CXL region 配置 |
| `region` | CXL 内存区域 | 按设计创建 | 无 region：尚未配置或初始化失败 |

## 5. 结果分析与问题诊断方法

### 5.1 内存问题的分析总思路

不要一看到“内存带宽低”就直接怀疑 DIMM。正确顺序是：

1. 先确认 DIMM 是否识别完整
2. 再确认实际频率是否正常
3. 再确认 NUMA 和插法是否均衡
4. 再确认 BIOS 是否限制了模式
5. 再看 ECC/RAS 是否已经在报警
6. 最后才判断是 DIMM 本体、CPU IMC、主板、BIOS 还是业务绑定问题

### 5.2 常见异常一：总容量不对

表现：

- 系统显示总内存少于配置单
- 某个节点容量明显偏小

排查顺序：

1. `dmidecode -t memory`
2. `numactl -H`
3. BIOS 中内存训练/错误屏蔽信息
4. 物理检查 DIMM 槽位

结论习惯：

“先判断是没识别，还是识别了但被屏蔽。”

### 5.3 常见异常二：频率降到比预期低很多

表现：

- 配置了 DDR5 6400，但实际只跑 5600 或更低

常见原因：

- 2DPC 导致平台主动降频
- 混插不同容量/Rank/厂商
- CPU SKU 或 BIOS 不支持当前目标频率
- RAS 模式影响频率边界

排查顺序：

1. 看 `Configured Memory Speed`
2. 看 DIMM 组合是否一致
3. 看 BIOS 内存频率策略
4. 看 CPU 平台支持矩阵

### 5.4 常见异常三：带宽低、时延高

表现：

- MLC/STREAM 结果低于历史基线
- 本地访问和远端访问差异异常

常见原因：

- DIMM 未插满关键通道
- NUMA 模式不合理
- governor 或 BIOS 功耗模式保守
- 后台任务抢占

排查顺序：

1. 看插法
2. 看 NUMA
3. 看 CPU 频率和功耗模式
4. 看测试过程是否干净

### 5.5 常见异常四：ECC 持续增长

表现：

- 测试过程中 CE 不断累积

常见原因：

- 某条 DIMM 边缘不稳定
- 槽位接触或主板通道问题
- 温度、电压边界
- CPU 内存控制器问题

处理原则：

- CE 持续增长不应被当成“还能跑就算没事”
- 它是高级工程师必须提前拦截的风险信号

### 5.6 常见异常五：CXL 内存设备存在但用不起来

常见原因：

- BIOS 未开启相关项
- OS 内核版本不匹配
- region 未创建
- 固件与驱动版本链不一致

排查顺序：

1. 先看 `lspci`
2. 再看 `dmesg`
3. 再看 `cxl list`
4. 最后看 region 配置与上层应用

## 6. 最佳实践与注意事项

1. 做内存对比测试前，先统一 DIMM 厂商、容量、Rank、DPC 和 BIOS 模式。
2. 所有带宽和时延测试都要说明 NUMA 绑定策略。
3. 同一平台上，内存插法错误比“条子坏”更常见。
4. 长稳测试必须同时抓 `dmesg`、`journalctl`、EDAC/RAS 统计。
5. CE 持续增长要视为高风险，不要等 UE 才处理。
6. 混插测试不能只看“能开机”，必须看频率、带宽和长稳。
7. CXL 测试要把 BIOS、内核、固件和上层 region 配置一起记录。
8. AI 服务器做内存测试时，要特别关注 Host CPU 内存带宽是否成为数据供给瓶颈。

## 7. 进阶内容（高阶测试技巧、自动化思路、多厂商混配测试等）

### 7.1 建议沉淀的自动化采集项

建议把下面这些信息自动化采集并结构化：

- 每条 DIMM 的厂商、料号、容量、速度、槽位
- 总容量
- NUMA 节点容量
- 配置频率
- EDAC/CE/UE 计数
- 带宽与时延基线
- BIOS 内存相关关键项

输出建议：

- `memory_inventory.json`
- `memory_perf.csv`
- `memory_ras_summary.md`

### 7.2 适合汇报的内存健康结论模板

你在项目汇报中可以用这样的表达：

“当前样机内存配置为 24 条 DDR5 RDIMM，容量与槽位分布符合配置单，实际运行频率达到平台当前目标值；NUMA 节点容量分布均衡，本地带宽和远端时延表现符合预期。完成 2 小时高占用压力后未见新增不可纠错错误，但观测到少量可纠错错误增长，建议优先对对应槽位 DIMM 做互换复测，并持续跟踪 EDAC 计数。”

### 7.3 高级工程师必须形成的思维

普通工程师会说：

- “内存识别正常”
- “跑分还可以”

高级工程师会说：

- “内存已识别，但频率受 2DPC 和混插影响降级”
- “带宽偏低不是 DIMM 本体问题，而是 NUMA 绑定和 CPU 功耗策略共同导致”
- “当前没有 UE，但 CE 持续增长，存在量产风险”

这就是你从普通测试工程师走向高级工程师必须建立的表达能力。

## 参考来源

- [SK hynix：256GB DDR5 RDIMM 完成 Intel Xeon 6 平台认证](https://news.skhynix.com/sk-hynix-first-to-complete-intel-data-center-certificationfor-32gb-die-based-256gb-server-ddr5-rdimm/)
- [Samsung Semiconductor：CXL Memory](https://semiconductor.samsung.com/us/cxl-memory/)
- [Micron：128GB DDR5 RDIMM 产品资料](https://assets.micron.com/adobe/assets/urn%3Aaaid%3Aaem%3A6ffd17ac-e709-469d-9473-a0a904681dd9/renditions/original/as/128gb-ddr5-rdimm-product-brief.pdf)
- [Micron：DDR5 MRDIMM 产品资料](https://assets.micron.com/adobe/assets/urn%3Aaaid%3Aaem%3Ab19be6b5-f4bb-4367-bb0d-d583bdef5bae/original/as/mrdimm_product_brief.pdf)
- [长鑫存储产品页](https://www.cxmt.com/product.html)
- [CXMT DDR5 产品新闻](https://www.cxmt.com/en/news/info_20.html)
