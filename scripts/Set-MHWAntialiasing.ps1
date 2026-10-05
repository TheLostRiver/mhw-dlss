[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('DLAA', 'FSR22', 'NativeNoAA')][string]$Mode,
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

$nativeDll = Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime\experimental\no-aa\d3d12.dll'
if ($Mode -eq 'NativeNoAA') {
    $expectedMhwss = '55D52CAF2E7BBA5220EC721149BC067679BF9391BBF55D62BED3EC9522CCD09A'
    if ((Get-FileHash -LiteralPath (Join-Path $GameRoot 'MHWSS.dll')).Hash -ne $expectedMhwss) {
        throw 'NativeNoAA requires the verified MHWSS 1.0.2 DLL. Unknown versions are not patched.'
    }
    if (-not (Test-Path -LiteralPath $nativeDll -PathType Leaf)) { throw "Missing NativeNoAA runtime: $nativeDll" }
}
if (-not $PSCmdlet.ShouldProcess($GameRoot, "Select $Mode antialiasing with DLSSG frame-generation output")) { return }

$backupRoot = Join-Path $GameRoot ('MHW-Display-Backups\AA-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path (Join-Path $backupRoot 'MHWSS') | Out-Null
Copy-Item -LiteralPath $optiPath, $graphicsPath -Destination $backupRoot
Copy-Item -LiteralPath $mhwssPath -Destination (Join-Path $backupRoot 'MHWSS')
if ($Mode -eq 'NativeNoAA') {
    $gameDll = Join-Path $GameRoot 'd3d12.dll'
    if (Test-Path -LiteralPath $gameDll) { Copy-Item -LiteralPath $gameDll -Destination $backupRoot }
    Copy-Item -LiteralPath $nativeDll -Destination $gameDll
}

$backend = switch ($Mode) { 'FSR22' { 'fsr22' }; 'NativeNoAA' { 'native' }; default { 'dlss' } }
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
if ($Mode -eq 'NativeNoAA') {
    Write-Output 'Experimental No AA runtime installed. Native copy and projection jitter suppression replace DLAA.'
    Write-Output 'Switch back using -Mode DLAA, or restore the backed-up DLL and configs for a full rollback.'
}
