[CmdletBinding()]
param(
    [ValidateSet('Check', 'Write')]
    [string]$Action = 'Check',
    [string]$PackageRoot = (Join-Path $PSScriptRoot '..\..\.artifacts\legacy-build\current\package\Debug'),
    [string]$GoldenRoot = (Join-Path $PSScriptRoot '..\..\fixtures\code-derived'),
    [string]$BuildRoot = (Join-Path $PSScriptRoot '..\..\.artifacts\code-derived')
)

$ErrorActionPreference = 'Stop'
$PackageRoot = (Resolve-Path $PackageRoot).Path
$core = Join-Path $PackageRoot 'FreeTrain.Core.dll'
# The harness compares this hash with fixtures/code-derived/provenance.txt.
Write-Host "FreeTrain.Core.dll SHA-256 $((Get-FileHash -Algorithm SHA256 $core).Hash)"

New-Item -ItemType Directory -Force $BuildRoot | Out-Null
$exe = Join-Path $BuildRoot 'CodeDerivedTests.exe'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
$references = 'FreeTrain.Core.dll', 'DirectDraw.net.dll', 'Interop.DxVBLib.dll' |
    ForEach-Object { "/reference:$(Join-Path $PackageRoot $_)" }
& $csc /nologo /platform:x86 /target:exe /debug+ "/out:$exe" `
    /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /reference:System.Xml.dll `
    $references `
    (Join-Path $PSScriptRoot 'CodeDerivedTests.cs') `
    (Join-Path $PSScriptRoot 'IlTransplant.cs') `
    (Join-Path $PSScriptRoot 'Tests.cs')
if ($LASTEXITCODE -ne 0) { throw 'Test compilation failed.' }

# Package assemblies are resolved from $PackageRoot at run time, not copied.
& $exe $PackageRoot $Action.ToLowerInvariant() $GoldenRoot | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Code-derived tests ($Action) failed." }
