#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [switch]$Json,
    [string]$Slug,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Description
)
$ErrorActionPreference = 'Stop'

function Find-RepositoryRoot {
    param(
        [string]$StartDir,
        [string[]]$Markers = @('.git', '.specify')
    )
    $current = Resolve-Path $StartDir
    while ($true) {
        foreach ($marker in $Markers) {
            if (Test-Path (Join-Path $current $marker)) {
                return $current
            }
        }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) {
            return $null
        }
        $current = $parent
    }
}

function Get-CurrentFeatureBranch {
    param([string]$RepoRoot)

    if ($env:SPECIFY_FEATURE) {
        return $env:SPECIFY_FEATURE
    }

    try {
        $branch = git rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $branch) {
            return $branch.Trim()
        }
    } catch {}

    $specsDir = Join-Path $RepoRoot 'specs'
    if (Test-Path $specsDir) {
        $latest = Get-ChildItem -Path $specsDir -Directory |
            ForEach-Object {
                if ($_.Name -match '^(\d{3})-') {
                    [pscustomobject]@{
                        Name   = $_.Name
                        Number = [int]$matches[1]
                    }
                }
            } |
            Sort-Object -Property Number -Descending |
            Select-Object -First 1
        if ($latest) {
            return $latest.Name
        }
    }

    return 'main'
}

function Get-FeatureDirectoryByPrefix {
    param(
        [string]$RepoRoot,
        [string]$BranchName
    )

    $specsDir = Join-Path $RepoRoot 'specs'
    if ($BranchName -match '^(\d{3})-') {
        $prefix = $matches[1]
        if (Test-Path $specsDir) {
            $matchesList = Get-ChildItem -Path $specsDir -Directory |
                Where-Object { $_.Name -like "$prefix-*" }
            if ($matchesList.Count -eq 1) {
                return $matchesList[0].FullName
            }
        }
    }

    return Join-Path $specsDir $BranchName
}

function New-TinySlug {
    param([string]$Value)
    if (-not $Value) {
        return ''
    }
    return ($Value.ToLowerInvariant() -replace '[^a-z0-9]+','-' -replace '^-+','' -replace '-+$','')
}

$descText = ($Description -join ' ').Trim()

$fallbackRoot = Find-RepositoryRoot -StartDir $PSScriptRoot
if (-not $fallbackRoot) {
    throw "Could not determine repository root."
}

try {
    $repoRoot = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $repoRoot) {
        throw 'git not available'
    }
} catch {
    $repoRoot = $fallbackRoot
}

$repoRoot = Resolve-Path $repoRoot
$currentBranch = Get-CurrentFeatureBranch -RepoRoot $repoRoot
$featureDir = Get-FeatureDirectoryByPrefix -RepoRoot $repoRoot -BranchName $currentBranch

if (-not (Test-Path $featureDir)) {
    throw "Feature directory not found: $featureDir"
}

$slug = New-TinySlug -Value $Slug
if (-not $slug) {
    $slug = New-TinySlug -Value $descText
}
if (-not $slug) {
    $slug = "tiny-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
}

$tinyDir = Join-Path $featureDir 'tiny-specs'
New-Item -ItemType Directory -Path $tinyDir -Force | Out-Null

$filePath = Join-Path $tinyDir "$slug.md"
$counter = 2
while (Test-Path $filePath) {
    $filePath = Join-Path $tinyDir "$slug-$counter.md"
    $counter += 1
}

$template = Join-Path $repoRoot '.specify/templates/tiny-spec-template.md'
if (Test-Path $template) {
    Copy-Item -LiteralPath $template -Destination $filePath -Force
} else {
    @('# Tiny Spec','', 'Describe the quick fix or enhancement here.') | Set-Content -Path $filePath
}

$env:SPECIFY_FEATURE = $currentBranch

if ($Json) {
    [pscustomobject]@{
        TINY_SPEC   = $filePath
        SLUG        = $slug
        FEATURE_DIR = $featureDir
        BRANCH      = $currentBranch
    } | ConvertTo-Json -Compress
} else {
    Write-Output "Tiny spec file: $filePath"
    Write-Output "Slug: $slug"
    Write-Output "Feature directory: $featureDir"
    Write-Output "Branch: $currentBranch"
}
