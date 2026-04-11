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
- 放入一个示例 source
- 提供一键编译脚本

当前还缺：

- `ANTHROPIC_API_KEY`

没有 key 时，可以先阅读目录结构和示例 source；有 key 后再执行编译和查询。

## 目录说明

- `sources/` 原始资料
- `wiki/` 编译后的知识库页面
- `run-compile.ps1` 编译辅助脚本

## 最短使用方式

先在 PowerShell 里设置 key：

```powershell
$env:ANTHROPIC_API_KEY="你的key"
```

然后进入本目录执行：

```powershell
.\run-compile.ps1
```

编译完成后可以继续问：

```powershell
llmwiki.cmd query "What did Andrej Karpathy focus on?"
```

如果你以后想继续扩展资料，只要把新的 `.md` 或其他文本资料放进 `sources/`，再重新编译即可。
