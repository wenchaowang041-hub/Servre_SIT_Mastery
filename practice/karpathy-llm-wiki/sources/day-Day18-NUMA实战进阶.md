# Day18：NUMA实战进阶

## 今天学什么

今天不再停留在 NUMA 概念层面，而是直接落到现场判断：

- 机器有几个 NUMA 节点
- 进程跑在哪个节点
- 内存主要落在哪个节点
- 设备属于哪个节点
- `fio` 结果是否具备解释价值

## 核心结论

NUMA 实战不是背“本地快、远端慢”这句话，而是要会判断：

```text
设备在哪个节点
线程在哪个节点
内存落在哪个节点
```

如果三者尽量对齐，结果通常更稳定；如果三者分裂，问题会先体现在延迟、抖动和尾延迟上。

## 今天用到的核心命令

```bash
lscpu | grep -i numa
numactl -H
ps -ef | grep '[f]io'
numastat -p <fio_pid>
ps -o pid,psr,comm -p <fio_pid>
readlink -f /sys/class/block/nvme6n1/device
cat /sys/class/block/nvme6n1/device/numa_node
cat /sys/bus/pci/devices/0000:ca:00.0/numa_node
lspci -s ca:00.0 -vv | grep -i numa
```

## 真实现场样例

这次现场机器的关键结论如下：

- 机器有 `4` 个 NUMA 节点
- 每个节点 `64` 个逻辑 CPU
- `node3` CPU 范围是 `192-255`
- `fio` 子进程 `58010` 的 `PSR=227`，说明线程当前跑在 `node3`
- `numastat -p 58010` 显示内存主要落在 `node3`
- `nvme6n1` 对应设备 `0000:ca:00.0`
- `cat /sys/class/block/nvme6n1/device/numa_node` 结果是 `3`
- `lspci -s ca:00.0 -vv` 也确认 `NUMA node: 3`

最终判断链路是：

```text
CPU = node3
内存 = node3
设备 = node3
```

所以这次 `fio` 的 NUMA 路径是合理的，这组结果更有资格作为基线去看。

## 第五步：怎么判断 fio 结果是否可信

NUMA 对齐只是前提，结果判断还要继续往下看。

顺序建议固定成下面这套：

1. 顺序场景先看 `BW`
2. 随机场景先看 `IOPS`
3. 混合场景必须看 `R/W` 双向
4. 平均值之外，还要盯 `p99`
5. 同样参数多跑几次，看是否稳定

如果 NUMA 已经对齐，但结果还是明显波动，就继续排查：

- 后台业务干扰
- IRQ 热点
- 队列深度设置
- 盘共享
- 固件或驱动状态

## 最容易犯的错

- 把 `numastat -p 1` 当成测试进程分析
- 只看 `fio` 父进程，不看真正工作的子进程
- 只看设备在哪，不看进程在哪
- 只看 CPU，不看内存
- 只看平均值，不看尾延迟
- 混合读写场景只看一边

## 一句话记忆

```text
先看进程在哪，再看内存在哪，再看设备在哪，最后再看结果稳不稳。
```

## 对应博客稿

- [《服务器测试百日学习计划——Day18：NUMA实战进阶，用 numactl、numastat 看懂内存分布》](/C:/Users/王文超/Desktop/Servre_SIT_Mastery/docs/100-day-plan/blog-posts/《服务器测试百日学习计划——Day18：NUMA实战进阶，用 numactl、numastat 看懂内存分布》.md)

## 后续可延伸

- 结合 NVMe 压测继续看 `BW / IOPS / p99`
- 结合网卡和 IRQ 看中断与 NUMA 的关系
- 结合 NPU / GPU 看设备归属与业务线程对齐
