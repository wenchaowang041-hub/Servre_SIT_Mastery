# NVMe 热插拔测试通用详细执行手册

## 1. 文档目的

本手册用于指导 Linux 服务器环境下的 NVMe SSD 热插拔测试，适用于：

- 不带 IO 的热插拔测试
- 带 IO 的热插拔测试
- 多拓扑槽位覆盖测试
- 现场执行、日志保留、结果判定、问题追溯

本手册设计为通用流程，可在后续其他平台复用。

## 2. 测试目标

验证被测 NVMe SSD 在热拔插过程中以下项目是否正常：

- 盘片掉电、回插后的重新识别能力
- PCIe 链路训练与速率协商是否正常
- IO 压力场景下的设备稳定性
- 分区 1 中文件完整性是否保持一致
- 操作系统日志是否存在硬盘相关异常
- BMC/FDM 日志是否存在硬盘相关异常
- 硬盘外观、金手指、接插件是否损伤

## 3. 适用前提

执行本手册前应满足：

- 服务器支持 NVMe 热插拔
- 服务器 BIOS / BMC / OS 已正确识别 NVMe 设备
- 测试人员具备 root 权限
- 已安装下列工具：
  - `nvme-cli`
  - `smartmontools`
  - `fio`
  - `ipmitool`
  - `pciutils`
  - `util-linux`
  - `parted`
  - `md5sum`

建议先确认：

```bash
which nvme
which smartctl
which fio
which ipmitool
which lspci
which fdisk
which parted
```

## 4. 测试原则

### 4.1 不操作系统盘

系统盘禁止用于热插拔测试，禁止重新分区，禁止加入测试盘列表。

### 4.2 被测盘允许清盘

被测盘在测试前通常会重新分区，原有数据会被清除。

### 4.3 优先覆盖不同拓扑

“遍历所有拓扑不同的槽位”优先指覆盖不同 PCIe 拓扑，而不是机械地覆盖所有物理槽位。

如果不同槽位共享同一个上游 Root Port 或同一条 PCIe 分支，通常可视为同一种拓扑。

### 4.4 每轮日志独立保存

每一轮测试必须独立保存日志，避免不同轮次日志混淆。

## 5. 测试前准备

### 5.1 硬件准备

- 准备 2 块被测 SSD
- 服务器其余槽位可插满引入盘
- 明确本轮需要测试的 2 个物理槽位
- 明确本轮是否属于新的拓扑覆盖

### 5.2 软件准备

建议预先创建测试目录：

```bash
mkdir -p /root/hotplug_logs
mkdir -p /root/nvme_hotplug_scripts
```

将脚本上传到：

```bash
/root/nvme_hotplug_scripts
```

授权：

```bash
chmod +x /root/nvme_hotplug_scripts/*.sh
```

## 6. 如何识别系统盘

先查看块设备和挂载关系：

```bash
lsblk
nvme list
```

重点查看：

- `/`
- `/boot`
- `/boot/efi`
- LVM / RAID / 文件系统挂载关系

如果某块 NVMe 盘承载根分区、启动分区或系统 LVM，该盘就是系统盘。

## 7. 如何识别拓扑

### 7.1 查看 NVMe 控制器

```bash
lspci | grep -i "Non-Volatile"
```

### 7.2 查看 PCIe 树

```bash
lspci -tv
```

### 7.3 查看盘符与 PCI 路径映射

```bash
for d in /dev/nvme*n1; do
    name=$(basename "$d")
    ctrl=${name%n1}
    path=$(readlink -f /sys/class/nvme/$ctrl)
    nvme_bdf=$(basename "$(dirname "$(dirname "$path")")")
    root_bdf=$(basename "$(dirname "$(dirname "$(dirname "$(dirname "$path")")")")")
    echo "$d -> NVMe:$nvme_bdf  RootPort:$root_bdf"
done | sort
```

### 7.4 如何判断是不是新拓扑

一般满足以下任一条件，即视为不同拓扑：

- 上游 `Root Port` 不同
- `lspci -tv` 中 PCIe 树路径不同
- 所属 CPU / Host Bridge 不同
- 所属 PCIe Switch 分支不同

一般以下情况不算新拓扑：

- 仅盘符变化
- 仅槽位编号变化，但 PCIe 树路径本质不变

## 8. 建议的测试覆盖方法

通用建议如下：

1. 先将所有可测槽位按拓扑分组
2. 每种拓扑至少选择 2 个槽位
3. 每种拓扑用 2 块被测盘做一整轮完整测试
4. 再换到下一种拓扑

如果项目规范明确要求全槽位覆盖，则在完成拓扑覆盖后，再增加槽位全覆盖测试。

## 9. 测试目录与日志目录规范

建议使用以下目录结构：

```bash
/root/hotplug_logs/
  2026-04-09_topoA/
  2026-04-09_topoB/
  2026-04-09_topoC/
```

每轮测试前进入对应目录，再调用脚本：

```bash
cd /root/hotplug_logs/2026-04-09_topoA
/root/nvme_hotplug_scripts/1-check-Begin.sh
```

这样脚本生成的 `logs/` 会自动保存在当前轮次目录中。

## 10. 被测盘分区规范

每块被测盘按以下方式分区：

- 分区 1：10GB
- 分区 2：剩余全部空间

用途如下：

- `p1`：格式化为 `ext4`，用于写入校验文件并做 `MD5` 校验
- `p2`：用于 `fio` 压测

## 11. 标准测试流程总览

完整流程分为以下阶段：

1. 确认系统盘与被测盘
2. 确认拓扑并选择槽位
3. 修改脚本配置
4. 初始化被测盘
5. 记录基线信息
6. 生成校验文件
7. 启动 IO 压力
8. 人工热拔插
9. 回插后校验识别、MD5、日志
10. 重复至规定次数
11. 收集收尾日志
12. 打包归档

## 12. 脚本使用说明

假定脚本目录为：

```bash
/root/nvme_hotplug_scripts
```

### 12.1 `config.sh`

功能：

- 配置本轮被测盘
- 控制日志目录、挂载根目录、`fio` 参数

核心配置：

```bash
DUTS=(
  "/dev/nvme0n1"
  "/dev/nvme1n1"
)
```

要求：

- 只填写本轮 2 块被测盘
- 禁止填写系统盘

### 12.2 `0-prepare-nvme.sh`

功能：

- 对被测盘重新建 GPT
- 创建 `p1`、`p2`
- 格式化 `p1`
- 更新 `/etc/fstab`
- 创建挂载目录

注意：

- 会清空被测盘数据
- 每组被测盘首次使用时执行一次

### 12.3 `1-check-Begin.sh`

功能：

- 记录 `lsblk`
- 记录 `lsscsi`
- 清空 `dmesg`
- 清空 BMC SEL
- 记录 `nvme smart-log`
- 记录 `smartctl`
- 记录 BDF、slot、Speed 信息

### 12.4 `2-md5.sh`

功能：

- 挂载 `p1`
- 生成 1GB 随机文件
- 计算源文件 MD5
- 将文件拷贝到被测盘分区 1
- 计算盘上文件 MD5

### 12.5 `fio.sh`

功能：

- 对被测盘 `p2` 启动顺序混合读写压力
- 默认读写比 `50/50`

### 12.6 `3-check-md5.sh`

功能：

- 回插后等待设备稳定
- 检查盘是否识别
- 挂载 `p1`
- 对比 MD5
- 记录 `smart-log`
- 记录 `dmesg`
- 记录 `BMC SEL`

### 12.7 `4-check-Finish.sh`

功能：

- 汇总本轮结束时的 `lsblk`
- 汇总 `dmesg`
- 汇总 `BMC SEL`
- 汇总结束时的 `smart-log`

## 13. 现场标准执行步骤

以下步骤适用于每一轮测试。

### 步骤 1：进入本轮目录

示例：

```bash
cd /root/hotplug_logs/2026-04-09_topoA
```

### 步骤 2：保存环境基线

```bash
date > env_info.txt
hostname >> env_info.txt
uname -a >> env_info.txt
nvme list > nvme_list.txt
lsblk > lsblk.txt
fdisk -l > fdisk.txt
lspci -tv > lspci_tv.txt
```

保存盘符拓扑映射：

```bash
for d in /dev/nvme*n1; do
    name=$(basename "$d")
    ctrl=${name%n1}
    path=$(readlink -f /sys/class/nvme/$ctrl)
    nvme_bdf=$(basename "$(dirname "$(dirname "$path")")")
    root_bdf=$(basename "$(dirname "$(dirname "$(dirname "$(dirname "$path")")")")")
    echo "$d -> NVMe:$nvme_bdf  RootPort:$root_bdf"
done | sort > nvme_topology_map.txt
```

### 步骤 3：修改 `config.sh`

将 `DUTS` 改成本轮被测盘。

### 步骤 4：初始化被测盘

首次针对该组盘执行：

```bash
/root/nvme_hotplug_scripts/0-prepare-nvme.sh
```

### 步骤 5：记录基线

```bash
/root/nvme_hotplug_scripts/1-check-Begin.sh
```

### 步骤 6：生成校验文件

```bash
/root/nvme_hotplug_scripts/2-md5.sh
```

### 步骤 7：启动 IO 压力

```bash
/root/nvme_hotplug_scripts/fio.sh
```

### 步骤 8：人工执行热插拔

单次循环：

1. 拔出一块被测盘
2. 等待 30 秒
3. 慢插回去
4. 再等待 6 秒
5. 执行：

```bash
/root/nvme_hotplug_scripts/3-check-md5.sh
```

第二块盘按同样流程执行。

建议采用交替方式：

- 第 1 次拔 DUT1
- 第 2 次拔 DUT2
- 第 3 次拔 DUT1
- 第 4 次拔 DUT2

直至达到规定次数，例如 30 次。

### 步骤 9：本轮结束收尾

```bash
/root/nvme_hotplug_scripts/4-check-Finish.sh
```

### 步骤 10：打包本轮日志

退出到日志总目录：

```bash
cd /root/hotplug_logs
tar -czf 2026-04-09_topoA.tar.gz 2026-04-09_topoA
```

## 14. 现场最简执行版

可直接记忆为：

```bash
cd /root/hotplug_logs/本轮目录
/root/nvme_hotplug_scripts/0-prepare-nvme.sh     # 每轮首次一次
/root/nvme_hotplug_scripts/1-check-Begin.sh
/root/nvme_hotplug_scripts/2-md5.sh
/root/nvme_hotplug_scripts/fio.sh
/root/nvme_hotplug_scripts/3-check-md5.sh        # 每次插回 6 秒后执行
/root/nvme_hotplug_scripts/4-check-Finish.sh
```

## 15. 每次循环建议记录方法

每次人工操作完成后，建议追加一行结果。

示例：

```bash
echo "loop01 pull nvme0n1 PASS $(date '+%F %T')" >> loop_record.txt
echo "loop02 pull nvme1n1 PASS $(date '+%F %T')" >> loop_record.txt
echo "loop03 pull nvme0n1 FAIL fio_error $(date '+%F %T')" >> loop_record.txt
```

建议记录字段：

- 循环次数
- 被拔盘符
- PASS/FAIL
- 失败原因
- 时间

## 16. 结果判定标准

### 16.1 PASS 条件

满足以下条件可判定单次循环通过：

- 设备回插后系统能重新识别
- 分区 1 能正常挂载
- `MD5` 校验一致
- `fio` 无异常报错
- `dmesg` 无盘相关严重错误
- `BMC/FDM` 无盘相关错误

### 16.2 FAIL 条件

满足以下任一项即可判为失败：

- 盘回插后无法识别
- 分区无法挂载
- `MD5` 校验失败
- `fio` 报 I/O error、device lost、timeout
- `dmesg` 出现 reset failed、abort、I/O error、timeout
- `BMC/FDM` 存在硬盘掉线、故障、失联相关告警

## 17. 必须保留的日志

每轮必须保留：

- `env_info.txt`
- `nvme_list.txt`
- `lsblk.txt`
- `fdisk.txt`
- `lspci_tv.txt`
- `nvme_topology_map.txt`
- `loop_record.txt`
- `logs/dmesg-After-Reinsert.log`
- `logs/dmesg-Finish.log`
- `logs/bmc-After-Reinsert.log`
- `logs/bmc-Finish.log`
- `logs/*-Begin.log`
- `logs/*-check-md5.log`
- `logs/*-Finish.log`
- `logs/*-fio.log`

## 18. 现场常见问题

### 18.1 `fio` 还没起来就拔盘

处理：

- 重新执行 `fio.sh`
- 确认已生成 `fio-pids.log`
- 再开始拔盘

### 18.2 盘回插后盘符变化

处理：

- 先执行 `nvme list`
- 再看 `lsblk`
- 再核对 `nvme_topology_map.txt`
- 必要时重新确认 `config.sh`

### 18.3 `MD5` 校验失败

处理：

- 立即保存 `dmesg`
- 保存 `smart-log`
- 保存 `BMC SEL`
- 在 `loop_record.txt` 明确记录失败轮次

### 18.4 回插后不识别

处理：

- 立即执行 `dmesg | tail -200`
- 立即执行 `ipmitool sel list | tail -100`
- 保存 `nvme list`
- 记录槽位、次数、盘符、时间

## 19. 测试结束后的外观检查

测试完成后需执行外观检查：

- 盘体无明显损伤
- 金手指无明显划伤
- 接插件无明显损坏
- 无烧蚀、断裂、变形

## 20. 当前会话对应平台实例

本节用于保留当前机器的实际拓扑，后续可作为参考样例。

### 当前系统盘

```bash
/dev/nvme5n1
```

### 当前拓扑组

#### 拓扑 1：`RootPort = pci0000:06`

```bash
/dev/nvme0n1 -> NVMe:0000:07:00.0
/dev/nvme1n1 -> NVMe:0000:08:00.0
/dev/nvme2n1 -> NVMe:0000:09:00.0
/dev/nvme3n1 -> NVMe:0000:0a:00.0
```

建议测试组合：

```bash
/dev/nvme0n1 + /dev/nvme1n1
```

#### 拓扑 2：`RootPort = pci0000:c7`

```bash
/dev/nvme4n1 -> NVMe:0000:c8:00.0
/dev/nvme5n1 -> NVMe:0000:c9:00.0   # 系统盘
/dev/nvme6n1 -> NVMe:0000:ca:00.0
/dev/nvme7n1 -> NVMe:0000:cb:00.0
```

建议测试组合：

```bash
/dev/nvme4n1 + /dev/nvme6n1
```

#### 拓扑 3：`RootPort = pci0000:e3`

```bash
/dev/nvme8n1  -> NVMe:0000:e4:00.0
/dev/nvme9n1  -> NVMe:0000:e5:00.0
/dev/nvme10n1 -> NVMe:0000:e6:00.0
/dev/nvme11n1 -> NVMe:0000:e7:00.0
```

建议测试组合：

```bash
/dev/nvme8n1 + /dev/nvme9n1
```

### 当前机器推荐测试顺序

第一轮：

- 拓扑 `pci0000:06`
- 测试盘：`nvme0n1 + nvme1n1`

第二轮：

- 拓扑 `pci0000:e3`
- 测试盘：`nvme8n1 + nvme9n1`

第三轮：

- 拓扑 `pci0000:c7`
- 测试盘：`nvme4n1 + nvme6n1`

## 21. 与协同支持人员的配合方式

现场执行时，建议每一步都保留以下信息，便于远程协助判断：

- 当前轮次
- 当前拓扑
- 当前 `DUTS`
- 当前执行的脚本
- 命令输出
- 报错截图或文本
- `loop_record.txt`

如果现场边测边反馈，可按以下顺序发送：

1. 当前轮次和被测盘
2. `config.sh` 中 `DUTS`
3. 脚本输出
4. `dmesg` 关键内容
5. `fio` 关键内容
6. `3-check-md5.sh` 结果

## 22. 结论

本手册的核心原则只有三条：

1. 不动系统盘
2. 按不同拓扑覆盖测试
3. 每轮日志独立保存并及时归档

按本手册执行后，可满足现场测试、问题追溯和后续复用三类需求。
