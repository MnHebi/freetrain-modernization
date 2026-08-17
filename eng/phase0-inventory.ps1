[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$source = Join-Path $root 'FreeTrain'
$extras = Join-Path $root 'PluginsExtra'

if (-not (Test-Path -LiteralPath (Join-Path $source 'FreeTrain_VS2008.sln'))) {
    throw 'FreeTrain/FreeTrain_VS2008.sln is missing.'
}
if (-not (Test-Path -LiteralPath (Join-Path $source 'lib/DirectDraw.net'))) {
    throw 'FreeTrain/lib/DirectDraw.net is missing.'
}

$projects = @(Get-ChildItem -LiteralPath $source -Recurse -File -Include '*.csproj', '*.vcproj', '*.vcxproj')
$mainFiles = @(Get-ChildItem -LiteralPath $source -Recurse -File)
$extraFiles = @(Get-ChildItem -LiteralPath $extras -Recurse -File)
$solutionText = @(Get-Content -LiteralPath (Join-Path $source 'FreeTrain_VS2008.sln'))

$result = [ordered]@{
    repositoryRoot = $root
    sourceRoot = $source
    gitBranch = (git -C $root branch --show-current)
    pristineTagCommit = (git -C $root rev-list -n 1 'pristine/r389')
    mainTree = [ordered]@{
        files = $mainFiles.Count
        bytes = ($mainFiles | Measure-Object -Property Length -Sum).Sum
        csharpFiles = (@(Get-ChildItem -LiteralPath $source -Recurse -File -Filter '*.cs')).Count
        cppFiles = (@(Get-ChildItem -LiteralPath $source -Recurse -File -Filter '*.cpp')).Count
        headerFiles = (@(Get-ChildItem -LiteralPath $source -Recurse -File -Filter '*.h')).Count
    }
    projects = [ordered]@{
        total = $projects.Count
        csharp = (@($projects | Where-Object Extension -EQ '.csproj')).Count
        vcproj = (@($projects | Where-Object Extension -EQ '.vcproj')).Count
        vcxproj = (@($projects | Where-Object Extension -EQ '.vcxproj')).Count
        solutionEntries = (@($solutionText | Select-String -Pattern '^Project\(')).Count
    }
    plugins = [ordered]@{
        bundledManifests = (@(Get-ChildItem -LiteralPath (Join-Path $source 'plugins') -Recurse -File -Filter 'plugin.xml')).Count
        bundledProjects = (@(Get-ChildItem -LiteralPath (Join-Path $source 'plugins') -Recurse -File -Filter '*.csproj')).Count
        extraFiles = $extraFiles.Count
        extraBytes = ($extraFiles | Measure-Object -Property Length -Sum).Sum
        extraManifests = (@(Get-ChildItem -LiteralPath $extras -Recurse -File -Filter 'plugin.xml')).Count
        extraDlls = (@(Get-ChildItem -LiteralPath $extras -Recurse -File -Filter '*.dll')).Count
    }
    fixtures = [ordered]@{
        legacySaves = (@(Get-ChildItem -LiteralPath $root -Recurse -File -Include '*.ftgd', '*.ftgt')).Count
        midi = (@(Get-ChildItem -LiteralPath $root -Recurse -File -Include '*.mid', '*.midi')).Count
        wave = (@(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.wav')).Count
    }
    tests = [ordered]@{
        knownFrameworkReferences = (@(rg -l -i '\bNUnit\b|\bxUnit\b|Microsoft\.VisualStudio\.TestTools|TestFixture|\[Test\]' $source -g '*.{cs,csproj,sln}' 2>$null)).Count
    }
}

[pscustomobject]$result | ConvertTo-Json -Depth 5
