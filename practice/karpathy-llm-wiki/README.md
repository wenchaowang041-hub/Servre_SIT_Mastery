# Karpathy LLM Wiki Demo

## 这是什么

这是一个基于 `llm-wiki-compiler` 的本地知识库示例。

它对应的是 Andrej Karpathy 最近提到的 `LLM Wiki` 思路：

- 原始资料先进入 `sources/`
- 再由 LLM 编译成结构化的 `wiki/`
- 后续查询不是每次都临时做 RAG，而是持续复用、持续增长

## 当前状态

这台机器已经完成：

- 全局安装 `llm-wiki-compiler`
- 创建本地工作目录
- 提供一键编译脚本
- 提供仓库内容同步脚本

当前还缺：

- Anthropic key，或者
- OpenAI-compatible key + base URL

没有 key 时，可以先同步资料并查看 `sources/` 结构；有 key 后再执行编译和查询。

## 目录说明

- `sources/` 原始资料
- `wiki/` 编译后的知识库页面
- `run-compile.ps1` 编译辅助脚本
- `sync-repo-sources.ps1` 把当前仓库里的手册、Day 学习稿、案例同步到 `sources/`

## 建议工作流

### 1. 先同步仓库资料

```powershell
powershell -ExecutionPolicy Bypass -File .\sync-repo-sources.ps1
```

同步后你会在 `sources/` 里看到：

- `manual-*.md`
- `day-*.md`
- `case-*.md`

### 2. 设置 key

#### 方案 A：Anthropic 原生

```powershell
$env:ANTHROPIC_API_KEY="your-key"
```

#### 方案 B：千问 / OpenAI-compatible

```powershell
$env:LLMWIKI_OPENAI_BASE_URL="https://dashscope.aliyuncs.com/compatible-mode/v1"
$env:LLMWIKI_OPENAI_API_KEY="your-qwen-key"
$env:LLMWIKI_MODEL="qwen-max"
```

也可以先参考：

```text
.env.example
```

现在这台机器上的 `llm-wiki-compiler` 已经补了本地兼容层，支持读取上面这组 `LLMWIKI_OPENAI_*` 变量。

### 3. 编译成 wiki

```powershell
powershell -ExecutionPolicy Bypass -File .\run-compile.ps1
```

### 4. 查询

```powershell
llmwiki.cmd query "How do I troubleshoot PCIe device recognition issues?"
```

或者：

```powershell
powershell -ExecutionPolicy Bypass -File .\run-query.ps1 "How do I troubleshoot PCIe device recognition issues?"
```

## 适合放进知识库的仓库内容

优先同步这些：

- `docs/manual/` 下的正式手册
- `daily-work-学习总结/` 下的 `Day*.md`
- `daily-work-学习总结/` 下的 `案例-*.md`

不建议直接同步这些：

- `README.md`
- 模板文件
- 原始日志
- 仍然很零散、还没整理成方法论的临时记录

## 后续扩展

如果你后面觉得好用，可以再继续扩展：

- 加入 `docs/bmc-cases/` 的正式案例
- 加入 `docs/100-day-plan/` 里的博客稿
- 按主题拆成多个知识库目录
