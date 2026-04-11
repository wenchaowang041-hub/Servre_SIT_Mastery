# Day19：PCIe自动检测脚本

## 对齐计划表

- 阶段：Phase0-基础架构
- 周次：W3
- 模块：Python
- 主题：PCIe自动检测脚本

## 今天要解决什么

前面 Day4 你已经建立了 PCIe 的基础认知：

- 设备是怎么挂在总线上的
- `lspci` 能看到什么
- 为什么服务器里的 NVMe、NIC、NPU 都离不开 PCIe

Day19 不再停留在“人工看输出”，而是开始把这些检查动作自动化，做出第一版可复用脚本 `check_pcie.py`。

## 今日目标

- 学会用 Python 调用 `lspci`
- 自动统计 NVMe、NIC、NPU 的数量
- 根据预期阈值输出正常/异常提示
- 把“人工肉眼检查”变成“机器一次性巡检”

## 先记住一句话

```text
Day19 的核心不是写多复杂的 Python，而是把 PCIe 设备清点动作标准化、可重复化。
```

## 一、为什么 Day19 要做脚本

如果你每次都手工执行：

```bash
lspci
```

再从几十上百行输出里找：

- 有几块 NVMe
- 有几张网卡
- 有几张 NPU
- 有没有设备没识别出来

那这种方式有几个问题：

- 容易漏看
- 不方便批量机台复用
- 不方便做“预期值”比对
- 不方便形成标准化检查流程

所以 Day19 的目标，是把“看 PCIe”升级成“检 PCIe”。

## 二、今天脚本要完成的最小能力

按照计划表，`check_pcie.py v1` 最少应具备下面这些能力：

### 1. 拉取 PCIe 设备列表

核心命令：

```bash
lspci
```

脚本要能调用这个命令，并拿到完整输出。

### 2. 按类型做设备统计

第一版先统计三类最关键设备：

- NVMe
- NIC
- NPU

这三类设备刚好对应服务器里最常见的高速数据路径：

```text
Storage -> NVMe
Network -> NIC
AI/加速 -> NPU
```

### 3. 支持阈值检查

也就是把“识别出来多少”与“理论上应该有多少”做对比。

例如一台目标机器预期：

- NVMe = 2
- NIC = 4
- NPU = 8

如果实际数量不一致，脚本就要给出告警。

### 4. 输出可读结果

不是只打印一个数字，而是要至少做到：

- 每类设备数量
- 对应设备条目
- 是否满足预期
- 最终结论：PASS / WARN

## 三、今天会用到的 Python 方法

Day19 不要求你写复杂框架，第一版只要掌握这些就够了：

### 1. `subprocess.run`

用来执行系统命令。

典型写法：

```python
subprocess.run(["lspci"], capture_output=True, text=True, check=True)
```

### 2. 字符串匹配

通过关键字判断设备类型，例如：

- `Ethernet`
- `Network`
- `Non-Volatile memory controller`
- `NPU`
- `Accelerator`

### 3. 基础列表处理

把 `lspci` 输出按行拆开，再一行一行过滤、归类、计数。

## 四、建议你今天先怎么人工观察一次

写脚本前，先手工看一遍输出，建立直觉。

```bash
lspci
lspci | grep -i ethernet
lspci | grep -i 'non-volatile'
lspci | grep -Ei 'npu|accelerator|processing'
```

你要先确认三件事：

1. 你机器上的 NVMe 在 `lspci` 里是什么描述
2. 你机器上的 NIC 在 `lspci` 里是什么描述
3. 你机器上的 NPU 在 `lspci` 里是什么描述

因为不同平台、不同驱动、不同卡型，关键字可能会有差异。

## 五、脚本设计思路

第一版建议按下面这条链路写：

```text
执行 lspci
-> 读取每一行
-> 识别设备类型
-> 分类存入列表
-> 统计数量
-> 和预期值比较
-> 打印结论
```

这已经足够构成一个合格的 `v1`。

## 六、推荐输出格式

脚本运行后，建议输出类似下面这种结构：

```text
[INFO] PCIe device scan start
[INFO] NVMe count: 2
[INFO] NIC count: 4
[INFO] NPU count: 8
[PASS] NVMe count matched expected value 2
[PASS] NIC count matched expected value 4
[PASS] NPU count matched expected value 8
[SUMMARY] overall status: PASS
```

如果设备缺失，就改成：

```text
[WARN] NPU count mismatch: expected 8, got 7
```

## 七、今天最容易犯的错

### 错误1：只会 `print(lspci_output)`，不会做分类

这不叫检测脚本，这只是把命令又打印了一遍。

### 错误2：关键字写得过死

例如只写一种网卡关键字，结果换一台机型就识别不到。

所以第一版就要留多个匹配词。

### 错误3：只统计，不校验

统计只是第一步，真正有工程价值的是“与预期做比对”。

### 错误4：输出没有结论

你必须让脚本最后能回答一句话：

```text
这台机器 PCIe 设备识别是否正常？
```

## 八、今天的硬性产出

你今天至少要完成：

- 1 个脚本：`check_pcie.py`
- 1 份结果截图或输出记录
- 3 条当天结论

建议当天结论往这个方向写：

- `lspci` 可以作为 PCIe 设备总入口
- NVMe/NIC/NPU 可以先通过关键字做基础识别
- 自动化比人工逐行清点更适合 SIT 日常巡检

## 九、和前后内容的关系

Day19 不是孤立的，它正好承上启下：

- 承接 Day4：把 PCIe 基础知识落到脚本
- 承接 Day18：设备与 NUMA 的关系之后，也可以继续扩展到 PCIe 自动检查
- 服务 Day20：总复盘时，你就不只是会看结构，还能拿出自动化工具

## 十、今天建议你顺手做的扩展

如果 `v1` 跑通了，可以继续加两个小能力：

- 打印每个设备的 PCI BDF 地址
- 为每类设备加上 `expected_*` 命令行参数

这样脚本会更像真实工程工具，而不是练习题。

## 十一、面试式自测题

### 题1

为什么服务器整机检查里，PCIe 设备清点适合优先做自动化？

标准回答方向：

- 因为设备数量多、输出长、容易漏看，而且需要和预期配置做快速比对

### 题2

`check_pcie.py v1` 最少应该包含哪些能力？

标准回答方向：

- 拉取 `lspci`
- 分类识别 NVMe/NIC/NPU
- 数量统计
- 预期值校验
- 输出 PASS/WARN

### 题3

为什么 Day19 里统计 NVMe/NIC/NPU 这三类设备最重要？

标准回答方向：

- 因为它们分别对应存储、网络、AI 加速路径，是服务器整机结构里最关键的高速 PCIe 设备

## 十二、今天的收尾结论

- Day19 的重点不是高级 Python 语法，而是把 PCIe 巡检动作做成脚本
- 第一版只要做到“拉取、分类、计数、校验、输出结论”，就已经有工程价值
- 后续完全可以在这份脚本上继续叠加 NUMA、链路速率、设备健康状态等能力

## 对应脚本

- [check_pcie.py](/C:/Users/王文超/Desktop/Servre_SIT_Mastery/practice/scripts-练手脚本/check_pcie.py)
