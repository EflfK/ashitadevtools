param(
    [string]$AshitaRoot = "C:\Games\CatsEyeXI\catseyexi-client\Ashita",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$source = Join-Path $PSScriptRoot "ashitadevtools"
$target = Join-Path $AshitaRoot "addons\ashitadevtools"
$backupRoot = Join-Path $PSScriptRoot ".local-backups"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path $backupRoot $timestamp

if (-not (Test-Path -LiteralPath $source)) {
    throw "Source addon folder does not exist: $source"
}

if (-not (Test-Path -LiteralPath $AshitaRoot)) {
    throw "Ashita root does not exist: $AshitaRoot"
}

if (Test-Path -LiteralPath $target) {
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    Copy-Item -LiteralPath $target -Destination (Join-Path $backup "ashitadevtools") -Recurse -Force

    if (-not $Force) {
        Write-Host "Existing addon backed up to: $backup"
    }
}

if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
}

Copy-Item -LiteralPath $source -Destination $target -Recurse -Force

$rollback = Join-Path $backupRoot "rollback-$timestamp.ps1"
$rollbackContent = @"
`$ErrorActionPreference = "Stop"
`$target = "$target"
`$backupAddon = "$(Join-Path $backup "ashitadevtools")"

if (Test-Path -LiteralPath `$target) {
    Remove-Item -LiteralPath `$target -Recurse -Force
}

if (Test-Path -LiteralPath `$backupAddon) {
    Copy-Item -LiteralPath `$backupAddon -Destination `$target -Recurse -Force
    Write-Host "Restored previous ashitadevtools addon."
} else {
    Write-Host "Removed ashitadevtools addon. No previous addon backup was present."
}
"@

New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
Set-Content -LiteralPath $rollback -Value $rollbackContent -Encoding UTF8

Write-Host "Installed ashitadevtools addon to: $target"
Write-Host "Load in game with: /addon load ashitadevtools"
Write-Host "Local endpoint: http://127.0.0.1:19772/status"
Write-Host "Rollback script: $rollback"
