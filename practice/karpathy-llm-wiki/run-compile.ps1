$ErrorActionPreference = "Stop"

if (-not $env:ANTHROPIC_API_KEY) {
    Write-Host "ANTHROPIC_API_KEY 未设置，先执行：" -ForegroundColor Yellow
    Write-Host '$env:ANTHROPIC_API_KEY="你的key"' -ForegroundColor Cyan
    exit 1
}

Write-Host "开始编译 sources/ -> wiki/" -ForegroundColor Green
llmwiki.cmd compile

Write-Host "编译完成。可以继续执行：" -ForegroundColor Green
Write-Host 'llmwiki.cmd query "What did Andrej Karpathy focus on?"' -ForegroundColor Cyan
