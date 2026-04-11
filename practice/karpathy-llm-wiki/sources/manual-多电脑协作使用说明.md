# 多电脑协作使用说明

## 适用场景

当你需要在不同电脑上继续维护 `Server-SIT-Mastery` 项目时，统一使用 GitHub 仓库同步。

当前远程仓库：

- [Servre_SIT_Mastery](https://github.com/wenchaowang041-hub/Servre_SIT_Mastery)

## 第一台新电脑如何开始

### 1. 安装基础环境

至少保证以下工具可用：

- `git`
- `powershell`
- `python`（如果后续要跑脚本）

### 2. 克隆项目

```bash
git clone https://github.com/wenchaowang041-hub/Servre_SIT_Mastery.git
cd Servre_SIT_Mastery
```

### 3. 检查远程是否正常

```bash
git remote -v
git status
```

正常情况下应看到：

- 远程为 `origin`
- 当前分支为 `main`

## 日常同步流程

### 场景一：你在这台电脑开始工作前

先拉最新代码：

```bash
git pull
```

### 场景二：你在这台电脑工作完成后

提交并推送：

```bash
git add .
git commit -m "更新说明"
git push
```

## 推荐提交习惯

建议按内容提交，不要所有修改都混在一个提交里。

推荐提交信息示例：

```bash
git commit -m "更新 Day13 训练笔记"
git commit -m "补充 NPU 日志分析案例"
git commit -m "新增 博客草稿：NUMA 与 PCIe 排查"
git commit -m "完善 第五章 网络测试手册"
```

## 多电脑切换时的建议规则

### 规则 1：一台电脑改完，先推送，再换另一台

不要在两台电脑上同时修改同一批文件后再合并，这样最容易冲突。

### 规则 2：开始工作前先 `git pull`

不管你记不记得上次有没有改，先拉一次最新版本。

### 规则 3：每天至少做一次提交

这样即使当天内容没完全写完，也不会丢记录。

### 规则 4：真实日志和手册分开管理

建议继续保持当前结构：

- `docs/manual/`：主知识库
- `daily-work-学习总结/logs-每天工作日志/`：真实工作日志
- 博客草稿：可放在后续新增目录中统一管理

## 常见问题

### 1. 为什么空文件夹在另一台电脑上看不到

因为 Git 默认不跟踪空目录。

解决方式：

- 在空目录中放一个 `.gitkeep`

### 2. 为什么 `git pull` 提示有冲突

说明两台电脑改了同一文件，且 Git 不能自动合并。

处理原则：

1. 先看冲突文件
2. 保留正确内容
3. 再重新提交

### 3. 为什么另一台电脑 `git push` 失败

常见原因：

- 没先 `git pull`
- Git 没配置好
- 网络或认证有问题

先检查：

```bash
git status
git remote -v
git pull
```

## 推荐工作方式

最推荐的多电脑节奏：

1. 主电脑负责白天工作日志整理
2. 另一台电脑负责晚上复盘、手册补充、博客输出
3. 两边都通过 GitHub 保持同步

## 一句话原则

开始前先 `pull`，结束后再 `commit + push`。
