# 第十二章 DPU/SmartNIC 测试

## 1. 模块概述与重要性

DPU/SmartNIC 是 2026 年数据中心基础设施的重要方向。  
它不只是“高级网卡”，而是把网络、存储、安全、虚拟化卸载下沉到专用器件。

因此测试重点也不再只是“有网卡”，而是：

- Host 侧是否正常
- DPU 侧是否正常
- 卸载能力是否生效
- 虚拟化/容器/存储场景是否协同

## 2. 2026年厂商与主流产品信息对比表

| 厂商 | 主流产品方向 | 典型亮点 | 典型应用 | 重点测试关注点 |
|---|---|---|---|---|
| NVIDIA | BlueField 系列 | 网络/存储/安全卸载成熟 | 云、AI、基础设施卸载 | host/dpu 双侧、SR-IOV、OVS |
| Intel | IPU / 基础设施处理器方向 | 云基础设施卸载 | 云平台 | 固件、虚拟化、网络卸载 |
| Broadcom / Marvell 等 | SmartNIC 方向 | 企业和云覆盖 | 数据中心网络与安全 | 兼容性、稳定性 |

## 3. 基础原理讲解

### 3.1 DPU 测试到底在测什么

1. 设备是否枚举
2. 固件和驱动是否匹配
3. Host 侧和 DPU 侧能否正常通信
4. VF、SR-IOV、OVS/NVMe-oF 卸载是否生效

### 3.2 为什么 DPU 测试必须双侧采集

因为很多问题只看 host 看不出来，只看 DPU 也看不出来。  
必须保留：

- host 侧日志
- dpu 侧日志
- 网络与虚拟化配置

## 4. 详细测试用例

### 用例 1：设备枚举与驱动固件检查

```bash
lspci | grep -i -E "bluefield|smartnic|ethernet"
ethtool -i eth0
```

### 用例 2：SR-IOV/VF 验证

```bash
echo 8 > /sys/class/net/eth0/device/sriov_numvfs
ip link show
```

### 用例 3：host/dpu 联通与吞吐测试

```bash
ping -c 4 <peer_ip>
iperf3 -c <peer_ip> -P 4 -t 30
```

### 用例 4：卸载功能基本验证

步骤：
1. 配置 VF 或虚拟交换路径
2. 观察 host CPU 降低趋势
3. 对比卸载开关前后的性能与 CPU 占用

## 5. 结果分析与问题诊断方法

先判断问题在 host 侧还是 dpu 侧，再看固件、驱动、IOMMU、SR-IOV 和网络配置。

## 6. 最佳实践与注意事项

1. DPU 测试必须保留双侧版本与日志。
2. SR-IOV 与 IOMMU 一定一起看。
3. 不要只看链路，要看卸载是否真的带来 CPU 收益。

## 7. 进阶内容（高阶测试技巧、自动化思路、多厂商混配测试等）

建议增加：

- OVS/OVN 卸载
- NVMe-oF 卸载
- 安全与加密卸载

