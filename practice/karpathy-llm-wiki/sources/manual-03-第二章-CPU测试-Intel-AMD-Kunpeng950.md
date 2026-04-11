# 第二章 CPU 测试（Intel、AMD、华为 Kunpeng 950 系列）

## 1. 模块概述与重要性

CPU 是服务器的控制中枢。即使在 2026 年 AI 服务器大量采用 GPU、NPU、DPU，加速器已经成为主角，CPU 仍然决定以下关键能力：

- 系统是否能稳定启动和枚举所有设备
- NUMA 拓扑是否合理
- 中断、调度、内存分配是否高效
- 存储、网络、虚拟化、容器等基础服务是否稳定
- AI 训练或推理时，Host 侧供数是否充足

很多工程师在服务器测试中犯的典型错误，是把 CPU 测试理解成“跑个 `stress-ng` 或 `sysbench` 就结束”。这是远远不够的。

真正的 CPU 测试，至少要覆盖四类问题：

1. 功能正确性
   - CPU 是否被正确识别，核数、线程数、缓存、指令集是否符合规格
2. 性能达标性
   - 单核、多核、跨 NUMA、虚拟化场景下是否达到平台预期
3. 稳定性与热设计
   - 长时间高负载是否降频、报错、死机、MCE
4. 兼容性与平台协同
   - 与 BIOS、电源策略、内存配置、PCIe 资源、操作系统调度是否匹配

对于高薪高级工程师岗位，CPU 测试绝不是“基础活”。恰恰相反，很多棘手问题最后都落回 CPU 层：

- GPU/NPU 算力上不去，根因其实是 Host CPU 供数不足
- 高速网卡吞吐不稳，根因是中断绑核和 NUMA 绑定错误
- NVMe 跑分波动，根因是 CPU C-state、P-state 或调度抖动
- 虚拟化性能不稳定，根因是 SMT、NPS、SNC、内存策略配置不当

所以，CPU 测试是整个平台测试的基础章，也是最能体现你是否具备平台级视角的一章。

## 2. 2026年厂商与主流产品信息对比表

> 本章对比表只聚焦 CPU 厂商与主流服务器处理器，后续章节会严格按模块主题匹配对应厂商和产品。

| 厂商 | 2026主流 CPU 型号 | 核心/线程 | 频率与缓存 | TDP | 内存能力 | I/O 能力 | 性能亮点 | 典型测试关注点 |
|---|---|---|---|---|---|---|---|---|
| 华为 | Kunpeng 950（标准版） | 96核 / 192线程 | 官方已公开 2026Q1 发布节奏；面向通算超节点 | 官方公开口径未完全展开 | 面向新一代 TaiShan 平台 | 面向超节点扩展 | 高核密度、机密计算、四层隔离 | NUMA、调度、BMC、功耗模式、RAS |
| 华为 | Kunpeng 950（高核版） | 192核 / 384线程 | 同属 Kunpeng 950 系列 | 官方公开口径未完全展开 | 面向高密度通算 | 面向超节点扩展 | 更高核密度与并发能力 | 高并发、线程调度、内存带宽、散热 |
| Intel | Xeon 6980P | 128核 / 256线程 | Base 2.0GHz，All-core Turbo 3.2GHz，Cache 504MB | 500W | 12通道 DDR5；最高 MRDIMM 8800MT/s；最大 3TB | 96条 PCIe 5.0，6条 UPI 24GT/s | 高内存带宽、适合企业与 AI Host | SNC、UPI、功耗模式、MRDIMM、PCIe 资源 |
| Intel | Xeon 6972P / 6960P 等 Xeon 6 | 72-96核及以上 | Granite Rapids 产品线 | 350W-500W 级别 | DDR5 / MRDIMM | PCIe 5.0 | 企业通算与虚拟化稳态强 | 单核、多核、虚拟化和频率策略 |
| AMD | EPYC 9965 | 192核 / 384线程 | Base 2.25GHz，All-core Boost 3.35GHz，Max Boost 3.7GHz，L3 384MB | 500W | 12通道 DDR5-6400，单路带宽 614GB/s | 128条 PCIe 5.0 | 超高核心密度，云与 AI Host 强 | NPS、SMT、CCD/NUMA、功耗与温度 |
| AMD | EPYC 9755 | 128核 / 256线程 | EPYC 9005 系列 | 500W 级别 | 12通道 DDR5 | PCIe 5.0 | 核数与频率平衡 | 虚拟化、数据库、多队列调度 |
| AMD | EPYC 9655 | 96核 / 192线程 | EPYC 9005 系列 | 400W-500W 级别 | 12通道 DDR5 | PCIe 5.0 | 通算/HPC 兼顾 | CPU 频率稳定性、内存与 I/O 绑定 |

## 3. 基础原理讲解（通俗易懂）

### 3.1 CPU 测试到底在测什么

CPU 测试不是只看“跑分高不高”，而是同时测四层能力：

1. 识别层
   - CPU 型号、核数、线程数、缓存、指令集是否正确
2. 拓扑层
   - Socket、NUMA、Core、SMT 是否按预期工作
3. 性能层
   - 单核性能、多核性能、跨 NUMA 性能是否稳定
4. 稳定层
   - 长时间高负载下有没有降频、MCE、硬件纠错、死机、重启

### 3.2 为什么 2026 年 CPU 测试更复杂

因为 CPU 不再只是“跑业务逻辑”，而是整机所有资源调度的中心。

举三个现场最常见的例子：

#### 例子 1：AI 服务器卡很强，但训练速度不高

根因可能不是 GPU/NPU，而是 CPU Host 侧：

- DataLoader 不够快
- 中断绑核错误
- NUMA 绑错，导致跨 socket 访问
- C-state 太深，导致时延抖动
- BIOS 电源模式保守

#### 例子 2：网卡吞吐达不到线速

根因可能是 CPU：

- 中断分布不合理
- 网卡队列和 CPU 核没对齐
- CPU 频率不稳
- SMT 和亲和性配置不合理

#### 例子 3：存储跑分波动大

根因可能是 CPU：

- fio 线程跨 NUMA 跑
- CPU governor 处于省电模式
- 背景任务抢占 CPU
- CPU 热降频

### 3.3 CPU 测试中的几个核心概念

#### 3.3.1 Socket、Core、Thread

- Socket：物理 CPU 路数
- Core：真实核心
- Thread：超线程或 SMT 后 OS 可见逻辑线程

例如：

- `2S * 96C * 2T = 384 logical CPUs`

你必须先会把这个公式和 `lscpu` 对上。

#### 3.3.2 NUMA

NUMA 的意思是“非统一内存访问”。

简单理解：

- CPU 访问本地内存更快
- 访问远端 socket 的内存更慢

所以在双路或多路平台上：

- CPU 测试要看 NUMA
- 内存测试要看 NUMA
- 网卡测试要看 NUMA
- GPU/NPU 测试更要看 NUMA

如果 NUMA 不理解，后面很多性能问题都只会停留在“感觉有点慢”，说不清根因。

#### 3.3.3 频率、功耗与热限制

CPU 标称频率并不等于真实运行频率。真实运行频率受以下因素影响：

- BIOS 电源策略
- OS governor
- 温度
- 功耗墙
- 核心数量
- AVX/矩阵类指令负载强度

因此，高级工程师不会只看“最大睿频”，而会看：

- 单核压测时频率是否冲得上去
- 全核压测时频率是否稳定
- 温度是否逼近 Tj 限制
- 长稳时是否出现明显掉频

#### 3.3.4 厂商特性差异

##### Intel Xeon 6

重点关注：

- SNC（Sub-NUMA Clustering）
- UPI 链路
- P-state / C-state
- MRDIMM 带来的内存带宽收益
- BIOS Power Profile

##### AMD EPYC 9005

重点关注：

- NPS（NUMA Per Socket）
- CCD/CCX 结构对时延和带宽的影响
- SMT 开关
- Determinism / Power 模式

##### 华为 Kunpeng 950

重点关注：

- 高核数调度能力
- 通算场景下的线程并发效率
- NUMA / 内存分布与 BMC 散热策略协同
- 机密计算和隔离机制下的性能验证

### 3.4 `SPEC CPU` 在服务器 CPU 测试中的定位

`sysbench`、`stress-ng` 更适合做快速验证和工程现场排查；`SPEC CPU` 更适合做标准化 CPU 性能评估、跨平台横向比较和对外可解释的性能基线。

你可以把几种工具这样理解：

- `lscpu` / `numactl`：看 CPU 身份和拓扑
- `sysbench`：快速看单核、多核扩展趋势
- `stress-ng`：看长稳、功耗、热和错误
- `SPEC CPU`：看标准化计算性能，适合做正式基线和平台对比

`SPEC CPU` 常见有两种结果模式：

- `speed`：测单任务完成时间，更偏单实例性能
- `rate`：测并发吞吐能力，更偏多任务总吞吐

对于服务器测试：

- 做数据库、虚拟化、单实例业务，更关注 `speed`
- 做高并发通算、云资源池、AI Host 供数，更关注 `rate`

注意：`SPEC CPU` 是商业授权工具。正式测试前必须确认你使用的是合法版本，并记录版本号、config 文件、编译器和编译选项，否则结果不具备可复现性。

## 4. 详细测试用例

### 用例 1：CPU 基础识别与拓扑核对

#### 测试目的

确认 CPU 型号、核数、线程数、Socket 数、NUMA 拓扑和在线状态与产品规格一致。

#### 前置条件

- 系统正常启动
- 已安装 `lscpu`、`numactl`

#### 所需工具

- `lscpu`
- `numactl`
- `dmidecode`

#### 测试步骤

1. 采集 CPU 总体信息。
2. 采集 CPU 扩展拓扑。
3. 采集 NUMA 分布。
4. 采集 BIOS 侧 CPU 识别信息。
5. 对照 CPU 规格，检查核数、线程数、Socket 与 NUMA 是否一致。

#### 完整测试命令

```bash
TS=$(date +%F_%H%M%S)
OUT=/tmp/cpu_ident_${TS}
mkdir -p "${OUT}"

lscpu > "${OUT}/01_lscpu.txt"
lscpu -e=cpu,node,socket,core,online,maxmhz,minmhz > "${OUT}/02_lscpu_extended.txt"
numactl -H > "${OUT}/03_numactl.txt"
dmidecode -t processor > "${OUT}/04_dmidecode_processor.txt"

echo "cpu identity snapshot saved to ${OUT}"
```

#### 关键参数解析

| 参数/命令 | 含义 | 作用 |
|---|---|---|
| `lscpu` | CPU 总览 | 看架构、核数、线程、缓存、频率信息 |
| `lscpu -e=...` | 扩展 CPU 枚举 | 看每个逻辑 CPU 属于哪个 node/socket/core |
| `numactl -H` | NUMA 拓扑 | 看本地/远端内存布局 |
| `dmidecode -t processor` | BIOS 处理器信息 | 交叉验证 CPU 型号与插槽信息 |

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `Model name` | CPU 型号 | 与送测 CPU SKU 一致 | 不一致：查样机配置或 BIOS 识别 |
| `CPU(s)` | 总逻辑 CPU 数 | `Socket * Core * Thread` | 偏少：查 SMT、坏核、内核参数 |
| `Socket(s)` | 路数 | 与整机设计一致 | 少路：查 CPU 插槽、电源、主板 |
| `NUMA node(s)` | NUMA 节点数 | 与 BIOS/NPS/SNC 设计一致 | 异常：查 BIOS 模式 |
| `online` | CPU 在线状态 | 全部 `yes` | 离线核心：查 OS 隔离、故障、热插拔配置 |

### 用例 2：CPU 频率与功耗模式检查

#### 测试目的

确认 CPU 是否在正确的性能模式下运行，识别是否存在省电策略、频率限制、热降频等问题。

#### 前置条件

- 已安装 `cpupower` 或系统具备 `sysfs` 接口

#### 所需工具

- `cpupower`
- `turbostat`（Intel 平台优先）
- `watch`
- `grep`

#### 测试步骤

1. 查看 CPU governor。
2. 查看当前和最大频率。
3. Intel 平台使用 `turbostat` 采样频率和功耗。
4. 压测期间观察频率是否持续下降。
5. 结合温度与功耗判断是否降频。

#### 完整测试命令

```bash
TS=$(date +%F_%H%M%S)
OUT=/tmp/cpu_freq_${TS}
mkdir -p "${OUT}"

cpupower frequency-info > "${OUT}/01_cpupower_frequency_info.txt" 2>/dev/null || true
grep . /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > "${OUT}/02_scaling_governor.txt" 2>/dev/null || true
grep . /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq > "${OUT}/03_scaling_cur_freq.txt" 2>/dev/null || true
turbostat --Summary --show Busy%,Bzy_MHz,TSC_MHz,PkgWatt,CorWatt -i 5 -n 6 > "${OUT}/04_turbostat.txt" 2>/dev/null || true

echo "cpu frequency snapshot saved to ${OUT}"
```

#### 关键参数解析

| 参数 | 含义 | 作用 |
|---|---|---|
| `cpupower frequency-info` | 频率策略信息 | 看 governor、驱动、频率范围 |
| `scaling_governor` | 当前调频策略 | 判断是否为 `performance` 或省电策略 |
| `scaling_cur_freq` | 当前频率 | 观察频率是否稳定 |
| `turbostat --show ...` | Intel 平台频率/功耗采样 | 看忙碌度、有效频率、包功耗 |

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `governor` | 调频策略 | 压测场景通常建议 `performance` | `powersave`：切换性能模式 |
| `Bzy_MHz` | 实际忙碌频率 | 应接近场景期望 | 偏低：查功耗墙、热墙、BIOS |
| `PkgWatt` | CPU 包功耗 | 应在负载下合理提升 | 长期过低：可能未跑满或被限功耗 |
| `Busy%` | CPU 忙碌度 | 压测时应高 | 负载低：查绑核或工具参数 |

### 用例 3：CPU 单核/多核性能测试

#### 测试目的

评估单核性能、多核性能和线程扩展效率，识别频率策略、调度、NUMA 等问题。

#### 前置条件

- 已安装 `sysbench`

#### 所需工具

- `sysbench`

#### 测试步骤

1. 先跑单线程基线。
2. 再跑等于物理核心数的多线程测试。
3. 再跑等于逻辑线程数的满线程测试。
4. 对比事件数和耗时变化。
5. 观察扩展效率是否异常。

#### 完整测试命令

```bash
sysbench cpu --cpu-max-prime=20000 --threads=1 run
sysbench cpu --cpu-max-prime=20000 --threads=$(lscpu | awk '/Core\\(s\\) per socket/ {c=$4} /Socket\\(s\\)/ {s=$2} END {print c*s}') run
sysbench cpu --cpu-max-prime=20000 --threads=$(nproc) run
```

#### 关键参数解析

| 参数 | 含义 | 作用 |
|---|---|---|
| `--cpu-max-prime=20000` | 计算质数上限 | 控制计算量，便于横向比较 |
| `--threads=1` | 单线程测试 | 观察单核性能 |
| `--threads=$(nproc)` | 满线程测试 | 观察全核/全线程扩展效率 |

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `events per second` | 每秒完成事件数 | 随线程增加而上升 | 增长异常：查 NUMA、频率、绑核 |
| `total time` | 总耗时 | 线程增加后应下降 | 下降不明显：查调度与频率 |
| `threads fairness` | 线程公平性 | 差异不应过大 | 差异大：查绑核和背景抢占 |

### 用例 4：使用 `SPEC CPU` 做标准化 CPU 性能评估

#### 测试目的

使用 `SPEC CPU` 对服务器 CPU 进行标准化单实例性能和吞吐性能测试，建立跨平台、跨版本可比的 CPU 基线。

#### 前置条件

- 已获得合法的 `SPEC CPU` 授权介质
- 已安装编译工具链，如 `gcc/g++/gfortran` 或厂商建议编译器
- 已完成系统基础信息采集
- 已确认 BIOS、governor、NUMA、散热环境处于目标测试状态

#### 所需工具

- `SPEC CPU`
- `lscpu`
- `numactl`
- `cpupower`

#### 测试步骤

1. 解压并安装 `SPEC CPU` 到测试目录。
2. 执行环境自检，确认编译器和依赖正常。
3. 准备对应平台的 `config` 文件，记录编译器、优化参数、绑定策略。
4. 先执行 `intrate speed` 或单基准试跑，确认环境无误。
5. 再执行完整的 `speed` 或 `rate` 套件。
6. 保存 HTML、CSV、原始日志和 `config` 文件。
7. 将结果与同平台历史基线或竞品平台基线进行对比。

#### 完整测试命令

```bash
cd /opt/spec_cpu

source shrc

mkdir -p result_logs

runcpu --action=build --config=my-kunpeng950.cfg intrate fprate

runcpu --config=my-kunpeng950.cfg \
       --tune=base \
       --copies=1 \
       --iterations=1 \
       --reportable \
       intrate

runcpu --config=my-kunpeng950.cfg \
       --tune=base \
       --copies=$(nproc) \
       --iterations=1 \
       --reportable \
       intrate
```

如果你要先做小规模验证，而不是一次跑完整套件，可先这样试跑：

```bash
cd /opt/spec_cpu
source shrc

runcpu --config=my-kunpeng950.cfg \
       --tune=base \
       --copies=1 \
       --iterations=1 \
       500.perlbench_r 502.gcc_r
```

#### 关键参数解析

| 参数 | 含义 | 作用 |
|---|---|---|
| `source shrc` | 加载 SPEC 环境 | 初始化路径和运行环境 |
| `--action=build` | 只编译不执行 | 先验证编译链是否正常 |
| `--config=my-kunpeng950.cfg` | 指定配置文件 | 固化编译器、优化参数、绑定策略 |
| `--tune=base` | 基础调优模式 | 适合标准化比较和报告输出 |
| `--copies=1` | 单实例 | 近似 `speed` 型单任务性能 |
| `--copies=$(nproc)` | 按逻辑 CPU 数并发 | 观察吞吐型 `rate` 能力 |
| `--iterations=1` | 每项跑 1 轮 | 快速出基线；正式认证可按规范增加轮次 |
| `--reportable` | 生成正式报告格式 | 结果更适合归档和横向比对 |
| `intrate` / `fprate` | 整数/浮点吞吐套件 | 分别看整数和浮点负载能力 |

#### 建议的 `config` 关注项

| 配置项 | 含义 | 建议关注点 |
|---|---|---|
| `CC/CXX/FC` | C/C++/Fortran 编译器 | 固定版本，避免结果漂移 |
| `PORTABILITY` | 可移植性参数 | 按架构修正编译兼容性 |
| `OPTIMIZE` | 优化选项 | 明确记录 `-O2/-O3`、架构参数 |
| `submit` | 任务提交方式 | 可用于 `numactl` 绑核绑定 |
| `label` | 结果标签 | 标明平台、BIOS、日期 |

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `Estimated SPECrate2017_int_base` 或同类总分 | 整数吞吐总分 | 同平台版本间应相对稳定 | 明显偏低：查频率、绑核、BIOS、编译器 |
| `Estimated SPECrate2017_fp_base` 或同类总分 | 浮点吞吐总分 | 同平台版本间应相对稳定 | 偏低：查 AVX/向量能力、散热、编译优化 |
| `Run time` | 单项运行时间 | 不应异常拉长 | 某项异常慢：查 NUMA、热降频、后台负载 |
| `Copies` | 并发副本数 | 应与测试设计一致 | 设置错误会导致结果不可比 |
| `Base/Peak` | 基础/峰值调优 | 对外比较通常优先看 Base | Peak 结果不可直接替代 Base |
| `Compiler Version` | 编译器版本 | 必须固定记录 | 编译器变更会直接影响结果 |

#### `speed` 与 `rate` 的使用建议

| 模式 | 适用场景 | 推荐解释方式 |
|---|---|---|
| `speed` | 单实例数据库、单任务编译、单业务线程响应 | 看单任务完成效率 |
| `rate` | 云资源池、批处理、高并发通算、AI Host 供数 | 看单位时间总吞吐 |

#### 常见异常及处理

| 现象 | 常见原因 | 处理方法 |
|---|---|---|
| 编译失败 | 编译器缺失、库依赖不全、架构参数不兼容 | 补齐编译环境，修订 `config` |
| 分数偏低 | governor 不是 `performance`、BIOS 保守、NUMA 绑定差 | 统一功耗模式并补充绑核策略 |
| 某几个子项波动大 | 背景任务干扰、热降频、内存布局不稳 | 清理后台任务，补采温度和频率 |
| 多次结果差异大 | 环境不一致、风扇策略变化、编译器变动 | 固定环境并保存 `config` 与日志 |

### 用例 5：CPU 多核长稳压力测试

#### 测试目的

验证 CPU 在高负载下长时间运行时的稳定性、温度、功耗和错误状态。

#### 前置条件

- 已安装 `stress-ng`
- BMC 传感器可读取

#### 所需工具

- `stress-ng`
- `ipmitool`
- `dmesg`

#### 测试步骤

1. 记录压测前温度、SEL 和 `dmesg` 基线。
2. 运行长时间 CPU 压力。
3. 压测期间定时采集温度和频率。
4. 压测结束后检查 `dmesg`、MCE、SEL 是否新增异常。

#### 完整测试命令

```bash
TS=$(date +%F_%H%M%S)
OUT=/tmp/cpu_stress_${TS}
mkdir -p "${OUT}"

dmesg -T > "${OUT}/01_dmesg_before.txt"
ipmitool sensor > "${OUT}/02_sensor_before.txt"
ipmitool sel list > "${OUT}/03_sel_before.txt"

stress-ng --cpu 0 --cpu-method matrixprod --metrics-brief --timeout 2h > "${OUT}/04_stressng.txt" 2>&1

dmesg -T > "${OUT}/05_dmesg_after.txt"
ipmitool sensor > "${OUT}/06_sensor_after.txt"
ipmitool sel list > "${OUT}/07_sel_after.txt"

echo "cpu stress test logs saved to ${OUT}"
```

#### 关键参数解析

| 参数 | 含义 | 作用 |
|---|---|---|
| `--cpu 0` | 使用所有在线 CPU | 做全核满载压力 |
| `--cpu-method matrixprod` | 矩阵乘法压力模式 | 更容易触发高负载与热功耗 |
| `--metrics-brief` | 输出关键统计 | 便于收集结果 |
| `--timeout 2h` | 持续 2 小时 | 验证中期稳定性 |

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `bogo ops/s` | 压测吞吐指标 | 同平台应相对稳定 | 明显偏低：查频率、热降频、绑核 |
| `Temp` | CPU 或系统温度 | 不应持续逼近临界值 | 高温：查散热、导风、风扇策略 |
| `dmesg` 中 `MCE/EDAC` | 硬件错误 | 不应新增严重错误 | 出现错误：暂停测试，查 CPU/内存/RAS |
| `SEL` 新事件 | BMC 历史事件 | 不应新增过温/掉电 | 有新增：查机房环境和供电 |

### 用例 6：NUMA 亲和性与跨节点性能测试

#### 测试目的

验证本地 NUMA 绑定和跨 NUMA 访问对 CPU 计算性能的影响，帮助后续网络、存储和 AI 场景调优。

#### 前置条件

- 已安装 `numactl`
- 已安装 `sysbench`

#### 所需工具

- `numactl`
- `sysbench`

#### 测试步骤

1. 先查看 NUMA 节点列表。
2. 在本地节点绑定 CPU 和内存执行基线测试。
3. 再故意跨节点绑定，观察差异。
4. 记录两组结果并分析。

#### 完整测试命令

```bash
numactl -H

numactl --cpunodebind=0 --membind=0 \
  sysbench cpu --cpu-max-prime=20000 --threads=32 run

numactl --cpunodebind=0 --membind=1 \
  sysbench cpu --cpu-max-prime=20000 --threads=32 run
```

#### 关键参数解析

| 参数 | 含义 | 作用 |
|---|---|---|
| `--cpunodebind=0` | 线程绑定在 NUMA 节点 0 | 固定计算发生位置 |
| `--membind=0` | 内存也绑定节点 0 | 本地内存访问基线 |
| `--membind=1` | 内存绑定到其他节点 | 观察跨节点访问损失 |

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `events per second` | 性能指标 | 本地绑定应优于跨节点 | 差异过大：说明 NUMA 非常敏感 |
| `total time` | 总耗时 | 本地绑定更优 | 无差异或异常反转：检查绑定是否生效 |

### 用例 7：CPU 错误日志与 RAS 检查

#### 测试目的

检查 CPU 测试期间是否出现硬件纠错、机器检查异常、EDAC 报错等可靠性问题。

#### 前置条件

- 系统支持 `rasdaemon` 或可读取 `mcelog`

#### 所需工具

- `dmesg`
- `journalctl`
- `rasdaemon`
- `mcelog`

#### 测试步骤

1. 测试前清点当前错误记录。
2. 执行性能和压力测试。
3. 测试后再次检查错误日志。
4. 对比前后差异，定位是否是测试触发的新问题。

#### 完整测试命令

```bash
dmesg -T | egrep -i "mce|edac|hardware error|thermal|throttle"
journalctl -k | egrep -i "mce|edac|hardware error|thermal|throttle"
ras-mc-ctl --summary 2>/dev/null || true
mcelog --client 2>/dev/null || true
```

#### 重点输出字段表

| 字段 | 含义 | 正常范围 | 常见异常及处理方法 |
|---|---|---|---|
| `MCE` | 机器检查异常 | 不应出现未恢复错误 | 立即停测，查 CPU/供电/散热 |
| `EDAC` | ECC/内存控制器纠错 | 可有少量已纠错，但不可持续增长 | 持续增长：排查 DIMM、IMC、散热 |
| `thermal throttle` | 热降频记录 | 不应频繁出现 | 出现频繁：查散热与风扇策略 |

## 5. 结果分析与问题诊断方法

### 5.1 CPU 测试分析总思路

看到异常时，按这条链路分析：

1. 先看识别是否正确
2. 再看拓扑是否正确
3. 再看频率和功耗是否正确
4. 再看压力下是否稳定
5. 最后再看专项场景的业务表现

### 5.2 常见异常一：核数/线程数不对

表现：

- `lscpu` 显示的逻辑 CPU 少于预期
- 某一路 CPU 信息缺失

排查顺序：

1. 查 `dmidecode -t processor`
2. 查 BIOS 中 SMT/核限制选项
3. 查 OS 启动参数，如 `isolcpus`、`maxcpus`
4. 查 CPU 插槽、供电、硬件故障

### 5.3 常见异常二：CPU 频率跑不起来

表现：

- 单核性能低
- 多核压测时频率远低于预期
- 性能波动大

排查顺序：

1. 查 governor 是否为 `performance`
2. 查 BIOS Power Profile
3. 查包功耗和温度
4. 查散热和风扇策略
5. 查是否运行在虚拟机或容器受限环境

### 5.4 常见异常三：长稳压测出现掉频或错误

表现：

- 压测前 10 分钟正常，后面逐渐下降
- `dmesg` 出现 `MCE`、`thermal throttle`
- BMC `SEL` 出现过温

排查顺序：

1. 查 BMC 传感器
2. 查机房环境温度
3. 查散热器贴合、导热材料、风道
4. 查 BMC 风扇曲线策略
5. 查 PSU 和输入功率是否受限

### 5.5 常见异常四：NUMA 敏感导致业务性能差

表现：

- 本地绑核运行正常，业务实测却很差
- 网络、存储、AI 数据预处理吞吐不稳

排查顺序：

1. 查业务进程绑核
2. 查网卡/NVMe/GPU/NPU 所在 NUMA 节点
3. 查中断亲和性
4. 查容器 cpuset 或 K8s CPU Manager 策略

## 6. 最佳实践与注意事项

1. CPU 测试必须先做基础识别和拓扑校验，再跑性能。
2. 做性能对比时，必须统一 BIOS、governor、散热环境、内存配置。
3. 双路及以上平台必须关注 NUMA，不能只看总核数。
4. Intel 平台重点看 UPI、SNC、MRDIMM 与功耗策略。
5. AMD 平台重点看 NPS、SMT、Determinism、CCD/NUMA 影响。
6. 华为 Kunpeng 平台重点看高核数调度、通算并发与平台固件一致性。
7. 长稳测试一定结合 `dmesg`、BMC 传感器和 SEL 一起看，不能只看压测工具是否退出成功。
8. CPU 压测通过，不代表整机通过；它只是后续内存、网络、存储、AI 模块的前提。

## 7. 进阶内容（高阶测试技巧、自动化思路、多厂商混配测试等）

### 7.1 建议沉淀 CPU 自动化采集脚本

建议你后续做一套统一脚本，至少自动收以下内容：

- CPU 基础识别
- NUMA 拓扑
- governor 和频率
- 压测结果
- `dmesg` 和 BMC 温度

输出建议：

- `cpu_summary.md`
- `cpu_topology.json`
- `cpu_stress.log`

### 7.2 混配平台中的 CPU 测试思路

在 AI 服务器中，CPU 测试不应孤立做，而应回答下面这几个问题：

- CPU 是否离 GPU/NPU/NIC 最近
- 中断是否绑在本地核
- DataLoader 是否占满错误的 NUMA 节点
- CPU 是否因为功耗墙影响整机吞吐

### 7.3 高级工程师的标准输出方式

做完本章后，你应该能写出类似这样的结论：

“当前平台 CPU 识别与拓扑符合规格，双路共 384 逻辑线程，NUMA 分布均衡。性能模式已切换为 `performance`，全核 2 小时压力测试未见新增 MCE/EDAC 严重错误，但在满载后期观察到频率轻微回落，结合 BMC 温度数据判断存在一定散热余量不足风险，建议进入内存与整机混合压力测试前先复核风扇策略与机房进风温度。”

### 7.4 `SPEC CPU` 在 Intel / AMD / Kunpeng 平台上的配置建议

`SPEC CPU` 真正拉开工程师水平的地方，不是“会运行”，而是会把配置文件写得稳定、可复现、能解释。

下面给你一个平台化思路，不是要求你照抄，而是要求你知道每个平台该关注什么。

#### Intel Xeon 平台建议

- 重点固定 BIOS 的 `Performance` 或等效高性能模式
- 明确是否开启 `SNC`
- 记录是否开启 `Hyper-Threading`
- 对支持 `MRDIMM` 的平台，记录 DIMM 类型和频率
- 编译与运行阶段尽量避免后台遥测干扰

示例思路：

```bash
# my-intel-xeon6.cfg 中建议重点记录
# - 编译器版本
# - base 优化参数
# - 是否使用 numactl 绑定
# - BIOS/HT/SNC 标签
```

#### AMD EPYC 平台建议

- 重点记录 `NPS` 模式
- 记录是否开启 `SMT`
- 记录 `Determinism` 或类似功耗模式
- 高核数平台尤其要说明 `copies` 的设置依据
- 注意区分“逻辑线程并发”与“物理核心并发”的结论

示例思路：

```bash
# my-amd-epyc9005.cfg 中建议重点记录
# - NPS=1/NPS=2/NPS=4
# - SMT on/off
# - gcc/llvm 版本
# - 运行时 submit 中的绑核策略
```

#### 华为 Kunpeng 平台建议

- 重点记录 Kunpeng 平台的 BIOS / 固件版本
- 明确内核版本与编译器版本
- 高核数场景下优先记录线程调度与绑定策略
- 在通算场景中建议同时保留 `speed` 与 `rate` 两类结果
- 对需要做对外对比的结果，必须写清测试环境和版本前提

示例思路：

```bash
# my-kunpeng950.cfg 中建议重点记录
# - GCC 版本
# - tune=base 的统一参数
# - NUMA 绑定方式
# - 平台标签（BIOS/BMC/Kernel）
```

#### 一个更实战的 `submit` 绑定示例

如果你需要在 `SPEC CPU` 中显式做 NUMA 绑定，可以在 `config` 里使用类似思路：

```bash
# 仅示意，实际语法需按 SPEC CPU config 格式编写
# submit = numactl --cpunodebind=$SPECCOPYNUM --membind=$SPECCOPYNUM $command
```

它的价值在于：

- `rate` 测试时减少副本之间的互相争抢
- 更容易解释跨平台差异
- 更接近服务器整机优化场景

最终要求只有一句：跑 `SPEC CPU`，一定要把“分数”和“配置文件”一起保存。只有分数，没有 `config`，这在高级工程师视角里几乎等于没有结果。

## 参考来源

- [Huawei HUAWEI CONNECT 2025：Kunpeng 950 公布 96核/192线程 与 192核/384线程版本](https://www.huawei.com/cn/news/2025/9/hc-xu-keynote-speech)
- [Intel Xeon 6980P 官方规格](https://www.intel.com/content/www/us/en/products/sku/240777/intel-xeon-6980p-processor-504m-cache-2-00-ghz/specifications.html)
- [Intel Xeon 6 官方产品系列](https://www.intel.com/content/www/us/en/ark/products/series/240357/intel-xeon-6-processors.html)
- [AMD EPYC 9965 官方规格](https://www.amd.com/en/products/processors/server/epyc/9005-series/amd-epyc-9965.html)
- [AMD EPYC 9005 系列数据表](https://www.amd.com/content/dam/amd/en/documents/epyc-business-docs/datasheets/amd-epyc-9005-series-processor-datasheet.pdf)
