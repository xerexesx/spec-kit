#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [switch]$Json,
    [string]$Targets = 'spec',
    [switch]$ClarifyOnly,
    [switch]$SkipChecklists,
    [switch]$NoBackup,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Notes
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
    } catch {
        # ignore
    }

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

function Resolve-Targets {
    param([string]$Raw = 'spec')

    $valid = @('spec', 'plan', 'tasks')
    $tokens = ($Raw -replace ',', ' ') -split '\s+' | Where-Object { $_ -and $_.Trim().Length -gt 0 }
    $results = New-Object System.Collections.Generic.List[string]

    foreach ($token in $tokens) {
        $value = $token.Trim().ToLowerInvariant()
        if ($value -eq 'all') {
            return @('spec', 'plan', 'tasks')
        }
        if ($valid -contains $value) {
            if (-not $results.Contains($value)) {
                $null = $results.Add($value)
            }
        } else {
            throw "Unknown target '$token'. Allowed values: spec, plan, tasks, all."
        }
    }

    if ($results.Count -eq 0) {
        $null = $results.Add('spec')
    }

    return $results.ToArray()
}

$fallbackRoot = Find-RepositoryRoot -StartDir $PSScriptRoot
if (-not $fallbackRoot) {
    throw "Could not determine repository root."
}

try {
    $repoRoot = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $repoRoot) {
        throw 'git not available'
    }
    $hasGit = $true
} catch {
    $repoRoot = $fallbackRoot
    $hasGit = $false
}

$repoRoot = Resolve-Path $repoRoot
$specsDir = Join-Path $repoRoot 'specs'
$currentBranch = Get-CurrentFeatureBranch -RepoRoot $repoRoot
$featureDir = Get-FeatureDirectoryByPrefix -RepoRoot $repoRoot -BranchName $currentBranch

if (-not (Test-Path $featureDir)) {
    throw "Feature directory not found: $featureDir"
}

$specFile = Join-Path $featureDir 'spec.md'
$planFile = Join-Path $featureDir 'plan.md'
$tasksFile = Join-Path $featureDir 'tasks.md'

if (-not (Test-Path $specFile)) {
    throw "spec.md not found in $featureDir. Run /speckit.specify first."
}

$targets = Resolve-Targets -Raw $Targets
$files = [ordered]@{
    spec  = $specFile
    plan  = $planFile
    tasks = $tasksFile
}

$missing = @()
foreach ($target in $targets) {
    $path = $files[$target]
    if (-not (Test-Path $path)) {
        $missing += $target
    }
}

if ($missing.Count -gt 0) {
    foreach ($item in $missing) {
        switch ($item) {
            'spec'  { Write-Error "spec.md missing; run /speckit.specify first." }
            'plan'  { Write-Error "plan.md missing; run /speckit.plan before targeting plan updates." }
            'tasks' { Write-Error "tasks.md missing; run /speckit.tasks before targeting tasks." }
        }
    }
    exit 1
}

$backups = @()
if (-not $NoBackup) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    foreach ($target in $targets) {
        $path = $files[$target]
        if (Test-Path $path) {
            $backup = "$path.bak.$timestamp"
            Copy-Item -LiteralPath $path -Destination $backup -Force
            $backups += $backup
        }
    }
}

$env:SPECIFY_FEATURE = $currentBranch

if ($Json) {
    $result = [ordered]@{
        FEATURE_DIR    = $featureDir
        BRANCH         = $currentBranch
        TARGETS        = $targets
        FILES          = @{}
        BACKUPS        = $backups
        CLARIFY_ONLY   = [bool]$ClarifyOnly
        SKIP_CHECKLISTS = [bool]$SkipChecklists
    }
    foreach ($target in $targets) {
        $result.FILES[$target] = $files[$target]
    }
    $result | ConvertTo-Json -Depth 4 -Compress
} else {
    Write-Output "Feature directory: $featureDir"
    Write-Output "Branch: $currentBranch"
    Write-Output "Targets: $($targets -join ', ')"
    Write-Output "Clarify only: $ClarifyOnly"
    Write-Output "Skip checklists: $SkipChecklists"
    if ($NoBackup) {
        Write-Output "Backups: skipped (-NoBackup)"
    } elseif ($backups.Count -eq 0) {
        Write-Output "Backups: none created"
    } else {
        Write-Output "Backups:"
        foreach ($item in $backups) {
            Write-Output "  - $item"
        }
    }
}
