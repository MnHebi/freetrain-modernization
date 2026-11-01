[CmdletBinding()]
param(
    # Build:  compile XpPrimitiveDump.exe (CLR 2, x86) and list its cases. Host-safe.
    # Stage:  Build, then write the read-only transfer ISO for the XP VM.
    # Verify: check one dump tree's integrity (index, sizes, SHA-256, stray files).
    # Check:  Verify two dump trees and require identical cases, e.g. committed
    #         fixtures against a fresh VM run, or reconstructed against official.
    [ValidateSet('Build', 'Stage', 'Verify', 'Check')]
    [string]$Action = 'Build',
    [string]$PackageRoot = (Join-Path $PSScriptRoot '..\..\.artifacts\legacy-build\current\package\Debug'),
    [string]$OfficialArchive = (Join-Path $PSScriptRoot '..\..\FreeTrain20070604.zip'),
    [string]$BuildRoot = (Join-Path $PSScriptRoot '..\..\.artifacts\xp-primitive-dump'),
    [string]$Path = (Join-Path $PSScriptRoot '..\..\fixtures\xp-primitive-dumps'),
    [string]$OtherPath
)

$ErrorActionPreference = 'Stop'
$BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
$alphaSha = 'B8153302A76F3768528453D18C9025A5017B0B5EA2350F9B3F57A8A2B37F165D'
$officialSha = '70374A836A9F1BC28B16DD65C323FC1B21B4142F10344D19335A65690C16C23D'
$kitFiles = 'DirectDraw.net.dll', 'Interop.DxVBLib.dll', 'Interop.DirectDrawAlphaBlendLib.dll', 'DirectDraw.AlphaBlend.dll'

function Invoke-Build {
    $pkg = (Resolve-Path $PackageRoot).Path
    $bin = Join-Path $BuildRoot 'bin'
    New-Item -ItemType Directory -Force $bin | Out-Null
    $exe = Join-Path $bin 'XpPrimitiveDump.exe'
    # The v3.5 compiler runs on CLR 2 and references the v2.0.50727 framework,
    # which is what the XP guest has (phase1d-dotnet35sp1-prerequisite.md).
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v3.5\csc.exe'
    if (-not (Test-Path $csc)) { throw "Missing $csc (enable .NET Framework 3.5 on the host)." }
    & $csc /nologo /platform:x86 /target:exe /optimize- "/out:$exe" `
        "/reference:$(Join-Path $pkg 'DirectDraw.net.dll')" `
        "/reference:$(Join-Path $pkg 'Interop.DxVBLib.dll')" `
        "/reference:$(Join-Path $pkg 'Interop.DirectDrawAlphaBlendLib.dll')" `
        /reference:System.Drawing.dll /reference:System.Windows.Forms.dll `
        (Join-Path $PSScriptRoot 'XpPrimitiveDump.cs')
    if ($LASTEXITCODE -ne 0) { throw 'XpPrimitiveDump compilation failed.' }
    Copy-Item (Join-Path $PSScriptRoot 'XpPrimitiveDump.exe.config') "$exe.config" -Force
    # `list` touches no DirectDraw type; it proves the binary starts on CLR 2.
    $cases = & $exe list
    if ($LASTEXITCODE -ne 0) { throw 'XpPrimitiveDump list failed.' }
    Write-Host "Built $exe ($(@($cases).Count) cases)."
    $exe
}

function Copy-KitFiles([string]$from, [string]$to) {
    New-Item -ItemType Directory -Force $to | Out-Null
    foreach ($f in $kitFiles) { Copy-Item (Join-Path $from $f) $to -Force }
    if ((Get-FileHash -Algorithm SHA256 (Join-Path $to 'DirectDraw.AlphaBlend.dll')).Hash -ne $alphaSha) {
        throw "Unexpected DirectDraw.AlphaBlend.dll hash in $from."
    }
}

# ISO 9660 + Joliet image through the in-box IMAPI2 COM API (no admin, no tools).
function New-Iso([string]$folder, [string]$iso) {
    if (-not ('XpDumpIso' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices.ComTypes;
public static class XpDumpIso {
    public static void Save(object stream, string path) {
        IStream s = (IStream)stream;
        byte[] buf = new byte[65536];
        IntPtr read = System.Runtime.InteropServices.Marshal.AllocHGlobal(4);
        try {
            using (FileStream o = File.Create(path)) {
                while (true) {
                    s.Read(buf, buf.Length, read);
                    int n = System.Runtime.InteropServices.Marshal.ReadInt32(read);
                    if (n <= 0) break;
                    o.Write(buf, 0, n);
                }
            }
        } finally { System.Runtime.InteropServices.Marshal.FreeHGlobal(read); }
    }
}
'@
    }
    $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    $fsi.FileSystemsToCreate = 3
    $fsi.VolumeName = 'FTXPDUMP'
    $fsi.Root.AddTree($folder, $false)
    [XpDumpIso]::Save($fsi.CreateResultImage().ImageStream, $iso)
}

function Invoke-Stage {
    $exe = Invoke-Build
    $kit = Join-Path $BuildRoot 'kit'
    if (Test-Path $kit) { Remove-Item -Recurse -Force $kit }
    New-Item -ItemType Directory -Force (Join-Path $kit 'tool') | Out-Null
    Copy-Item $exe, "$exe.config" (Join-Path $kit 'tool')
    Copy-KitFiles (Resolve-Path $PackageRoot).Path (Join-Path $kit 'reconstructed')

    $archive = (Resolve-Path $OfficialArchive).Path
    if ((Get-FileHash -Algorithm SHA256 $archive).Hash -ne $officialSha) { throw "Unexpected official archive hash: $archive" }
    $tmp = Join-Path $BuildRoot 'official-extract'
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    New-Item -ItemType Directory -Force $tmp | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach ($f in $kitFiles) {
            $entry = $zip.GetEntry("FreeTrain/$f")
            if (-not $entry) { throw "FreeTrain/$f missing from the official archive." }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $tmp $f))
        }
    } finally { $zip.Dispose() }
    Copy-KitFiles $tmp (Join-Path $kit 'official')

    $sums = Get-ChildItem -Recurse -File $kit | Sort-Object FullName | ForEach-Object {
        '{0}  {1}' -f (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLowerInvariant(), $_.FullName.Substring($kit.Length + 1)
    }
    [IO.File]::WriteAllLines((Join-Path $kit 'SHA256SUMS.txt'), [string[]]$sums)
    $iso = Join-Path $BuildRoot 'xp-primitive-dump-kit.iso'
    if (Test-Path $iso) { Remove-Item -Force $iso }
    New-Iso $kit $iso
    Write-Host "Staged $iso"
    Write-Host "SHA-256 $((Get-FileHash -Algorithm SHA256 $iso).Hash)"
    $sums | ForEach-Object { Write-Host "  $_" }
}

# Returns @{ <relative dir> = parsed index } for every index.json under $root.
function Read-Tree([string]$root, [System.Collections.Generic.List[string]]$failures) {
    $root = (Resolve-Path $root).Path
    $tree = @{}
    foreach ($ix in Get-ChildItem -Recurse -File -Filter index.json $root) {
        $dir = $ix.DirectoryName
        $rel = if ($dir.Length -gt $root.Length) { $dir.Substring($root.Length + 1) } else { '.' }
        $index = [IO.File]::ReadAllText($ix.FullName) | ConvertFrom-Json
        $tree[$rel] = @{ Dir = $dir; Index = $index }
        if ($index.provenance -ne 'captured-legacy-dump') { $failures.Add("${rel}: provenance is '$($index.provenance)'") }
        $ids = @{}
        foreach ($c in $index.cases) {
            if ($ids.ContainsKey($c.id)) { $failures.Add("${rel}: duplicate case $($c.id)") }
            $ids[$c.id] = $true
            if ($c.error -like 'harness:*') { $failures.Add("${rel}/$($c.id): $($c.error)"); continue }
            $bin = Join-Path $dir "$($c.id).bin"
            if (-not (Test-Path $bin)) { $failures.Add("${rel}/$($c.id): missing .bin"); continue }
            $size = 0; foreach ($b in $c.blocks) { $size += [int]$b[1] }
            if ((Get-Item $bin).Length -ne $size) { $failures.Add("${rel}/$($c.id): size $((Get-Item $bin).Length), blocks say $size") }
            if ((Get-FileHash -Algorithm SHA256 $bin).Hash.ToLowerInvariant() -ne $c.sha256) { $failures.Add("${rel}/$($c.id): SHA-256 mismatch") }
        }
        foreach ($f in Get-ChildItem -File $dir) {
            if ($f.Name -eq 'index.json') { continue }
            if ($f.Extension -ne '.bin' -or -not $ids.ContainsKey($f.BaseName)) { $failures.Add("${rel}: stray file $($f.Name)") }
        }
    }
    if ($tree.Count -eq 0) { $failures.Add("no index.json under $root") }
    $tree
}

# First differing byte of two case files, named by block.
function Get-FirstDifference([string]$a, [string]$b, $blocks) {
    $x = [IO.File]::ReadAllBytes($a); $y = [IO.File]::ReadAllBytes($b)
    $n = [Math]::Min($x.Length, $y.Length)
    for ($i = 0; $i -lt $n; $i++) { if ($x[$i] -ne $y[$i]) { break } }
    if ($i -eq $n -and $x.Length -eq $y.Length) { return 'bytes identical' }
    $offset = $i
    foreach ($blk in $blocks) {
        if ($offset -lt [int]$blk[1]) { return "first difference in block '$($blk[0])' at byte $offset" }
        $offset -= [int]$blk[1]
    }
    "lengths differ ($($x.Length) vs $($y.Length))"
}

function Compare-Trees($left, $right, [System.Collections.Generic.List[string]]$failures) {
    foreach ($rel in @($left.Keys) + @($right.Keys) | Sort-Object -Unique) {
        if (-not $left.ContainsKey($rel)) { $failures.Add("${rel}: only in -OtherPath"); continue }
        if (-not $right.ContainsKey($rel)) { $failures.Add("${rel}: only in -Path"); continue }
        $l = $left[$rel]; $r = $right[$rel]
        # Package identity legitimately differs; everything that describes behavior must not.
        foreach ($p in 'pixelMode', 'access', 'layout') {
            if ($l.Index.$p -ne $r.Index.$p) { $failures.Add("${rel}: $p '$($l.Index.$p)' vs '$($r.Index.$p)'") }
        }
        if (($l.Index.pixelFormat | ConvertTo-Json -Compress) -ne ($r.Index.pixelFormat | ConvertTo-Json -Compress)) { $failures.Add("${rel}: pixelFormat differs") }
        $rc = @{}; foreach ($c in $r.Index.cases) { $rc[$c.id] = $c }
        $lc = @{}; foreach ($c in $l.Index.cases) { $lc[$c.id] = $c }
        foreach ($c in $l.Index.cases) {
            if (-not $rc.ContainsKey($c.id)) { $failures.Add("${rel}/$($c.id): only in -Path"); continue }
            $o = $rc[$c.id]
            $diff = @()
            foreach ($prop in @($c.PSObject.Properties.Name) + @($o.PSObject.Properties.Name) | Sort-Object -Unique) {
                if ((ConvertTo-Json -Compress -Depth 8 $c.$prop) -ne (ConvertTo-Json -Compress -Depth 8 $o.$prop)) { $diff += $prop }
            }
            if ($diff.Count -eq 0) { continue }
            $detail = ''
            if ($diff -contains 'sha256') {
                $detail = ' (' + (Get-FirstDifference (Join-Path $l.Dir "$($c.id).bin") (Join-Path $r.Dir "$($c.id).bin") $c.blocks) + ')'
            }
            $failures.Add("${rel}/$($c.id): differs in $($diff -join ', ')$detail")
        }
        foreach ($c in $r.Index.cases) { if (-not $lc.ContainsKey($c.id)) { $failures.Add("${rel}/$($c.id): only in -OtherPath") } }
    }
}

function Write-Result([string]$what, [System.Collections.Generic.List[string]]$failures) {
    if ($failures.Count -eq 0) { Write-Host "$what passed."; return }
    $failures | ForEach-Object { Write-Host "  FAIL $_" }
    throw "$what failed with $($failures.Count) finding(s)."
}

switch ($Action) {
    'Build' { Invoke-Build | Out-Null }
    'Stage' { Invoke-Stage }
    'Verify' {
        $failures = New-Object System.Collections.Generic.List[string]
        $tree = Read-Tree $Path $failures
        Write-Host "$($tree.Count) dump(s) under $Path."
        Write-Result 'Verify' $failures
    }
    'Check' {
        if (-not $OtherPath) { throw 'Check needs -OtherPath (the fresh dump tree to compare against -Path).' }
        $failures = New-Object System.Collections.Generic.List[string]
        $left = Read-Tree $Path $failures
        $right = Read-Tree $OtherPath $failures
        Compare-Trees $left $right $failures
        Write-Host "Compared $($left.Count) dump(s) under $Path with $($right.Count) under $OtherPath."
        Write-Result 'Check' $failures
    }
}
