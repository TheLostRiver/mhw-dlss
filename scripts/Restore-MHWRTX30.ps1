[CmdletBinding()]
param(
    [string]$GameRoot = 'D:\Software\Steam\steamapps\common\Monster Hunter World',
    [string]$RepositoryRoot = '',
    [string]$BackupRoot = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = Split-Path -Parent $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($BackupRoot)) { $BackupRoot = (Get-ChildItem -Directory (Join-Path $RepositoryRoot 'backups') | Sort-Object Name -Descending | Select-Object -First 1).FullName }
$manifestPath = Join-Path $BackupRoot 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "manifest.json not found: $manifestPath" }
$items = Get-Content -Raw $manifestPath | ConvertFrom-Json
foreach ($item in @($items)) {
    if (Test-Path -LiteralPath $item.Backup -PathType Leaf) {
        New-Item -ItemType Directory -Force -Path (Split-Path $item.Original) | Out-Null
        Copy-Item -LiteralPath $item.Backup -Destination $item.Original -Force
    }
}
foreach ($pair in @(
    @('nvngx_dlisp.dll.disabled','nvngx_dlisp.dll'),
    @('nativePC\plugins\OptiScaler.dll.disabled','nativePC\plugins\OptiScaler.dll'),
    @('nativePC\plugins\OptiScaler.ini.disabled','nativePC\plugins\OptiScaler.ini')
)) {
    $from = Join-Path $GameRoot $pair[0]; $to = Join-Path $GameRoot $pair[1]
    if ((Test-Path -LiteralPath $from) -and -not (Test-Path -LiteralPath $to)) { Move-Item -LiteralPath $from -Destination $to }
}
Write-Output "Restored preserved files from $BackupRoot. Remove newly added files manually after checking other mods."
