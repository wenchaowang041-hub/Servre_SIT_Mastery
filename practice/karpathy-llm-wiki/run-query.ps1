param(
    [Parameter(Mandatory = $true)]
    [string]$Question
)

$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

if (-not $env:ANTHROPIC_API_KEY -and (-not $env:LLMWIKI_OPENAI_BASE_URL -or -not $env:LLMWIKI_OPENAI_API_KEY)) {
    Write-Host "No valid API configuration found." -ForegroundColor Yellow
    Write-Host 'Anthropic: $env:ANTHROPIC_API_KEY="your-key"' -ForegroundColor Cyan
    Write-Host 'OpenAI-compatible: $env:LLMWIKI_OPENAI_BASE_URL="https://.../v1"' -ForegroundColor Cyan
    Write-Host 'OpenAI-compatible: $env:LLMWIKI_OPENAI_API_KEY="your-key"' -ForegroundColor Cyan
    Write-Host 'Optional: $env:LLMWIKI_MODEL="qwen-max"' -ForegroundColor Cyan
    exit 1
}

llmwiki.cmd query $Question
