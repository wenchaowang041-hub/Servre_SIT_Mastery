# 金丝雀 2SW 与 NVMe 测试记录整理

## 1. 资料来源

- 原始目录：`E:\桌面\金丝雀\2SW`
- 子目录：
  - `SW_LOG`
  - `NVME_LOG`
  - `BUG`

本整理基于目录名、文件名，以及可直接提取文字内容的 `docx` 文件完成。  
对于仅有截图的项目，以下结论按文件名和目录结构归纳，适合作为后续复盘和补全文档的骨架，不作为最终证据替代原始截图。

## 2. 2SW 相关测试项整理

### 2.1 BMC 侧温度与功耗检测

来源：`100015_BMC侧温度&功耗检测`

从 `docx` 可确认的结论：

- BMC Web 路径可查看背板上的 GPU 温度变化
- BMC Web 可查看 `SwitchBoard Power`
- BMC 侧温度、功耗信息与 OS 查询结果保持一致

可沉淀为测试检查点：

- 传感器项是否存在
- 温度值是否实时变化
- 功耗值是否实时变化
- BMC 与 OS 数据是否一致

### 2.2 Redfish 信息查询

来源：`100016_Redfish工具信息查询`

从文件名可归纳的内容：

- 已记录登录路径
- 已分别查询 PCIe 槽位信息
- 适合作为 2SW 设备在 BMC/Redfish 下的信息采集入口

建议后续补充统一命令模板：

```bash
curl -k -u <user>:<pass> https://<bmc>/redfish/v1/
curl -k -u <user>:<pass> https://<bmc>/redfish/v1/Systems/1
curl -k -u <user>:<pass> https://<bmc>/redfish/v1/Chassis/1/PCIeDevices
```

### 2.3 GPU 序列信息与在位联动检查

来源：`100017_GPU序列信息查询`

从 `docx` 可确认的结论：

- BMC 下可以查看 GPU 相关信息
- 逐个移除 Switch 背板上的 GPU 卡后，BMC 中对应 GPU 信息同步消失
- 剩余 GPU 显示正确，对应关系正确
- 拔掉两张 NPU 后，BMC 显示剩余 NPU 在位信息共 8 张

这类记录可作为：

- 在位联动检查
- 序列号/槽位映射检查
- 拔插异常复现材料

### 2.4 PCIe 设备序列信息检查

来源：`100018_PCIE设备序列信息检查`

从文件名可归纳的内容：

- 使用了 `lspci -tv`
- 使用了 `lspci -vv -s <BDF>`

建议固定关注字段：

- `LnkCap`
- `LnkSta`
- `Width`
- `Speed`
- 设备拓扑关系

### 2.5 背板 FRU 查询

来源：`100019_背板fru查询与烧录no`

从文件名可归纳的内容：

- 已存在 BMC Web 下的背板 FRU 查询记录
- 后续可继续补齐 FRU 刷新/烧录前后对比

### 2.6 外观、尺寸、丝印、接口与规格核对

来源：

- `100025_整体外观检查`
- `100026_尺寸规格检查`
- `100027_丝印检查`
- `100028_接口与插槽检查`
- `100029_规格文档书检查`

从 `100025_整体外观检查.docx` 可确认的结论：

- BMC 系统信息页可记录 PCIe 设备型号、接口类型、固件版本、SN、在位状态
- BMC 设备清单可记录设备名称、厂商、带宽、速率
- 整机设备记录无丢失、无异常
- BMC 查询结果与 OS、BIOS 下查询信息一致

这部分适合作为整机到料和 Bring-up 初期的基础核对项：

- 外观是否完好
- 丝印是否正确
- 插槽/接口布局是否与规格一致
- BMC、BIOS、OS 三侧设备信息是否对齐

### 2.7 OS 下 2SW 板信息、在位和供电验证

来源：

- `100030_OS下sw板信息查询`
- `100031_OS在位设备信息检查`
- `100032_OS下电源供电测试`
- `100033_OS下温度功耗检测`
- `100034_BMC侧在位设备信息检查`

从文件名可归纳的重点：

- `100030`：已收集 SW 板在 BMC 下和 FRU 维度的信息
- `100031`：已检查 `LnkCap/LnkSta` 与 NPU 卡在位信息
- `100032`：验证了拔掉 SW 板 I2C/低速线及 NPU 卡后的信息变化
- `100033`：OS 下温度功耗检测与 BMC 检查形成对照
- `100034`：BMC 侧 PCIe 设备信息与设备清单有截图留存

其中 `100032_OS下电源供电测试` 很有价值，按文件名可直接沉淀为一条排障经验：

- 当 SW 板低速线异常时，BMC 可能无法看到 SW 板信息或板上 PCIe 设备信息

这类现象在现场可优先归类到：

- 低速链路异常
- 板间管理通信异常
- 不是纯粹的主链路带宽问题

## 3. NVMe 相关测试项整理

### 3.1 规格书与外观资料

来源：

- `100016_规格书文档`
- `尺寸规格、丝印、接口与插槽`

用途：

- 用于核对背板尺寸、接口分布、丝印与物料一致性
- 适合作为 NVMe 背板到料检查和装配确认资料

### 3.2 BIOS 侧在位设备信息检查

来源：`100147_BIOS侧在位设备信息检查`

从文件名可归纳的内容：

- 已有 BIOS 侧 NVMe 在位信息截图
- 适合作为 BIOS 枚举是否完整的对照证据

### 3.3 FRU 信息查询与刷新

来源：`100150_FRU信息查询与刷新`

从文件名可归纳的内容：

- 已记录背板 FRU 查询
- 后续可补充 FRU 刷新前后版本、序列号或字段变化

### 3.4 OS 在位设备信息检查

来源：`100162_OS在位设备信息检查`

从文件名可归纳的内容：

- 使用了 `lsblk`
- 使用了 `nvme list`
- 使用了 `nvme smart-log`
- 现有记录显示 `smart-log` 无错误

这部分可以直接沉淀为 OS 侧标准检查命令：

```bash
lsblk
nvme list
nvme id-ctrl /dev/nvme0
nvme smart-log /dev/nvme0
```

现场重点关注：

- 盘符数量是否正确
- `SN` / `Model` / `Firmware` 是否可读取
- `critical_warning` 是否异常
- `media_errors` 是否非 0

### 3.5 OS 下温度检查

来源：`100163_OS下温度检查`

从文件名可归纳的内容：

- 已安装 `nvme-cli`
- 使用了 `ipmitool sensor list`
- 使用了 `nvme smart-log`

适合作为 BMC 与 OS 双侧交叉验证模板：

```bash
ipmitool sensor list
nvme smart-log /dev/nvme0
```

### 3.5.1 `nvme smart-log` 工具补充说明

结合当天现场交流，`nvme smart-log` 这个命令本身属于 `nvme-cli`，不是系统默认自带命令。

不同场景建议这样处理：

- Linux OS 下查询 NVMe SMART、SN、型号、固件、健康状态时，优先安装并使用 `nvme-cli`
- Windows OS 下通常不直接使用 `nvme smart-log`，更常见的是使用厂商工具或 `smartmontools`
- BMC 侧不默认认为可以直接执行 `nvme smart-log`，优先通过 Redfish、SEL、Sensor、Storage 相关接口取数

Linux 常用安装方式：

```bash
# Ubuntu / Debian
apt install nvme-cli

# Rocky / RHEL / CentOS
dnf install nvme-cli
```

Linux 常用查询命令：

```bash
nvme list
nvme id-ctrl /dev/nvme0
nvme smart-log /dev/nvme0
```

重点关注字段：

- `sn`
- `mn`
- `fr`
- `critical_warning`
- `temperature`
- `media_errors`
- `percentage_used`

Windows 场景补充：

- 如果只是查序列号，可用系统命令或厂商工具
- 如果要看更完整的 NVMe 健康信息，优先考虑 `smartmontools`
- Windows 自带命令对 PCIe 速率、链路宽度和 NVMe SMART 的可见性不如 Linux 直接，服务器整合测试场景下更推荐进 Linux 环境确认

结论：

- Linux 下查 NVMe SMART，优先工具是 `nvme-cli`
- Windows 下不要默认能跑 `nvme smart-log`
- BMC 下优先走带外接口，不把 OS 命令当成默认手段

### 3.6 BMC 侧背板与在位设备信息检查

来源：

- `100164_BMC侧背板信息检查`
- `100165_BMC侧在位设备信息检查`

从文件名可归纳的内容：

- BMC 侧已检查 NVMe 背板信息
- BIOS 下 12 块 NVMe 在位正常
- BMC 下 12 块 NVMe 在位数正常

这部分可沉淀为一条一致性检查要求：

- BIOS、BMC、OS 三侧的 NVMe 数量与映射必须一致

## 4. BUG 资料整理

来源：`BUG`

文件：

- `openUBMC_20260401-0745-NPU温度缺失.tar.gz`
- `线缆相关告警.png`

从文件名可直接归类的两个问题方向：

- `NPU温度缺失`：优先检查传感器项缺失、设备在位状态、BMC 传感器映射、低速管理链路
- `线缆相关告警`：优先结合线缆连接关系、背板低速线、I2C/SMBus 管理链路、告警日志定位

结合 `100032_OS下电源供电测试` 的资料，后续排查时可以优先验证：

- 低速线是否接好
- BMC 是否还能看到 SW 板和板上设备
- 设备主链路在位与管理链路在位是否出现分离

## 5. 可复用的现场速查命令

### 5.1 2SW / PCIe / NPU

```bash
lspci
lspci -tv
lspci -vv -s <BDF>
dmidecode
ipmitool sensor list
ipmitool sel list
```

### 5.2 NVMe

```bash
lsblk
nvme list
nvme id-ctrl /dev/nvme0
nvme smart-log /dev/nvme0
```

### 5.3 BMC / Redfish

```bash
curl -k -u <user>:<pass> https://<bmc>/redfish/v1/
curl -k -u <user>:<pass> https://<bmc>/redfish/v1/Systems/1
curl -k -u <user>:<pass> https://<bmc>/redfish/v1/Chassis/1/PCIeDevices
curl -k -u <user>:<pass> https://<bmc>/redfish/v1/Systems/1/Storages
```

## 6. 建议补齐项

- 把关键截图中的命令输出转成文字版，避免后续只能看图复盘
- 对每个测试项补齐“步骤-预期-实际-结论-截图路径”
- 对 `BUG` 目录中的 `tar.gz` 日志补一份文本结论
- 把 2SW 与 NVMe 测试项补成标准化 checklist，便于后续项目复用

## 7. 当前可直接复用的经验

- 2SW 板相关温度、功耗信息可以从 BMC 与 OS 两侧交叉确认
- GPU/NPU 在位变化可以通过 BMC 信息联动验证
- PCIe 链路状态需要结合 `LnkCap/LnkSta` 判断是否降速或降宽
- NVMe 在位检查至少要同时覆盖 BIOS、BMC、OS 三侧
- 低速线异常可能导致 BMC 看不到 SW 板或板上设备，这类问题不能只按主链路故障处理
