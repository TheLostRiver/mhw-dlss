[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('DLAA', 'FSR22')][string]$Mode,
    [string]$GameRoot = 'D:\Software\Steam\steamapps\common\Monster Hunter World'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ConfigFile.ps1')
$GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path
$optiPath = Join-Path $GameRoot 'OptiScaler.ini'
$graphicsPath = Join-Path $GameRoot 'graphics_option.ini'
$mhwssPath = Join-Path $GameRoot 'MHWSS\MHWSS_config.toml'
foreach ($path in @($optiPath, $graphicsPath, $mhwssPath, (Join-Path $GameRoot 'MonsterHunterWorld.exe'), (Join-Path $GameRoot 'MHWSS.dll'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $path" }
}
$running = @(Get-Process -Name MonsterHunterWorld -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq (Join-Path $GameRoot 'MonsterHunterWorld.exe') })
if ($running.Count) { throw 'Exit the game normally before changing the antialiasing backend.' }
if (-not $PSCmdlet.ShouldProcess($GameRoot, "Select $Mode antialiasing with DLSSG frame-generation output")) { return }

$backupRoot = Join-Path $GameRoot ('MHW-Display-Backups\AA-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path (Join-Path $backupRoot 'MHWSS') | Out-Null
Copy-Item -LiteralPath $optiPath, $graphicsPath -Destination $backupRoot
Copy-Item -LiteralPath $mhwssPath -Destination (Join-Path $backupRoot 'MHWSS')

$backend = if ($Mode -eq 'FSR22') { 'fsr22' } else { 'dlss' }
$opti = [IO.File]::ReadAllText($optiPath)
$opti = Set-SectionValue $opti 'Upscalers' 'Dx12Upscaler' $backend ' = '
$opti = Set-SectionValue $opti 'Inputs' 'EnableDlssInputs' 'true' ' = '
$opti = Set-SectionValue $opti 'FrameGen' 'FGInput' 'upscaler' ' = '
$opti = Set-SectionValue $opti 'FrameGen' 'FGOutput' 'dlssg' ' = '
# Preserve FG Enabled/InterpolationCount and both UI scales for a controlled comparison.
$mhwss = Set-SectionValue ([IO.File]::ReadAllText($mhwssPath)) 'Upscale' 'Upscaler' '"DLSS"' ' = '
$graphics = [IO.File]::ReadAllText($graphicsPath)
$graphics = Set-SectionValue $graphics 'GraphicsOption' 'DirectX12Enable' 'On'
$graphics = Set-SectionValue $graphics 'GraphicsOption' 'NVIDIA DLSS' 'Off'
$graphics = Set-SectionValue $graphics 'GraphicsOption' 'FidelityFX CAS' 'Off'
$graphics = Set-SectionValue $graphics 'GraphicsOption' 'Anti-Aliasing' 'TAA'
Write-GameConfig $optiPath $opti
Write-GameConfig $mhwssPath $mhwss
Write-GameConfig $graphicsPath $graphics
Write-Output "Antialiasing backend: $backend. Backup: $backupRoot"
Write-Output 'Keep MHWSS on DLSS for its inputs. MHWFG performs the selected antialiasing; FG output stays DLSSG.'
if ($Mode -eq 'FSR22') {
    Write-Output 'Experimental MHW profile: compare real FPS and visual stability with Active off, then on.'
}
