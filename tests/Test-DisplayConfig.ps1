$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'scripts\ConfigFile.ps1')
$fixtureRoot = Join-Path $repoRoot ('build\display-config-test-' + [guid]::NewGuid().ToString('N'))
$gameRoot = Join-Path $fixtureRoot 'game'
New-Item -ItemType Directory -Path $gameRoot | Out-Null

Add-Type -TypeDefinition @'
using System.Text;
using System.Runtime.InteropServices;
public static class MhwIniTest {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    public static extern uint GetPrivateProfileString(string section, string key,
        string fallback, StringBuilder value, uint size, string file);
}
'@
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Read-NativeIni([string]$Path, [string]$Section, [string]$Key) {
    $value = New-Object Text.StringBuilder 256
    [void][MhwIniTest]::GetPrivateProfileString($Section, $Key, 'MISSING', $value, 256, $Path)
    $value.ToString()
}
function Assert-NoBom([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)) "BOM in $Path"
}

$graphicsPath = Join-Path $gameRoot 'graphics_option.ini'
$optiPath = Join-Path $gameRoot 'OptiScaler.ini'
$graphics = "[GraphicsOption]`r`nDirectX12Enable=On`r`nResolution=2560x1440`r`nFrameRate=No Limit`r`nV-Sync=Off`r`n[Other]`r`nDirectX12Enable=Off`r`n"
[IO.File]::WriteAllText($graphicsPath, $graphics, [Text.UTF8Encoding]::new($true))
[IO.File]::WriteAllText((Join-Path $gameRoot 'MonsterHunterWorld.exe'), 'test fixture only')
[IO.File]::WriteAllText($optiPath, "[Menu]`nScale = 1.5`nFpsScale = 1.3`n[FrameGen]`nEnabled = false`n")
# Exercise the Windows INI reader, not a parser that silently ignores the BOM.
Assert-True ((Read-NativeIni $graphicsPath 'GraphicsOption' 'DirectX12Enable') -eq 'MISSING') 'Expected BOM regression was not reproduced'

$beforeHash = (Get-FileHash -LiteralPath $graphicsPath).Hash
& (Join-Path $repoRoot 'scripts\Repair-MHWDisplay.ps1') -GameRoot $gameRoot -WhatIf
Assert-True ((Get-FileHash -LiteralPath $graphicsPath).Hash -eq $beforeHash) 'WhatIf changed configuration'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $gameRoot 'MHW-Display-Backups'))) 'WhatIf wrote a backup'

& (Join-Path $repoRoot 'scripts\Repair-MHWDisplay.ps1') -GameRoot $gameRoot
Assert-NoBom $graphicsPath
Assert-NoBom $optiPath
Assert-True ((Read-NativeIni $graphicsPath 'GraphicsOption' 'DirectX12Enable') -eq 'On') 'DX12 not visible to Windows INI reader'
Assert-True ((Read-NativeIni $graphicsPath 'Other' 'DirectX12Enable') -eq 'Off') 'Unrelated section changed'
Assert-True ((Read-NativeIni $optiPath 'Menu' 'FpsScale') -eq '1.3') 'FPS scale changed'
Assert-True ((Read-NativeIni $optiPath 'Menu' 'Scale') -eq '1.5') 'Menu scale changed'
Assert-True ((Read-NativeIni $optiPath 'FrameGen' 'Enabled') -eq 'false') 'FG preference changed'
Assert-True ((Read-NativeIni $optiPath 'Framerate' 'FramerateLimit') -eq '0') 'FPS limit not reset'
Assert-True ((Read-NativeIni $optiPath 'V-Sync' 'OverrideVsync') -eq 'true') 'Tearing override missing'
Assert-True ((Read-NativeIni $optiPath 'V-Sync' 'ForceVsync') -eq 'false') 'VSync not disabled'
$afterHash = (Get-FileHash -LiteralPath $graphicsPath).Hash
& (Join-Path $repoRoot 'scripts\Repair-MHWDisplay.ps1') -GameRoot $gameRoot
Assert-True ((Get-FileHash -LiteralPath $graphicsPath).Hash -eq $afterHash) 'Repair is not idempotent'
& (Join-Path $repoRoot 'scripts\Repair-MHWDisplay.ps1') -GameRoot $gameRoot -Presentation GameControlled
Assert-True ((Read-NativeIni $optiPath 'V-Sync' 'ForceVsync') -eq 'auto') 'GameControlled did not release VSync override'

# Run the installer with harmless stub runtime files in an isolated fixture.
$packageRoot = Join-Path $fixtureRoot 'package'
New-Item -ItemType Directory -Path (Join-Path $packageRoot 'config'),(Join-Path $packageRoot 'runtime\OptiScaler\streamline') | Out-Null
Copy-Item -Path (Join-Path $repoRoot 'config\*') -Destination (Join-Path $packageRoot 'config')
foreach ($relative in @('d3d12.dll','version.dll','OptiScaler\nvngx_dlss.dll','OptiScaler\streamline\sl.common.dll')) {
    [IO.File]::WriteAllText((Join-Path (Join-Path $packageRoot 'runtime') $relative), 'test fixture only')
}
foreach ($name in @('MHWSS.dll','MHWSSLauncher.exe')) { [IO.File]::WriteAllText((Join-Path $gameRoot $name), 'test fixture only') }
& (Join-Path $repoRoot 'scripts\Install-MHWRTX30.ps1') -GameRoot $gameRoot -RepositoryRoot $packageRoot -WhatIf
Assert-True (-not (Test-Path -LiteralPath (Join-Path $gameRoot 'd3d12.dll'))) 'Installer WhatIf copied DLLs'
& (Join-Path $repoRoot 'scripts\Install-MHWRTX30.ps1') -GameRoot $gameRoot -RepositoryRoot $packageRoot
$mhwssPath = Join-Path $gameRoot 'MHWSS\MHWSS_config.toml'
Assert-NoBom $mhwssPath
Assert-NoBom $graphicsPath
Assert-True ([IO.File]::ReadAllText($mhwssPath).Contains('Upscaler = "DLSS"')) 'Installer did not create MHWSS config'
Assert-True ((Read-NativeIni $graphicsPath 'GraphicsOption' 'DirectX12Enable') -eq 'On') 'Installer broke DX12'
Assert-True ((Read-NativeIni $graphicsPath 'GraphicsOption' 'NVIDIA DLSS') -eq 'Off') 'Installer enabled legacy DLSS'
$toml = "KeyOverlay = `"End`"`n[Upscale]`nDLSSRenderPreset = 11`n[Other]`nUpscaler = `"None`"`n"
$updated = Set-SectionValue $toml 'Upscale' 'Upscaler' '"DLSS"' ' = '
Assert-True ($updated.Contains("DLSSRenderPreset = 11`nUpscaler = `"DLSS`"`n[Other]`nUpscaler = `"None`"")) 'Missing key insertion changed unrelated settings'
# AA selection changes the reconstruction backend, never the requested FG state/multiplier.
$opti = Set-SectionValue ([IO.File]::ReadAllText($optiPath)) 'FrameGen' 'Enabled' 'false' ' = '
Write-GameConfig $optiPath $opti
$beforeHash = (Get-FileHash -LiteralPath $optiPath).Hash
& (Join-Path $repoRoot 'scripts\Set-MHWAntialiasing.ps1') -GameRoot $gameRoot -Mode FSR22 -WhatIf
Assert-True ((Get-FileHash -LiteralPath $optiPath).Hash -eq $beforeHash) 'AA WhatIf changed configuration'
& (Join-Path $repoRoot 'scripts\Set-MHWAntialiasing.ps1') -GameRoot $gameRoot -Mode FSR22
Assert-True ((Read-NativeIni $optiPath 'Upscalers' 'Dx12Upscaler') -eq 'fsr22') 'FSR AA backend not selected'
Assert-True ((Read-NativeIni $optiPath 'FrameGen' 'FGOutput') -eq 'dlssg') 'AA script selected FSR frame generation'
Assert-True ((Read-NativeIni $optiPath 'FrameGen' 'Enabled') -eq 'false') 'AA script enabled FG during comparison'
Assert-True ((Read-NativeIni $optiPath 'DLSSG' 'InterpolationCount') -eq '3') 'AA script changed multiplier'
Assert-True ((Read-NativeIni $optiPath 'Menu' 'Scale') -eq '1.5') 'AA script changed menu scale'
Assert-True ((Read-NativeIni $optiPath 'Menu' 'FpsScale') -eq '1.3') 'AA script changed FPS scale'
Assert-True ((Read-NativeIni $graphicsPath 'GraphicsOption' 'Anti-Aliasing') -eq 'TAA') 'TAA hook input disabled'
Assert-NoBom $mhwssPath
Assert-NoBom $graphicsPath
Assert-NoBom $optiPath
& (Join-Path $repoRoot 'scripts\Set-MHWAntialiasing.ps1') -GameRoot $gameRoot -Mode DLAA
Assert-True ((Read-NativeIni $optiPath 'Upscalers' 'Dx12Upscaler') -eq 'dlss') 'Return to DLAA failed'
$beforeHash = (Get-FileHash -LiteralPath $optiPath).Hash
$rejected = $false
try {
    & (Join-Path $repoRoot 'scripts\Set-MHWAntialiasing.ps1') -GameRoot $gameRoot -Mode NativeNoAA
} catch {
    $rejected = $_.Exception.Message -like '*verified MHWSS 1.0.2*'
}
Assert-True $rejected 'Unknown MHWSS version was not rejected for the jitter hook'
Assert-True ((Get-FileHash -LiteralPath $optiPath).Hash -eq $beforeHash) 'Rejected NativeNoAA request changed configuration'
Write-Output "PASS: Windows INI regression, repair, WhatIf, installer, AA profiles, UI scales and FG preferences. PowerShell $($PSVersionTable.PSVersion). Fixtures: $fixtureRoot"
