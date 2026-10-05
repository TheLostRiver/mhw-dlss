[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [string]$OutputDirectory = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$revision = 'a0421ee5937eb2d803f67a89d6993fb13c670c04'
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repo ('build\no-aa-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$checkout = Join-Path $OutputDirectory 'source'
if (Test-Path -LiteralPath $checkout) { throw 'Choose a new output directory; an existing source checkout will not be overwritten.' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$msbuild = @(& $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe') | Select-Object -First 1
if (-not $msbuild) { throw 'Visual Studio C++ Build Tools / MSBuild not found.' }
& git -C $SourceRoot cat-file -e "${revision}^{commit}"
if ($LASTEXITCODE -ne 0) { throw "SourceRoot must contain MHW-DLSSFrameGen commit $revision" }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
& git -C $SourceRoot worktree add --detach $checkout $revision
if ($LASTEXITCODE -ne 0) { throw 'Could not create isolated source checkout.' }
& git -C $checkout apply --check (Join-Path $repo 'patches\native-no-aa.patch')
if ($LASTEXITCODE -ne 0) { throw 'Integration patch does not match the pinned source.' }
& git -C $checkout apply (Join-Path $repo 'patches\native-no-aa.patch')
if ($LASTEXITCODE -ne 0) { throw 'Integration patch failed.' }
$nativeSource = Join-Path $checkout 'OptiScaler\upscalers\native'
New-Item -ItemType Directory -Force -Path $nativeSource | Out-Null
Copy-Item -Path (Join-Path $repo 'src\native\*') -Destination $nativeSource
$bin = Join-Path $OutputDirectory 'bin'
$obj = Join-Path $OutputDirectory 'obj'
$log = Join-Path $OutputDirectory 'build.log'
# Build only: no upstream pre/post events, DLL deployment, or recursive cleanup.
& $msbuild (Join-Path $checkout 'OptiScaler.sln') /nologo /m:1 /t:Build /p:Configuration=Release /p:Platform=x64 /p:MHWFGProduction=true /p:PreBuildEventUseInBuild=false /p:PostBuildEventUseInBuild=false "/p:IntDir=$obj\" "/p:OutDir=$bin\" /verbosity:minimal > $log 2>&1
if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath $log -Tail 40; throw "Build failed. See $log" }
$dll = Join-Path $bin 'd3d12.dll'
Copy-Item -LiteralPath (Join-Path $bin 'OptiScaler.dll') -Destination $dll
Get-FileHash -LiteralPath $dll -Algorithm SHA256
Write-Output "Experimental runtime built: $dll"
