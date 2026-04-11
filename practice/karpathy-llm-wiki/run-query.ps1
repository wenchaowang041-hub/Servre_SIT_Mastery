param(
    [Parameter(Mandatory = $true)]
    [string]$Question
)

$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

if (-not $env:ANTHROPIC_API_KEY) {
    Write-Host "ANTHROPIC_API_KEY is missing." -ForegroundColor Yellow
    Write-Host 'Run: $env:ANTHROPIC_API_KEY="your-key"' -ForegroundColor Cyan
    exit 1
}

llmwiki.cmd query $Question
