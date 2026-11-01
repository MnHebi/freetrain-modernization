[CmdletBinding()]
param(
    [ValidateSet('Check', 'Write')]
    [string]$Action = 'Check',
    [string]$PackageRoot,
    [string]$GoldenRoot,
    [string]$BuildRoot
)

$ErrorActionPreference = 'Stop'
# Defaults are resolved here: Windows PowerShell 5.1 leaves $PSScriptRoot empty in
# param-block defaults when the script is started with powershell.exe -File.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $PackageRoot) { $PackageRoot = Join-Path $here '..\..\.artifacts\legacy-build\current\package\Debug' }
if (-not $GoldenRoot) { $GoldenRoot = Join-Path $here '..\..\fixtures\code-derived' }
if (-not $BuildRoot) { $BuildRoot = Join-Path $here '..\..\.artifacts\code-derived' }
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
    (Join-Path $here 'CodeDerivedTests.cs') `
    (Join-Path $here 'IlTransplant.cs') `
    (Join-Path $here 'Tests.cs')
if ($LASTEXITCODE -ne 0) { throw 'Test compilation failed.' }

# Package assemblies are resolved from $PackageRoot at run time, not copied.
& $exe $PackageRoot $Action.ToLowerInvariant() $GoldenRoot | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Code-derived tests ($Action) failed." }
