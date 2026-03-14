<#
.SYNOPSIS
    Pre-flight validation for Intelligent Work Layer deployment.

.DESCRIPTION
    Validates that the local environment and target Power Platform environment are
    ready for an IWL deployment. Checks tools, authentication, Dataverse tables,
    connections, and placeholder configuration.

    Designed to run BEFORE any deploy-* or provision-* script. Returns a pass/fail
    report with actionable fix instructions for every failed check.

    Exit codes:
      0 = All checks passed
      1 = One or more checks failed
      2 = Critical error (cannot run checks)

.PARAMETER EnvironmentId
    Target Power Platform environment ID. If omitted, skips remote environment checks
    and runs local-only validation.

.PARAMETER OrgUrl
    Dataverse organization URL (e.g., https://orgname.crm.dynamics.com).
    Required for Dataverse table and connection checks. If omitted, remote checks
    that require OrgUrl are skipped.

.PARAMETER PublisherPrefix
    Dataverse publisher prefix. Default: "cr"

.PARAMETER SkipRemote
    Skip all remote checks (PAC auth, Dataverse, connections). Useful for validating
    local setup only.

.EXAMPLE
    .\preflight-check.ps1
    # Local-only checks (tools, placeholder file, schemas).

.EXAMPLE
    .\preflight-check.ps1 -EnvironmentId "abc-123" -OrgUrl "https://myorg.crm.dynamics.com"
    # Full validation including remote environment checks.

.EXAMPLE
    .\preflight-check.ps1 -SkipRemote
    # Explicitly skip all remote checks.
#>

param(
    [string]$EnvironmentId,

    [string]$OrgUrl,

    [string]$PublisherPrefix = "cr",

    [switch]$SkipRemote
)

$ErrorActionPreference = "Continue"

# ─────────────────────────────────────
# Helpers
# ─────────────────────────────────────
$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0
$script:SkipCount = 0

function Report-Pass([string]$Message) {
    Write-Host "  PASS  $Message" -ForegroundColor Green
    $script:PassCount++
}

function Report-Fail([string]$Message, [string]$Fix) {
    Write-Host "  FAIL  $Message" -ForegroundColor Red
    if ($Fix) { Write-Host "        Fix: $Fix" -ForegroundColor Yellow }
    $script:FailCount++
}

function Report-Warn([string]$Message, [string]$Fix) {
    Write-Host "  WARN  $Message" -ForegroundColor Yellow
    if ($Fix) { Write-Host "        $Fix" -ForegroundColor Gray }
    $script:WarnCount++
}

function Report-Skip([string]$Message) {
    Write-Host "  SKIP  $Message" -ForegroundColor Gray
    $script:SkipCount++
}

$ewaRoot = Join-Path $PSScriptRoot ".."

# ─────────────────────────────────────
# Banner
# ─────────────────────────────────────
Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  IWL — Pre-Flight Deployment Check                  ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$remoteEnabled = -not $SkipRemote -and ($EnvironmentId -or $OrgUrl)
if ($remoteEnabled) {
    Write-Host "  Mode: Full (local + remote)" -ForegroundColor White
    if ($EnvironmentId) { Write-Host "  Environment: $EnvironmentId" -ForegroundColor Gray }
    if ($OrgUrl) { Write-Host "  Org URL: $OrgUrl" -ForegroundColor Gray }
} else {
    Write-Host "  Mode: Local-only (pass -EnvironmentId and -OrgUrl for remote checks)" -ForegroundColor White
}
Write-Host ""

# ═════════════════════════════════════
# CHECK 1: Required Tools
# ═════════════════════════════════════
Write-Host "[1/7] Required Tools" -ForegroundColor Cyan

# PowerShell 7+
$psVer = $PSVersionTable.PSVersion
if ($psVer.Major -ge 7) {
    Report-Pass "PowerShell $psVer"
} elseif ($psVer.Major -ge 5) {
    Report-Warn "PowerShell $psVer (7+ recommended for cross-platform support)" "Install: winget install Microsoft.PowerShell"
} else {
    Report-Fail "PowerShell $psVer (7+ required)" "Install: winget install Microsoft.PowerShell"
}

# PAC CLI
if (Get-Command pac -ErrorAction SilentlyContinue) {
    $pacVer = pac --version 2>&1
    $versionMatch = [regex]::Match("$pacVer", '(\d+)\.(\d+)')
    if ($versionMatch.Success) {
        $major = [int]$versionMatch.Groups[1].Value
        $minor = [int]$versionMatch.Groups[2].Value
        if ($major -lt 1 -or ($major -eq 1 -and $minor -lt 32)) {
            Report-Warn "PAC CLI $pacVer (1.32+ recommended)" "Update: dotnet tool update --global Microsoft.PowerApps.CLI.Tool"
        } else {
            Report-Pass "PAC CLI $pacVer"
        }
    } else {
        Report-Pass "PAC CLI (version parse skipped)"
    }
} else {
    Report-Fail "PAC CLI not found" "Install: dotnet tool install --global Microsoft.PowerApps.CLI.Tool"
}

# Azure CLI
if (Get-Command az -ErrorAction SilentlyContinue) {
    $azVer = az version --query '"azure-cli"' -o tsv 2>&1
    Report-Pass "Azure CLI $azVer"
} else {
    Report-Fail "Azure CLI not found" "Install: winget install Microsoft.AzureCLI"
}

# Node.js
if (Get-Command node -ErrorAction SilentlyContinue) {
    $nodeVer = node --version 2>&1
    Report-Pass "Node.js $nodeVer"
} else {
    Report-Fail "Node.js not found" "Install: https://nodejs.org (LTS recommended)"
}

# npm
if (Get-Command npm -ErrorAction SilentlyContinue) {
    $npmVer = npm --version 2>&1
    Report-Pass "npm $npmVer"
} else {
    Report-Fail "npm not found" "npm is included with Node.js — reinstall Node.js"
}

# ═════════════════════════════════════
# CHECK 2: PAC CLI Authentication
# ═════════════════════════════════════
Write-Host "`n[2/7] PAC CLI Authentication" -ForegroundColor Cyan

if ($SkipRemote) {
    Report-Skip "Skipped (remote checks disabled)"
} elseif (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
    Report-Skip "Skipped (PAC CLI not installed)"
} else {
    $authList = pac auth list 2>&1
    $authStr = "$authList"
    if ($authStr -match "No profiles" -or $LASTEXITCODE -ne 0) {
        Report-Fail "PAC CLI has no authentication profiles" "Run: pac auth create --tenant <tenant-id>"
    } else {
        # Check for an active profile (marked with *)
        if ($authStr -match '\*') {
            Report-Pass "PAC CLI authenticated (active profile found)"
        } else {
            Report-Warn "PAC CLI has profiles but none marked active" "Run: pac auth select --index <n>"
        }
    }
}

# ═════════════════════════════════════
# CHECK 3: Azure CLI Authentication
# ═════════════════════════════════════
Write-Host "`n[3/7] Azure CLI Authentication" -ForegroundColor Cyan

if ($SkipRemote) {
    Report-Skip "Skipped (remote checks disabled)"
} elseif (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Report-Skip "Skipped (Azure CLI not installed)"
} else {
    $azAccount = az account show 2>&1
    if ($LASTEXITCODE -ne 0) {
        Report-Fail "Azure CLI is not authenticated" "Run: az login --tenant <tenant-id>"
    } else {
        try {
            $acct = "$azAccount" | ConvertFrom-Json -ErrorAction Stop
            Report-Pass "Azure CLI authenticated as $($acct.user.name) (tenant: $($acct.tenantId.Substring(0,8))...)"
        } catch {
            Report-Pass "Azure CLI authenticated"
        }
    }
}

# ═════════════════════════════════════
# CHECK 4: Target Environment
# ═════════════════════════════════════
Write-Host "`n[4/7] Target Environment" -ForegroundColor Cyan

if (-not $remoteEnabled -or -not $EnvironmentId) {
    Report-Skip "Skipped (no -EnvironmentId provided)"
} elseif (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
    Report-Skip "Skipped (PAC CLI not installed)"
} else {
    try {
        $envListRaw = pac admin list --json 2>&1
        if ($LASTEXITCODE -ne 0) {
            Report-Fail "Cannot list environments (pac admin list failed)" "Ensure PAC CLI is authenticated with admin permissions"
        } else {
            $envList = "$envListRaw" | ConvertFrom-Json -ErrorAction Stop
            $targetEnv = @($envList | Where-Object { $_.EnvironmentId -eq $EnvironmentId -or $_.Id -eq $EnvironmentId }) | Select-Object -First 1
            if ($targetEnv) {
                Report-Pass "Environment found: $($targetEnv.DisplayName)"
            } else {
                Report-Fail "Environment '$EnvironmentId' not found in tenant" "Verify the environment ID in admin.powerplatform.microsoft.com"
            }
        }
    } catch {
        Report-Warn "Could not verify environment (pac admin list parse error)" "Verify manually in admin.powerplatform.microsoft.com"
    }
}

# ═════════════════════════════════════
# CHECK 5: Dataverse Tables
# ═════════════════════════════════════
Write-Host "`n[5/7] Dataverse Tables" -ForegroundColor Cyan

$schemasDir = Join-Path $ewaRoot "schemas"

if (-not (Test-Path $schemasDir)) {
    Report-Fail "Schemas directory not found: $schemasDir" "Ensure the repo is cloned completely"
} else {
    # Discover expected tables from schema files
    $tableSchemas = Get-ChildItem -Path $schemasDir -Filter "*-table.json" -File
    $expectedTables = @()

    foreach ($schema in $tableSchemas) {
        try {
            $schemaJson = Get-Content $schema.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($schemaJson.tableName) {
                $expectedTables += [PSCustomObject]@{
                    LogicalName = $schemaJson.tableName
                    DisplayName = $schemaJson.displayName
                    SchemaFile  = $schema.Name
                }
            }
        } catch {
            Report-Warn "Cannot parse schema: $($schema.Name)" "$($_.Exception.Message)"
        }
    }

    Write-Host "  Expected tables (from schemas/):" -ForegroundColor Gray
    foreach ($t in $expectedTables) {
        Write-Host "    • $($t.LogicalName) ($($t.DisplayName))" -ForegroundColor Gray
    }

    if (-not $remoteEnabled -or -not $OrgUrl) {
        Report-Skip "Remote table existence check skipped (no -OrgUrl provided)"
    } else {
        # Acquire token for Dataverse
        $dvToken = $null
        try {
            $dvToken = az account get-access-token --resource "$($OrgUrl.TrimEnd('/'))" --query accessToken -o tsv 2>$null
        } catch {}

        if (-not $dvToken) {
            Report-Fail "Cannot acquire Dataverse token for $OrgUrl" "Run: az login --tenant <tenantId>"
        } else {
            $dvHeaders = @{
                "Authorization"    = "Bearer $dvToken"
                "Content-Type"     = "application/json"
                "OData-MaxVersion" = "4.0"
                "OData-Version"    = "4.0"
            }

            foreach ($t in $expectedTables) {
                $entitySet = $t.LogicalName + "s"
                # Try the entitySetName from schema if available
                try {
                    $schemaJson = Get-Content (Join-Path $schemasDir $t.SchemaFile) -Raw | ConvertFrom-Json -ErrorAction Stop
                    if ($schemaJson.entitySetName) { $entitySet = $schemaJson.entitySetName }
                } catch {}

                try {
                    $null = Invoke-RestMethod -Uri "$($OrgUrl.TrimEnd('/'))/api/data/v9.2/EntityDefinitions(LogicalName='$($t.LogicalName)')?`$select=LogicalName" -Headers $dvHeaders -ErrorAction Stop
                    Report-Pass "Table exists: $($t.LogicalName)"
                } catch {
                    $status = $_.Exception.Response.StatusCode.value__
                    if ($status -eq 404) {
                        Report-Fail "Table missing: $($t.LogicalName) ($($t.DisplayName))" "Run: .\provision-environment.ps1 to create Dataverse tables"
                    } else {
                        Report-Warn "Cannot verify table $($t.LogicalName) (HTTP $status)" "Check Dataverse permissions and OrgUrl"
                    }
                }
            }
        }
    }
}

# ═════════════════════════════════════
# CHECK 6: Connections
# ═════════════════════════════════════
Write-Host "`n[6/7] Power Platform Connections" -ForegroundColor Cyan

# Required connectors for IWL
$requiredConnectors = @(
    @{ Key = "shared_office365";                Display = "Office 365 Outlook" }
    @{ Key = "shared_office365users";           Display = "Office 365 Users" }
    @{ Key = "shared_teams";                    Display = "Microsoft Teams" }
    @{ Key = "shared_commondataserviceforapps"; Display = "Microsoft Dataverse" }
    @{ Key = "shared_webcontents";              Display = "HTTP with Entra ID" }
    @{ Key = "shared_microsoftcopilotstudio";   Display = "Microsoft Copilot Studio" }
)

if (-not $remoteEnabled -or -not $EnvironmentId) {
    Report-Skip "Skipped (no -EnvironmentId provided)"
    Write-Host "  Required connectors:" -ForegroundColor Gray
    foreach ($c in $requiredConnectors) {
        Write-Host "    • $($c.Display) ($($c.Key))" -ForegroundColor Gray
    }
} elseif (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Report-Skip "Skipped (Azure CLI not installed)"
} else {
    $paToken = $null
    try {
        $paToken = az account get-access-token --resource "https://service.powerapps.com/" --query accessToken -o tsv 2>$null
    } catch {}

    if (-not $paToken) {
        Report-Fail "Cannot acquire PowerApps API token" "Run: az login --tenant <tenantId>"
    } else {
        $paHeaders = @{ "Authorization" = "Bearer $paToken" }
        try {
            $connUrl = "https://api.powerapps.com/providers/Microsoft.PowerApps/connections?api-version=2016-11-01&`$filter=environment eq '$EnvironmentId'"
            $connections = Invoke-RestMethod -Uri $connUrl -Headers $paHeaders -ErrorAction Stop

            # Build connector → status map
            $connStatusMap = @{}
            foreach ($conn in $connections.value) {
                $apiName = $conn.properties.apiId -replace '.*/apis/', ''
                $status = ($conn.properties.statuses | Select-Object -First 1).status
                if (-not $connStatusMap.ContainsKey($apiName) -or $status -eq "Connected") {
                    $connStatusMap[$apiName] = $status
                }
            }

            foreach ($c in $requiredConnectors) {
                if ($connStatusMap.ContainsKey($c.Key)) {
                    $status = $connStatusMap[$c.Key]
                    if ($status -eq "Connected") {
                        Report-Pass "Connection: $($c.Display) (Connected)"
                    } else {
                        Report-Warn "Connection: $($c.Display) (status: $status)" "Re-authenticate the connection in Power Automate"
                    }
                } else {
                    Report-Fail "Connection missing: $($c.Display)" "Create in Power Automate → Connections → New connection → $($c.Display)"
                }
            }
        } catch {
            Report-Warn "Cannot list connections (API error)" "$($_.Exception.Message)"
        }
    }
}

# ═════════════════════════════════════
# CHECK 7: Deployment Placeholders
# ═════════════════════════════════════
Write-Host "`n[7/7] Deployment Placeholders" -ForegroundColor Cyan

$placeholderFile = Join-Path $ewaRoot "copilot-studio" "deployment-placeholders.json"

if (-not (Test-Path $placeholderFile)) {
    Report-Fail "Placeholder file not found: $placeholderFile" "Ensure copilot-studio/deployment-placeholders.json exists"
} else {
    try {
        $phJson = Get-Content $placeholderFile -Raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $phJson.placeholders) {
            Report-Fail "Placeholder file missing 'placeholders' property" "Check the JSON structure"
        } else {
            $totalPh = 0
            $emptyPh = 0
            $filledPh = 0

            foreach ($category in $phJson.placeholders.PSObject.Properties) {
                foreach ($entry in $category.Value.PSObject.Properties) {
                    $totalPh++
                    if ([string]::IsNullOrWhiteSpace($entry.Value)) {
                        $emptyPh++
                    } else {
                        $filledPh++
                    }
                }
            }

            if ($emptyPh -eq 0) {
                Report-Pass "All $totalPh placeholders have values"
            } elseif ($filledPh -eq 0) {
                Report-Fail "All $totalPh placeholders are empty (no GUIDs configured)" "Fill in deployment-placeholders.json with environment-specific GUIDs, then run substitute-placeholders.ps1"
            } else {
                Report-Fail "$emptyPh of $totalPh placeholders are empty" "Fill in all values in deployment-placeholders.json"
            }

            # Also check if topic YAML files still have unresolved {{PLACEHOLDER}} tokens
            $topicDir = Join-Path $ewaRoot "copilot-studio" "topics"
            if (Test-Path $topicDir) {
                $unresolvedFiles = @()
                $topicFiles = Get-ChildItem -Path $topicDir -Filter "*.topic.mcs.yml" -Recurse
                foreach ($tf in $topicFiles) {
                    $content = Get-Content $tf.FullName -Raw
                    if ($content -match '\{\{[A-Z_]+\}\}') {
                        $unresolvedFiles += $tf.Name
                    }
                }
                if ($unresolvedFiles.Count -gt 0) {
                    Report-Warn "$($unresolvedFiles.Count) topic file(s) contain unresolved {{PLACEHOLDER}} tokens" "Run: .\substitute-placeholders.ps1 after filling in the JSON"
                    foreach ($uf in $unresolvedFiles) {
                        Write-Host "          • $uf" -ForegroundColor Yellow
                    }
                } else {
                    Report-Pass "No unresolved {{PLACEHOLDER}} tokens in topic files"
                }
            }
        }
    } catch {
        Report-Fail "Cannot parse placeholder file" "$($_.Exception.Message)"
    }
}

# ═════════════════════════════════════
# Summary
# ═════════════════════════════════════
Write-Host "`n  ═════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Pre-Flight Summary" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────" -ForegroundColor Gray
Write-Host "  PASS:    $script:PassCount" -ForegroundColor Green
if ($script:FailCount -gt 0) {
    Write-Host "  FAIL:    $script:FailCount" -ForegroundColor Red
} else {
    Write-Host "  FAIL:    0" -ForegroundColor Green
}
if ($script:WarnCount -gt 0) {
    Write-Host "  WARN:    $script:WarnCount" -ForegroundColor Yellow
} else {
    Write-Host "  WARN:    0" -ForegroundColor Green
}
if ($script:SkipCount -gt 0) {
    Write-Host "  SKIP:    $script:SkipCount" -ForegroundColor Gray
}
Write-Host "  ═════════════════════════════════════`n" -ForegroundColor Cyan

if ($script:FailCount -gt 0) {
    Write-Host "  ✗ Pre-flight check FAILED — resolve issues above before deploying.`n" -ForegroundColor Red
    exit 1
} elseif ($script:WarnCount -gt 0) {
    Write-Host "  ⚠ Pre-flight check PASSED with warnings — review items above.`n" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "  ✓ Pre-flight check PASSED — environment is ready for deployment.`n" -ForegroundColor Green
    exit 0
}
