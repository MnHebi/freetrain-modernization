[CmdletBinding()]
param(
    [ValidateSet('Check', 'Write')]
    [string]$Action = 'Check',
    [string]$PackageRoot,
    [string]$VectorRoot,
    [string]$BuildRoot
)

$ErrorActionPreference = 'Stop'
# Defaults are resolved here: Windows PowerShell 5.1 leaves $PSScriptRoot empty in
# param-block defaults when the script is started with powershell.exe -File.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $PackageRoot) { $PackageRoot = Join-Path $here '..\..\.artifacts\legacy-build\current\package\Debug' }
if (-not $VectorRoot) { $VectorRoot = Join-Path $here '..\..\fixtures\native-vectors' }
if (-not $BuildRoot) { $BuildRoot = Join-Path $here '..\..\.artifacts\native-vectors' }
$PackageRoot = (Resolve-Path $PackageRoot).Path
$dll = Join-Path $PackageRoot 'DirectDraw.AlphaBlend.dll'
$expectedHash = 'B8153302A76F3768528453D18C9025A5017B0B5EA2350F9B3F57A8A2B37F165D'
if ((Get-FileHash -Algorithm SHA256 $dll).Hash -ne $expectedHash) { throw "Unexpected DirectDraw.AlphaBlend.dll hash." }

New-Item -ItemType Directory -Force $BuildRoot | Out-Null
$exe = Join-Path $BuildRoot 'NativeVectorProbe.exe'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
& $csc /nologo /platform:x86 /target:exe "/out:$exe" `
    "/reference:$(Join-Path $PackageRoot 'Interop.DxVBLib.dll')" `
    (Join-Path $here 'NativeVectorProbe.cs')
if ($LASTEXITCODE -ne 0) { throw 'Probe compilation failed.' }
Copy-Item (Join-Path $PackageRoot 'Interop.DxVBLib.dll') $BuildRoot -Force

# One process per pixel mode: the DLL caches the display mode on first use.
$failed = $false
foreach ($mode in '555', '565', '24', '32') {
    & $exe $dll $mode $Action.ToLowerInvariant() $VectorRoot
    if ($LASTEXITCODE -ne 0) { $failed = $true }
}
if ($failed) { throw "Native vector $Action failed." }
