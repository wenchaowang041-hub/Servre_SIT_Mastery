$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$manualRoot = Join-Path $repoRoot "docs\manual"
$bmcCaseRoot = Join-Path $repoRoot "docs\bmc-cases"
$dailyRoot = Get-ChildItem -LiteralPath $repoRoot -Directory |
    Where-Object { $_.Name -like "daily-work-*" } |
    Select-Object -First 1 -ExpandProperty FullName
$sourceRoot = Join-Path $PSScriptRoot "sources"

if (-not $dailyRoot) {
    throw "daily-work directory not found"
}

if (-not (Test-Path $sourceRoot)) {
    New-Item -ItemType Directory -Force -Path $sourceRoot | Out-Null
}

Get-ChildItem -LiteralPath $sourceRoot -File |
    Where-Object {
        $_.Name -like "manual-*" -or
        $_.Name -like "day-*" -or
        $_.Name -like "case-*" -or
        $_.Name -like "bmc-case-*"
    } |
    Remove-Item -Force

function Copy-WithPrefix {
    param(
        [string]$Prefix,
        [string[]]$Files
    )

    foreach ($file in $Files) {
        $name = Split-Path $file -Leaf
        $target = Join-Path $sourceRoot ("{0}-{1}" -f $Prefix, $name)
        Copy-Item -LiteralPath $file -Destination $target -Force
    }
}

$manualFiles = Get-ChildItem -LiteralPath $manualRoot -File -Filter *.md |
    Where-Object { $_.Name -ne "README.md" } |
    Select-Object -ExpandProperty FullName

$dayFiles = Get-ChildItem -LiteralPath $dailyRoot -File -Filter *.md |
    Where-Object {
        $_.BaseName -match '^Day\d+'
    } |
    Select-Object -ExpandProperty FullName

$caseFiles = Get-ChildItem -LiteralPath $dailyRoot -File -Filter *.md |
    Where-Object { $_.BaseName.StartsWith("案例-") } |
    Select-Object -ExpandProperty FullName

$bmcCaseFiles = @()
if (Test-Path $bmcCaseRoot) {
    $bmcCaseFiles = Get-ChildItem -LiteralPath $bmcCaseRoot -File -Filter *.md |
        Where-Object { $_.Name -ne "README.md" } |
        Select-Object -ExpandProperty FullName
}

Copy-WithPrefix -Prefix "manual" -Files $manualFiles
Copy-WithPrefix -Prefix "day" -Files $dayFiles
Copy-WithPrefix -Prefix "case" -Files $caseFiles
Copy-WithPrefix -Prefix "bmc-case" -Files $bmcCaseFiles

Write-Host "Synced to sources/" -ForegroundColor Green
Write-Host ("manual: {0}" -f $manualFiles.Count)
Write-Host ("day: {0}" -f $dayFiles.Count)
Write-Host ("case: {0}" -f $caseFiles.Count)
Write-Host ("bmc-case: {0}" -f $bmcCaseFiles.Count)
