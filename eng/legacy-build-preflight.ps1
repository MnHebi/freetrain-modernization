[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [switch] $ReportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$source = Join-Path $root 'FreeTrain'
$issues = [Collections.Generic.List[string]]::new()
$observations = [Collections.Generic.List[string]]::new()

function Test-TypeLibraryRegistration {
    param([Parameter(Mandatory)][string] $Guid)

    $locations = @(
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\TypeLib\$Guid",
        "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Classes\TypeLib\$Guid",
        "Registry::HKEY_CLASSES_ROOT\TypeLib\$Guid"
    )
    return (@($locations | Where-Object { Test-Path -LiteralPath $_ })).Count -gt 0
}

function Test-MSBuildHost {
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ path = $Path; usable = $false; output = 'not found' }
    }

    $probe = Join-Path ([IO.Path]::GetTempPath()) ("freetrain-msbuild-{0}.proj" -f [Guid]::NewGuid().ToString('N'))
    try {
        $project = '<Project ToolsVersion="3.5" xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><Target Name="Probe" /></Project>'
        [IO.File]::WriteAllText($probe, $project, [Text.UTF8Encoding]::new($false))
        $output = (& $Path $probe /target:Probe /nologo /verbosity:quiet 2>&1 | Out-String).Trim()
        $usable = ($LASTEXITCODE -eq 0)
    } finally {
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        path = $Path
        usable = $usable
        output = $output
    }
}

$msbuildAttempts = @(
    Test-MSBuildHost 'C:\Windows\Microsoft.NET\Framework\v3.5\MSBuild.exe'
    Test-MSBuildHost 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe'
)
$selectedMSBuild = $msbuildAttempts | Where-Object usable | Select-Object -First 1
if ($null -eq $selectedMSBuild) {
    $issues.Add('No usable classic MSBuild host was found.')
}

$dx7Guid = '{E1211242-8E94-11D1-8808-00C04FC2C602}'
$dx8Guid = '{E1211242-8E94-11D1-8808-00C04FC2C603}'
$quartzGuid = '{56A868B0-0AD4-11CE-B03A-0020AF0BA770}'
$dx7File = Join-Path $source 'extlib/dx7vb.dll'
$dx8TypeLibraryCandidates = @(
    (Join-Path $source 'extlib/dx8vb.dll'),
    'C:\Windows\SysWOW64\dx8vb.dll',
    'C:\Windows\System32\dx8vb.dll'
)
$dx8Interop = Join-Path $source 'extlib/Interop.DxVBLibA.dll'
$tlbImpCandidates = @(
    'C:\Program Files\Microsoft SDKs\Windows\v6.0A\bin\TlbImp.exe',
    'C:\Program Files (x86)\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8 Tools\TlbImp.exe'
)

$dx7Registered = Test-TypeLibraryRegistration $dx7Guid
$dx8Registered = Test-TypeLibraryRegistration $dx8Guid
$quartzRegistered = Test-TypeLibraryRegistration $quartzGuid
$dx7SourcePresent = Test-Path -LiteralPath $dx7File -PathType Leaf
$dx8TypeLibrary = $dx8TypeLibraryCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
$dx8InteropPresent = Test-Path -LiteralPath $dx8Interop -PathType Leaf
$tlbImp = $tlbImpCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

if (-not $dx7Registered -and (-not $dx7SourcePresent -or $null -eq $tlbImp)) {
    $issues.Add('DxVBLib is unregistered and cannot be generated from the preserved local input.')
}
if (-not $dx8Registered -and $null -eq $dx8TypeLibrary -and -not $dx8InteropPresent) {
    $issues.Add('DxVBLibA is unregistered and no local DirectX 8 type-library or interop input exists.')
} elseif (-not $dx8Registered -and $null -eq $dx8TypeLibrary) {
    $issues.Add('A DxVBLibA interop assembly exists, but no DirectX 8 Visual Basic runtime/type-library input is available for the runnable baseline.')
}
if (-not $quartzRegistered) {
    $issues.Add('QuartzTypeLib is not registered.')
}

$sdkRoot = $null
$sdkProperties = Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\.NETFramework' -Name 'SDKInstallRootv2.0' -ErrorAction SilentlyContinue
if ($null -ne $sdkProperties) {
    $sdkProperty = $sdkProperties.PSObject.Properties['SDKInstallRootv2.0']
    if ($null -ne $sdkProperty) {
        $sdkRoot = $sdkProperty.Value
    }
}
if ([string]::IsNullOrWhiteSpace([string]$sdkRoot)) {
    $observations.Add('.NET Framework SDKInstallRootv2.0 is not configured; Phase 1A proved that this informational property is not consumed by the FreeTrain build.')
}

$vcBuild = Get-Command 'vcbuild.exe' -ErrorAction SilentlyContinue
$alphaDebugDll = Join-Path $source 'bin/Debug/DirectDraw.AlphaBlend.dll'
$alphaReleaseDll = Join-Path $source 'bin/Release/DirectDraw.AlphaBlend.dll'
$alphaInterop = Join-Path $source 'lib/DirectDraw.net/Interop.DirectDrawAlphaBlendLib.DLL'
$expectedAlphaHash = 'B8153302A76F3768528453D18C9025A5017B0B5EA2350F9B3F57A8A2B37F165D'
$alphaFilesPresent =
    (Test-Path -LiteralPath $alphaDebugDll -PathType Leaf) -and
    (Test-Path -LiteralPath $alphaReleaseDll -PathType Leaf) -and
    (Test-Path -LiteralPath $alphaInterop -PathType Leaf)

$alphaDebugHash = if (Test-Path -LiteralPath $alphaDebugDll -PathType Leaf) {
    (Get-FileHash -LiteralPath $alphaDebugDll -Algorithm SHA256).Hash
} else {
    $null
}
$alphaReleaseHash = if (Test-Path -LiteralPath $alphaReleaseDll -PathType Leaf) {
    (Get-FileHash -LiteralPath $alphaReleaseDll -Algorithm SHA256).Hash
} else {
    $null
}
$alphaPreservationReady =
    $alphaFilesPresent -and
    $alphaDebugHash -eq $expectedAlphaHash -and
    $alphaReleaseHash -eq $expectedAlphaHash

if ($null -eq $vcBuild -and -not $alphaPreservationReady) {
    $issues.Add('Neither the verified pinned native-alpha binary set nor a VCBuild/compatible native ATL toolchain is available.')
} elseif ($null -eq $vcBuild) {
    $observations.Add('VCBuild is not available; Phase 1A accepted the checked native-alpha DLL and interop assembly for the preservation baseline.')
}

$report = [ordered]@{
    repositoryRoot = $root
    ready = ($issues.Count -eq 0)
    selectedMSBuild = if ($null -eq $selectedMSBuild) { $null } else { $selectedMSBuild.path }
    msbuildAttempts = $msbuildAttempts
    typeLibraries = [ordered]@{
        directX7 = [ordered]@{
            guid = $dx7Guid
            registered = $dx7Registered
            preservedSource = $dx7SourcePresent
            tlbImp = $tlbImp
        }
        directX8Audio = [ordered]@{
            guid = $dx8Guid
            registered = $dx8Registered
            typeLibraryInput = $dx8TypeLibrary
            interopInput = if ($dx8InteropPresent) { $dx8Interop } else { $null }
        }
        quartz = [ordered]@{
            guid = $quartzGuid
            registered = $quartzRegistered
        }
    }
    nativeAlpha = [ordered]@{
        debugDll = (Test-Path -LiteralPath $alphaDebugDll -PathType Leaf)
        releaseDll = (Test-Path -LiteralPath $alphaReleaseDll -PathType Leaf)
        debugSha256 = $alphaDebugHash
        releaseSha256 = $alphaReleaseHash
        expectedSha256 = $expectedAlphaHash
        copiesIdentical = ($null -ne $alphaDebugHash -and $alphaDebugHash -eq $alphaReleaseHash)
        interopAssembly = (Test-Path -LiteralPath $alphaInterop -PathType Leaf)
        preservationBinaryAccepted = $alphaPreservationReady
        vcBuildOnPath = ($null -ne $vcBuild)
    }
    dotNet20SdkRoot = $sdkRoot
    observations = $observations
    issues = $issues
}

[pscustomobject]$report | ConvertTo-Json -Depth 6

if (-not $ReportOnly -and $issues.Count -ne 0) {
    throw "Legacy build preflight failed with $($issues.Count) issue(s)."
}
