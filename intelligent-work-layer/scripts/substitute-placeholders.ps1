<#
.SYNOPSIS
    Substitutes deployment placeholders in Copilot Studio topic YAML files.

.DESCRIPTION
    Reads copilot-studio/deployment-placeholders.json and replaces all
    {{PLACEHOLDER_NAME}} tokens in *.topic.mcs.yml files with the corresponding
    GUID values from the JSON mapping.

    Supports three modes:
      - Default: Perform substitution (replaces {{TOKEN}} → GUID)
      - -WhatIf:  Dry-run showing what would be substituted without modifying files
      - -Revert:  Restores original {{PLACEHOLDER_NAME}} tokens from the JSON keys

    Exit codes:
      0 = Success (or WhatIf completed)
      1 = Placeholder file not found or invalid
      2 = Empty placeholder values detected (non-Revert mode)
      3 = Substitution errors occurred

.PARAMETER PlaceholderFile
    Path to the deployment-placeholders.json file.
    Default: ../copilot-studio/deployment-placeholders.json (relative to script directory)

.PARAMETER TopicDir
    Directory containing *.topic.mcs.yml files to process.
    Default: ../copilot-studio/topics (relative to script directory)

.PARAMETER Revert
    Restores {{PLACEHOLDER_NAME}} tokens by reversing GUID → {{TOKEN}} using
    the values currently in the placeholder JSON.

.PARAMETER WhatIf
    Shows what substitutions would be performed without modifying any files.

.EXAMPLE
    .\substitute-placeholders.ps1
    # Substitute all placeholders using the default JSON and topic directory.

.EXAMPLE
    .\substitute-placeholders.ps1 -WhatIf
    # Preview substitutions without modifying files.

.EXAMPLE
    .\substitute-placeholders.ps1 -Revert
    # Restore {{PLACEHOLDER}} tokens from current GUID values.

.EXAMPLE
    .\substitute-placeholders.ps1 -PlaceholderFile ".\my-env.json" -TopicDir ".\topics"
    # Use custom paths.
#>

param(
    [string]$PlaceholderFile = (Join-Path $PSScriptRoot ".." "copilot-studio" "deployment-placeholders.json"),

    [string]$TopicDir = (Join-Path $PSScriptRoot ".." "copilot-studio" "topics"),

    [switch]$Revert,

    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# ─────────────────────────────────────
# 0. Banner
# ─────────────────────────────────────
Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  IWL — Placeholder Substitution                    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "  ⚡ DRY-RUN MODE — no files will be modified`n" -ForegroundColor Yellow
}
if ($Revert) {
    Write-Host "  ↩ REVERT MODE — restoring {{PLACEHOLDER}} tokens`n" -ForegroundColor Yellow
}

# ─────────────────────────────────────
# 1. Load and Validate Placeholder File
# ─────────────────────────────────────
Write-Host "[1/3] Loading placeholder definitions..." -ForegroundColor Cyan

$PlaceholderFile = Resolve-Path $PlaceholderFile -ErrorAction SilentlyContinue
if (-not $PlaceholderFile -or -not (Test-Path $PlaceholderFile)) {
    Write-Host "  ✗ Placeholder file not found: $PlaceholderFile" -ForegroundColor Red
    Write-Host "  Expected: copilot-studio/deployment-placeholders.json" -ForegroundColor Yellow
    exit 1
}
Write-Host "  File: $PlaceholderFile" -ForegroundColor Gray

try {
    $raw = Get-Content $PlaceholderFile -Raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Host "  ✗ Invalid JSON: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not $raw.placeholders) {
    Write-Host "  ✗ Missing 'placeholders' property in JSON" -ForegroundColor Red
    exit 1
}

# Flatten the nested categories into a single Name → Value map
$placeholderMap = [ordered]@{}
foreach ($category in $raw.placeholders.PSObject.Properties) {
    foreach ($entry in $category.Value.PSObject.Properties) {
        $placeholderMap[$entry.Name] = $entry.Value
    }
}

$totalPlaceholders = $placeholderMap.Count
Write-Host "  Found $totalPlaceholders placeholder definitions" -ForegroundColor Green

# ─────────────────────────────────────
# 2. Validate All Values Are Non-Empty (unless Revert)
# ─────────────────────────────────────
Write-Host "`n[2/3] Validating placeholder values..." -ForegroundColor Cyan

$emptyKeys = @()
foreach ($kv in $placeholderMap.GetEnumerator()) {
    if ([string]::IsNullOrWhiteSpace($kv.Value)) {
        $emptyKeys += $kv.Key
    }
}

if ($emptyKeys.Count -gt 0 -and -not $Revert) {
    Write-Host "  ✗ $($emptyKeys.Count) placeholder(s) have empty values:" -ForegroundColor Red
    foreach ($ek in $emptyKeys) {
        Write-Host "    • $ek" -ForegroundColor Red
    }
    Write-Host "`n  Fill in all GUID values in $PlaceholderFile before deploying." -ForegroundColor Yellow
    Write-Host "  Hint: AI Builder model GUIDs are found in make.powerapps.com → AI models." -ForegroundColor Yellow
    Write-Host "  Hint: Flow GUIDs are printed by deploy-agent-flows.ps1 after deployment." -ForegroundColor Yellow
    exit 2
}

if ($Revert -and $emptyKeys.Count -gt 0) {
    Write-Host "  ⚠ $($emptyKeys.Count) placeholder(s) are empty — these cannot be reverted" -ForegroundColor Yellow
    foreach ($ek in $emptyKeys) {
        Write-Host "    • $ek (skipped)" -ForegroundColor Yellow
    }
    # Filter to only non-empty for revert
    $revertMap = [ordered]@{}
    foreach ($kv in $placeholderMap.GetEnumerator()) {
        if (-not [string]::IsNullOrWhiteSpace($kv.Value)) {
            $revertMap[$kv.Key] = $kv.Value
        }
    }
    $placeholderMap = $revertMap
}

if ($emptyKeys.Count -eq 0) {
    Write-Host "  ✓ All $totalPlaceholders values are non-empty" -ForegroundColor Green
}

# ─────────────────────────────────────
# 3. Scan and Substitute in Topic YAML Files
# ─────────────────────────────────────
Write-Host "`n[3/3] Processing topic files..." -ForegroundColor Cyan

$TopicDir = Resolve-Path $TopicDir -ErrorAction SilentlyContinue
if (-not $TopicDir -or -not (Test-Path $TopicDir)) {
    Write-Host "  ✗ Topic directory not found: $TopicDir" -ForegroundColor Red
    exit 1
}

$topicFiles = Get-ChildItem -Path $TopicDir -Filter "*.topic.mcs.yml" -Recurse
if ($topicFiles.Count -eq 0) {
    Write-Host "  ⚠ No *.topic.mcs.yml files found in $TopicDir" -ForegroundColor Yellow
    exit 0
}

Write-Host "  Scanning $($topicFiles.Count) topic file(s)..." -ForegroundColor Gray

$totalSubstitutions = 0
$filesModified = 0
$errors = 0

foreach ($file in $topicFiles) {
    $content = Get-Content $file.FullName -Raw
    $originalContent = $content
    $fileSubCount = 0
    $fileName = $file.Name

    foreach ($kv in $placeholderMap.GetEnumerator()) {
        $name = $kv.Key
        $guid = $kv.Value

        if ($Revert) {
            # Replace GUID → {{PLACEHOLDER_NAME}}
            $searchPattern = [regex]::Escape($guid)
            $replacement = "{{$name}}"
        } else {
            # Replace {{PLACEHOLDER_NAME}} → GUID
            $searchPattern = [regex]::Escape("{{$name}}")
            $replacement = $guid
        }

        $matches = [regex]::Matches($content, $searchPattern)
        if ($matches.Count -gt 0) {
            $content = $content -replace $searchPattern, $replacement
            $fileSubCount += $matches.Count

            $direction = if ($Revert) { "←" } else { "→" }
            $from = if ($Revert) { $guid.Substring(0, [Math]::Min($guid.Length, 20)) + "..." } else { "{{$name}}" }
            $to = if ($Revert) { "{{$name}}" } else { $guid.Substring(0, [Math]::Min($guid.Length, 20)) + "..." }
            Write-Host "    $direction $fileName : $from → $to ($($matches.Count)x)" -ForegroundColor White
        }
    }

    if ($fileSubCount -gt 0) {
        if (-not $WhatIf) {
            try {
                Set-Content -Path $file.FullName -Value $content -NoNewline -Encoding UTF8
            } catch {
                Write-Host "    ✗ Failed to write $fileName : $($_.Exception.Message)" -ForegroundColor Red
                $errors++
                continue
            }
        }
        $totalSubstitutions += $fileSubCount
        $filesModified++
    }

    # Warn about any remaining unresolved placeholders (in non-revert mode)
    if (-not $Revert) {
        $remaining = [regex]::Matches($content, '\{\{([A-Z_]+)\}\}')
        foreach ($m in $remaining) {
            $unknownName = $m.Groups[1].Value
            if (-not $placeholderMap.Contains($unknownName)) {
                Write-Host "    ⚠ $fileName : unrecognized placeholder {{$unknownName}}" -ForegroundColor Yellow
            }
        }
    }
}

# ─────────────────────────────────────
# Summary
# ─────────────────────────────────────
Write-Host "`n  ─────────────────────────────────────" -ForegroundColor Gray
$action = if ($WhatIf) { "Would substitute" } elseif ($Revert) { "Reverted" } else { "Substituted" }
Write-Host "  $action $totalSubstitutions occurrence(s) across $filesModified file(s)" -ForegroundColor $(if ($totalSubstitutions -gt 0) { "Green" } else { "Yellow" })

if ($WhatIf -and $totalSubstitutions -gt 0) {
    Write-Host "  Re-run without -WhatIf to apply changes." -ForegroundColor Gray
}

if ($errors -gt 0) {
    Write-Host "  ✗ $errors file write error(s) occurred" -ForegroundColor Red
    exit 3
}

Write-Host ""
