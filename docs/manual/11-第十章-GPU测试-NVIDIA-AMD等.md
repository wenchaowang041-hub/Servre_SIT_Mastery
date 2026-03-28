# 第十章 GPU 测试（NVIDIA、AMD 等）

## 1. 模块概述与重要性

GPU 是现代 AI 服务器最核心的算力器件之一。  
但 GPU 测试真正难的地方，从来不是“卡在不在”，而是：

- 多卡拓扑是否正确
- 驱动和固件是否匹配
- 显存、温度、功耗是否稳定
- 卡间互联是否正常
- Host CPU、PCIe、网络是否拖后腿

所以 GPU 测试必须站在整机视角做。

## 2. 2026年厂商与主流产品信息对比表

| 厂商 | 2026主流产品方向 | 典型亮点 | 典型应用 | 重点测试关注点 |
|---|---|---|---|---|
| NVIDIA | Blackwell B200 / DGX B200 生态 | 大显存、高带宽、NVLink 强 | AI 训练/推理 | 驱动、NVLink、热功耗、拓扑 |
| AMD | Instinct MI300/MI350 方向 | 大显存与 HPC/AI 并重 | HPC、AI | ROCm、拓扑、长稳 |
| Intel | 数据中心 GPU 方向 | 异构加速生态 | 推理/HPC | 驱动、兼容性、调度 |

## 3. 基础原理讲解

### 3.1 GPU 测试到底在测什么

1. 卡是否全部识别
2. 显存是否健康
3. 互联是否正常
4. 功耗温度是否在边界内
5. 长时间负载是否降频或掉卡

### 3.2 GPU 测试为什么不能只看 `nvidia-smi`

因为 `nvidia-smi` 只能说明一部分问题。  
你还要看：

- `lspci`
- CPU/NUMA
- PCIe
- 网络
- 存储

## 4. 详细测试用例

### 用例 1：GPU 枚举与健康状态检查

```bash
nvidia-smi
nvidia-smi -q
nvidia-smi topo -m
lspci | egrep -i "vga|3d"
```

| 字段 | 含义 | 正常范围 | 异常处理 |
|---|---|---|---|
| `GPU UUID` | 卡唯一标识 | 每卡唯一 | 缺失：设备异常 |
| `Temperature` | 温度 | 不应接近极限 | 高温：查散热 |
| `Power Draw` | 当前功耗 | 随负载提升 | 过低：可能未跑满 |
| `FB Memory Usage` | 显存使用量 | 随业务变化 | 异常：查任务分配 |

### 用例 2：基础环境与样例检查

```bash
cuda-samples/bin/x86_64/linux/release/deviceQuery
cuda-samples/bin/x86_64/linux/release/bandwidthTest
```

### 用例 3：多卡拓扑与互联检查

```bash
nvidia-smi topo -m
```

### 用例 4：长稳运行与热功耗观察

```bash
watch -n 5 nvidia-smi
```

## 5. 结果分析与问题诊断方法

先看漏卡，再看拓扑，再看驱动，再看热功耗，再看长稳是否掉频。

## 6. 最佳实践与注意事项

1. GPU 测试必须和 CPU、PCIe、网络一起看。
2. 训练和推理要分开建立基线。
3. 多卡平台优先检查拓扑和互联矩阵。

## 7. 进阶内容（高阶测试技巧、自动化思路、多厂商混配测试等）

建议建立：

- 单卡基线
- 多卡基线
- 卡间通信基线
- 端到端训练基线

