[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $ManifestPath = 'docs/modernization/pristine-r389-files.sha256'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$manifest = if ([IO.Path]::IsPathRooted($ManifestPath)) {
    $ManifestPath
} else {
    Join-Path $root $ManifestPath
}

if (-not (Test-Path -LiteralPath $manifest)) {
    throw "Manifest not found: $manifest"
}

$checked = 0
$failures = [Collections.Generic.List[string]]::new()

foreach ($line in Get-Content -LiteralPath $manifest) {
    if ($line -notmatch '^([0-9a-f]{64}) \*(.+)$') {
        throw "Malformed manifest line: $line"
    }

    $expected = $Matches[1]
    $relative = $Matches[2].Replace('/', [IO.Path]::DirectorySeparatorChar)
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("missing: $relative")
        continue
    }

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        $failures.Add("changed: $relative")
    }
    $checked++
}

if ($failures.Count -ne 0) {
    $failures | Write-Error
    throw "$($failures.Count) pristine file verification failure(s)."
}

Write-Output "Verified $checked files against $manifest"
