[CmdletBinding()]
param(
    [ValidateSet('Validate', 'Compare')]
    [string] $Action = 'Validate',

    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot),

    [string] $FixtureRoot = 'fixtures/renderer-oracle',

    # Validate: fail if any catalogued capture or reproduction is still missing.
    [switch] $RequireComplete,

    # Compare: two sidecars; each PNG is the sidecar's sibling with the same stem.
    [string] $InputPath,

    [string] $OtherInputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
public static class RegionDiff {
    public static int Count(byte[] a, byte[] b, int stride, int x, int y, int w, int h) {
        int n = 0;
        for (int row = y; row < y + h; row++)
            for (int i = row * stride + x * 4, end = i + w * 4; i < end; i += 4)
                if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] || a[i + 3] != b[i + 3]) n++;
        return n;
    }
}
'@

$fixturePath = if ([IO.Path]::IsPathRooted($FixtureRoot)) { $FixtureRoot } else { Join-Path $RepositoryRoot $FixtureRoot }
$fixturePath = (Resolve-Path -LiteralPath $fixturePath).Path
$errors = New-Object System.Collections.Generic.List[string]

function Get-Sha256([string] $Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }

# Decodes a PNG to 32bpp ARGB bytes without holding a lock on the file. System.Drawing
# also decodes BMP, JPEG, GIF, and TIFF, so require the PNG signature and decoder.
function Read-Png([string] $Path) {
    $raw = [IO.File]::ReadAllBytes($Path)
    $signature = [byte[]] (0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    if ($raw.Length -lt 8 -or (Compare-Object $signature $raw[0..7] -SyncWindow 0)) { throw 'file does not start with the PNG signature' }
    $stream = New-Object IO.MemoryStream (, $raw)
    $bitmap = New-Object Drawing.Bitmap $stream
    try {
        if ($bitmap.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid) { throw 'decoder did not identify the file as PNG' }
        $rect = New-Object Drawing.Rectangle 0, 0, $bitmap.Width, $bitmap.Height
        $data = $bitmap.LockBits($rect, [Drawing.Imaging.ImageLockMode]::ReadOnly, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $bytes = New-Object byte[] ($data.Stride * $data.Height)
        [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
        $bitmap.UnlockBits($data)
        [pscustomobject]@{ Width = $bitmap.Width; Height = $bitmap.Height; Stride = $data.Stride; Bytes = $bytes }
    } finally { $bitmap.Dispose(); $stream.Dispose() }
}

function Get-Regions($Sidecar, [string] $Name) {
    $property = $Sidecar.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return @() }
    @($property.Value)
}

# Checks one sidecar/PNG pair; returns the decoded image, or $null after recording errors.
function Test-Capture([string] $Label, [string] $JsonPath, [string] $PngPath, $Capture) {
    $before = $errors.Count
    $sidecar = Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
    foreach ($field in 'captureId', 'save', 'saveSha256', 'screenshotSha256', 'view', 'exactRegions') {
        if ($null -eq $sidecar.PSObject.Properties[$field]) { $errors.Add("${Label}: missing '$field'.") }
    }
    if ($errors.Count -gt $before) { return $null }
    if ($sidecar.captureId -ne $Capture.id) { $errors.Add("${Label}: captureId '$($sidecar.captureId)' does not match '$($Capture.id)'.") }
    if ($sidecar.save -ne $Capture.save) { $errors.Add("${Label}: save '$($sidecar.save)' does not match catalog '$($Capture.save)'.") }

    $savePath = Join-Path $fixturePath "saves/$($Capture.save).ftgd"
    if (-not (Test-Path -LiteralPath $savePath)) { $errors.Add("${Label}: save file saves/$($Capture.save).ftgd is missing.") }
    elseif ((Get-Sha256 $savePath) -ne $sidecar.saveSha256) { $errors.Add("${Label}: save hash does not match saves/$($Capture.save).ftgd.") }
    if ((Get-Sha256 $PngPath) -ne $sidecar.screenshotSha256) { $errors.Add("${Label}: screenshot hash does not match.") }

    try { $image = Read-Png $PngPath } catch { $errors.Add("${Label}: not a valid PNG: $($_.Exception.Message)"); return $null }
    if ($image.Width -ne $catalog.display.width -or $image.Height -ne $catalog.display.height) {
        $errors.Add("${Label}: image is $($image.Width)x$($image.Height), catalog requires $($catalog.display.width)x$($catalog.display.height).")
    }

    $exact = @(Get-Regions $sidecar 'exactRegions')
    if ($exact.Count -eq 0) { $errors.Add("${Label}: no exact regions.") }
    $ids = @{}
    foreach ($region in $exact + @(Get-Regions $sidecar 'reviewRegions')) {
        if ($ids.ContainsKey([string] $region.id)) { $errors.Add("${Label}: duplicate region id '$($region.id)'.") }
        $ids[[string] $region.id] = $true
        if ($region.width -le 0 -or $region.height -le 0 -or $region.x -lt 0 -or $region.y -lt 0 -or
            $region.x + $region.width -gt $image.Width -or $region.y + $region.height -gt $image.Height) {
            $errors.Add("${Label}: region '$($region.id)' is empty or outside the image.")
        }
    }
    if ($errors.Count -gt $before) { return $null }
    [pscustomobject]@{ Sidecar = $sidecar; Image = $image }
}

function Compare-Regions($A, $B) {
    foreach ($region in $A.Sidecar.exactRegions) {
        $other = @($B.Sidecar.exactRegions | Where-Object { $_.id -eq $region.id })
        if ($other.Count -ne 1 -or ($other[0] | ConvertTo-Json -Compress) -ne ($region | ConvertTo-Json -Compress)) {
            [pscustomobject]@{ Region = $region.id; Pixels = $region.width * $region.height; Differing = $null; Note = 'rectangle differs or is absent' }
            continue
        }
        $diff = [RegionDiff]::Count($A.Image.Bytes, $B.Image.Bytes, $A.Image.Stride, $region.x, $region.y, $region.width, $region.height)
        [pscustomobject]@{ Region = $region.id; Pixels = $region.width * $region.height; Differing = $diff; Note = '' }
    }
}

$catalog = Get-Content -Raw -LiteralPath (Join-Path $fixturePath 'catalog.json') | ConvertFrom-Json

if ($Action -eq 'Compare') {
    if (-not $InputPath -or -not $OtherInputPath) { throw 'Compare requires -InputPath and -OtherInputPath.' }
    $sides = foreach ($path in $InputPath, $OtherInputPath) {
        $json = (Resolve-Path -LiteralPath $path).Path
        $sidecar = Get-Content -Raw -LiteralPath $json | ConvertFrom-Json
        [pscustomobject]@{ Sidecar = $sidecar; Image = Read-Png ([IO.Path]::ChangeExtension($json, '.png')) }
    }
    if ($sides[0].Image.Width -ne $sides[1].Image.Width -or $sides[0].Image.Height -ne $sides[1].Image.Height) { throw 'Images differ in size.' }
    Compare-Regions $sides[0] $sides[1] | Format-Table -AutoSize
    return
}

# Validate.
$captures = @{}
foreach ($capture in $catalog.captures) {
    if ($captures.ContainsKey($capture.id)) { $errors.Add("catalog: duplicate capture '$($capture.id)'.") }
    if ($catalog.saves -notcontains $capture.save) { $errors.Add("catalog: capture '$($capture.id)' uses undeclared save '$($capture.save)'.") }
    $captures[$capture.id] = $capture
}
foreach ($id in $catalog.reproductions) { if (-not $captures.ContainsKey($id)) { $errors.Add("catalog: reproduction '$id' is not a capture.") } }

# Every file must be expected; READMEs are documentation.
$expected = @{ 'catalog.json' = $true; 'environment.json' = $true }
foreach ($save in $catalog.saves) { $expected["saves/$save.ftgd"] = $true }
foreach ($id in $captures.Keys) { $expected["screenshots/$id.png"] = $true; $expected["screenshots/$id.json"] = $true }
foreach ($id in $catalog.reproductions) { $expected["reproduction/$id.png"] = $true; $expected["reproduction/$id.json"] = $true }
foreach ($file in Get-ChildItem -LiteralPath $fixturePath -Recurse -File) {
    $relative = $file.FullName.Substring($fixturePath.Length + 1).Replace('\', '/')
    if ($file.Name -ne 'README.md' -and -not $expected.ContainsKey($relative)) { $errors.Add("uncatalogued file: $relative") }
}

$present = @{}
$pending = New-Object System.Collections.Generic.List[string]
$saveHashes = @{}
foreach ($kind in 'screenshots', 'reproduction') {
    $ids = if ($kind -eq 'screenshots') { $catalog.captures | ForEach-Object id } else { $catalog.reproductions }
    foreach ($id in $ids) {
        $json = Join-Path $fixturePath "$kind/$id.json"; $png = Join-Path $fixturePath "$kind/$id.png"
        $haveJson = Test-Path -LiteralPath $json; $havePng = Test-Path -LiteralPath $png
        if (-not $haveJson -and -not $havePng) { $pending.Add("$kind/$id"); continue }
        if ($haveJson -ne $havePng) { $errors.Add("$kind/${id}: PNG and sidecar must be added together."); continue }
        $result = Test-Capture "$kind/$id" $json $png $captures[$id]
        if ($null -eq $result) { continue }
        $present["$kind/$id"] = $result
        $save = $captures[$id].save
        if ($saveHashes.ContainsKey($save) -and $saveHashes[$save] -ne $result.Sidecar.saveSha256) { $errors.Add("$kind/${id}: save '$save' hash differs from another capture of the same save.") }
        $saveHashes[$save] = $result.Sidecar.saveSha256
    }
}

foreach ($id in $catalog.reproductions) {
    $primary = $present["screenshots/$id"]; $repro = $present["reproduction/$id"]
    if ($null -eq $primary -or $null -eq $repro) { continue }
    if (($primary.Sidecar.view | ConvertTo-Json -Compress -Depth 5) -ne ($repro.Sidecar.view | ConvertTo-Json -Compress -Depth 5)) { $errors.Add("reproduction/${id}: view state differs from the primary.") }
    foreach ($row in Compare-Regions $primary $repro) {
        if ($row.Differing -ne 0) { $errors.Add("reproduction/${id}: region '$($row.Region)' $(if ($null -eq $row.Differing) { $row.Note } else { "has $($row.Differing) differing pixels" }).") }
    }
}

if ($present.Count -gt 0) {
    $envPath = Join-Path $fixturePath 'environment.json'
    if (-not (Test-Path -LiteralPath $envPath)) { $errors.Add('environment.json is required once any capture exists.') }
    else {
        $environment = Get-Content -Raw -LiteralPath $envPath | ConvertFrom-Json
        foreach ($field in 'guest', 'clr', 'ddrawVersion', 'ddrawSha256', 'dx8vbVersion', 'dx8vbSha256', 'virtualBox', 'graphicsController', 'displayMode') {
            $property = $environment.PSObject.Properties[$field]
            if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string] $property.Value)) { $errors.Add("environment.json: '$field' is missing or empty.") }
        }
    }
}

if ($RequireComplete) { foreach ($item in $pending) { $errors.Add("missing: $item") } }
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "FAIL $_" }
    throw "Renderer oracle validation failed with $($errors.Count) error(s)."
}
Write-Output ("Validated {0} capture(s) + {1} reproduction(s): {2} present, {3} pending." -f
    $catalog.captures.Count, @($catalog.reproductions).Count, $present.Count, $pending.Count)
