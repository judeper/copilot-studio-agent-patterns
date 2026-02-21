# Phase 6: PowerShell Script Fixes - Research

**Researched:** 2026-02-21
**Domain:** PowerShell scripting, Power Platform CLI (PAC), deployment automation
**Confidence:** HIGH

## Summary

Phase 6 is a fix-only phase targeting two existing PowerShell scripts (`deploy-solution.ps1` and `create-security-roles.ps1`) and the deployment guide documentation. The scripts are well-structured but need alignment with the Bun migration (Phase 3), improved import verification, better error handling, `-WhatIf` support, logging, and prerequisite checks. The deployment guide's manual build commands in Phase 5 also need updating from npm to bun.

The changes are straightforward PowerShell pattern applications: `[CmdletBinding(SupportsShouldProcess)]` for WhatIf, `Start-Transcript` for logging, `Get-Command` for prerequisite detection, structured exit codes, and string replacement of `npm` with `bun`. The `create-security-roles.ps1` already has a `-PublisherPrefix` parameter (contrary to DOC-06's original assumption), so that requirement is satisfied -- but the error handling needs hardening (fail on missing privilege instead of warning).

**Primary recommendation:** Apply all changes as direct edits to existing scripts following standard PowerShell patterns. No new scripts, modules, or dependencies needed.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Import verification**: Keep synchronous `pac solution import` -- no async polling needed for a single PCF component. Trust the pac exit code for success/failure detection. Remove the current `pac solution list` verification step (checks existence, not import result). Improve error messaging on import failure.
- **Deployment guide sync**: Update deployment-guide.md Phase 5 manual build commands from `npm install` / `npm run build` to `bun install` / `bun run build` alongside the script changes (don't defer to Phase 7).
- **WhatIf support**: Add `-WhatIf` flag to deploy-solution.ps1 that shows planned steps without executing. Standard PowerShell pattern for reference quality.
- **Error & failure behavior**: Fail fast, no cleanup on build failure -- partial build artifacts are harmless and overwritten on next run. Structured exit codes: 0=success, 1=prerequisite failure, 2=build failure, 3=import failure. Write a timestamped deploy.log alongside console output for troubleshooting. create-security-roles.ps1: fail the whole script if any privilege is not found (table not published yet), rather than warning and continuing.
- **Prerequisite checks**: deploy-solution.ps1: check Bun, Node.js, dotnet SDK, PAC CLI, and PAC auth. create-security-roles.ps1: add upfront Azure CLI (az) installed + authenticated check. All missing-prerequisite error messages include the install command or URL.
- **PublisherPrefix**: create-security-roles.ps1 `-PublisherPrefix` parameter already exists and works -- no changes needed there.

### Claude's Discretion
- Version checking strictness (existence-only vs minimum versions for Bun/Node)
- Exact log file format and rotation
- WhatIf output formatting
- deploy.log file location and naming convention

### Deferred Ideas (OUT OF SCOPE)
- Packaging Power Automate flows and Copilot Studio agents into the solution (currently manual setup) -- would be a new capability beyond this fix-only milestone
- Expanding deploy-solution.ps1 into a full end-to-end deployment orchestrator covering all 7 deployment phases
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DOC-05 | deploy-solution.ps1 polling logic checks import operation status (not solution existence) | Current script uses `pac solution list` after import to "verify" -- this checks existence, not import result. User decision: remove verification step entirely, trust `pac solution import` exit code (synchronous, sets `$LASTEXITCODE`). PAC CLI docs confirm synchronous import returns non-zero on failure. |
| DOC-06 | create-security-roles.ps1 accepts publisher prefix as parameter instead of hardcoding 'cr_' | Already implemented: script has `[string]$PublisherPrefix = "cr"` parameter and uses `${PublisherPrefix}_assistantcard` throughout. No code change needed for the parameter itself. However, error handling must be hardened: currently uses `Write-Warning` when privilege not found, must throw instead. |
</phase_requirements>

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| PowerShell | 7+ | Script runtime | Already required by project (see deployment-guide.md prerequisites) |
| PAC CLI | Latest | Power Platform solution import | `pac solution import` is the standard deployment mechanism; synchronous by default |
| Bun | 1.3.8+ | Package manager and build runner | Migrated in Phase 3; `bun.lock` already exists in `src/` |
| Azure CLI (`az`) | Latest | Dataverse API authentication | Used by create-security-roles.ps1 for OAuth token acquisition |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `Start-Transcript` | PowerShell built-in logging | Captures all console output to timestamped log file |
| `Get-Command` | Prerequisite detection | Check whether CLI tools (bun, node, dotnet, pac, az) are on PATH |
| `$PSCmdlet.ShouldProcess` | WhatIf/Confirm support | Wrap each destructive operation in deploy-solution.ps1 |

### Alternatives Considered

None. All tools are already in use in the project or are PowerShell built-ins. No new dependencies needed.

## Architecture Patterns

### Pattern 1: Prerequisite Checking with `Get-Command`

**What:** Use `Get-Command -ErrorAction SilentlyContinue` to check tool availability, with optional version extraction.
**When to use:** At script start, before any operations.
**Confidence:** HIGH (standard PowerShell pattern, verified against current script structure)

```powershell
# Source: Standard PowerShell pattern
function Test-Prerequisite {
    param(
        [string]$Command,
        [string]$DisplayName,
        [string]$InstallHint
    )
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Host "  MISSING: $DisplayName" -ForegroundColor Red
        Write-Host "  Install: $InstallHint" -ForegroundColor Yellow
        return $false
    }
    # Get version (best effort)
    try {
        $ver = & $Command --version 2>&1 | Select-Object -First 1
        Write-Host "  $DisplayName: $ver" -ForegroundColor Green
    } catch {
        Write-Host "  $DisplayName: found (version unknown)" -ForegroundColor Green
    }
    return $true
}
```

**Recommendation for discretion area (version checking):** Use existence-only checks. Minimum version enforcement adds complexity and fragility (version string parsing varies across tools), and the project already specifies prerequisites in documentation. If a wrong version is installed, the build step itself will fail with a clear error.

### Pattern 2: SupportsShouldProcess for `-WhatIf`

**What:** Add `[CmdletBinding(SupportsShouldProcess)]` to the script's `param()` block and wrap each destructive step in `if ($PSCmdlet.ShouldProcess(...))`.
**When to use:** deploy-solution.ps1 has multiple destructive steps (install deps, build, pack, import).
**Confidence:** HIGH (verified against Microsoft official docs)

```powershell
# Source: https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-shouldprocess
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,
    # ...other params...
)

# Non-destructive setup runs always (prerequisite checks, path resolution)
# ...

# Destructive step wrapped in ShouldProcess
if ($PSCmdlet.ShouldProcess("$SolutionPath", "Install dependencies (bun install)")) {
    Push-Location $SolutionPath
    try {
        bun install
        if ($LASTEXITCODE -ne 0) { exit 2 }
    } finally {
        Pop-Location
    }
}
```

The two-parameter form `$PSCmdlet.ShouldProcess('TARGET', 'OPERATION')` produces the output:
```
What if: Performing the operation "OPERATION" on target "TARGET".
```

This is the recommended form for deployment scripts because it makes the WhatIf output descriptive.

**WhatIf output formatting (discretion area):** Use the two-parameter `ShouldProcess('target', 'operation')` form. This gives clear output like `What if: Performing the operation "Install dependencies (bun install)" on target "C:\path\to\src".`

### Pattern 3: Structured Exit Codes

**What:** Use explicit `exit N` with documented codes instead of `throw` for top-level failures.
**When to use:** At each major failure point in deploy-solution.ps1.
**Confidence:** HIGH (straightforward PowerShell)

```powershell
# Exit codes documented in help block:
# 0 = success
# 1 = prerequisite failure
# 2 = build failure
# 3 = import failure

# Example: prerequisite failure
if (-not $allPrereqsMet) {
    Write-Host "Prerequisite check failed. See above for details." -ForegroundColor Red
    exit 1
}

# Example: build failure
bun run build
if ($LASTEXITCODE -ne 0) {
    Write-Host "PCF build failed. Check TypeScript errors above." -ForegroundColor Red
    exit 2
}
```

**Important:** When using `Start-Transcript`, call `Stop-Transcript` before `exit` to ensure the log file is properly closed. Use a `try/finally` pattern at the top level.

### Pattern 4: `Start-Transcript` for Logging

**What:** Capture all console output to a timestamped log file using PowerShell's built-in `Start-Transcript`.
**When to use:** At the start of deploy-solution.ps1 execution.
**Confidence:** HIGH (verified against Microsoft docs: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.host/start-transcript)

```powershell
# Source: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.host/start-transcript
$logFile = Join-Path $PSScriptRoot "deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $logFile -UseMinimalHeader

try {
    # ... all script logic ...
} finally {
    Stop-Transcript
}
```

**Log file location and naming (discretion area):** Place log files in the `scripts/` directory alongside the script itself (`$PSScriptRoot`). Use format `deploy-YYYYMMDD-HHmmss.log`. No rotation needed -- timestamped filenames prevent overwrite, and users can manually clean old logs. This keeps it simple and the log is findable next to the script.

### Pattern 5: Removing Broken Verification Step (DOC-05)

**What:** Remove the `pac solution list` call that currently serves as "verification" after import.
**Why:** `pac solution list` only checks that a solution exists in the environment. It does not verify the import succeeded -- the solution may have existed before the import, or the import may have partially failed. The `pac solution import` command itself runs synchronously and returns a non-zero exit code on failure, which is already checked on line 126.
**Confidence:** HIGH (verified against PAC CLI docs -- `pac solution import` is synchronous by default, `--async` flag is opt-in)

Current code to remove (lines 131-134):
```powershell
# REMOVE: This verifies solution existence, not import success
Write-Host "Verifying deployment..." -ForegroundColor Cyan
pac solution list --environment $EnvironmentId
```

Replace with improved error messaging on the existing `$LASTEXITCODE` check:
```powershell
pac solution import --path $zipPath --environment $EnvironmentId
if ($LASTEXITCODE -ne 0) {
    Write-Host "Solution import failed (exit code: $LASTEXITCODE)." -ForegroundColor Red
    Write-Host "Check the PAC CLI output above for details." -ForegroundColor Yellow
    Write-Host "Common causes: missing dependencies, version conflict, auth expired." -ForegroundColor Yellow
    exit 3
}
Write-Host "  Solution imported and verified (exit code 0)." -ForegroundColor Green
```

### Pattern 6: Fail-Fast on Missing Privilege (create-security-roles.ps1)

**What:** Change `Write-Warning` to `throw` when a privilege is not found during security role assignment.
**Why:** If a privilege is not found, the table has not been published yet. Continuing silently creates a role with incomplete permissions.
**Confidence:** HIGH (direct code analysis)

Current code (lines 117-119):
```powershell
} else {
    Write-Warning "  Privilege '$privName' not found. Table may not be published yet."
}
```

Change to:
```powershell
} else {
    throw "Privilege '$privName' not found. The cr_assistantcard table may not be published yet. Import the solution first, then re-run this script."
}
```

Also change the outer `catch` block (lines 121-123) from `Write-Warning` to `throw`:
```powershell
} catch {
    throw "Failed to assign privilege '$privName': $($_.Exception.Message)"
}
```

### Anti-Patterns to Avoid

- **Async polling for single-component imports:** The PAC CLI `pac solution import` is synchronous by default. Adding `--async` and polling would add complexity with no benefit for a single PCF component.
- **Version string parsing for prerequisites:** Different tools format version strings differently (`v20.11.0`, `1.3.8`, `8.0.100`). Parsing and comparing these is fragile. Use existence checks only.
- **Cleanup on build failure:** Build artifacts (`node_modules/`, `out/`, `bin/`) are harmless and overwritten on next run. Adding cleanup logic is unnecessary complexity.
- **Using `throw` vs `exit` in scripts:** In scripts (not modules), use `exit N` for structured exit codes. `throw` sets `$LASTEXITCODE` to 1 regardless of the actual failure category, losing the structured information.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| WhatIf/Confirm support | Custom `-DryRun` parameter with manual checks | `[CmdletBinding(SupportsShouldProcess)]` + `$PSCmdlet.ShouldProcess()` | Built-in PowerShell pattern; handles `-WhatIf`, `-Confirm`, verbose output, and scope propagation automatically |
| Console output logging | Custom `Write-Log` function that tees to file | `Start-Transcript` / `Stop-Transcript` | Captures all output streams (host, verbose, warning, error) without modifying any Write-Host calls |
| Tool availability check | Manual `try { tool --version } catch` | `Get-Command -ErrorAction SilentlyContinue` | Returns `$null` cleanly when not found; no exception overhead; works for all executable types |

**Key insight:** Every pattern needed in this phase is a built-in PowerShell feature. No external modules, no custom utilities, no new files beyond editing the existing scripts and docs.

## Common Pitfalls

### Pitfall 1: `Start-Transcript` + `exit` Truncates Log

**What goes wrong:** Calling `exit` without `Stop-Transcript` first can leave the transcript file without a proper closing, and in some PowerShell hosts may truncate or lose buffered output.
**Why it happens:** `exit` terminates the process without running cleanup code outside of `try/finally` blocks.
**How to avoid:** Wrap the entire script body in `try { ... } finally { Stop-Transcript }`. Call `exit` only inside the `try` block, which triggers the `finally`.
**Warning signs:** Log files that end abruptly without "Transcript stopped" footer.

### Pitfall 2: `$LASTEXITCODE` Stale Value

**What goes wrong:** `$LASTEXITCODE` retains the value from the last native command. If a PowerShell cmdlet (not native command) runs between the native command and the check, `$LASTEXITCODE` still holds the old value.
**Why it happens:** PowerShell only updates `$LASTEXITCODE` for native/external commands, not for cmdlets.
**How to avoid:** Check `$LASTEXITCODE` immediately after each native command (`bun install`, `bun run build`, `dotnet build`, `pac solution import`). Do not insert PowerShell cmdlets between the native call and the exit code check.
**Warning signs:** Script reports success when a build step actually failed.

### Pitfall 3: `ShouldProcess` in Scripts vs Functions

**What goes wrong:** In a standalone `.ps1` script, `$PSCmdlet` is available when `[CmdletBinding()]` is used in the `param()` block. However, script-level `ShouldProcess` applies to the entire script scope.
**Why it happens:** Scripts with `[CmdletBinding(SupportsShouldProcess)]` in their param block behave like advanced functions.
**How to avoid:** Place `[CmdletBinding(SupportsShouldProcess)]` immediately before the `param()` block. Use `$PSCmdlet.ShouldProcess()` for each destructive step. Non-destructive steps (prerequisite checks, path resolution) should run even in `-WhatIf` mode.
**Warning signs:** `-WhatIf` either does nothing or skips prerequisite validation.

### Pitfall 4: `Push-Location`/`Pop-Location` Without `finally`

**What goes wrong:** If an error occurs between `Push-Location` and `Pop-Location`, the working directory is not restored.
**Why it happens:** `$ErrorActionPreference = "Stop"` converts errors to terminating exceptions that skip `Pop-Location`.
**How to avoid:** Always pair with `try/finally`. The current scripts already do this correctly -- maintain this pattern.
**Warning signs:** Subsequent steps fail because they run from the wrong directory.

### Pitfall 5: Bun vs npm Subtle Differences

**What goes wrong:** `bun install` and `bun run build` behave slightly differently from npm counterparts in edge cases (exit codes, output format).
**Why it happens:** Bun is a different runtime that aims for npm compatibility but has its own behaviors.
**How to avoid:** Check `$LASTEXITCODE` after both `bun install` and `bun run build` just as the current script checks after `npm install` and `npm run build`. Bun follows the same convention of returning non-zero on failure.
**Warning signs:** Build appears to succeed but `$LASTEXITCODE` was not checked.

## Code Examples

### Complete Prerequisite Check Block for deploy-solution.ps1

```powershell
# Source: Research synthesis of standard PowerShell patterns
Write-Host "Validating prerequisites..." -ForegroundColor Cyan
$prereqFailed = $false

# Check Bun
if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
    Write-Host "  MISSING: Bun" -ForegroundColor Red
    Write-Host "  Install: https://bun.sh or 'curl -fsSL https://bun.sh/install | bash'" -ForegroundColor Yellow
    $prereqFailed = $true
} else {
    $bunVer = bun --version 2>&1
    Write-Host "  Bun: $bunVer" -ForegroundColor Green
}

# Check Node.js
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "  MISSING: Node.js" -ForegroundColor Red
    Write-Host "  Install: https://nodejs.org (v18+ required)" -ForegroundColor Yellow
    $prereqFailed = $true
} else {
    $nodeVer = node --version 2>&1
    Write-Host "  Node.js: $nodeVer" -ForegroundColor Green
}

# Check dotnet SDK
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host "  MISSING: .NET SDK" -ForegroundColor Red
    Write-Host "  Install: https://dotnet.microsoft.com/download" -ForegroundColor Yellow
    $prereqFailed = $true
} else {
    $dotnetVer = dotnet --version 2>&1
    Write-Host "  .NET SDK: $dotnetVer" -ForegroundColor Green
}

# Check PAC CLI
if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
    Write-Host "  MISSING: PAC CLI" -ForegroundColor Red
    Write-Host "  Install: dotnet tool install --global Microsoft.PowerApps.CLI.Tool" -ForegroundColor Yellow
    $prereqFailed = $true
} else {
    $pacVer = pac --version 2>&1
    Write-Host "  PAC CLI: $pacVer" -ForegroundColor Green
}

# Check PAC auth (only if pac exists)
if (-not $prereqFailed -or (Get-Command pac -ErrorAction SilentlyContinue)) {
    $authList = pac auth list 2>&1
    if ($authList -match "No profiles" -or $LASTEXITCODE -ne 0) {
        Write-Host "  MISSING: PAC CLI authentication" -ForegroundColor Red
        Write-Host "  Run: pac auth create --tenant <tenant-id>" -ForegroundColor Yellow
        $prereqFailed = $true
    } else {
        Write-Host "  PAC auth: OK" -ForegroundColor Green
    }
}

if ($prereqFailed) {
    Write-Host ""
    Write-Host "Prerequisite check failed. Install missing tools and retry." -ForegroundColor Red
    exit 1
}
```

### Complete Prerequisite Check Block for create-security-roles.ps1

```powershell
# Source: Research synthesis of standard PowerShell patterns
Write-Host "Validating prerequisites..." -ForegroundColor Cyan

# Check Azure CLI
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) is not installed. Install from https://aka.ms/installazurecli"
}
$azVer = az version --query '"azure-cli"' -o tsv 2>&1
Write-Host "  Azure CLI: $azVer" -ForegroundColor Green

# Check Azure CLI authentication
$azAccount = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI is not authenticated. Run 'az login --tenant <tenant-id>' first."
}
Write-Host "  Azure CLI auth: OK" -ForegroundColor Green
```

### deploy-solution.ps1 Help Block with Exit Codes

```powershell
<#
.SYNOPSIS
    Builds and deploys the PCF component solution to a Power Platform environment.

.DESCRIPTION
    Validates prerequisites (Bun, Node.js, .NET SDK, PAC CLI),
    runs the PCF build pipeline (bun install, bun run build),
    packs the solution, and imports it to the target environment.
    All output is logged to a timestamped deploy-*.log file.

    Exit codes:
      0 = Success
      1 = Prerequisite check failure
      2 = Build failure (bun install, bun run build, or dotnet build)
      3 = Solution import failure

.PARAMETER EnvironmentId
    Target Power Platform environment ID (required).

.PARAMETER SolutionPath
    Path to the PCF src/ directory. Default: "../src"

.PARAMETER SolutionName
    Name for the packed solution. Default: "EnterpriseWorkAssistant"

.PARAMETER WhatIf
    Shows what operations would be performed without executing them.

.EXAMPLE
    .\deploy-solution.ps1 -EnvironmentId "abc-123-def"

.EXAMPLE
    .\deploy-solution.ps1 -EnvironmentId "abc-123-def" -WhatIf
#>
```

### Bun Build Steps (Replacing npm)

```powershell
# BEFORE (current):
Write-Host "Installing npm dependencies..." -ForegroundColor Cyan
npm install
if ($LASTEXITCODE -ne 0) { throw "npm install failed." }

npm run build
if ($LASTEXITCODE -ne 0) { throw "PCF build failed." }

# AFTER (with Bun + ShouldProcess + exit codes):
if ($PSCmdlet.ShouldProcess($SolutionPath, "Install dependencies (bun install)")) {
    Write-Host "Installing dependencies..." -ForegroundColor Cyan
    Push-Location $SolutionPath
    try {
        bun install
        if ($LASTEXITCODE -ne 0) {
            Write-Host "bun install failed." -ForegroundColor Red
            exit 2
        }
        Write-Host "  Dependencies installed." -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

if ($PSCmdlet.ShouldProcess($SolutionPath, "Build PCF component (bun run build)")) {
    Write-Host "Building PCF component..." -ForegroundColor Cyan
    Push-Location $SolutionPath
    try {
        bun run build
        if ($LASTEXITCODE -ne 0) {
            Write-Host "PCF build failed. Check TypeScript errors above." -ForegroundColor Red
            exit 2
        }
        Write-Host "  Build successful." -ForegroundColor Green
    } finally {
        Pop-Location
    }
}
```

### Deployment Guide Fix (deployment-guide.md Phase 5)

```markdown
# BEFORE:
Or manually:
```bash
cd enterprise-work-assistant/src
npm install
npm run build
```

# AFTER:
Or manually:
```bash
cd enterprise-work-assistant/src
bun install
bun run build
```
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `npm install` / `npm run build` | `bun install` / `bun run build` | Phase 3 (this project) | Scripts and docs must match; bun.lock already exists |
| `pac solution list` for verification | Trust `pac solution import` exit code | Current phase decision | Remove misleading verification step |
| `Write-Warning` for missing privilege | `throw` for missing privilege | Current phase decision | Fail-fast prevents incomplete security roles |
| No `-WhatIf` support | `[CmdletBinding(SupportsShouldProcess)]` | Current phase addition | Reference-quality scripts |
| `try/catch` with implicit exit codes | Structured exit codes (0/1/2/3) | Current phase addition | CI pipeline can distinguish failure stages |

## Open Questions

1. **PAC CLI `--version` output format on all platforms**
   - What we know: PAC CLI has a `--version` flag that outputs version info. The current script wraps this in try/catch.
   - What's unclear: Whether the output format is consistent across Windows/macOS/Linux (this is a cross-platform .NET tool).
   - Recommendation: Use `Get-Command pac -ErrorAction SilentlyContinue` for existence check (reliable). Display version with `pac --version 2>&1` (best effort). Do not parse the version string.

2. **`bun --version` exit code behavior**
   - What we know: `bun --version` returns the version string (e.g., `1.3.8`). Expected to return exit code 0.
   - What's unclear: Edge cases on PATH but misconfigured bun installations.
   - Recommendation: Capture with `2>&1` to handle any stderr output. The `Get-Command` check before this prevents the "not found" case.

## Sources

### Primary (HIGH confidence)
- [Microsoft PAC CLI solution command reference](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/solution) - Verified `pac solution import` is synchronous by default, `--async` is opt-in, exit code signals success/failure.
- [Microsoft PowerShell ShouldProcess deep dive](https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-shouldprocess?view=powershell-7.5) - Verified `[CmdletBinding(SupportsShouldProcess)]` pattern, two-parameter `ShouldProcess('target', 'operation')` form, script-level usage.
- [Microsoft Start-Transcript documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.host/start-transcript?view=powershell-7.5) - Verified `-UseMinimalHeader`, `-Path` parameters, and `Stop-Transcript` pairing.
- Direct code analysis of `deploy-solution.ps1`, `create-security-roles.ps1`, `provision-environment.ps1`, `deployment-guide.md` in project repository.

### Secondary (MEDIUM confidence)
- Bun CLI compatibility with npm commands - Based on Phase 3 migration already completed in this project; `bun.lock` exists confirming working setup.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools already in project; no new dependencies
- Architecture: HIGH - Standard PowerShell patterns, verified against official Microsoft documentation
- Pitfalls: HIGH - Identified from direct analysis of current script code and known PowerShell behaviors
- Code examples: HIGH - Based on current script structure + verified patterns

**Research date:** 2026-02-21
**Valid until:** 2026-03-21 (stable domain, low change velocity)
