[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GameRoot = 'D:\Software\Steam\steamapps\common\Monster Hunter World',
    [ValidateSet('Uncapped', 'GameControlled')][string]$Presentation = 'Uncapped'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ConfigFile.ps1')
$GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path
if (-not (Test-Path -LiteralPath (Join-Path $GameRoot 'MonsterHunterWorld.exe'))) {
    throw 'Select the directory containing MonsterHunterWorld.exe.'
}
$runningGame = @(Get-Process -Name MonsterHunterWorld -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq (Join-Path $GameRoot 'MonsterHunterWorld.exe') })
if ($runningGame.Count) { throw 'Exit Monster Hunter: World normally before changing display configuration.' }
$graphicsPath = Join-Path $GameRoot 'graphics_option.ini'
$optiPath = Join-Path $GameRoot 'OptiScaler.ini'
foreach ($path in @($graphicsPath, $optiPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing configuration: $path" }
}
if (-not $PSCmdlet.ShouldProcess($GameRoot, "Repair DX12 configuration and use $Presentation presentation")) { return }

$backupRoot = Join-Path $GameRoot ('MHW-Display-Backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $backupRoot | Out-Null
Copy-Item -LiteralPath $graphicsPath, $optiPath -Destination $backupRoot
$graphics = [IO.File]::ReadAllText($graphicsPath)
$graphics = Set-SectionValue $graphics 'GraphicsOption' 'DirectX12Enable' 'On'
$graphics = Set-SectionValue $graphics 'GraphicsOption' 'NVIDIA DLSS' 'Off'
$graphics = Set-SectionValue $graphics 'GraphicsOption' 'FidelityFX CAS' 'Off'

$opti = [IO.File]::ReadAllText($optiPath)
if ($Presentation -eq 'Uncapped') {
    $graphics = Set-SectionValue $graphics 'GraphicsOption' 'FrameRate' 'No Limit'
    $graphics = Set-SectionValue $graphics 'GraphicsOption' 'V-Sync' 'Off'
    $opti = Set-SectionValue $opti 'Framerate' 'FramerateLimit' '0' ' = '
    $opti = Set-SectionValue $opti 'V-Sync' 'OverrideVsync' 'true' ' = '
    $opti = Set-SectionValue $opti 'V-Sync' 'ForceVsync' 'false' ' = '
} else {
    $opti = Set-SectionValue $opti 'V-Sync' 'OverrideVsync' 'auto' ' = '
    $opti = Set-SectionValue $opti 'V-Sync' 'ForceVsync' 'auto' ' = '
}
Write-GameConfig $graphicsPath $graphics
Write-GameConfig $optiPath $opti
Write-Output "Display configuration repaired. Backup: $backupRoot"
Write-Output 'Launch using MHWSSLauncher.exe. Compare real FPS with frame generation disabled.'
