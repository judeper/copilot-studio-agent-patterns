<#
.SYNOPSIS
    Audits Dataverse table naming conventions across the Enterprise Work Assistant codebase.

.DESCRIPTION
    Scans all files under a given root directory for references to cr_assistantcard
    (the Dataverse table logical name) and classifies each occurrence as CORRECT,
    EXCLUDED, or VIOLATION based on context:

    - Singular (cr_assistantcard) is correct in metadata contexts: EntityDefinitions,
      SchemaName, privilege names, variable assignments for entity name, qualified
      column references.
    - Plural (cr_assistantcards) is correct in OData/data contexts: entity set URLs,
      @odata.bind references, entitySetName definitions.
    - Primary key (cr_assistantcardid) is always correct.
    - Application-level TypeScript names (AssistantCard) are correct by convention.
    - Natural-language prose in comments, Write-Host strings, and documentation is excluded.

    Reports results grouped by file with color-coded output. Exits with code 0 if no
    violations are found, or code 1 if any violations exist.

.PARAMETER SearchRoot
    Root directory to scan. Defaults to the current directory.

.EXAMPLE
    .\audit-table-naming.ps1 -SearchRoot "."

.EXAMPLE
    .\audit-table-naming.ps1 -SearchRoot "../enterprise-work-assistant"
#>

param(
    [string]$SearchRoot = "."
)

$ErrorActionPreference = "Stop"

# ─────────────────────────────────────
# Configuration
# ─────────────────────────────────────

$ScriptFileName = "audit-table-naming.ps1"

# Directories to exclude from scanning
$ExcludeDirs = @('node_modules', 'out', 'bin', 'obj', '.git')

# ─────────────────────────────────────
# File Discovery
# ─────────────────────────────────────

Write-Host ""
Write-Host "Table Naming Convention Audit" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan
Write-Host "Search root: $((Resolve-Path $SearchRoot).Path)" -ForegroundColor White
Write-Host ""

$allFiles = Get-ChildItem -Path $SearchRoot -Recurse -File | Where-Object {
    $fullPath = $_.FullName
    $exclude = $false
    foreach ($dir in $ExcludeDirs) {
        if ($fullPath -match "[\\/]$dir[\\/]") {
            $exclude = $true
            break
        }
    }
    -not $exclude
}

$totalFilesScanned = $allFiles.Count
$filesWithMatches = 0

# ─────────────────────────────────────
# Counters
# ─────────────────────────────────────

$correctCount = 0
$violationCount = 0
$excludedCount = 0
$totalMatches = 0

# Collect all results for grouped reporting
$results = @()

# ─────────────────────────────────────
# Classification Functions
# ─────────────────────────────────────

function Test-IsExcludedProse {
    param([string]$Line, [string]$FilePath)

    $trimmed = $Line.TrimStart()

    # PowerShell comments
    if ($trimmed -match '^\s*#') { return $true }

    # Write-Host display strings -- match Write-Host with a string containing assistantcard (case-insensitive)
    if ($trimmed -match 'Write-Host\s+["''].*assistantcard' ) { return $true }

    # PowerShell docstring tags (.SYNOPSIS, .DESCRIPTION, .EXAMPLE, .PARAMETER, .NOTES)
    if ($trimmed -match '^\s*\.(SYNOPSIS|DESCRIPTION|EXAMPLE|PARAMETER|NOTES)') { return $true }
    # Lines inside a comment-based help block (between <# and #>) -- we detect these
    # by checking if the file is .ps1 and the line is inside a block comment.
    # For simplicity, if the line does not start with code, we check for common prose patterns.

    # JavaScript/TypeScript single-line comments
    if ($trimmed -match '^\s*//') { return $true }

    # JavaScript/TypeScript block comment lines
    if ($trimmed -match '^\s*/?\*') { return $true }

    # HTML/XML comments
    if ($trimmed -match '^\s*<!--') { return $true }

    # Markdown prose lines -- in .md files, lines not starting with backtick code
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    if ($ext -eq '.md') {
        # Inline code references like `cr_assistantcard` in prose are documentation
        # But lines that are purely code blocks (indented 4+ spaces or in ``` blocks) could be functional
        # For safety, treat all .md file matches as excluded (documentation)
        return $true
    }

    # XML comment content
    if ($ext -eq '.xml' -and $trimmed -match '<!--.*-->') { return $true }

    # Description strings in PowerShell hashtables (natural language)
    if ($trimmed -match '^\s*description\s*=\s*".*assistantcard' ) { return $true }

    return $false
}

function Test-IsApplicationLevel {
    param([string]$Line)

    # TypeScript/JavaScript AssistantCard type references (no cr_ prefix)
    # Match: AssistantCard as interface, type, variable type annotation, import
    if ($Line -match '\bAssistantCard\b' -and $Line -notmatch '\bcr_assistantcard') {
        return $true
    }

    return $false
}

function Test-IsPrimaryKey {
    param([string]$Line)

    # cr_assistantcardid is always correct (primary key = {logicalname}id)
    if ($Line -match '\bcr_assistantcardid\b') {
        return $true
    }

    return $false
}

function Test-IsCorrectSingular {
    param([string]$Line)

    # EntityDefinitions(LogicalName='..._assistantcard')
    if ($Line -match "EntityDefinitions\s*\(\s*LogicalName\s*=\s*['""].*_assistantcard['""]") {
        return $true
    }

    # SchemaName containing _assistantcard
    if ($Line -match 'SchemaName\s*=\s*["''].*_assistantcard["'']') {
        return $true
    }

    # Privilege name construction: prv{Action} followed by entity name containing _assistantcard
    if ($Line -match 'prv(Create|Read|Write|Delete|Append|AppendTo|Assign|Share).*_assistantcard') {
        return $true
    }

    # $entityName variable assignment with singular value
    if ($Line -match '\$entityName\s*=\s*["''].*_assistantcard["'']') {
        return $true
    }

    # Qualified column reference: cr_assistantcard.cr_
    if ($Line -match 'cr_assistantcard\.cr_') {
        return $true
    }

    # Table name display in Write-Host that shows the logical name as a functional reference
    # e.g., Write-Host "Table: ${PublisherPrefix}_assistantcard..."
    if ($Line -match 'Write-Host\s+["''].*Table:\s*.*_assistantcard') {
        return $true
    }

    return $false
}

function Test-IsCorrectPlural {
    param([string]$Line)

    # OData URL path containing /cr_assistantcards
    if ($Line -match '/cr_assistantcards') {
        return $true
    }

    # @odata.bind references with plural form
    if ($Line -match '@odata\.bind.*cr_assistantcards') {
        return $true
    }

    # entitySetName property definition with plural value
    if ($Line -match 'entitySetName.*cr_assistantcards') {
        return $true
    }

    return $false
}

function Get-MatchClassification {
    param(
        [string]$Line,
        [string]$FilePath,
        [string]$FileName
    )

    # Skip the audit script itself
    if ($FileName -eq $ScriptFileName) {
        return @{ Status = "EXCLUDED"; Reason = "Audit script (self)" }
    }

    # 1. Check if natural language / prose (EXCLUDED)
    if (Test-IsExcludedProse -Line $Line -FilePath $FilePath) {
        return @{ Status = "EXCLUDED"; Reason = "Natural language / prose" }
    }

    # 2. Check application-level TypeScript names (no cr_ prefix)
    if ((Test-IsApplicationLevel -Line $Line) -and ($Line -notmatch '\bcr_assistantcard')) {
        return @{ Status = "CORRECT"; Reason = "Application-level TypeScript name" }
    }

    # 3. Check primary key references
    if (Test-IsPrimaryKey -Line $Line) {
        # If line ONLY has cr_assistantcardid (not also cr_assistantcard without id), it is purely PK
        $lineWithoutPK = $Line -replace 'cr_assistantcardid', ''
        if ($lineWithoutPK -notmatch 'cr_assistantcard') {
            return @{ Status = "CORRECT"; Reason = "Primary key reference (cr_assistantcardid)" }
        }
        # If both PK and other references exist, classify the other reference
    }

    # 4. Check correct singular usage (metadata context)
    if (Test-IsCorrectSingular -Line $Line) {
        return @{ Status = "CORRECT"; Reason = "Correct singular (metadata context)" }
    }

    # 5. Check correct plural usage (OData/data context)
    if (Test-IsCorrectPlural -Line $Line) {
        return @{ Status = "CORRECT"; Reason = "Correct plural (OData/data context)" }
    }

    # 6. Check for the specific cr_ prefixed patterns that need classification
    # If we reach here, the line has cr_assistantcard but doesn't match known correct patterns

    # Check if it is a singular form in a context that should be plural (OData context)
    if ($Line -match '/cr_assistantcard[^si]' -or ($Line -match '/cr_assistantcard\s' -and $Line -notmatch '/cr_assistantcards')) {
        return @{ Status = "VIOLATION"; Reason = "Singular form in OData URL context (should be plural)" }
    }

    # Check if it is a plural form in a metadata context
    if ($Line -match 'EntityDefinitions.*cr_assistantcards') {
        return @{ Status = "VIOLATION"; Reason = "Plural form in metadata context (should be singular)" }
    }
    if ($Line -match 'SchemaName.*cr_assistantcards') {
        return @{ Status = "VIOLATION"; Reason = "Plural form in SchemaName (should be singular)" }
    }

    # JSON schema property definitions (e.g., tableName, entitySetName in JSON files)
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    if ($ext -eq '.json') {
        if ($Line -match '"tableName"\s*:\s*"cr_assistantcard"') {
            return @{ Status = "CORRECT"; Reason = "Correct singular (tableName in schema)" }
        }
        if ($Line -match '"entitySetName"\s*:\s*"cr_assistantcards"') {
            return @{ Status = "CORRECT"; Reason = "Correct plural (entitySetName in schema)" }
        }
        # Other JSON references -- check context
        if ($Line -match 'cr_assistantcards') {
            return @{ Status = "CORRECT"; Reason = "Plural form in JSON data context" }
        }
        if ($Line -match 'cr_assistantcard[^si]' -or $Line -match 'cr_assistantcard"') {
            return @{ Status = "CORRECT"; Reason = "Singular form in JSON metadata context" }
        }
    }

    # If we still cannot classify and it only has the application-level AssistantCard
    if ($Line -match '\bAssistantCard\b' -and $Line -notmatch '\bcr_assistantcard') {
        return @{ Status = "CORRECT"; Reason = "Application-level TypeScript name" }
    }

    # Unclassified cr_assistantcard references -- flag as violation for manual review
    if ($Line -match '\bcr_assistantcards\b') {
        return @{ Status = "VIOLATION"; Reason = "Unclassified plural cr_assistantcards reference" }
    }
    if ($Line -match '\bcr_assistantcard\b') {
        return @{ Status = "VIOLATION"; Reason = "Unclassified singular cr_assistantcard reference" }
    }

    # Should not reach here, but just in case
    return @{ Status = "EXCLUDED"; Reason = "No cr_ prefixed Dataverse reference found" }
}

# ─────────────────────────────────────
# Scan Files
# ─────────────────────────────────────

foreach ($file in $allFiles) {
    $relativePath = $file.FullName
    if ($file.FullName.StartsWith((Resolve-Path $SearchRoot).Path)) {
        $relativePath = $file.FullName.Substring((Resolve-Path $SearchRoot).Path.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
    }

    $fileName = $file.Name

    # Quick check: does the file contain any reference?
    $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }
    if ($content -notmatch 'assistantcard' -and $content -notmatch 'AssistantCard') { continue }

    $filesWithMatches++
    $lines = Get-Content $file.FullName -ErrorAction SilentlyContinue
    $fileResults = @()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match 'assistantcard|AssistantCard') {
            $lineNum = $i + 1
            $classification = Get-MatchClassification -Line $line -FilePath $file.FullName -FileName $fileName
            $totalMatches++

            $result = @{
                File = $relativePath
                Line = $lineNum
                Status = $classification.Status
                Reason = $classification.Reason
                Snippet = $line.Trim()
            }

            $fileResults += $result

            switch ($classification.Status) {
                "CORRECT"   { $correctCount++ }
                "VIOLATION" { $violationCount++ }
                "EXCLUDED"  { $excludedCount++ }
            }
        }
    }

    if ($fileResults.Count -gt 0) {
        $results += ,@{ File = $relativePath; Results = $fileResults }
    }
}

# ─────────────────────────────────────
# Report Results
# ─────────────────────────────────────

Write-Host "Results by File" -ForegroundColor Cyan
Write-Host "───────────────" -ForegroundColor Cyan
Write-Host ""

foreach ($fileGroup in $results) {
    $filePath = $fileGroup.File
    Write-Host "  $filePath" -ForegroundColor White

    foreach ($r in $fileGroup.Results) {
        $statusLabel = $r.Status
        $snippet = if ($r.Snippet.Length -gt 100) { $r.Snippet.Substring(0, 97) + "..." } else { $r.Snippet }

        switch ($r.Status) {
            "CORRECT" {
                Write-Host "    [CORRECT]   L$($r.Line) -- $($r.Reason)" -ForegroundColor Green
                Write-Host "                $snippet" -ForegroundColor DarkGray
            }
            "VIOLATION" {
                Write-Host "    [VIOLATION] L$($r.Line) -- $($r.Reason)" -ForegroundColor Red
                Write-Host "                $snippet" -ForegroundColor Red
            }
            "EXCLUDED" {
                Write-Host "    [EXCLUDED]  L$($r.Line) -- $($r.Reason)" -ForegroundColor DarkGray
                Write-Host "                $snippet" -ForegroundColor DarkGray
            }
        }
    }
    Write-Host ""
}

# ─────────────────────────────────────
# Summary
# ─────────────────────────────────────

Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " AUDIT SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Files scanned:    $totalFilesScanned" -ForegroundColor White
Write-Host "  Files with refs:  $filesWithMatches" -ForegroundColor White
Write-Host "  Total matches:    $totalMatches" -ForegroundColor White
Write-Host ""
Write-Host "  Correct:          $correctCount" -ForegroundColor Green
Write-Host "  Excluded (prose): $excludedCount" -ForegroundColor DarkGray
Write-Host "  Violations:       $violationCount" -ForegroundColor $(if ($violationCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($violationCount -eq 0) {
    Write-Host "  PASS: No violations found" -ForegroundColor Green
} else {
    Write-Host "  FAIL: $violationCount violation(s) found" -ForegroundColor Red
}

Write-Host ""

# ─────────────────────────────────────
# Exit Code
# ─────────────────────────────────────

if ($violationCount -gt 0) {
    exit 1
} else {
    exit 0
}
