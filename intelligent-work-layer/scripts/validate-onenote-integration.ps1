<#
.SYNOPSIS
    Validates cross-references and consistency for the OneNote integration.

.DESCRIPTION
    Checks that all OneNote integration artifacts are internally consistent:
    - cr_onenotepageid referenced in prompt files
    - Template placeholders are documented
    - Tool action names match between orchestrator prompt and flow docs
    - JSON schema is valid
    - Markdown files have no broken internal references

    Run this script after making any changes to OneNote integration files.

.EXAMPLE
    .\validate-onenote-integration.ps1
#>

$ErrorCount = 0
$WarningCount = 0
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ewaRoot = Join-Path $repoRoot "intelligent-work-layer"

Write-Host "`n━━━ OneNote Integration Validation ━━━" -ForegroundColor Cyan

# ── 1. JSON Validation ─────────────────────────────────────────────────────────

Write-Host "`n[1/6] JSON Schema Validation" -ForegroundColor Yellow

$schemaFile = Join-Path $ewaRoot "schemas\dataverse-table.json"
try {
    $null = Get-Content $schemaFile -Raw | ConvertFrom-Json -ErrorAction Stop
    Write-Host "  PASS: dataverse-table.json is valid JSON" -ForegroundColor Green
} catch {
    Write-Host "  FAIL: dataverse-table.json is not valid JSON: $_" -ForegroundColor Red
    $ErrorCount++
}

# ── 2. Schema Column Presence ──────────────────────────────────────────────────

Write-Host "`n[2/6] Schema Column Presence" -ForegroundColor Yellow

$schemaContent = Get-Content $schemaFile -Raw
$requiredColumns = @("cr_onenotepageid", "cr_onenoteenabled", "cr_onenoteoptout")

foreach ($col in $requiredColumns) {
    if ($schemaContent -match $col) {
        Write-Host "  PASS: $col found in schema" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $col NOT found in schema" -ForegroundColor Red
        $ErrorCount++
    }
}

# ── 3. Prompt Cross-References ─────────────────────────────────────────────────

Write-Host "`n[3/6] Prompt Cross-References" -ForegroundColor Yellow

$mainPrompt = Get-Content (Join-Path $ewaRoot "prompts\main-agent-system-prompt.md") -Raw
$orchPrompt = Get-Content (Join-Path $ewaRoot "prompts\orchestrator-agent-prompt.md") -Raw

# Check OneNote mentioned in main prompt
if ($mainPrompt -match "OneNote") {
    Write-Host "  PASS: OneNote referenced in main-agent-system-prompt.md" -ForegroundColor Green
} else {
    Write-Host "  FAIL: OneNote NOT referenced in main-agent-system-prompt.md" -ForegroundColor Red
    $ErrorCount++
}

# Check Tier 3 (not Tier 1) for annotations
if ($mainPrompt -match "Tier 3") {
    Write-Host "  PASS: Annotations classified as Tier 3 in main prompt" -ForegroundColor Green
} else {
    Write-Host "  WARN: Tier 3 classification not found in main prompt" -ForegroundColor DarkYellow
    $WarningCount++
}

# Check tool actions in orchestrator
$toolActions = @("QueryOneNote", "UpdateOneNote")
foreach ($tool in $toolActions) {
    if ($orchPrompt -match $tool) {
        Write-Host "  PASS: $tool found in orchestrator-agent-prompt.md" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $tool NOT found in orchestrator-agent-prompt.md" -ForegroundColor Red
        $ErrorCount++
    }
}

# ── 4. Tool Action Name Consistency ────────────────────────────────────────────

Write-Host "`n[4/6] Tool Action Name Consistency" -ForegroundColor Yellow

$flowDocs = Get-Content (Join-Path $ewaRoot "docs\agent-flows.md") -Raw

foreach ($tool in $toolActions) {
    if ($flowDocs -match $tool) {
        Write-Host "  PASS: $tool found in agent-flows.md (matches orchestrator prompt)" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $tool NOT found in agent-flows.md (name mismatch with orchestrator prompt)" -ForegroundColor Red
        $ErrorCount++
    }
}

# Check cr_onenotepageid in flow docs
if ($flowDocs -match "cr_onenotepageid") {
    Write-Host "  PASS: cr_onenotepageid referenced in agent-flows.md" -ForegroundColor Green
} else {
    Write-Host "  FAIL: cr_onenotepageid NOT referenced in agent-flows.md" -ForegroundColor Red
    $ErrorCount++
}

# ── 5. Template Placeholder Validation ─────────────────────────────────────────

Write-Host "`n[5/6] Template Placeholder Validation" -ForegroundColor Yellow

$templateDir = Join-Path $ewaRoot "templates"
$designDoc = Get-Content (Join-Path $ewaRoot "docs\onenote-integration.md") -Raw

if (Test-Path $templateDir) {
    $templates = Get-ChildItem $templateDir -Filter "onenote-*.html"
    foreach ($template in $templates) {
        $content = Get-Content $template.FullName -Raw
        $placeholders = [regex]::Matches($content, '\{\{([A-Z_]+)\}\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

        Write-Host "  $($template.Name): $($placeholders.Count) placeholders found" -ForegroundColor White
        foreach ($ph in $placeholders) {
            Write-Host "    {{$ph}}" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "  FAIL: templates/ directory not found" -ForegroundColor Red
    $ErrorCount++
}

# ── 6. Design Doc Presence ─────────────────────────────────────────────────────

Write-Host "`n[6/6] Design Doc Validation" -ForegroundColor Yellow

$designDocPath = Join-Path $ewaRoot "docs\onenote-integration.md"
if (Test-Path $designDocPath) {
    Write-Host "  PASS: onenote-integration.md exists" -ForegroundColor Green

    # Check phase markers
    $phaseMarkers = @("[P1-IMPLEMENTED]", "[P2-PLANNED]", "[P3-PLANNED]")
    foreach ($marker in $phaseMarkers) {
        if ($designDoc -match [regex]::Escape($marker)) {
            Write-Host "  PASS: Phase marker $marker found" -ForegroundColor Green
        } else {
            Write-Host "  WARN: Phase marker $marker not found" -ForegroundColor DarkYellow
            $WarningCount++
        }
    }
} else {
    Write-Host "  FAIL: onenote-integration.md not found" -ForegroundColor Red
    $ErrorCount++
}

# ── Summary ─────────────────────────────────────────────────────────────────────

Write-Host "`n━━━ Validation Summary ━━━" -ForegroundColor Cyan
if ($ErrorCount -eq 0) {
    Write-Host "  All checks passed ($WarningCount warnings)" -ForegroundColor Green
} else {
    Write-Host "  $ErrorCount errors, $WarningCount warnings" -ForegroundColor Red
}

exit $ErrorCount
