[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $Dx8VbArchive,
    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Debug',
    [switch] $PrepareOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedDx8Hash = '19149F082F3CA68AA893ADAF0309E5E6C8EA8710C0FE2040F95E8DA5A329F846'
$expectedDx7Hash = 'D69CDC170AAC0AE611ECA3BEE84E7BE346A3BA1B3C79216E13E87C8EE6CD2084'
$expectedTlbImpHash = '955314E8012FA44AE493D14BEA4DAC144920EF062E5914B6BBCAF59A24E55186'
$expectedAlphaHash = 'B8153302A76F3768528453D18C9025A5017B0B5EA2350F9B3F57A8A2B37F165D'

$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($Dx8VbArchive)) {
    $Dx8VbArchive = Join-Path $root 'dx8vb.zip'
}
$Dx8VbArchive = (Resolve-Path -LiteralPath $Dx8VbArchive).Path

$source = Join-Path $root 'FreeTrain'
$artifactRoot = Join-Path $root '.artifacts/legacy-build'
$runRoot = Join-Path $artifactRoot 'current'
$inputRoot = Join-Path $runRoot 'inputs'
$interopRoot = Join-Path $runRoot 'interop'
$rawInteropRoot = Join-Path $runRoot 'interop-raw'
$logRoot = Join-Path $runRoot 'logs'
$packageRoot = Join-Path $runRoot ("package/{0}" -f $Configuration)

function Reset-ArtifactDirectory {
    param([Parameter(Mandatory)][string] $Path)

    $artifactFull = [IO.Path]::GetFullPath($artifactRoot).TrimEnd('\')
    $targetFull = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $targetFull.StartsWith($artifactFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to reset a directory outside the Phase 1 artifact root: $targetFull"
    }
    if (Test-Path -LiteralPath $targetFull) {
        Remove-Item -LiteralPath $targetFull -Recurse -Force
    }
    New-Item -ItemType Directory -Path $targetFull -Force | Out-Null
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Export-SingleDllFromZip {
    param(
        [Parameter(Mandatory)][string] $Archive,
        [Parameter(Mandatory)][string] $Destination
    )

    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::OpenRead($Archive)
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            $entries = @($zip.Entries)
            if ($entries.Count -ne 1 -or $entries[0].FullName -cne 'dx8vb.dll') {
                throw 'The external archive must contain exactly one root entry named dx8vb.dll.'
            }
            $entryStream = $entries[0].Open()
            try {
                $output = [IO.File]::Create($Destination)
                try {
                    $entryStream.CopyTo($output)
                } finally {
                    $output.Dispose()
                }
            } finally {
                $entryStream.Dispose()
            }
        } finally {
            $zip.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public sealed class LegacyTypeLibraryIdentity
{
    public string Name;
    public string Guid;
    public short Major;
    public short Minor;
    public int Lcid;
    public string SysKind;
    public int TypeCount;
}

public static class LegacyTypeLibraryInspector
{
    private enum REGKIND { DEFAULT = 0, REGISTER = 1, NONE = 2 }

    [DllImport("oleaut32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
    private static extern int LoadTypeLibEx(string file, REGKIND regkind, out ITypeLib typeLib);

    public static LegacyTypeLibraryIdentity Inspect(string file)
    {
        ITypeLib library;
        int hr = LoadTypeLibEx(file, REGKIND.NONE, out library);
        if (hr != 0 || library == null) Marshal.ThrowExceptionForHR(hr);

        IntPtr attributes = IntPtr.Zero;
        try
        {
            library.GetLibAttr(out attributes);
            TYPELIBATTR value = (TYPELIBATTR)Marshal.PtrToStructure(attributes, typeof(TYPELIBATTR));
            string name, documentation, helpFile;
            int helpContext;
            library.GetDocumentation(-1, out name, out documentation, out helpContext, out helpFile);
            return new LegacyTypeLibraryIdentity {
                Name = name,
                Guid = value.guid.ToString("D"),
                Major = value.wMajorVerNum,
                Minor = value.wMinorVerNum,
                Lcid = value.lcid,
                SysKind = value.syskind.ToString(),
                TypeCount = library.GetTypeInfoCount()
            };
        }
        finally
        {
            if (attributes != IntPtr.Zero) library.ReleaseTLibAttr(attributes);
            if (Marshal.IsComObject(library)) Marshal.ReleaseComObject(library);
        }
    }
}
'@

function Assert-TypeLibraryIdentity {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Guid,
        [int] $Major = 1,
        [int] $Minor = 0,
        [int] $Lcid = 0
    )

    $actual = [LegacyTypeLibraryInspector]::Inspect($Path)
    if ($actual.Name -cne $Name -or
        $actual.Guid -ine $Guid -or
        $actual.Major -ne $Major -or
        $actual.Minor -ne $Minor -or
        $actual.Lcid -ne $Lcid -or
        $actual.SysKind -cne 'SYS_WIN32') {
        throw "Unexpected type-library identity in $Path"
    }
    return $actual
}

function Find-ByteSequence {
    param(
        [Parameter(Mandatory)][byte[]] $Bytes,
        [Parameter(Mandatory)][byte[]] $Needle
    )

    $matches = [Collections.Generic.List[int]]::new()
    for ($offset = 0; $offset -le $Bytes.Length - $Needle.Length; $offset++) {
        $equal = $true
        for ($index = 0; $index -lt $Needle.Length; $index++) {
            if ($Bytes[$offset + $index] -ne $Needle[$index]) {
                $equal = $false
                break
            }
        }
        if ($equal) { $matches.Add($offset) }
    }
    return $matches.ToArray()
}

function Set-DeterministicInteropMetadata {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Descriptor
    )

    $bytes = [IO.File]::ReadAllBytes($Path)
    $assembly = [Reflection.Assembly]::Load($bytes)
    $oldMvidBytes = $assembly.ManifestModule.ModuleVersionId.ToByteArray()
    $locations = @(Find-ByteSequence -Bytes $bytes -Needle $oldMvidBytes)
    if ($locations.Count -ne 1) {
        throw "Expected exactly one MVID occurrence in $Path; found $($locations.Count)."
    }

    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    if ([Text.Encoding]::ASCII.GetString($bytes, $peOffset, 4) -cne "PE`0`0") {
        throw "Invalid PE signature in $Path"
    }
    [Array]::Clear($bytes, $peOffset + 8, 4)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $seed = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Descriptor))
    } finally {
        $sha.Dispose()
    }
    $deterministicMvidBytes = [byte[]]::new(16)
    [Array]::Copy($seed, $deterministicMvidBytes, 16)
    $deterministicMvidBytes[7] = [byte](($deterministicMvidBytes[7] -band 0x0f) -bor 0x50)
    $deterministicMvidBytes[8] = [byte](($deterministicMvidBytes[8] -band 0x3f) -bor 0x80)
    [Array]::Copy($deterministicMvidBytes, 0, $bytes, $locations[0], 16)
    [IO.File]::WriteAllBytes($Path, $bytes)

    $normalized = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($Path))
    $expectedMvid = [Guid]::new($deterministicMvidBytes)
    if ($normalized.ManifestModule.ModuleVersionId -ne $expectedMvid) {
        throw "Deterministic MVID validation failed for $Path"
    }
    return $expectedMvid
}

function New-DeterministicInterop {
    param(
        [Parameter(Mandatory)][string] $TypeLibrary,
        [Parameter(Mandatory)][string] $Namespace,
        [Parameter(Mandatory)][string] $AssemblyFile,
        [Parameter(Mandatory)][string] $RequiredType,
        [Parameter(Mandatory)][string] $TlbImp,
        [Parameter(Mandatory)][string] $TlbImpHash
    )

    $inputHash = Get-Sha256 $TypeLibrary
    $descriptor = "FreeTrain Phase 1 interop|$AssemblyFile|$Namespace|$inputHash|$TlbImpHash|/namespace:$Namespace /silent /nologo"
    $firstDirectory = Join-Path $rawInteropRoot ("{0}-first" -f $Namespace)
    $secondDirectory = Join-Path $rawInteropRoot ("{0}-second" -f $Namespace)
    New-Item -ItemType Directory -Path $firstDirectory, $secondDirectory -Force | Out-Null
    $first = Join-Path $firstDirectory $AssemblyFile
    $second = Join-Path $secondDirectory $AssemblyFile

    foreach ($target in @($first, $second)) {
        & $TlbImp $TypeLibrary "/out:$target" "/namespace:$Namespace" /silent /nologo
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "TlbImp failed for $TypeLibrary with exit code $LASTEXITCODE"
        }
        Set-DeterministicInteropMetadata -Path $target -Descriptor $descriptor | Out-Null
    }

    $firstHash = Get-Sha256 $first
    $secondHash = Get-Sha256 $second
    if ($firstHash -cne $secondHash) {
        throw "Normalized interop output is not reproducible for $AssemblyFile"
    }

    $destination = Join-Path $interopRoot $AssemblyFile
    Copy-Item -LiteralPath $first -Destination $destination -Force
    $assembly = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($destination))
    if ($null -eq $assembly.GetType($RequiredType, $false, $false)) {
        throw "$AssemblyFile does not expose required type $RequiredType"
    }

    return [pscustomobject]@{
        assembly = $AssemblyFile
        namespace = $Namespace
        input = $TypeLibrary
        inputSha256 = $inputHash
        output = $destination
        outputSha256 = $firstHash
        mvid = $assembly.ManifestModule.ModuleVersionId.ToString('D')
        assemblyIdentity = $assembly.FullName
        deterministicReplayMatched = $true
    }
}

function Copy-FilteredTree {
    param(
        [Parameter(Mandatory)][string] $From,
        [Parameter(Mandatory)][string] $To,
        [string[]] $Exclude = @()
    )

    $sourceFull = [IO.Path]::GetFullPath($From).TrimEnd('\')
    foreach ($file in Get-ChildItem -LiteralPath $sourceFull -File -Recurse) {
        $excluded = $false
        foreach ($pattern in $Exclude) {
            if ($file.FullName.IndexOf($pattern, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $excluded = $true
                break
            }
        }
        if ($excluded) { continue }

        $relative = $file.FullName.Substring($sourceFull.Length).TrimStart('\')
        $destination = Join-Path $To $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }
}

function Get-BuildErrorCategory {
    param([Parameter(Mandatory)][string] $Line)

    if ($Line -match '\berror CS\d+:') { return 'source/compiler incompatibility' }
    if ($Line -match '\berror MSB1025:') { return 'environmental' }
    if ($Line -match '\berror MSB(3245|3243|3105):') { return 'missing dependency' }
    if ($Line -match '\berror MSB(3073|3021|3027|3026):') { return 'project/configuration' }
    if ($Line -match '\berror (MSB4\d+|MSB3\d+):') { return 'environmental' }
    return 'project/configuration'
}

function Get-SolutionProjectBuildOrder {
    param([Parameter(Mandatory)][string] $Solution)

    $solutionDirectory = Split-Path -Parent $Solution
    $nodes = [Collections.Generic.List[object]]::new()
    foreach ($line in Get-Content -LiteralPath $Solution) {
        if ($line -match '^Project\("\{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC\}"\) = "([^"]+)", "([^"]+)",') {
            $fullPath = [IO.Path]::GetFullPath((Join-Path $solutionDirectory $matches[2]))
            $nodes.Add([pscustomobject]@{
                name = $matches[1]
                relativePath = $matches[2]
                fullPath = $fullPath
                dependencies = @()
            })
        }
    }

    $byPath = @{}
    foreach ($node in $nodes) { $byPath[$node.fullPath.ToLowerInvariant()] = $node }
    foreach ($node in $nodes) {
        [xml]$project = Get-Content -LiteralPath $node.fullPath -Raw
        $namespaces = [Xml.XmlNamespaceManager]::new($project.NameTable)
        $namespaces.AddNamespace('m', 'http://schemas.microsoft.com/developer/msbuild/2003')
        $dependencies = [Collections.Generic.List[string]]::new()
        foreach ($reference in $project.SelectNodes('//m:ProjectReference', $namespaces)) {
            $dependencyPath = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $node.fullPath) $reference.Include))
            $key = $dependencyPath.ToLowerInvariant()
            if ($byPath.ContainsKey($key)) { $dependencies.Add($key) }
        }
        $node.dependencies = $dependencies.ToArray()
    }

    $built = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $ordered = [Collections.Generic.List[object]]::new()
    while ($ordered.Count -lt $nodes.Count) {
        $progress = $false
        foreach ($node in $nodes) {
            if ($built.Contains($node.fullPath)) { continue }
            $ready = $true
            foreach ($dependency in $node.dependencies) {
                if (-not $built.Contains($dependency)) { $ready = $false; break }
            }
            if (-not $ready) { continue }
            $ordered.Add($node)
            $built.Add($node.fullPath) | Out-Null
            $progress = $true
        }
        if (-not $progress) {
            throw 'The VS2008 solution project-reference graph contains a cycle or unresolved dependency.'
        }
    }
    return $ordered.ToArray()
}

Reset-ArtifactDirectory $runRoot
New-Item -ItemType Directory -Path $inputRoot, $interopRoot, $rawInteropRoot, $logRoot -Force | Out-Null

$dx8 = Join-Path $inputRoot 'dx8vb.dll'
Export-SingleDllFromZip -Archive $Dx8VbArchive -Destination $dx8
$actualDx8Hash = Get-Sha256 $dx8
if ($actualDx8Hash -cne $expectedDx8Hash) {
    throw "The supplied dx8vb.dll hash is $actualDx8Hash; expected $expectedDx8Hash."
}

$dx7 = Join-Path $source 'extlib/dx7vb.dll'
if ((Get-Sha256 $dx7) -cne $expectedDx7Hash) {
    throw 'The preserved dx7vb.dll no longer matches the Phase 1 pinned hash.'
}
$quartz = 'C:\Windows\SysWOW64\quartz.dll'
if (-not (Test-Path -LiteralPath $quartz -PathType Leaf)) {
    throw 'The 32-bit Quartz type-library input is unavailable.'
}

$dx7Identity = Assert-TypeLibraryIdentity $dx7 'DxVBLib' 'e1211242-8e94-11d1-8808-00c04fc2c602'
$dx8Identity = Assert-TypeLibraryIdentity $dx8 'DxVBLibA' 'e1211242-8e94-11d1-8808-00c04fc2c603'
$quartzIdentity = Assert-TypeLibraryIdentity $quartz 'QuartzTypeLib' '56a868b0-0ad4-11ce-b03a-0020af0ba770'

$tlbImp = 'C:\Program Files\Microsoft SDKs\Windows\v6.0A\bin\TlbImp.exe'
if (-not (Test-Path -LiteralPath $tlbImp -PathType Leaf)) {
    throw 'The pinned Windows SDK v6.0A TlbImp.exe generation tool is unavailable.'
}
$actualTlbImpHash = Get-Sha256 $tlbImp
if ($actualTlbImpHash -cne $expectedTlbImpHash) {
    throw "TlbImp.exe does not match the pinned Phase 1 tool hash: $actualTlbImpHash"
}

$interopRecords = @(
    New-DeterministicInterop $dx7 'DxVBLib' 'Interop.DxVBLib.dll' 'DxVBLib.DirectX7Class' $tlbImp $actualTlbImpHash
    New-DeterministicInterop $dx8 'DxVBLibA' 'Interop.DxVBLibA.dll' 'DxVBLibA.DirectX8Class' $tlbImp $actualTlbImpHash
    New-DeterministicInterop $quartz 'QuartzTypeLib' 'Interop.QuartzTypeLib.dll' 'QuartzTypeLib.FilgraphManagerClass' $tlbImp $actualTlbImpHash
)

$alphaSource = Join-Path $source ("bin/{0}/DirectDraw.AlphaBlend.dll" -f $Configuration)
if (-not (Test-Path -LiteralPath $alphaSource -PathType Leaf) -or (Get-Sha256 $alphaSource) -cne $expectedAlphaHash) {
    throw "The verified $Configuration native alpha DLL is unavailable or has changed."
}

$preflightJson = & (Join-Path $PSScriptRoot 'legacy-build-preflight.ps1') -RepositoryRoot $root -Dx8TypeLibraryPath $dx8 -LegacyInteropPath $interopRoot -ReportOnly
$preflight = $preflightJson | ConvertFrom-Json
if (-not $preflight.ready) {
    throw "Legacy build preflight failed: $($preflight.issues -join '; ')"
}

$preparation = [ordered]@{
    repositoryRoot = $root
    configuration = $Configuration
    externalArchive = $Dx8VbArchive
    externalArchiveSha256 = Get-Sha256 $Dx8VbArchive
    stagedDx8Sha256 = $actualDx8Hash
    stagedDx8TypeLibrary = $dx8Identity
    dx7TypeLibrary = $dx7Identity
    quartzTypeLibrary = $quartzIdentity
    tlbImp = $tlbImp
    tlbImpSha256 = $actualTlbImpHash
    interops = $interopRecords
    nativeAlphaSha256 = Get-Sha256 $alphaSource
    noComRegistrationPerformed = $true
    preflight = $preflight
}
$preparation | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'preparation.json') -Encoding UTF8

if ($PrepareOnly) {
    [pscustomobject]$preparation | ConvertTo-Json -Depth 8
    return
}

$msbuild = [string]$preflight.selectedMSBuild
$solution = Join-Path $source 'FreeTrain_VS2008.sln'
$buildLog = Join-Path $logRoot 'msbuild.log'
$projectOrder = @(Get-SolutionProjectBuildOrder $solution)
$projectResults = [Collections.Generic.List[object]]::new()
$classifiedErrors = [Collections.Generic.List[object]]::new()
$buildExitCode = 0
Set-Content -LiteralPath $buildLog -Value '' -Encoding UTF8

for ($projectIndex = 0; $projectIndex -lt $projectOrder.Count; $projectIndex++) {
    $project = $projectOrder[$projectIndex]
    $safeName = $project.name -replace '[^A-Za-z0-9_.-]', '_'
    $projectLog = Join-Path $logRoot ("{0:D2}-{1}.log" -f ($projectIndex + 1), $safeName)
    $msbuildArguments = @(
        $project.fullPath,
        '/target:Rebuild',
        '/toolsversion:3.5',
        "/property:Configuration=$Configuration",
        '/property:Platform=AnyCPU',
        '/property:PlatformTarget=x86',
        '/property:BuildProjectReferences=false',
        "/property:SolutionDir=$source\",
        "/property:LegacyInteropPath=$interopRoot",
        '/property:PostBuildEvent=',
        '/nologo',
        '/verbosity:minimal'
    )

    & $msbuild @msbuildArguments 2>&1 | Tee-Object -FilePath $projectLog
    $projectExitCode = $LASTEXITCODE
    Add-Content -LiteralPath $buildLog -Value (Get-Content -LiteralPath $projectLog) -Encoding UTF8
    $projectErrors = @(Get-Content -LiteralPath $projectLog | Where-Object { $_ -match ':\s*(fatal\s+)?error\s+[A-Z]+\d+:' })
    foreach ($errorLine in $projectErrors) {
        $classifiedErrors.Add([pscustomobject]@{
            project = $project.name
            category = Get-BuildErrorCategory $errorLine
            message = $errorLine
        })
    }
    $projectResults.Add([pscustomobject]@{
        project = $project.name
        path = $project.fullPath
        exitCode = $projectExitCode
        log = $projectLog
        errorCount = $projectErrors.Count
    })
    if ($projectExitCode -ne 0) {
        $buildExitCode = $projectExitCode
        break
    }
}

$buildResult = [ordered]@{
    msbuild = $msbuild
    traversal = 'solution projects in deterministic topological order; BuildProjectReferences=false'
    solutionProjectCount = $projectOrder.Count
    attemptedProjectCount = $projectResults.Count
    log = $buildLog
    exitCode = $buildExitCode
    projects = $projectResults
    errors = $classifiedErrors
}
$buildResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runRoot 'build-result.json') -Encoding UTF8
if ($buildExitCode -ne 0) {
    [pscustomobject]$buildResult | ConvertTo-Json -Depth 6
    exit $buildExitCode
}

Reset-ArtifactDirectory $packageRoot
$centralBin = Join-Path $source ("bin/{0}" -f $Configuration)
Copy-FilteredTree -From $centralBin -To $packageRoot

$exclusions = @(Get-Content -LiteralPath (Join-Path $source 'excludelist.txt') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
Copy-FilteredTree -From (Join-Path $source 'core/res') -To (Join-Path $packageRoot 'res') -Exclude $exclusions
Copy-FilteredTree -From (Join-Path $source 'plugins') -To (Join-Path $packageRoot 'plugins') -Exclude $exclusions
Copy-FilteredTree -From (Join-Path $source 'doc') -To $packageRoot -Exclude $exclusions

$requiredPackageFiles = @(
    'FreeTrain.exe',
    'FreeTrain.Core.dll',
    'FreeTrain.Controls.dll',
    'DirectAudio.net.dll',
    'DirectDraw.net.dll',
    'Interop.DxVBLib.dll',
    'Interop.DxVBLibA.dll',
    'Interop.QuartzTypeLib.dll',
    'Interop.DirectDrawAlphaBlendLib.dll',
    'DirectDraw.AlphaBlend.dll'
)
$packageChecks = @($requiredPackageFiles | ForEach-Object {
    $path = Join-Path $packageRoot $_
    [pscustomobject]@{
        file = $_
        present = Test-Path -LiteralPath $path -PathType Leaf
        sha256 = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Sha256 $path } else { $null }
    }
})
$missingPackageFiles = @($packageChecks | Where-Object { -not $_.present })
if ($missingPackageFiles.Count -ne 0) {
    throw "The package is missing: $($missingPackageFiles.file -join ', ')"
}
$packagedAlpha = Join-Path $packageRoot 'DirectDraw.AlphaBlend.dll'
if ((Get-Sha256 $packagedAlpha) -cne $expectedAlphaHash) {
    throw 'The packaged native alpha DLL does not match the verified preservation binary.'
}

$corFlags = 'C:\Program Files (x86)\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8 Tools\CorFlags.exe'
$architectureChecks = foreach ($managedFile in @('FreeTrain.exe', 'FreeTrain.Core.dll', 'DirectAudio.net.dll', 'DirectDraw.net.dll')) {
    $path = Join-Path $packageRoot $managedFile
    $output = (& $corFlags $path 2>&1 | Out-String)
    $required32 = $output -match '32BITREQ\s*:\s*1'
    [pscustomobject]@{ file = $managedFile; required32Bit = $required32; output = $output.Trim() }
}
if (@($architectureChecks | Where-Object { -not $_.required32Bit }).Count -ne 0) {
    throw 'One or more primary managed package assemblies are not marked 32BITREQUIRED.'
}

$packageResult = [ordered]@{
    package = $packageRoot
    fileCount = @(Get-ChildItem -LiteralPath $packageRoot -File -Recurse).Count
    requiredFiles = $packageChecks
    architecture = $architectureChecks
    nativeAlphaSha256 = Get-Sha256 $packagedAlpha
    sourceDx8Included = $false
    comRegistrationPerformed = $false
}
$packageResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runRoot 'package-result.json') -Encoding UTF8
[pscustomobject]$packageResult | ConvertTo-Json -Depth 6
