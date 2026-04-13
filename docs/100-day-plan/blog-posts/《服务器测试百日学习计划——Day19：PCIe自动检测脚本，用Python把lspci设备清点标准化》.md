# 《服务器测试百日学习计划——Day19：PCIe自动检测脚本，用Python把lspci设备清点标准化》

大家好，我是 JACK，本篇是服务器测试百日学习计划 Day19。

前面 Day4 我们已经建立了 PCIe 的基础认知，知道服务器里的 NVMe、网卡、NPU 这些关键设备，本质上都是挂在 PCIe 总线上的。Day17、Day18 又把 NUMA 和设备路径这条线补起来了。到了 Day19，就不能再停留在“我会手工看 `lspci`”这个层次，而是要往前走一步，把人工检查动作做成脚本。

这一天的重点不是学多复杂的 Python，而是学会把 PCIe 设备清点动作标准化、可重复化，让它变成真正能落到整机 SIT 日常里的工具。

## 一、为什么 Day19 要开始写 PCIe 检测脚本

平时做机器初检或者项目 bring-up，很多人都会先敲一条命令：

```bash
lspci
```

然后开始肉眼看：

- 有几块 NVMe
- 有几张网卡
- 有几张 NPU
- 有没有关键设备没识别出来

这种方法不能说错，但它有几个明显问题：

- 设备一多，输出很长，容易漏看
- 不适合批量机台重复检查
- 不方便和 BOM、预期配置做快速比对
- 检查结果不够标准化，不利于沉淀成固定动作

所以 Day19 的意义很明确：

**把“看 PCIe”升级成“检 PCIe”。**

## 二、Day19 的核心目标到底是什么

这一天你要完成的，不是一个功能很花哨的脚本，而是一版能回答实际问题的 `check_pcie.py`。

它最少应该具备这 5 个能力：

1. 调用 `lspci`
2. 自动识别关键设备类型
3. 统计各类设备数量
4. 和预期值做比对
5. 输出明确结论

也就是说，它最后要能回答这句话：

```text
这台机器的 PCIe 关键设备识别是否正常？
```

这才是自动化脚本的价值。如果只是把 `lspci` 输出重新打印一遍，那不叫检测工具。

## 三、为什么第一版先抓 NVMe、NIC、NPU

我建议 Day19 的第一版，先只统计三类设备：

- NVMe
- NIC
- NPU

理由很简单，这三类刚好对应服务器最核心的三条高速路径：

```text
存储路径 -> NVMe
网络路径 -> NIC
AI 加速路径 -> NPU
```

你后面做整机 SIT，无论是上电初检、OS 安装后识别确认、还是专项测试前基线确认，这三类设备都是高频检查对象。

所以 Day19 的脚本，不是随便拿 PCIe 做练习，而是在做一件非常贴近现场的事情。

## 四、写脚本前，先手工看一遍 `lspci`

写脚本之前，我建议先手工观察一次。原因很实际，不同平台、不同卡型、不同驱动下，`lspci` 里的描述字段不完全一样，不能一上来就把关键字写死。

先看整机：

```bash
lspci
```

再分别过滤：

```bash
lspci | grep -i ethernet
lspci | grep -i "non-volatile"
lspci | grep -Ei "npu|accelerator|processing"
```

这一步你要先搞清楚三件事：

1. 你机器上的 NVMe 在 `lspci` 里是什么描述
2. 你机器上的 NIC 在 `lspci` 里是什么描述
3. 你机器上的 NPU 在 `lspci` 里是什么描述

只有先建立这个直觉，后面脚本里的关键字匹配才不会脱离实际。

## 五、Day19 会用到哪些 Python 能力

第一版脚本不复杂，但它很典型。核心只会用到这些基础能力：

### 1. `subprocess.run`

用来执行系统命令。

例如：

```python
result = subprocess.run(
    ["lspci"],
    capture_output=True,
    text=True,
    check=True,
)
```

这一步的作用，就是把 Linux 命令的输出接到 Python 里。

### 2. 字符串匹配

拿到 `lspci` 输出后，不需要一开始就做复杂解析。第一版完全可以先靠关键字识别设备类型。

例如：

- `non-volatile memory controller`
- `ethernet controller`
- `network controller`
- `infiniband controller`
- `accelerator`
- `co-processor`

### 3. 列表分类与计数

脚本把 `lspci` 的每一行拆开后，可以按设备类型分别放进不同列表，再统计数量。

这就是 Day19 最核心的处理链。

## 六、`check_pcie.py` 的设计思路

这类脚本的结构其实非常标准，建议你直接记住这条主线：

```text
执行 lspci
-> 读取每一行
-> 识别设备类型
-> 分类存入列表
-> 统计数量
-> 和预期值比较
-> 打印最终结论
```

这已经足够构成一个合格的 `v1`。

在我的仓库练习版里，这个脚本的关键字设计大致是这样的：

```python
KEYWORDS = {
    "nvme": [
        "non-volatile memory controller",
        "nvme",
    ],
    "nic": [
        "ethernet controller",
        "network controller",
        "infiniband controller",
    ],
    "npu": [
        "npu",
        "neural",
        "accelerator",
        "processing accelerators",
        "co-processor",
    ],
}
```

这种写法的价值在于：

- 结构清楚
- 容易扩展
- 比只写一个关键字更稳

后面如果你换平台、换设备、换卡型，只要补关键字，不用重写主逻辑。

## 七、为什么“统计”还不够，必须加“校验”

很多人第一次写这种脚本，会停在这一步：

```text
NVMe count: 2
NIC count: 4
NPU count: 8
```

这当然比肉眼数强，但还不够。

因为整机 SIT 不是在做“数数游戏”，而是在做“确认配置是否符合预期”。

所以更有工程价值的动作是：

- 统计实际值
- 引入预期值
- 自动比对
- 给出 `PASS / WARN`

例如一台机器预期应该有：

- NVMe = 2
- NIC = 4
- NPU = 8

如果脚本跑出来：

```text
[WARN] NPU count mismatch: expected 8, got 7
```

那这个工具就真正有用了。它能立刻告诉你：

这不是“我大概看着少了一张卡”，而是“识别结果已经和预期配置不一致”。

## 八、推荐的输出格式

一份合格的第一版输出，我建议至少长这样：

```text
[INFO] PCIe device scan start
[INFO] Total lspci lines: 77
[INFO] NVMe count: 2
[INFO] NIC count: 4
[INFO] NPU count: 8
[PASS] NVMe count matched expected value 2.
[PASS] NIC count matched expected value 4.
[PASS] NPU count matched expected value 8.
[SUMMARY] overall status: PASS
```

如果有设备缺失，则输出：

```text
[WARN] NPU count mismatch: expected 8, got 7.
[SUMMARY] overall status: WARN
```

这种输出格式有两个好处：

- 现场人员一眼能看懂
- 后续很容易接入更大一点的巡检流程

如果再往前走一步，最好把对应设备条目也打印出来，这样发现数量异常时，可以直接定位到具体哪类设备被识别到了、哪类没看到。

## 九、Day19 最容易犯的 4 个错误

### 1. 只会打印 `lspci` 原始输出

这不叫自动化，只是把命令包了一层。

### 2. 关键字写得太死

不同平台里，同一类设备的描述可能不完全一致。只写一种匹配词，脚本很快就会失效。

### 3. 只统计，不做阈值检查

真正有价值的不是“我识别出 7 张卡”，而是“我预期 8 张卡，现在只识别出 7 张”。

### 4. 没有最终结论

脚本最后必须能回答一句明确的话：

```text
当前 PCIe 关键设备识别是否正常？
```

如果最后没有 `PASS / WARN`，那它在现场上还是不够实用。

## 十、Day19 和前后内容怎么接起来

这一天不是孤立的，它刚好把前面的认知转成了工具。

- 承接 Day4：你已经知道什么是 PCIe，以及设备怎么挂在总线上
- 承接 Day17、Day18：你已经知道设备路径、NUMA 归属这些信息为什么重要
- 服务后续排障：你以后遇到“少盘、少卡、少加速器”的问题，可以先用脚本做第一轮清点

所以 Day19 其实是一个分水岭：

**从这里开始，你不只是会分析服务器结构，还开始会写属于自己的检测工具。**

## 十一、Day19 在真实 SIT 现场的意义

如果把这一天放回整机 SIT 现场，你会发现它非常实用。

例如新项目导入时，你拿到一台刚装好的机器，通常要先确认：

- NVMe 是否齐
- 网卡是否齐
- NPU 是否齐
- OS 是否把关键 PCIe 设备都识别出来

过去你是：

```text
手工看 lspci
```

现在你可以变成：

```text
跑 check_pcie.py
```

前者依赖经验和耐心，后者更容易形成固定流程，也更容易沉淀到仓库里变成团队资产。

## 十二、今天建议你顺手加的两个增强项

如果第一版跑通了，我建议继续补两点：

### 1. 打印 PCI BDF 地址

也就是把设备的 `Bus:Device.Function` 一起显示出来，方便后面继续查拓扑、查 NUMA、查驱动。

### 2. 加 `expected_*` 参数

例如：

```bash
python3 check_pcie.py --expected-nvme 2 --expected-nic 4 --expected-npu 8
```

这样脚本就不再只是练习题，而是开始有工程工具的味道了。

## 十三、今天这章你真正应该记住什么

Day19 不在于你会不会写一百行 Python，而在于你开始建立一个很重要的工程意识：

**重复性的检查动作，应该尽量工具化。**

对于整机 SIT 来说，PCIe 设备清点就是非常典型、也非常值得优先工具化的一类动作。

你今天只要把这件事吃透，后面很多脚本都会顺很多：

- 存储设备自动检测
- 网卡链路自动确认
- 驱动和固件版本收集
- NUMA 与 PCIe 设备归属校验

这些本质上都是同一种工程思路的延续。

## 十四、最后总结

把今天内容压成最短版，就是这 4 句话：

1. `lspci` 是 PCIe 设备识别的总入口。  
2. Day19 的重点不是 Python 语法，而是把 PCIe 清点动作标准化。  
3. 第一版脚本至少要做到拉取、分类、计数、校验、结论。  
4. 自动化的真正价值，不是打印输出，而是快速回答“识别是否正常”。  

如果你正在做服务器硬件整合测试，Day19 这种脚本化思路一定要早点建立。因为从这里开始，你就不再只是“会看机器”，而是开始“会做工具”。

