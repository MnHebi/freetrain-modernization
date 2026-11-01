[CmdletBinding()]
param(
    [ValidateSet('Validate', 'Catalog', 'Manifest', 'VerifyPng', 'CompareRegions')]
    [string] $Action = 'Validate',

    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot),

    [string] $FixtureRoot = 'fixtures/renderer-oracle',

    [string] $OutputPath,

    [string] $InputPath,

    [string] $OtherInputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$fixturePath = if ([IO.Path]::IsPathRooted($FixtureRoot)) {
    (Resolve-Path -LiteralPath $FixtureRoot).Path
} else {
    (Resolve-Path -LiteralPath (Join-Path $root $FixtureRoot)).Path
}
$catalogPath = Join-Path $fixturePath 'catalog.json'
$approvedManifestPath = Join-Path $fixturePath 'manifests/approved-files.sha256'
$validStatuses = @('planned', 'candidate', 'approved')
$sha256Pattern = '^[0-9a-f]{64}$'
$stableIdPattern = '^[a-z0-9]+(?:-[a-z0-9]+)*$'

function Get-RequiredProperty {
    param(
        [Parameter(Mandatory = $true)] $Object,
        [Parameter(Mandatory = $true)] [string] $Name,
        [Parameter(Mandatory = $true)] [string] $Context
    )

    if ($null -eq $Object -or -not (@($Object.PSObject.Properties.Name) -contains $Name)) {
        throw "$Context is missing required property '$Name'."
    }
    return $Object.PSObject.Properties[$Name].Value
}

function Assert-Equal {
    param($Actual, $Expected, [string] $Context)
    if ($Actual -ne $Expected) {
        throw "$Context must be '$Expected'; found '$Actual'."
    }
}

function Assert-NonPlaceholderString {
    param($Value, [string] $Context)
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value) -or $Value.StartsWith('replace-with-', [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Context must be a completed non-placeholder string."
    }
}

function Assert-StableId {
    param($Value, [string] $Context)
    if ($Value -isnot [string] -or $Value -notmatch $stableIdPattern) {
        throw "$Context must match $stableIdPattern."
    }
}

function Assert-Sha256 {
    param($Value, [string] $Context)
    if ($Value -isnot [string] -or $Value -cnotmatch $sha256Pattern) {
        throw "$Context must be a lowercase SHA-256 value."
    }
}

function Test-IntegerValue {
    param($Value)
    return $Value -is [sbyte] -or $Value -is [byte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Get-EvidencePath {
    param(
        [Parameter(Mandatory = $true)] [string] $RelativePath,
        [Parameter(Mandatory = $true)] [string] $Context
    )

    if ([IO.Path]::IsPathRooted($RelativePath)) {
        throw "$Context must be relative to the fixture root: $RelativePath"
    }

    $nativeRelative = $RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $fullPath = [IO.Path]::GetFullPath((Join-Path $fixturePath $nativeRelative))
    $prefix = $fixturePath.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Context escapes the fixture root: $RelativePath"
    }
    return $fullPath
}

function Get-FixtureRelativePath {
    param([Parameter(Mandatory = $true)] [string] $FullPath)
    $prefix = $fixturePath.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $resolved = [IO.Path]::GetFullPath($FullPath)
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the fixture root: $FullPath"
    }
    return $resolved.Substring($prefix.Length).Replace([IO.Path]::DirectorySeparatorChar, '/')
}

function Get-JsonFile {
    param([Parameter(Mandatory = $true)] [string] $Path)
    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "Invalid JSON in $Path`: $($_.Exception.Message)"
    }
}

function Get-UInt32BigEndian {
    param([byte[]] $Bytes, [int] $Offset)
    return [uint32]((([uint64]$Bytes[$Offset]) -shl 24) -bor
        (([uint64]$Bytes[$Offset + 1]) -shl 16) -bor
        (([uint64]$Bytes[$Offset + 2]) -shl 8) -bor
        ([uint64]$Bytes[$Offset + 3]))
}

function New-Crc32Table {
    $table = New-Object 'uint32[]' 256
    $polynomial = [uint32]3988292384
    for ($n = 0; $n -lt 256; $n++) {
        $value = [uint32]$n
        for ($k = 0; $k -lt 8; $k++) {
            if (($value -band 1) -ne 0) {
                $value = [uint32]($polynomial -bxor ($value -shr 1))
            } else {
                $value = [uint32]($value -shr 1)
            }
        }
        $table[$n] = $value
    }
    return $table
}

$crc32Table = New-Crc32Table

function Get-Crc32Segment {
    param([byte[]] $Bytes, [int] $Offset, [int] $Count)
    $crc = [uint32]4294967295
    for ($i = 0; $i -lt $Count; $i++) {
        $index = [int](($crc -bxor $Bytes[$Offset + $i]) -band 255)
        $crc = [uint32](($crc -shr 8) -bxor $crc32Table[$index])
    }
    return [uint32]($crc -bxor [uint32]4294967295)
}

function Get-PngInfo {
    param([Parameter(Mandatory = $true)] [string] $Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    [byte[]] $signature = 137, 80, 78, 71, 13, 10, 26, 10
    if ($bytes.Length -lt 33) {
        throw "PNG is too short: $Path"
    }
    for ($i = 0; $i -lt $signature.Length; $i++) {
        if ($bytes[$i] -ne $signature[$i]) {
            throw "PNG signature mismatch: $Path"
        }
    }

    $offset = 8
    $chunkIndex = 0
    $foundIhdr = $false
    $foundIdat = $false
    $foundIend = $false
    $width = 0
    $height = 0
    $bitDepth = 0
    $colorType = 0
    $interlace = 0
    $chunkTypes = [Collections.Generic.List[string]]::new()

    while ($offset -lt $bytes.Length) {
        if ($bytes.Length - $offset -lt 12) {
            throw "Truncated PNG chunk header at byte $offset`: $Path"
        }
        $lengthValue = Get-UInt32BigEndian $bytes $offset
        if ($lengthValue -gt [int]::MaxValue) {
            throw "Unsupported PNG chunk length $lengthValue`: $Path"
        }
        $length = [int]$lengthValue
        $chunkEnd = [int64]$offset + 12 + $length
        if ($chunkEnd -gt $bytes.Length) {
            throw "Truncated PNG chunk at byte $offset`: $Path"
        }

        $type = [Text.Encoding]::ASCII.GetString($bytes, $offset + 4, 4)
        $chunkTypes.Add($type)
        $expectedCrc = Get-UInt32BigEndian $bytes ($offset + 8 + $length)
        $actualCrc = Get-Crc32Segment $bytes ($offset + 4) ($length + 4)
        if ($actualCrc -ne $expectedCrc) {
            throw "PNG CRC mismatch in $type chunk at byte $offset`: $Path"
        }

        if ($type -in @('CgBI', 'acTL', 'fcTL', 'fdAT')) {
            throw "PNG contains unsupported nonstandard or animated chunk '$type': $Path"
        }

        if ($chunkIndex -eq 0 -and $type -ne 'IHDR') {
            throw "PNG IHDR is not the first chunk: $Path"
        }
        if ($type -eq 'IHDR') {
            if ($foundIhdr -or $length -ne 13) {
                throw "PNG has an invalid IHDR chunk: $Path"
            }
            $foundIhdr = $true
            $width = [int](Get-UInt32BigEndian $bytes ($offset + 8))
            $height = [int](Get-UInt32BigEndian $bytes ($offset + 12))
            $bitDepth = [int]$bytes[$offset + 16]
            $colorType = [int]$bytes[$offset + 17]
            $compression = [int]$bytes[$offset + 18]
            $filter = [int]$bytes[$offset + 19]
            $interlace = [int]$bytes[$offset + 20]
            if ($width -le 0 -or $height -le 0 -or $compression -ne 0 -or $filter -ne 0 -or $interlace -notin @(0, 1)) {
                throw "PNG has unsupported IHDR values: $Path"
            }
            $allowedDepths = switch ($colorType) {
                0 { @(1, 2, 4, 8, 16) }
                2 { @(8, 16) }
                3 { @(1, 2, 4, 8) }
                4 { @(8, 16) }
                6 { @(8, 16) }
                default { @() }
            }
            if ($bitDepth -notin $allowedDepths) {
                throw "PNG has invalid bit depth $bitDepth for color type $colorType`: $Path"
            }
        } elseif ($type -eq 'IDAT') {
            $foundIdat = $true
        } elseif ($type -eq 'IEND') {
            if ($length -ne 0) {
                throw "PNG IEND is not empty: $Path"
            }
            $foundIend = $true
            if ($chunkEnd -ne $bytes.Length) {
                throw "PNG contains trailing bytes after IEND: $Path"
            }
        }

        $offset = [int]$chunkEnd
        $chunkIndex++
    }

    if (-not $foundIhdr -or -not $foundIdat -or -not $foundIend) {
        throw "PNG is missing IHDR, IDAT, or IEND: $Path"
    }

    return [pscustomobject][ordered]@{
        width = $width
        height = $height
        bitDepth = $bitDepth
        colorType = $colorType
        interlace = $interlace
        chunks = @($chunkTypes)
        lossless = $true
    }
}

function Test-RegionSet {
    param(
        $Regions,
        [string] $Context,
        [int] $ImageWidth,
        [int] $ImageHeight,
        [bool] $RequireAction
    )

    $index = 0
    foreach ($region in @($Regions)) {
        $x = Get-RequiredProperty $region 'x' "$Context[$index]"
        $y = Get-RequiredProperty $region 'y' "$Context[$index]"
        $width = Get-RequiredProperty $region 'width' "$Context[$index]"
        $height = Get-RequiredProperty $region 'height' "$Context[$index]"
        $purpose = Get-RequiredProperty $region 'purpose' "$Context[$index]"
        if (-not (Test-IntegerValue $x) -or -not (Test-IntegerValue $y) -or
            -not (Test-IntegerValue $width) -or -not (Test-IntegerValue $height) -or
            $x -lt 0 -or $y -lt 0 -or $width -le 0 -or $height -le 0 -or
            ([int64]$x + $width) -gt $ImageWidth -or ([int64]$y + $height) -gt $ImageHeight) {
            throw "$Context[$index] is outside the ${ImageWidth}x${ImageHeight} screenshot."
        }
        Assert-NonPlaceholderString $purpose "$Context[$index].purpose"
        if ($RequireAction) {
            $actionValue = Get-RequiredProperty $region 'action' "$Context[$index]"
            if ($actionValue -notin @('mask', 'manual-review')) {
                throw "$Context[$index].action must be 'mask' or 'manual-review'."
            }
        }
        $index++
    }
    return $index
}

function ConvertTo-ComparableJson {
    param($Value)
    return ($Value | ConvertTo-Json -Depth 30 -Compress)
}

function Assert-ComparableEqual {
    param($Actual, $Expected, [string] $Context)
    if ((ConvertTo-ComparableJson $Actual) -cne (ConvertTo-ComparableJson $Expected)) {
        throw "$Context must be structurally identical."
    }
}

function Expand-CapturePattern {
    param([string] $Pattern, [string] $OracleId, [string] $CaptureId)
    return $Pattern.Replace('{oracleId}', $OracleId).Replace('{captureId}', $CaptureId)
}

function Test-PointInRectangle {
    param($Point, $Rectangle)
    return $Point.x -ge $Rectangle.x -and $Point.y -ge $Rectangle.y -and
        $Point.x -lt ([int64]$Rectangle.x + $Rectangle.width) -and
        $Point.y -lt ([int64]$Rectangle.y + $Rectangle.height)
}

function Assert-RectangleBounds {
    param($Rectangle, [string] $Context, [int] $ImageWidth, [int] $ImageHeight)
    foreach ($field in @('x', 'y', 'width', 'height')) {
        $value = Get-RequiredProperty $Rectangle $field $Context
        if (-not (Test-IntegerValue $value)) { throw "$Context.$field must be an integer." }
    }
    if ($Rectangle.x -lt 0 -or $Rectangle.y -lt 0 -or $Rectangle.width -le 0 -or $Rectangle.height -le 0 -or
        ([int64]$Rectangle.x + $Rectangle.width) -gt $ImageWidth -or
        ([int64]$Rectangle.y + $Rectangle.height) -gt $ImageHeight) {
        throw "$Context is outside the ${ImageWidth}x${ImageHeight} screenshot."
    }
}

function Get-EnvironmentSignature {
    param($Environment)
    $versions = @($Environment.clrDotNetVersions | Sort-Object)
    return [pscustomobject][ordered]@{
        equivalenceGroupId = $Environment.equivalenceGroupId
        guestOs = $Environment.guestOs
        clrDotNetVersions = $versions
        directXRuntime = $Environment.directXRuntime
        hypervisor = $Environment.hypervisor
        display = $Environment.display
        desktop = $Environment.desktop
    }
}

function Assert-RegionIds {
    param($Regions, [string] $Context)
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $index = 0
    foreach ($region in @($Regions)) {
        $id = Get-RequiredProperty $region 'regionId' "$Context[$index]"
        Assert-StableId $id "$Context[$index].regionId"
        if (-not $ids.Add($id)) {
            throw "Duplicate region ID in $Context`: $id"
        }
        $index++
    }
    return @($ids)
}

function Get-ValidatedPackage {
    param($Package, [string] $OracleId, [string] $Context)
    $kind = Get-RequiredProperty $Package 'kind' $Context
    Assert-Equal $kind $OracleId "$Context.kind"
    if ($OracleId -eq 'official-release') {
        Assert-Equal (Get-RequiredProperty $Package 'archiveFilename' $Context) 'FreeTrain20070604.zip' "$Context.archiveFilename"
        Assert-Equal (Get-RequiredProperty $Package 'archiveSha256' $Context) '70374a836a9f1bc28b16dd65c323fc1b21b4142f10344d19335a65690c16c23d' "$Context.archiveSha256"
        Assert-Sha256 (Get-RequiredProperty $Package 'executableSha256' $Context) "$Context.executableSha256"
    } else {
        $commit = Get-RequiredProperty $Package 'gitCommit' $Context
        if ($commit -isnot [string] -or $commit -cnotmatch '^[0-9a-f]{40}$') {
            throw "$Context.gitCommit must be a lowercase 40-character Git commit."
        }
        Assert-NonPlaceholderString (Get-RequiredProperty $Package 'preservationBuildIdentifier' $Context) "$Context.preservationBuildIdentifier"
        Assert-Sha256 (Get-RequiredProperty $Package 'packageManifestSha256' $Context) "$Context.packageManifestSha256"
        Assert-Equal (Get-RequiredProperty $Package 'executableSha256' $Context) '6449145b79d4f7d2b287ae8a9f7465bfb5c418c58903dfd847ef6530fe423c15' "$Context.executableSha256"
    }

    $payloadPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $payloadIndex = 0
    foreach ($payload in @(Get-RequiredProperty $Package 'relevantPayloads' $Context)) {
        $payloadPath = Get-RequiredProperty $payload 'path' "$Context.relevantPayloads[$payloadIndex]"
        Assert-NonPlaceholderString $payloadPath "$Context.relevantPayloads[$payloadIndex].path"
        if (-not $payloadPaths.Add($payloadPath)) {
            throw "Duplicate relevant payload path in $Context`: $payloadPath"
        }
        Assert-Sha256 (Get-RequiredProperty $payload 'sha256' "$Context.relevantPayloads[$payloadIndex]") "$Context.relevantPayloads[$payloadIndex].sha256"
        Assert-NonPlaceholderString (Get-RequiredProperty $payload 'reason' "$Context.relevantPayloads[$payloadIndex]") "$Context.relevantPayloads[$payloadIndex].reason"
        $payloadIndex++
    }
}

function Get-ValidatedCaptureMetadata {
    param(
        [string] $MetadataRelative,
        [string] $ExpectedFixtureId,
        [string] $ExpectedCaptureId,
        [string] $ExpectedSave,
        [string] $ExpectedStatus,
        [string] $ExpectedRunKind,
        [string] $ExpectedOracleId,
        [string] $ExpectedRendererOracle,
        [string] $ExpectedInteractionMode,
        $Catalog
    )

    $metadataPath = Get-EvidencePath $MetadataRelative "metadata for $ExpectedOracleId/$ExpectedRunKind/$ExpectedCaptureId"
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "Metadata is missing for $ExpectedOracleId/$ExpectedRunKind/$ExpectedCaptureId`: $MetadataRelative"
    }
    $metadata = Get-JsonFile $metadataPath
    $context = $MetadataRelative

    Assert-Equal (Get-RequiredProperty $metadata 'schemaVersion' $context) 2 "$context.schemaVersion"
    Assert-Equal (Get-RequiredProperty $metadata 'approvalStatus' $context) $ExpectedStatus "$context.approvalStatus"
    Assert-Equal (Get-RequiredProperty $metadata 'fixtureId' $context) $ExpectedFixtureId "$context.fixtureId"
    Assert-Equal (Get-RequiredProperty $metadata 'captureId' $context) $ExpectedCaptureId "$context.captureId"
    Assert-Equal (Get-RequiredProperty $metadata 'runKind' $context) $ExpectedRunKind "$context.runKind"
    Assert-Equal (Get-RequiredProperty $metadata 'oracleId' $context) $ExpectedOracleId "$context.oracleId"
    Assert-Equal (Get-RequiredProperty $metadata 'rendererOracle' $context) $ExpectedRendererOracle "$context.rendererOracle"
    Assert-Equal (Get-RequiredProperty $metadata 'originatingSave' $context) $ExpectedSave "$context.originatingSave"
    Assert-Equal (Get-RequiredProperty $metadata 'freeTrainRevision' $context) 'r389' "$context.freeTrainRevision"
    Assert-StableId $ExpectedFixtureId "$context.fixtureId"
    Assert-StableId $ExpectedCaptureId "$context.captureId"
    Assert-NonPlaceholderString (Get-RequiredProperty $metadata 'provenanceNotes' $context) "$context.provenanceNotes"

    $saveHash = Get-RequiredProperty $metadata 'saveSha256' $context
    Assert-Sha256 $saveHash "$context.saveSha256"
    $savePath = Get-EvidencePath $ExpectedSave "$context.originatingSave"
    if (-not (Test-Path -LiteralPath $savePath -PathType Leaf)) {
        throw "Originating save is missing for $ExpectedCaptureId`: $ExpectedSave"
    }
    if ([IO.Path]::GetExtension($savePath).ToLowerInvariant() -notin @('.ftgd', '.ftgt')) {
        throw "$context.originatingSave must be .ftgd or .ftgt."
    }
    $actualSaveHash = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSaveHash -cne $saveHash) {
        throw "$context save hash mismatch: expected $saveHash, found $actualSaveHash."
    }

    $package = Get-RequiredProperty $metadata 'package' $context
    Get-ValidatedPackage $package $ExpectedOracleId "$context.package"

    $environment = Get-RequiredProperty $metadata 'environment' $context
    Assert-NonPlaceholderString (Get-RequiredProperty $environment 'equivalenceGroupId' "$context.environment") "$context.environment.equivalenceGroupId"
    Assert-NonPlaceholderString (Get-RequiredProperty $environment 'identifier' "$context.environment") "$context.environment.identifier"
    Assert-Equal (Get-RequiredProperty $environment 'vmRole' "$context.environment") $ExpectedOracleId "$context.environment.vmRole"
    Assert-NonPlaceholderString (Get-RequiredProperty $environment 'referenceStateIdentifier' "$context.environment") "$context.environment.referenceStateIdentifier"
    Assert-Equal (Get-RequiredProperty $environment 'networkDisconnected' "$context.environment") $true "$context.environment.networkDisconnected"
    $guestOs = Get-RequiredProperty $environment 'guestOs' "$context.environment"
    Assert-NonPlaceholderString (Get-RequiredProperty $guestOs 'product' "$context.environment.guestOs") "$context.environment.guestOs.product"
    Assert-NonPlaceholderString (Get-RequiredProperty $guestOs 'version' "$context.environment.guestOs") "$context.environment.guestOs.version"
    Assert-Equal (Get-RequiredProperty $guestOs 'servicePack' "$context.environment.guestOs") 'SP3' "$context.environment.guestOs.servicePack"
    Assert-Equal (Get-RequiredProperty $guestOs 'architecture' "$context.environment.guestOs") 'x86' "$context.environment.guestOs.architecture"
    $clrVersions = @(Get-RequiredProperty $environment 'clrDotNetVersions' "$context.environment")
    if ($clrVersions.Count -lt 1) { throw "$context.environment.clrDotNetVersions must not be empty." }
    foreach ($version in $clrVersions) { Assert-NonPlaceholderString $version "$context.environment.clrDotNetVersions" }
    $directX = Get-RequiredProperty $environment 'directXRuntime' "$context.environment"
    Assert-NonPlaceholderString (Get-RequiredProperty $directX 'version' "$context.environment.directXRuntime") "$context.environment.directXRuntime.version"
    Assert-NonPlaceholderString (Get-RequiredProperty $directX 'dx8vbDllVersion' "$context.environment.directXRuntime") "$context.environment.directXRuntime.dx8vbDllVersion"
    Assert-Sha256 (Get-RequiredProperty $directX 'dx8vbDllSha256' "$context.environment.directXRuntime") "$context.environment.directXRuntime.dx8vbDllSha256"

    $hypervisor = Get-RequiredProperty $environment 'hypervisor' "$context.environment"
    Assert-Equal (Get-RequiredProperty $hypervisor 'product' "$context.environment.hypervisor") 'Oracle VM VirtualBox' "$context.environment.hypervisor.product"
    Assert-NonPlaceholderString (Get-RequiredProperty $hypervisor 'version' "$context.environment.hypervisor") "$context.environment.hypervisor.version"
    Assert-NonPlaceholderString (Get-RequiredProperty $hypervisor 'graphicsController' "$context.environment.hypervisor") "$context.environment.hypervisor.graphicsController"
    $videoMemory = Get-RequiredProperty $hypervisor 'videoMemoryMiB' "$context.environment.hypervisor"
    if (-not (Test-IntegerValue $videoMemory) -or $videoMemory -lt 1) { throw "$context.environment.hypervisor.videoMemoryMiB must be a positive integer." }
    if ((Get-RequiredProperty $hypervisor 'acceleration3d' "$context.environment.hypervisor") -isnot [bool]) { throw "$context.environment.hypervisor.acceleration3d must be boolean." }
    $driver = Get-RequiredProperty $hypervisor 'guestDisplayDriver' "$context.environment.hypervisor"
    Assert-NonPlaceholderString (Get-RequiredProperty $driver 'name' "$context.environment.hypervisor.guestDisplayDriver") "$context.environment.hypervisor.guestDisplayDriver.name"
    Assert-NonPlaceholderString (Get-RequiredProperty $driver 'version' "$context.environment.hypervisor.guestDisplayDriver") "$context.environment.hypervisor.guestDisplayDriver.version"
    $guestAdditions = Get-RequiredProperty $hypervisor 'guestAdditions' "$context.environment.hypervisor"
    if ((Get-RequiredProperty $guestAdditions 'present' "$context.environment.hypervisor.guestAdditions") -isnot [bool]) { throw "$context.environment.hypervisor.guestAdditions.present must be boolean." }
    Assert-NonPlaceholderString (Get-RequiredProperty $guestAdditions 'version' "$context.environment.hypervisor.guestAdditions") "$context.environment.hypervisor.guestAdditions.version"

    $display = Get-RequiredProperty $environment 'display' "$context.environment"
    foreach ($field in @('width', 'height', 'colorDepthBits', 'dpi')) {
        $value = Get-RequiredProperty $display $field "$context.environment.display"
        if (-not (Test-IntegerValue $value) -or $value -lt 1) { throw "$context.environment.display.$field must be a positive integer." }
    }
    Assert-Equal $display.width $Catalog.plannedEnvironment.displayWidth "$context.environment.display.width"
    Assert-Equal $display.height $Catalog.plannedEnvironment.displayHeight "$context.environment.display.height"
    Assert-Equal $display.colorDepthBits $Catalog.plannedEnvironment.colorDepthBits "$context.environment.display.colorDepthBits"
    Assert-Equal $display.dpi $Catalog.plannedEnvironment.dpi "$context.environment.display.dpi"
    Assert-Equal (Get-RequiredProperty $display 'scaling' "$context.environment.display") 'none' "$context.environment.display.scaling"
    $desktop = Get-RequiredProperty $environment 'desktop' "$context.environment"
    foreach ($field in @('theme', 'wallpaper', 'fontSmoothing')) {
        Assert-NonPlaceholderString (Get-RequiredProperty $desktop $field "$context.environment.desktop") "$context.environment.desktop.$field"
    }

    $state = Get-RequiredProperty $metadata 'state' $context
    Assert-NonPlaceholderString (Get-RequiredProperty $state 'clockDisplay' "$context.state") "$context.state.clockDisplay"
    Assert-Equal (Get-RequiredProperty $state 'clockPaused' "$context.state") $true "$context.state.clockPaused"
    if ((Get-RequiredProperty $state 'dayNight' "$context.state") -notin @('align-clock-day', 'align-clock-night', 'always-day', 'always-night')) { throw "$context.state.dayNight has an unsupported value." }
    if ((Get-RequiredProperty $state 'season' "$context.state") -notin @('spring', 'summer', 'autumn', 'winter')) { throw "$context.state.season has an unsupported value." }
    Assert-Equal (Get-RequiredProperty $state 'weather' "$context.state") 'none' "$context.state.weather"
    Assert-NonPlaceholderString (Get-RequiredProperty $state 'heightCut' "$context.state") "$context.state.heightCut"
    Assert-NonPlaceholderString (Get-RequiredProperty $state 'controller' "$context.state") "$context.state.controller"
    [void](Get-RequiredProperty $state 'overlays' "$context.state")
    $stationNames = Get-RequiredProperty $state 'stationNames' "$context.state"
    if ($stationNames -notin @('on', 'off')) { throw "$context.state.stationNames must be 'on' or 'off'." }
    Assert-Equal (Get-RequiredProperty $state 'cameraRotation' "$context.state") 'none' "$context.state.cameraRotation"
    $viewport = Get-RequiredProperty $state 'viewport' "$context.state"
    Assert-NonPlaceholderString (Get-RequiredProperty $viewport 'mapWindowState' "$context.state.viewport") "$context.state.viewport.mapWindowState"
    foreach ($field in @('scrollX', 'scrollY')) {
        $value = Get-RequiredProperty $viewport $field "$context.state.viewport"
        if (-not (Test-IntegerValue $value) -or $value -lt 0) { throw "$context.state.viewport.$field must be a nonnegative integer." }
    }
    $mapClientRegion = Get-RequiredProperty $viewport 'mapClientRegion' "$context.state.viewport"

    $interaction = Get-RequiredProperty $metadata 'interaction' $context
    $interactionMode = Get-RequiredProperty $interaction 'mode' "$context.interaction"
    Assert-Equal $interactionMode $ExpectedInteractionMode "$context.interaction.mode"
    Assert-Equal (Get-RequiredProperty $interaction 'coordinateSpace' "$context.interaction") 'full-screen-png' "$context.interaction.coordinateSpace"
    $points = @(Get-RequiredProperty $interaction 'points' "$context.interaction")
    if ($points.Count -lt 1) { throw "$context.interaction.points must not be empty." }
    $pointRoles = @()
    for ($pointIndex = 0; $pointIndex -lt $points.Count; $pointIndex++) {
        $point = $points[$pointIndex]
        $role = Get-RequiredProperty $point 'role' "$context.interaction.points[$pointIndex]"
        if ($role -notin @('pointer', 'anchor-click', 'current-pointer', 'drag-start', 'drag-end')) { throw "$context.interaction.points[$pointIndex].role is unsupported." }
        $pointRoles += $role
        foreach ($field in @('x', 'y')) {
            $value = Get-RequiredProperty $point $field "$context.interaction.points[$pointIndex]"
            if (-not (Test-IntegerValue $value) -or $value -lt 0 -or (($field -eq 'x') -and $value -ge $display.width) -or (($field -eq 'y') -and $value -ge $display.height)) {
                throw "$context.interaction.points[$pointIndex].$field is outside the screenshot."
            }
        }
    }
    $requiredRoles = switch ($interactionMode) {
        'parked' { @('pointer') }
        'pointer-hover' { @('pointer') }
        'click-move-preview' { @('anchor-click', 'current-pointer') }
        'drag-preview' { @('drag-start', 'drag-end') }
    }
    foreach ($requiredRole in $requiredRoles) {
        if ($pointRoles -notcontains $requiredRole) { throw "$context.interaction.points must include role '$requiredRole' for mode '$interactionMode'." }
    }
    $cursorDisposition = Get-RequiredProperty $interaction 'cursorDisposition' "$context.interaction"
    if ($interactionMode -eq 'parked') {
        if ($cursorDisposition -notin @('outside-deterministic-regions', 'not-captured-by-hypervisor')) { throw "$context neutral capture must park the cursor outside deterministic regions or prove the hypervisor did not capture it." }
    } elseif ($cursorDisposition -notin @('masked', 'not-captured-by-hypervisor')) {
        throw "$context preview/overlay capture must keep its recorded interaction coordinates and either mask the cursor or prove it was not captured."
    }
    Assert-NonPlaceholderString (Get-RequiredProperty $interaction 'notes' "$context.interaction") "$context.interaction.notes"

    $capture = Get-RequiredProperty $metadata 'capture' $context
    Assert-Equal (Get-RequiredProperty $capture 'mechanism' "$context.capture") 'hypervisor-console' "$context.capture.mechanism"
    Assert-Equal (Get-RequiredProperty $capture 'format' "$context.capture") 'png' "$context.capture.format"
    Assert-Equal (Get-RequiredProperty $capture 'lossless' "$context.capture") $true "$context.capture.lossless"
    $runDirectory = if ($ExpectedRunKind -eq 'primary') { 'primary' } else { 'reproduction' }
    $expectedScreenshot = "screenshots/$ExpectedOracleId/$runDirectory/$ExpectedCaptureId.png"
    $screenshotRelative = Get-RequiredProperty $capture 'screenshot' "$context.capture"
    Assert-Equal $screenshotRelative $expectedScreenshot "$context.capture.screenshot"
    $screenshotHash = Get-RequiredProperty $capture 'screenshotSha256' "$context.capture"
    Assert-Sha256 $screenshotHash "$context.capture.screenshotSha256"
    $screenshotPath = Get-EvidencePath $screenshotRelative "$context.capture.screenshot"
    if (-not (Test-Path -LiteralPath $screenshotPath -PathType Leaf)) { throw "Screenshot is missing for $ExpectedCaptureId`: $screenshotRelative" }
    $actualScreenshotHash = (Get-FileHash -LiteralPath $screenshotPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualScreenshotHash -cne $screenshotHash) { throw "$context screenshot hash mismatch: expected $screenshotHash, found $actualScreenshotHash." }
    $png = Get-PngInfo $screenshotPath
    if ($png.width -ne $display.width -or $png.height -ne $display.height) { throw "$context screenshot dimensions do not match the recorded display." }
    Assert-RectangleBounds $mapClientRegion "$context.state.viewport.mapClientRegion" $png.width $png.height

    $comparison = Get-RequiredProperty $metadata 'comparison' $context
    $deterministicRegions = @(Get-RequiredProperty $comparison 'deterministicRegions' "$context.comparison")
    if ((Test-RegionSet $deterministicRegions "$context.comparison.deterministicRegions" $png.width $png.height $false) -lt 1) { throw "$context must declare at least one deterministic region." }
    [void](Assert-RegionIds $deterministicRegions "$context.comparison.deterministicRegions")
    $gdiRegions = @(Get-RequiredProperty $comparison 'gdiFontRegions' "$context.comparison")
    $gdiCount = Test-RegionSet $gdiRegions "$context.comparison.gdiFontRegions" $png.width $png.height $true
    [void](Assert-RegionIds $gdiRegions "$context.comparison.gdiFontRegions")
    if ($stationNames -eq 'on' -and $gdiCount -lt 1) { throw "$context has station names on but declares no GDI/font region." }
    $pointerRegions = @(Get-RequiredProperty $comparison 'pointerCursorRegions' "$context.comparison")
    $pointerRegionCount = Test-RegionSet $pointerRegions "$context.comparison.pointerCursorRegions" $png.width $png.height $true
    [void](Assert-RegionIds $pointerRegions "$context.comparison.pointerCursorRegions")
    if ($cursorDisposition -eq 'masked' -and $pointerRegionCount -lt 1) { throw "$context masks a captured cursor but declares no pointer/cursor review region." }

    if ($interactionMode -eq 'parked' -and $cursorDisposition -eq 'outside-deterministic-regions') {
        $pointer = @($points | Where-Object role -EQ 'pointer')[0]
        foreach ($region in $deterministicRegions) {
            if (Test-PointInRectangle $pointer $region) { throw "$context parked pointer lies inside deterministic region '$($region.regionId)'." }
        }
    }
    if ($interactionMode -ne 'parked') {
        foreach ($point in $points) {
            if (-not (Test-PointInRectangle $point $mapClientRegion)) { throw "$context active interaction point '$($point.role)' must lie inside the recorded map client region." }
        }
    }

    $maskArtifacts = @(Get-RequiredProperty $comparison 'maskArtifacts' "$context.comparison")
    $validatedMasks = [Collections.Generic.List[object]]::new()
    for ($maskIndex = 0; $maskIndex -lt $maskArtifacts.Count; $maskIndex++) {
        $mask = $maskArtifacts[$maskIndex]
        $maskRelative = Get-RequiredProperty $mask 'path' "$context.comparison.maskArtifacts[$maskIndex]"
        if ($maskRelative -isnot [string] -or -not $maskRelative.StartsWith('masks/', [StringComparison]::Ordinal)) { throw "$context.comparison.maskArtifacts[$maskIndex].path must be under masks/." }
        $maskHash = Get-RequiredProperty $mask 'sha256' "$context.comparison.maskArtifacts[$maskIndex]"
        Assert-Sha256 $maskHash "$context.comparison.maskArtifacts[$maskIndex].sha256"
        $maskPath = Get-EvidencePath $maskRelative "$context.comparison.maskArtifacts[$maskIndex].path"
        if (-not (Test-Path -LiteralPath $maskPath -PathType Leaf)) { throw "Mask artifact is missing: $maskRelative" }
        $actualMaskHash = (Get-FileHash -LiteralPath $maskPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualMaskHash -cne $maskHash) { throw "$context mask hash mismatch for $maskRelative." }
        $validatedMasks.Add([pscustomobject]@{ relative = $maskRelative; path = $maskPath; hash = $actualMaskHash })
    }

    return [pscustomobject][ordered]@{
        fixtureId = $ExpectedFixtureId; captureId = $ExpectedCaptureId; status = $ExpectedStatus
        oracleId = $ExpectedOracleId; runKind = $ExpectedRunKind
        metadataRelative = $MetadataRelative; metadataPath = $metadataPath
        saveRelative = $ExpectedSave; savePath = $savePath; saveHash = $actualSaveHash
        screenshotRelative = $screenshotRelative; screenshotPath = $screenshotPath; screenshotHash = $actualScreenshotHash
        png = $png; metadata = $metadata; masks = @($validatedMasks)
    }
}

function Assert-CapturePair {
    param($Official, $Reconstructed, [string] $Context)
    Assert-Equal $Official.saveHash $Reconstructed.saveHash "$Context shared save hash"
    Assert-Equal $Official.saveRelative $Reconstructed.saveRelative "$Context shared save path"
    Assert-ComparableEqual $Official.metadata.state $Reconstructed.metadata.state "$Context state and viewport"
    Assert-ComparableEqual $Official.metadata.interaction $Reconstructed.metadata.interaction "$Context interaction coordinates"
    Assert-ComparableEqual $Official.metadata.comparison $Reconstructed.metadata.comparison "$Context comparison regions"
    Assert-ComparableEqual (Get-EnvironmentSignature $Official.metadata.environment) (Get-EnvironmentSignature $Reconstructed.metadata.environment) "$Context rendering environment"
    if ($Official.metadata.environment.identifier -ceq $Reconstructed.metadata.environment.identifier) { throw "$Context must use two independently identified VMs." }
    Assert-Equal $Official.png.width $Reconstructed.png.width "$Context screenshot width"
    Assert-Equal $Official.png.height $Reconstructed.png.height "$Context screenshot height"
}

function Assert-ReproductionMatchesPrimary {
    param($Primary, $Reproduction, [string] $Context)
    Assert-Equal $Primary.saveHash $Reproduction.saveHash "$Context save hash"
    Assert-ComparableEqual $Primary.metadata.package $Reproduction.metadata.package "$Context package identity"
    Assert-ComparableEqual $Primary.metadata.environment $Reproduction.metadata.environment "$Context environment"
    Assert-ComparableEqual $Primary.metadata.state $Reproduction.metadata.state "$Context state"
    Assert-ComparableEqual $Primary.metadata.interaction $Reproduction.metadata.interaction "$Context interaction"
    Assert-ComparableEqual $Primary.metadata.comparison $Reproduction.metadata.comparison "$Context comparison regions"
}

function Get-ExactRegionDifferences {
    param($First, $Second, [string] $Context)
    Assert-ComparableEqual $First.metadata.comparison.deterministicRegions $Second.metadata.comparison.deterministicRegions "$Context deterministic region definitions"
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $firstBitmap = [System.Drawing.Bitmap]::new($First.screenshotPath)
    $secondBitmap = [System.Drawing.Bitmap]::new($Second.screenshotPath)
    try {
        if ($firstBitmap.Width -ne $secondBitmap.Width -or $firstBitmap.Height -ne $secondBitmap.Height) { throw "$Context screenshot dimensions differ." }
        $results = @{}
        foreach ($region in @($First.metadata.comparison.deterministicRegions)) {
            Assert-RectangleBounds $region "$Context/$($region.regionId)" $firstBitmap.Width $firstBitmap.Height
            $differentPixels = [int64]0
            for ($y = $region.y; $y -lt ($region.y + $region.height); $y++) {
                for ($x = $region.x; $x -lt ($region.x + $region.width); $x++) {
                    if ($firstBitmap.GetPixel($x, $y).ToArgb() -ne $secondBitmap.GetPixel($x, $y).ToArgb()) { $differentPixels++ }
                }
            }
            $results[$region.regionId] = $differentPixels
        }
        return $results
    } finally {
        $firstBitmap.Dispose()
        $secondBitmap.Dispose()
    }
}

function Get-ValidatedComparison {
    param($ComparisonRelative, $Official, $Reconstructed, $OfficialReproduction, $ReconstructedReproduction, [bool] $ReproductionRequired, [string] $ExpectedStatus)
    $path = Get-EvidencePath $ComparisonRelative "comparison for $($Official.captureId)"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Comparison record is missing: $ComparisonRelative" }
    $item = Get-JsonFile $path
    $context = $ComparisonRelative
    Assert-Equal (Get-RequiredProperty $item 'schemaVersion' $context) 1 "$context.schemaVersion"
    Assert-Equal (Get-RequiredProperty $item 'approvalStatus' $context) $ExpectedStatus "$context.approvalStatus"
    Assert-Equal (Get-RequiredProperty $item 'fixtureId' $context) $Official.fixtureId "$context.fixtureId"
    Assert-Equal (Get-RequiredProperty $item 'captureId' $context) $Official.captureId "$context.captureId"
    Assert-Equal (Get-RequiredProperty $item 'officialPrimaryMetadata' $context) $Official.metadataRelative "$context.officialPrimaryMetadata"
    Assert-Equal (Get-RequiredProperty $item 'reconstructedPrimaryMetadata' $context) $Reconstructed.metadataRelative "$context.reconstructedPrimaryMetadata"
    Assert-Equal (Get-RequiredProperty $item 'sharedSaveSha256' $context) $Official.saveHash "$context.sharedSaveSha256"

    $environment = Get-RequiredProperty $item 'environmentEquivalence' $context
    Assert-Equal (Get-RequiredProperty $environment 'result' "$context.environmentEquivalence") 'exact-recorded-match' "$context.environmentEquivalence.result"
    $expectedFields = @('guestOs', 'clrDotNetVersions', 'directXRuntime', 'hypervisor', 'display', 'desktop')
    $actualFields = @((Get-RequiredProperty $environment 'comparedFields' "$context.environmentEquivalence") | Sort-Object)
    Assert-ComparableEqual $actualFields @($expectedFields | Sort-Object) "$context.environmentEquivalence.comparedFields"
    Assert-NonPlaceholderString (Get-RequiredProperty $environment 'notes' "$context.environmentEquivalence") "$context.environmentEquivalence.notes"

    $measuredDifferences = Get-ExactRegionDifferences $Official $Reconstructed "$context official-vs-reconstructed"
    $expectedRegionIds = @($Official.metadata.comparison.deterministicRegions | ForEach-Object regionId | Sort-Object)
    $actualRegions = @(Get-RequiredProperty $item 'deterministicRegions' $context)
    $actualRegionIds = @($actualRegions | ForEach-Object regionId | Sort-Object)
    Assert-ComparableEqual $actualRegionIds $expectedRegionIds "$context.deterministicRegions region IDs"
    $classifications = @('exact-match', 'gdi-font-platform-sensitive', 'package-resource-difference', 'plugin-version-payload-difference', 'debug-release-configuration-difference', 'runtime-environment-difference', 'historical-release-source-mismatch', 'reconstructed-build-defect', 'unexplained')
    $hasUnexplained = $false
    foreach ($region in $actualRegions) {
        Assert-StableId $region.regionId "$context.deterministicRegions.regionId"
        if ($region.result -notin @('exact-match', 'different')) { throw "$context deterministic region '$($region.regionId)' has an invalid result." }
        if (-not (Test-IntegerValue $region.differentPixelCount) -or $region.differentPixelCount -lt 0) { throw "$context deterministic region '$($region.regionId)' has an invalid pixel count." }
        if ($region.classification -notin $classifications) { throw "$context deterministic region '$($region.regionId)' has an invalid classification." }
        Assert-NonPlaceholderString $region.notes "$context deterministic region '$($region.regionId)'.notes"
        Assert-Equal $region.differentPixelCount $measuredDifferences[$region.regionId] "$context deterministic region '$($region.regionId)' measured pixel count"
        $measuredResult = if ($measuredDifferences[$region.regionId] -eq 0) { 'exact-match' } else { 'different' }
        Assert-Equal $region.result $measuredResult "$context deterministic region '$($region.regionId)' measured result"
        if ($region.result -eq 'exact-match' -and ($region.differentPixelCount -ne 0 -or $region.classification -ne 'exact-match')) { throw "$context exact region '$($region.regionId)' must have zero differences and exact-match classification." }
        if ($region.result -eq 'different' -and ($region.differentPixelCount -eq 0 -or $region.classification -eq 'exact-match')) { throw "$context different region '$($region.regionId)' needs a nonzero count and non-exact classification." }
        if ($region.classification -eq 'unexplained') { $hasUnexplained = $true }
    }

    $expectedGdiIds = @($Official.metadata.comparison.gdiFontRegions | ForEach-Object regionId | Sort-Object)
    $gdiReview = @(Get-RequiredProperty $item 'gdiFontReview' $context)
    Assert-ComparableEqual @($gdiReview | ForEach-Object regionId | Sort-Object) $expectedGdiIds "$context.gdiFontReview region IDs"
    foreach ($review in $gdiReview) {
        if ($review.classification -notin $classifications) { throw "$context GDI review '$($review.regionId)' has an invalid classification." }
        Assert-NonPlaceholderString $review.notes "$context GDI review '$($review.regionId)'.notes"
        if ($review.classification -eq 'unexplained') { $hasUnexplained = $true }
    }

    $differences = @(Get-RequiredProperty $item 'differences' $context)
    foreach ($difference in $differences) {
        if ($difference.classification -notin $classifications) { throw "$context has an invalid difference classification." }
        Assert-StableId $difference.regionId "$context.differences.regionId"
        Assert-NonPlaceholderString $difference.description "$context.differences.description"
        Assert-NonPlaceholderString $difference.disposition "$context.differences.disposition"
        if ($difference.classification -eq 'unexplained') { $hasUnexplained = $true }
    }
    $unexplainedCount = Get-RequiredProperty $item 'unexplainedDifferenceCount' $context
    if (-not (Test-IntegerValue $unexplainedCount) -or $unexplainedCount -lt 0) { throw "$context.unexplainedDifferenceCount must be nonnegative." }
    if (($unexplainedCount -eq 0) -eq $hasUnexplained) { throw "$context.unexplainedDifferenceCount disagrees with the recorded classifications." }

    $repeat = Get-RequiredProperty $item 'cleanSnapshotReproduction' $context
    Assert-Equal (Get-RequiredProperty $repeat 'required' "$context.cleanSnapshotReproduction") $ReproductionRequired "$context.cleanSnapshotReproduction.required"
    if ($ReproductionRequired) {
        Assert-Equal $repeat.officialMetadata $OfficialReproduction.metadataRelative "$context.cleanSnapshotReproduction.officialMetadata"
        Assert-Equal $repeat.reconstructedMetadata $ReconstructedReproduction.metadataRelative "$context.cleanSnapshotReproduction.reconstructedMetadata"
        if ($repeat.officialResult -notin @('exact-match', 'different') -or $repeat.reconstructedResult -notin @('exact-match', 'different')) { throw "$context clean-snapshot results must be exact-match or different." }
        $officialRepeatCounts = Get-ExactRegionDifferences $Official $OfficialReproduction "$context official clean-snapshot"
        $reconstructedRepeatCounts = Get-ExactRegionDifferences $Reconstructed $ReconstructedReproduction "$context reconstructed clean-snapshot"
        $officialRepeatResult = if (@($officialRepeatCounts.Values | Where-Object { $_ -ne 0 }).Count -eq 0) { 'exact-match' } else { 'different' }
        $reconstructedRepeatResult = if (@($reconstructedRepeatCounts.Values | Where-Object { $_ -ne 0 }).Count -eq 0) { 'exact-match' } else { 'different' }
        Assert-Equal $repeat.officialResult $officialRepeatResult "$context.cleanSnapshotReproduction measured official result"
        Assert-Equal $repeat.reconstructedResult $reconstructedRepeatResult "$context.cleanSnapshotReproduction measured reconstructed result"
    } else {
        if ($null -ne $repeat.officialMetadata -or $null -ne $repeat.reconstructedMetadata -or $repeat.officialResult -ne 'not-required' -or $repeat.reconstructedResult -ne 'not-required') { throw "$context must record the clean-snapshot check as not-required." }
    }
    Assert-NonPlaceholderString (Get-RequiredProperty $item 'comparisonMethod' $context) "$context.comparisonMethod"
    Assert-NonPlaceholderString (Get-RequiredProperty $item 'reviewer' $context) "$context.reviewer"
    Assert-NonPlaceholderString (Get-RequiredProperty $item 'notes' $context) "$context.notes"

    if ($ExpectedStatus -eq 'approved') {
        if ($unexplainedCount -ne 0 -or $hasUnexplained) { throw "$context cannot be approved with an unexplained difference." }
        if ($ReproductionRequired -and ($repeat.officialResult -ne 'exact-match' -or $repeat.reconstructedResult -ne 'exact-match')) { throw "$context cannot be approved until both clean-snapshot repetitions match exactly." }
    }
    return [pscustomobject][ordered]@{ status = $ExpectedStatus; captureId = $Official.captureId; relative = $ComparisonRelative; path = $path; comparison = $item }
}

function Get-OracleState {
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) { throw "Fixture catalog not found: $catalogPath" }
    foreach ($schema in @('capture-metadata.schema.json', 'comparison-metadata.schema.json')) { [void](Get-JsonFile (Join-Path $fixturePath $schema)) }
    $catalog = Get-JsonFile $catalogPath
    Assert-Equal (Get-RequiredProperty $catalog 'schemaVersion' 'catalog') 2 'catalog.schemaVersion'
    $camera = Get-RequiredProperty $catalog 'camera' 'catalog'
    Assert-Equal $camera.projection 'fixed-quarter-view' 'catalog.camera.projection'
    Assert-Equal $camera.rotation 'none' 'catalog.camera.rotation'
    $plan = Get-RequiredProperty $catalog 'capturePlan' 'catalog'
    $direction = Get-RequiredProperty $plan 'directionalAlternative' 'catalog.capturePlan'
    if ($direction.mode -notin @('single', 'split')) { throw "catalog directional mode must be 'single' or 'split'." }
    if ($direction.adequacyDecision -notin @('pending', 'adequate', 'inadequate')) { throw 'catalog directional adequacyDecision is invalid.' }
    if ($direction.mode -eq 'split' -and $direction.adequacyDecision -ne 'inadequate') { throw "Split directional captures require adequacyDecision = 'inadequate'." }

    $oracles = @(
        [pscustomobject]@{ id = $catalog.oraclePolicy.officialRelease.oracleId; renderer = $catalog.oraclePolicy.officialRelease.rendererOracle },
        [pscustomobject]@{ id = $catalog.oraclePolicy.reconstructedLegacy.oracleId; renderer = $catalog.oraclePolicy.reconstructedLegacy.rendererOracle }
    )
    Assert-Equal $oracles[0].id 'official-release' 'catalog official oracle ID'
    Assert-Equal $oracles[0].renderer 'captured-official-release' 'catalog official provenance'
    Assert-Equal $oracles[1].id 'reconstructed-legacy' 'catalog reconstructed oracle ID'
    Assert-Equal $oracles[1].renderer 'captured-reconstructed-legacy' 'catalog reconstructed provenance'

    $repeatIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($id in @($plan.cleanSnapshotReproductionCaptureIds)) { [void]$repeatIds.Add($id) }
    if ($direction.mode -eq 'split') {
        [void]$repeatIds.Remove($direction.singleCaptureId)
        foreach ($id in @($direction.splitCaptureIds)) { [void]$repeatIds.Add($id) }
    }

    $fixtureIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $captureIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $referencedEvidence = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $records = [Collections.Generic.List[object]]::new()
    $comparisonRecords = [Collections.Generic.List[object]]::new()
    $plannedCount = 0

    foreach ($fixture in @($catalog.fixtures)) {
        $fixtureId = Get-RequiredProperty $fixture 'fixtureId' 'catalog.fixture'
        Assert-StableId $fixtureId 'catalog.fixture.fixtureId'
        if (-not $fixtureIds.Add($fixtureId)) { throw "Duplicate fixture ID: $fixtureId" }
        $fixtureStatus = Get-RequiredProperty $fixture 'status' "catalog.fixture/$fixtureId"
        if ($fixtureStatus -notin $validStatuses) { throw "Invalid fixture status for $fixtureId`: $fixtureStatus" }
        $originatingSave = Get-RequiredProperty $fixture 'originatingSave' "catalog.fixture/$fixtureId"
        [void](Get-EvidencePath $originatingSave "catalog.fixture/$fixtureId.originatingSave")
        [void](Get-RequiredProperty $fixture 'provenance' "catalog.fixture/$fixtureId")
        [void](Get-RequiredProperty $fixture 'coverage' "catalog.fixture/$fixtureId")
        $fixtureCaptureStatuses = [Collections.Generic.List[string]]::new()

        foreach ($catalogCapture in @($fixture.captures)) {
            $baseCaptureId = Get-RequiredProperty $catalogCapture 'captureId' "catalog.fixture/$fixtureId.capture"
            $activeCaptureIds = if ($baseCaptureId -eq $direction.singleCaptureId -and $direction.mode -eq 'split') { @($direction.splitCaptureIds) } else { @($baseCaptureId) }
            foreach ($captureId in $activeCaptureIds) {
                Assert-StableId $captureId "catalog.fixture/$fixtureId.captureId"
                if (-not $captureIds.Add($captureId)) { throw "Duplicate capture ID: $captureId" }
                $captureStatus = Get-RequiredProperty $catalogCapture 'status' "catalog.capture/$captureId"
                if ($captureStatus -notin $validStatuses) { throw "Invalid capture status for $captureId`: $captureStatus" }
                $fixtureCaptureStatuses.Add($captureStatus)
                if ($baseCaptureId -eq $direction.singleCaptureId -and $captureStatus -ne 'planned') {
                    if ($direction.mode -eq 'single' -and $direction.adequacyDecision -ne 'adequate') { throw 'Directional capture cannot leave planned state until single-viewport adequacy is recorded as adequate.' }
                    if ($direction.mode -eq 'split' -and $direction.adequacyDecision -ne 'inadequate') { throw 'Split directional capture requires an inadequate single-viewport decision.' }
                }
                if ($captureStatus -eq 'planned') { $plannedCount++; continue }

                $interactionProperty = $plan.interactionModes.PSObject.Properties[$baseCaptureId]
                $interactionMode = if ($null -ne $interactionProperty) { $interactionProperty.Value } else { 'parked' }
                $primary = @{}
                $reproductions = @{}
                foreach ($oracle in $oracles) {
                    $metadataRelative = Expand-CapturePattern $plan.primaryMetadataPattern $oracle.id $captureId
                    $record = Get-ValidatedCaptureMetadata $metadataRelative $fixtureId $captureId $originatingSave $captureStatus 'primary' $oracle.id $oracle.renderer $interactionMode $catalog
                    $records.Add($record); $primary[$oracle.id] = $record
                    foreach ($relative in @($record.metadataRelative, $record.saveRelative, $record.screenshotRelative)) { [void]$referencedEvidence.Add($relative) }
                    foreach ($mask in $record.masks) { [void]$referencedEvidence.Add($mask.relative) }
                    if ($repeatIds.Contains($captureId)) {
                        $repeatRelative = Expand-CapturePattern $plan.reproductionMetadataPattern $oracle.id $captureId
                        $repeatRecord = Get-ValidatedCaptureMetadata $repeatRelative $fixtureId $captureId $originatingSave $captureStatus 'clean-snapshot-reproduction' $oracle.id $oracle.renderer $interactionMode $catalog
                        Assert-ReproductionMatchesPrimary $record $repeatRecord "$oracle.id/$captureId clean-snapshot reproduction"
                        $records.Add($repeatRecord); $reproductions[$oracle.id] = $repeatRecord
                        foreach ($relative in @($repeatRecord.metadataRelative, $repeatRecord.saveRelative, $repeatRecord.screenshotRelative)) { [void]$referencedEvidence.Add($relative) }
                        foreach ($mask in $repeatRecord.masks) { [void]$referencedEvidence.Add($mask.relative) }
                    }
                }
                Assert-CapturePair $primary['official-release'] $primary['reconstructed-legacy'] "$captureId primary pair"
                if ($repeatIds.Contains($captureId)) { Assert-CapturePair $reproductions['official-release'] $reproductions['reconstructed-legacy'] "$captureId reproduction pair" }
                $comparisonRelative = Expand-CapturePattern $plan.comparisonMetadataPattern '' $captureId
                $comparison = Get-ValidatedComparison $comparisonRelative $primary['official-release'] $primary['reconstructed-legacy'] $reproductions['official-release'] $reproductions['reconstructed-legacy'] $repeatIds.Contains($captureId) $captureStatus
                $comparisonRecords.Add($comparison); [void]$referencedEvidence.Add($comparison.relative)
            }
        }

        $nonPlannedCount = @($fixtureCaptureStatuses | Where-Object { $_ -ne 'planned' }).Count
        $approvedCaptureCount = @($fixtureCaptureStatuses | Where-Object { $_ -eq 'approved' }).Count
        if ($fixtureStatus -eq 'planned' -and $nonPlannedCount -ne 0) { throw "Fixture $fixtureId is planned but contains candidate/approved captures." }
        if ($fixtureStatus -eq 'candidate' -and $nonPlannedCount -eq 0) { throw "Fixture $fixtureId is candidate but all captures are planned." }
        if ($fixtureStatus -eq 'approved' -and $approvedCaptureCount -ne $fixtureCaptureStatuses.Count) { throw "Fixture $fixtureId is approved but not every capture is approved." }
    }

    foreach ($requiredRepeat in $repeatIds) {
        if (-not $captureIds.Contains($requiredRepeat)) { throw "Clean-snapshot capture ID is not active in the matrix: $requiredRepeat" }
    }
    foreach ($directory in @('saves', 'screenshots', 'metadata', 'masks', 'comparisons')) {
        foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $fixturePath $directory) -File -Recurse | Where-Object Name -NE 'README.md')) {
            $relative = Get-FixtureRelativePath $file.FullName
            if (-not $referencedEvidence.Contains($relative)) { throw "Uncatalogued evidence file: $relative. Complete both oracle captures and their comparison before changing the catalog status." }
        }
    }
    return [pscustomobject][ordered]@{
        catalog = $catalog; records = @($records); comparisons = @($comparisonRecords)
        fixtureCount = $fixtureIds.Count; captureCount = $captureIds.Count; plannedCount = $plannedCount
        reproductionCaptureCount = $repeatIds.Count
    }
}

function Get-ManifestLines {
    param($Records, $Comparisons)
    $hashes = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $items = [Collections.Generic.List[object]]::new()
    foreach ($record in @($Records | Where-Object status -EQ 'approved')) {
        foreach ($item in @(
            [pscustomobject]@{ relative = $record.saveRelative; path = $record.savePath },
            [pscustomobject]@{ relative = $record.screenshotRelative; path = $record.screenshotPath },
            [pscustomobject]@{ relative = $record.metadataRelative; path = $record.metadataPath }
        ) + @($record.masks)) { $items.Add($item) }
    }
    foreach ($comparison in @($Comparisons | Where-Object status -EQ 'approved')) { $items.Add([pscustomobject]@{ relative = $comparison.relative; path = $comparison.path }) }
    foreach ($item in $items) {
        $hash = (Get-FileHash -LiteralPath $item.path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hashes.ContainsKey($item.relative) -and $hashes[$item.relative] -cne $hash) { throw "Conflicting hashes for approved evidence path: $($item.relative)" }
        $hashes[$item.relative] = $hash
    }
    [string[]] $paths = @($hashes.Keys)
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($path in $paths) { $lines.Add(('{0} *{1}' -f $hashes[$path], $path)) }
    return @($lines)
}

function Test-ApprovedManifest {
    param([string[]] $ExpectedLines)
    if (-not (Test-Path -LiteralPath $approvedManifestPath -PathType Leaf)) {
        throw "Approved evidence manifest is missing: $approvedManifestPath"
    }
    [string[]] $actualLines = @(Get-Content -LiteralPath $approvedManifestPath | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('#', [StringComparison]::Ordinal)
    })
    foreach ($line in $actualLines) {
        if ($line -cnotmatch '^[0-9a-f]{64} \*.+$') {
            throw "Malformed approved manifest line: $line"
        }
    }
    if ($actualLines.Count -ne $ExpectedLines.Count) {
        throw "Approved manifest has $($actualLines.Count) entries; expected $($ExpectedLines.Count). Regenerate it with -Action Manifest."
    }
    for ($i = 0; $i -lt $ExpectedLines.Count; $i++) {
        if ($actualLines[$i] -cne $ExpectedLines[$i]) {
            throw "Approved manifest differs at entry $($i + 1). Regenerate it with -Action Manifest."
        }
    }
}

function Resolve-OutputPath {
    param([string] $RequestedPath)
    if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        return $null
    }
    if ([IO.Path]::IsPathRooted($RequestedPath)) {
        return [IO.Path]::GetFullPath($RequestedPath)
    }
    return [IO.Path]::GetFullPath((Join-Path $root $RequestedPath))
}

function Write-DerivedText {
    param([string] $Text, [string] $RequestedPath)
    $resolvedOutput = Resolve-OutputPath $RequestedPath
    if ($null -eq $resolvedOutput) {
        Write-Output $Text
        return
    }
    $parent = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $parent)) {
        [void][IO.Directory]::CreateDirectory($parent)
    }
    [IO.File]::WriteAllText($resolvedOutput, $Text, [Text.UTF8Encoding]::new($false))
    Write-Output "Wrote $resolvedOutput"
}

if ($Action -eq 'VerifyPng') {
    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        throw '-InputPath is required for -Action VerifyPng.'
    }
    $resolvedInput = if ([IO.Path]::IsPathRooted($InputPath)) {
        [IO.Path]::GetFullPath($InputPath)
    } else {
        [IO.Path]::GetFullPath((Join-Path $root $InputPath))
    }
    if (-not (Test-Path -LiteralPath $resolvedInput -PathType Leaf)) {
        throw "PNG not found: $resolvedInput"
    }
    $pngInfo = Get-PngInfo $resolvedInput
    [pscustomobject][ordered]@{
        path = $resolvedInput
        sha256 = (Get-FileHash -LiteralPath $resolvedInput -Algorithm SHA256).Hash.ToLowerInvariant()
        width = $pngInfo.width
        height = $pngInfo.height
        bitDepth = $pngInfo.bitDepth
        colorType = $pngInfo.colorType
        interlace = $pngInfo.interlace
        chunks = $pngInfo.chunks
        standardLosslessPng = $pngInfo.lossless
    } | ConvertTo-Json -Depth 4
    return
}

if ($Action -eq 'CompareRegions') {
    if ([string]::IsNullOrWhiteSpace($InputPath) -or [string]::IsNullOrWhiteSpace($OtherInputPath)) {
        throw '-InputPath and -OtherInputPath must name two completed capture metadata sidecars for -Action CompareRegions.'
    }
    $metadataPaths = @($InputPath, $OtherInputPath)
    $metadataItems = [Collections.Generic.List[object]]::new()
    foreach ($requested in $metadataPaths) {
        $resolved = if ([IO.Path]::IsPathRooted($requested)) { [IO.Path]::GetFullPath($requested) } else { [IO.Path]::GetFullPath((Join-Path $root $requested)) }
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Metadata not found: $resolved" }
        $metadata = Get-JsonFile $resolved
        $screenshotRelative = Get-RequiredProperty (Get-RequiredProperty $metadata 'capture' $resolved) 'screenshot' "$resolved.capture"
        $screenshotPath = Get-EvidencePath $screenshotRelative "$resolved.capture.screenshot"
        if (-not (Test-Path -LiteralPath $screenshotPath -PathType Leaf)) { throw "Screenshot not found: $screenshotPath" }
        $png = Get-PngInfo $screenshotPath
        $actualHash = (Get-FileHash -LiteralPath $screenshotPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Equal $actualHash $metadata.capture.screenshotSha256 "$resolved screenshot SHA-256"
        $metadataItems.Add([pscustomobject]@{ path = $resolved; metadata = $metadata; screenshot = $screenshotPath; png = $png })
    }
    Assert-Equal $metadataItems[0].metadata.fixtureId $metadataItems[1].metadata.fixtureId 'comparison fixture ID'
    Assert-Equal $metadataItems[0].metadata.captureId $metadataItems[1].metadata.captureId 'comparison capture ID'
    Assert-ComparableEqual $metadataItems[0].metadata.comparison.deterministicRegions $metadataItems[1].metadata.comparison.deterministicRegions 'deterministic region definitions'
    Assert-Equal $metadataItems[0].png.width $metadataItems[1].png.width 'comparison PNG width'
    Assert-Equal $metadataItems[0].png.height $metadataItems[1].png.height 'comparison PNG height'

    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $firstBitmap = [System.Drawing.Bitmap]::new($metadataItems[0].screenshot)
    $secondBitmap = [System.Drawing.Bitmap]::new($metadataItems[1].screenshot)
    try {
        $results = [Collections.Generic.List[object]]::new()
        $totalDifferences = [int64]0
        foreach ($region in @($metadataItems[0].metadata.comparison.deterministicRegions)) {
            Assert-RectangleBounds $region "comparison region $($region.regionId)" $firstBitmap.Width $firstBitmap.Height
            $differentPixels = [int64]0
            $firstDifference = $null
            for ($y = $region.y; $y -lt ($region.y + $region.height); $y++) {
                for ($x = $region.x; $x -lt ($region.x + $region.width); $x++) {
                    if ($firstBitmap.GetPixel($x, $y).ToArgb() -ne $secondBitmap.GetPixel($x, $y).ToArgb()) {
                        $differentPixels++
                        if ($null -eq $firstDifference) { $firstDifference = [pscustomobject]@{ x = $x; y = $y } }
                    }
                }
            }
            $totalDifferences += $differentPixels
            $results.Add([pscustomobject][ordered]@{
                regionId = $region.regionId
                comparedPixelCount = [int64]$region.width * $region.height
                differentPixelCount = $differentPixels
                result = if ($differentPixels -eq 0) { 'exact-match' } else { 'different' }
                firstDifference = $firstDifference
            })
        }
        [pscustomobject][ordered]@{
            schemaVersion = 1
            comparison = 'decoded-pixel-argb-exact'
            fixtureId = $metadataItems[0].metadata.fixtureId
            captureId = $metadataItems[0].metadata.captureId
            firstMetadata = $metadataItems[0].path
            secondMetadata = $metadataItems[1].path
            exactMatch = ($totalDifferences -eq 0)
            totalDifferentPixelCount = $totalDifferences
            deterministicRegions = @($results)
        } | ConvertTo-Json -Depth 8
    } finally {
        $firstBitmap.Dispose()
        $secondBitmap.Dispose()
    }
    return
}

$state = Get-OracleState
$approvedRecords = @($state.records | Where-Object status -EQ 'approved')
$candidateRecords = @($state.records | Where-Object status -EQ 'candidate')
$approvedComparisons = @($state.comparisons | Where-Object status -EQ 'approved')
$candidateComparisons = @($state.comparisons | Where-Object status -EQ 'candidate')
$manifestLines = @(Get-ManifestLines $state.records $state.comparisons)

switch ($Action) {
    'Validate' {
        Test-ApprovedManifest $manifestLines
        Write-Output ("Validated paired renderer-oracle catalog: {0} fixtures, {1} logical captures ({2} planned); {3} capture artifacts and {4} pair comparisons are catalogued." -f
            $state.fixtureCount, $state.captureCount, $state.plannedCount, $state.records.Count, $state.comparisons.Count)
        Write-Output ("Clean-snapshot gate: {0} capture states per oracle; official-release precedence is enforced and approved comparisons cannot contain unexplained differences." -f $state.reproductionCaptureCount)
        Write-Output 'All captured PNGs are structurally valid, CRC-checked standard lossless PNG files.'
        Write-Output "Approved evidence manifest matches $($manifestLines.Count) files."
    }
    'Catalog' {
        $catalogRecords = [Collections.Generic.List[object]]::new()
        foreach ($record in @($state.records | Sort-Object fixtureId, captureId)) {
            $metadata = $record.metadata
            $catalogRecords.Add([pscustomobject][ordered]@{
                fixtureId = $record.fixtureId
                captureId = $record.captureId
                approvalStatus = $record.status
                originatingSave = $record.saveRelative
                saveSha256 = $record.saveHash
                screenshot = $record.screenshotRelative
                screenshotSha256 = $record.screenshotHash
                pngWidth = $record.png.width
                pngHeight = $record.png.height
                pngBitDepth = $record.png.bitDepth
                pngColorType = $record.png.colorType
                oracleId = $record.oracleId
                rendererOracle = $metadata.rendererOracle
                runKind = $record.runKind
                freeTrainRevision = $metadata.freeTrainRevision
                packageKind = $metadata.package.kind
                environmentIdentifier = $metadata.environment.identifier
                graphicsController = $metadata.environment.hypervisor.graphicsController
                guestDisplayDriver = $metadata.environment.hypervisor.guestDisplayDriver
                dayNight = $metadata.state.dayNight
                season = $metadata.state.season
                weather = $metadata.state.weather
                heightCut = $metadata.state.heightCut
                controller = $metadata.state.controller
                metadata = $record.metadataRelative
            })
        }
        $output = [pscustomobject][ordered]@{
            schemaVersion = 2
            fixtureSet = $state.catalog.fixtureSet
            generatedBy = 'eng/renderer-oracle.ps1 -Action Catalog'
            recordCount = $catalogRecords.Count
            logicalCaptureCount = $state.captureCount
            pairComparisonCount = $state.comparisons.Count
            screenshots = @($catalogRecords)
        } | ConvertTo-Json -Depth 8
        Write-DerivedText ($output + [Environment]::NewLine) $OutputPath
    }
    'Manifest' {
        $outputLines = @(
            '# Generated by: eng/renderer-oracle.ps1 -Action Manifest',
            '# Contains every approved save, primary/reproduction screenshot, metadata sidecar, comparison record, and declared mask artifact.'
        ) + $manifestLines
        Write-DerivedText (($outputLines -join [Environment]::NewLine) + [Environment]::NewLine) $OutputPath
    }
}
