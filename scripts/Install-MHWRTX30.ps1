[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GameRoot = 'D:\Software\Steam\steamapps\common\Monster Hunter World',
    [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = Split-Path -Parent $PSScriptRoot }
$runtime = Join-Path $RepositoryRoot 'runtime'
$config = Join-Path $RepositoryRoot 'config'
$required = @(
    (Join-Path $GameRoot 'MonsterHunterWorld.exe'),
    (Join-Path $GameRoot 'MHWSSLauncher.exe'),
    (Join-Path $GameRoot 'MHWSS.dll'),
    (Join-Path $runtime 'd3d12.dll'),
    (Join-Path $runtime 'version.dll'),
    (Join-Path $config 'OptiScaler.ini'),
    (Join-Path $config 'dlssg_sm86.ini')
)
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missing.Count) { throw "Missing required files:`n$($missing -join "`n")" }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $RepositoryRoot "backups\$stamp"
New-Item -ItemType Directory -Force -Path "$backupRoot\root", "$backupRoot\nativePC\plugins", "$backupRoot\MHWSS" | Out-Null
$manifest = [System.Collections.Generic.List[object]]::new()
function Backup-File([string]$RelativePath) {
    $source = Join-Path $GameRoot $RelativePath
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        $destination = Join-Path $backupRoot $RelativePath
        New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $manifest.Add([pscustomobject]@{ Original = $source; Backup = $destination; Kind = 'file' })
    }
}
foreach ($name in @('d3d12.dll','version.dll','winmm.dll','OptiScaler.ini','dlssg_sm86.ini','MHWFG.cmd','nvngx_dlisp.dll')) { Backup-File $name }
foreach ($name in @('OptiScaler.dll','OptiScaler.ini')) { Backup-File "nativePC\plugins\$name" }
Backup-File 'MHWSS\MHWSS_config.toml'
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backupRoot 'manifest.json') -Encoding utf8

$dlisp = Join-Path $GameRoot 'nvngx_dlisp.dll'
if (Test-Path -LiteralPath $dlisp) { Move-Item -LiteralPath $dlisp -Destination (Join-Path $GameRoot 'nvngx_dlisp.dll.disabled') -Force }
foreach ($name in @('OptiScaler.dll','OptiScaler.ini')) {
    $old = Join-Path $GameRoot "nativePC\plugins\$name"
    if (Test-Path -LiteralPath $old) { Move-Item -LiteralPath $old -Destination (Join-Path $GameRoot "nativePC\plugins\$name.disabled") -Force }
}

Copy-Item -LiteralPath (Join-Path $runtime 'd3d12.dll') -Destination (Join-Path $GameRoot 'd3d12.dll') -Force
Copy-Item -LiteralPath (Join-Path $runtime 'version.dll') -Destination (Join-Path $GameRoot 'version.dll') -Force
Copy-Item -LiteralPath (Join-Path $config 'OptiScaler.ini') -Destination (Join-Path $GameRoot 'OptiScaler.ini') -Force
Copy-Item -LiteralPath (Join-Path $config 'dlssg_sm86.ini') -Destination (Join-Path $GameRoot 'dlssg_sm86.ini') -Force
New-Item -ItemType Directory -Force -Path (Join-Path $GameRoot 'OptiScaler\streamline') | Out-Null
Copy-Item -LiteralPath (Join-Path $runtime 'OptiScaler\nvngx_dlss.dll') -Destination (Join-Path $GameRoot 'OptiScaler\nvngx_dlss.dll') -Force
Copy-Item -Path (Join-Path $runtime 'OptiScaler\streamline\*') -Destination (Join-Path $GameRoot 'OptiScaler\streamline') -Force

$mhwssConfig = Join-Path $GameRoot 'MHWSS\MHWSS_config.toml'
if (Test-Path -LiteralPath $mhwssConfig) {
    $lines = Get-Content $mhwssConfig
    $section = ''
    $out = foreach ($line in $lines) {
        if ($line -match '^\s*\[(.+)\]') { $section = $Matches[1] }
        if ($section -eq 'Upscale' -and $line -match '^\s*Upscaler\s*=') { 'Upscaler = "DLSS"' } else { $line }
    }
    Set-Content -LiteralPath $mhwssConfig -Value $out -Encoding utf8
}
Write-Output "Installed MHW RTX30 package. Backup: $backupRoot"
Write-Output 'Launch with MHWSSLauncher.exe; do not add alternatives\winmm.dll beside version.dll.'
