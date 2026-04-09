# NVMe 热插拔测试简化操作手册

## 1. 适用范围

本手册适用于 Linux 系统下 NVMe SSD 暴力热插拔测试，采用带 IO 压力、慢插方式执行。

适用脚本目录：

`/root/nvme_hotplug_scripts`

对应脚本：

- `0-prepare-nvme.sh`
- `1-check-Begin.sh`
- `2-md5.sh`
- `3-check-md5.sh`
- `4-check-Finish.sh`
- `fio.sh`

## 2. 测试目的

验证 NVMe SSD 在热拔插过程中：

- 设备识别是否正常
- 业务 IO 是否异常
- 数据是否完整
- 系统日志、BMC/FDM 日志是否存在硬盘相关错误
- 硬盘外观及接插件是否损坏

## 3. 测试前准备

### 3.1 硬件准备

- 将 2 块被测 SSD 安装到服务器
- 其他槽位可插满引入盘
- 需要对 2 块被测盘进行交叉拔插

### 3.2 系统确认

进入 Linux 系统后，先确认盘符：

```bash
lsblk
nvme list
```

注意：

- 不要选择系统盘作为被测盘
- 你当前机器的系统盘是 `/dev/nvme5n1`
- 被测盘会被重新分区，盘内数据会被清空

### 3.3 修改脚本配置

编辑 `config.sh`，只修改 `DUTS`：

```bash
DUTS=(
  "/dev/nvme4n1"
  "/dev/nvme9n1"
)
```

要求：

- `DUTS` 中填写本轮测试的 2 块被测盘
- 绝对不要把 `/dev/nvme5n1` 放进去

## 4. 首次执行

首次针对某组被测盘执行时，先上传脚本目录并授权：

```bash
cd /root/nvme_hotplug_scripts
chmod +x *.sh
```

然后执行初始化：

```bash
./0-prepare-nvme.sh
```

说明：

- 此步骤每组被测盘只需执行一次
- 脚本会对 `DUTS` 中的盘重新分区
- 分区规则：
  - `p1` = 10GB
  - `p2` = 剩余全部容量
- `p1` 会格式化为 `ext4`

## 5. 现场最简执行顺序

每个槽位组合开始时，执行：

```bash
./1-check-Begin.sh
./2-md5.sh
./fio.sh
```

然后开始人工热插拔。

### 5.1 第 1 块盘

1. 拔出第 1 块被测盘
2. 等待 30 秒
3. 慢速插回
4. 插回 6 秒后执行：

```bash
./3-check-md5.sh
```

### 5.2 第 2 块盘

1. 拔出第 2 块被测盘
2. 等待 30 秒
3. 慢速插回
4. 插回 6 秒后执行：

```bash
./3-check-md5.sh
```

### 5.3 后续循环

之后按如下节奏交替执行：

1. 拔盘
2. 等 30 秒
3. 慢插回去
4. 等 6 秒
5. 执行 `./3-check-md5.sh`

重复至总次数达到 30 次。

### 5.4 本轮结束

30 次完成后执行：

```bash
./4-check-Finish.sh
```

## 6. 简化口令

现场可直接记这一版：

```bash
./0-prepare-nvme.sh        # 首次一次
./1-check-Begin.sh
./2-md5.sh
./fio.sh
./3-check-md5.sh          # 每次插回 6 秒后执行
./3-check-md5.sh
./3-check-md5.sh
...
./4-check-Finish.sh
```

## 7. 每一步含义

### 7.1 `./1-check-Begin.sh`

执行内容：

- 记录 `lsblk`
- 清空 `dmesg`
- 清空 BMC SEL
- 记录被测盘 `smart-log`
- 记录被测盘 BDF、slot、速率协商信息

### 7.2 `./2-md5.sh`

执行内容：

- 挂载被测盘 `p1`
- 生成 1GB 随机文件
- 计算 MD5
- 将文件拷入被测盘分区 1

### 7.3 `./fio.sh`

执行内容：

- 对被测盘 `p2` 启动顺序混合读写压力
- 读写比例为 `50/50`

### 7.4 `./3-check-md5.sh`

执行内容：

- 检查盘是否重新识别
- 挂载分区 1
- 对比回插前后的 MD5
- 记录 `smart-log`
- 记录 `dmesg`
- 记录 `BMC SEL`

### 7.5 `./4-check-Finish.sh`

执行内容：

- 收集本轮测试结束后的日志
- 收集硬盘健康信息
- 汇总错误日志

## 8. 判定标准

预期结果：

- 盘回插后能够正常识别
- `MD5` 校验一致
- `fio` 无任何报错
- `dmesg` 无硬盘相关严重错误
- `BMC/FDM` 无硬盘相关错误
- `smart-log` 无明显异常

异常判定示例：

- 盘回插后系统无法识别
- `MD5` 校验失败
- `fio` 出现 I/O error、device lost、timeout 等报错
- `dmesg` 中存在 NVMe reset failed、abort、timeout、I/O error 等
- `BMC/FDM` 存在硬盘掉线、故障告警

## 9. 换槽位后的执行方式

当 30 次完成后，如果要验证不同拓扑槽位：

1. 将 2 块被测盘换到新的槽位
2. 确认新的盘符、BDF、slot 信息
3. 如盘符或分区变化，重新执行：

```bash
./0-prepare-nvme.sh
```

4. 然后重复整套流程：

```bash
./1-check-Begin.sh
./2-md5.sh
./fio.sh
人工交替拔插 30 次，每次后执行 ./3-check-md5.sh
./4-check-Finish.sh
```

## 10. 测试完成后

测试结束后需确认：

- SSD 外观无明显损伤
- 接插件无明显划伤或损坏
- 收集 Smart、Dmesg、BMC/FDM 日志
- 无硬盘相关错误记录

日志目录默认在：

```bash
./logs
```

重点查看：

- `logs/dmesg-After-Reinsert.log`
- `logs/dmesg-Finish.log`
- `logs/bmc-After-Reinsert.log`
- `logs/*-Begin.log`
- `logs/*-check-md5.log`
- `logs/*-Finish.log`
- `logs/*-fio.log`

## 11. 注意事项

- 禁止把系统盘加入 `DUTS`
- `0-prepare-nvme.sh` 会清空被测盘数据
- 每次热插回盘后，必须等待 6 秒再执行校验
- 每次拔盘后，必须等待 30 秒再插回
- 建议现场同步记录每次拔插结果，标记 PASS 或 FAIL
