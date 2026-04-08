# Day18：NUMA实战进阶，用 numactl、numastat 看懂内存分布

## 今天要学什么

今天不再停留在 NUMA 的概念层面，而是把它落到命令和判断方法上，重点看三件事：

- 机器的 NUMA 拓扑长什么样
- 进程的内存是不是分布在合理的节点上
- 设备、线程、内存有没有跑到同一条路径上

## 核心命令

```bash
lscpu | grep NUMA
numactl -H
numastat
numastat -p <pid>
cat /sys/bus/pci/devices/0000:35:00.0/numa_node
```

## 第五步：判断 fio 结果是否可信

这一步不是看数字大不大，而是看 `CPU、内存、设备` 有没有对齐到同一个 NUMA 节点。

判断顺序：

1. 先找 `fio` 的真实子进程 PID
2. 看这个 PID 跑在哪个 CPU 上
3. 看这个 PID 的内存主要落在哪个节点
4. 看目标 NVMe 设备属于哪个节点
5. 三者尽量一致，结果才更可信

常用命令：

```bash
ps -ef | grep '[f]io'
numastat -p <fio_pid>
ps -o pid,psr,comm -p <fio_pid>
cat /sys/class/block/nvme6n1/device/numa_node
readlink -f /sys/class/block/nvme6n1/device
cat /sys/bus/pci/devices/0000:ca:00.0/numa_node
```

怎么判断：

- `fio` 在 `node3`，内存在 `node3`，设备也在 `node3`，这是比较理想的状态
- `fio` 在 `node2`，设备在 `node1`，就是跨节点访问，延迟和抖动更容易变差
- 只看 `numastat -p 1` 没意义，那只是 `systemd`，不是你的测试进程

## 第六步：怎么用 NUMA 结果反推 fio 结果

NUMA 对齐只是前提，不代表结果一定漂亮。下一步要看的，是结果是否和场景匹配。

判断顺序：

1. 顺序场景先看 `BW`
2. 随机场景先看 `IOPS`
3. 混合场景要看 `read/write` 两边是否都正常
4. 再看平均时延和尾延迟是否抖动
5. 同样参数多跑几次，结果是否稳定

判断原则：

- 顺序读写主要看吞吐，不要拿随机 IOPS 去比
- 随机读写主要看 IOPS，不要只看带宽
- 混合读写不能只看一边，必须看 `R/W` 双向数据
- 平均值好看不等于体验好，`p99` 往往更能暴露问题

你这次的典型判断方式是：

- `nvme6n1` 在 `node3`
- `fio` 子进程在 `node3`
- 内存也主要在 `node3`
- 所以如果 `BW`、`IOPS`、`lat` 正常，就更有资格把这组数据当作可信基线

## 第七步：常见错法

下面这些是最容易记错的点：

- 把 `numastat -p 1` 当成测试进程分析
- 只看 `fio` 父进程，不看真正工作的子进程
- 只看设备在哪个节点，不看进程在哪个节点
- 只看平均值，不看尾延迟
- 混合读写场景只看 `read` 或只看 `write`
- 把 `slat` 当成业务时延写进汇总表

简单记法：

```text
先看进程在哪，再看内存在哪，再看设备在哪，最后再看结果稳不稳。
```

## 今天的结论

NUMA 不是只看“本地快、远程慢”这么简单，真正要看的，是资源和业务路径有没有对齐。

如果设备、CPU、内存不在同一个合理节点上，性能问题就会先从延迟、抖动和吞吐下降体现出来。

## 今天的输出

- 一张 NUMA 节点表
- 一张设备归属表
- 一段关于“为什么这个机器路径是合理/不合理”的总结

## 命令速记

```bash
# 看 NUMA 拓扑
lscpu | grep -i numa
numactl -H

# 看进程内存分布
ps -ef | grep '[f]io'
numastat -p <fio_pid>
ps -o pid,psr,comm -p <fio_pid>

# 看设备属于哪个节点
readlink -f /sys/class/block/nvme6n1/device
cat /sys/class/block/nvme6n1/device/numa_node
cat /sys/bus/pci/devices/0000:ca:00.0/numa_node
```
