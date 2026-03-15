<#
.SYNOPSIS
    Master pre-flight validation for Intelligent Work Layer demo readiness.

.DESCRIPTION
    Runs all validation checks in sequence to verify the IWL environment is ready
    for a demo. Checks:

      1. Dataverse tables exist with expected columns
      2. Security roles are assigned
      3. Power Automate connections are active
      4. DLP policies allow required connector combinations
      5. Copilot Studio agent is published
      6. PCF component is importable
      7. Environment variables are configured

    This script orchestrates the individual validation scripts (validate-connections.ps1,
    validate-dlp-policy.ps1) and performs additional Dataverse table checks directly.

.PARAMETER EnvironmentId
    Power Platform environment ID (GUID).

.PARAMETER OrgUrl
    Dataverse organization URL (e.g., https://orgname.crm.dynamics.com).

.PARAMETER PublisherPrefix
    Dataverse publisher prefix. Default: "cr"

.PARAMETER SkipDlp
    Skip DLP policy validation (useful in sandbox environments without DLP).

.PARAMETER SkipConnections
    Skip connection validation.

.EXAMPLE
    .\validate-demo-readiness.ps1 `
        -EnvironmentId "af3070e1-da9a-e06b-85e5-dec492b54d1d" `
        -OrgUrl "https://enterpriseworkassistant.crm.dynamics.com"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [Parameter(Mandatory = $true)]
    [string]$OrgUrl,

    [string]$PublisherPrefix = "cr",

    [switch]$SkipDlp,

    [switch]$SkipConnections
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot
$passCount = 0
$failCount = 0
$warnCount = 0
$results = @()

function Add-Result {
    param([string]$Check, [string]$Status, [string]$Detail)
    $script:results += [PSCustomObject]@{ Check = $Check; Status = $Status; Detail = $Detail }
    switch ($Status) {
        "PASS" { $script:passCount++; Write-Host "  ✅ $Check" -ForegroundColor Green }
        "FAIL" { $script:failCount++; Write-Host "  ❌ $Check — $Detail" -ForegroundColor Red }
        "WARN" { $script:warnCount++; Write-Host "  ⚠️  $Check — $Detail" -ForegroundColor Yellow }
    }
}

Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " IWL DEMO READINESS VALIDATION" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────
# 0. Prerequisites
# ─────────────────────────────────────
Write-Host "Checking prerequisites..." -ForegroundColor Cyan
if (-not (Get-Command "pac" -ErrorAction SilentlyContinue)) {
    Add-Result -Check "PAC CLI installed" -Status "FAIL" -Detail "Install with: dotnet tool install --global Microsoft.PowerApps.CLI.Tool"
} else {
    Add-Result -Check "PAC CLI installed" -Status "PASS" -Detail ""
}

if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    Add-Result -Check "Azure CLI installed" -Status "FAIL" -Detail "Install with: winget install Microsoft.AzureCLI"
} else {
    Add-Result -Check "Azure CLI installed" -Status "PASS" -Detail ""
}

$OrgUrl = $OrgUrl.TrimEnd('/')
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv 2>$null
if (-not $token) {
    Add-Result -Check "Azure CLI authenticated" -Status "FAIL" -Detail "Run: az login --tenant <tenant-id>"
    Write-Host ""
    Write-Host "Cannot proceed without authentication. Fix the above issues and re-run." -ForegroundColor Red
    exit 1
} else {
    Add-Result -Check "Azure CLI authenticated" -Status "PASS" -Detail ""
}

$headers = @{
    "Authorization"    = "Bearer $token"
    "Content-Type"     = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
}
$apiBase = "$OrgUrl/api/data/v9.2"

# ─────────────────────────────────────
# 1. Dataverse Tables
# ─────────────────────────────────────
Write-Host ""
Write-Host "Checking Dataverse tables..." -ForegroundColor Cyan

$requiredTables = @(
    @{ LogicalName = "${PublisherPrefix}_assistantcard"; DisplayName = "AssistantCard" },
    @{ LogicalName = "${PublisherPrefix}_senderprofile"; DisplayName = "SenderProfile" },
    @{ LogicalName = "${PublisherPrefix}_briefingschedule"; DisplayName = "BriefingSchedule" },
    @{ LogicalName = "${PublisherPrefix}_errorlog"; DisplayName = "ErrorLog" },
    @{ LogicalName = "${PublisherPrefix}_episodicmemory"; DisplayName = "EpisodicMemory" },
    @{ LogicalName = "${PublisherPrefix}_semanticknowledge"; DisplayName = "SemanticKnowledge" },
    @{ LogicalName = "${PublisherPrefix}_userpersona"; DisplayName = "UserPersona" },
    @{ LogicalName = "${PublisherPrefix}_skillregistry"; DisplayName = "SkillRegistry" },
    @{ LogicalName = "${PublisherPrefix}_semanticepisodic"; DisplayName = "SemanticEpisodic (junction)" }
)

foreach ($table in $requiredTables) {
    try {
        $result = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='$($table.LogicalName)')?`$select=LogicalName" -Headers $headers
        Add-Result -Check "Table: $($table.DisplayName)" -Status "PASS" -Detail ""
    } catch {
        Add-Result -Check "Table: $($table.DisplayName)" -Status "FAIL" -Detail "Table '$($table.LogicalName)' not found. Run provision-environment.ps1"
    }
}

# Check critical columns on AssistantCard
$criticalColumns = @(
    "${PublisherPrefix}_triagetier",
    "${PublisherPrefix}_triggertype",
    "${PublisherPrefix}_priority",
    "${PublisherPrefix}_cardstatus",
    "${PublisherPrefix}_confidencescore",
    "${PublisherPrefix}_fulljson",
    "${PublisherPrefix}_humanizeddraft",
    "${PublisherPrefix}_cardoutcome"
)

try {
    $entityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='${PublisherPrefix}_assistantcard')/Attributes?`$select=LogicalName" -Headers $headers
    $existingCols = $entityMeta.value | ForEach-Object { $_.LogicalName }
    $missingCols = $criticalColumns | Where-Object { $_ -notin $existingCols }
    if ($missingCols.Count -eq 0) {
        Add-Result -Check "AssistantCard critical columns" -Status "PASS" -Detail ""
    } else {
        Add-Result -Check "AssistantCard critical columns" -Status "FAIL" -Detail "Missing: $($missingCols -join ', ')"
    }
} catch {
    Add-Result -Check "AssistantCard critical columns" -Status "WARN" -Detail "Could not query column metadata"
}

# Check SenderProfile alternate key
try {
    $keys = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='${PublisherPrefix}_senderprofile')/Keys" -Headers $headers
    $emailKey = $keys.value | Where-Object { $_.LogicalName -eq "${PublisherPrefix}_senderemail_key" }
    if ($emailKey) {
        Add-Result -Check "SenderProfile alternate key" -Status "PASS" -Detail ""
    } else {
        Add-Result -Check "SenderProfile alternate key" -Status "FAIL" -Detail "Alternate key '${PublisherPrefix}_senderemail_key' not found"
    }
} catch {
    Add-Result -Check "SenderProfile alternate key" -Status "WARN" -Detail "Could not query keys"
}

# ─────────────────────────────────────
# 2. Security Roles
# ─────────────────────────────────────
Write-Host ""
Write-Host "Checking security roles..." -ForegroundColor Cyan

try {
    $roles = Invoke-RestMethod -Uri "$apiBase/roles?`$filter=contains(name,'Intelligent Work Layer')&`$select=name,roleid" -Headers $headers
    if ($roles.value.Count -gt 0) {
        Add-Result -Check "Security role exists" -Status "PASS" -Detail "$($roles.value[0].name)"
    } else {
        Add-Result -Check "Security role exists" -Status "FAIL" -Detail "No 'Intelligent Work Layer' role found. Run create-security-roles.ps1"
    }
} catch {
    Add-Result -Check "Security role exists" -Status "WARN" -Detail "Could not query roles"
}

# ─────────────────────────────────────
# 3. Connections
# ─────────────────────────────────────
if (-not $SkipConnections) {
    Write-Host ""
    Write-Host "Checking connections..." -ForegroundColor Cyan
    $connScript = Join-Path $scriptDir "validate-connections.ps1"
    if (Test-Path $connScript) {
        try {
            & $connScript -EnvironmentId $EnvironmentId 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Add-Result -Check "Power Automate connections" -Status "PASS" -Detail ""
            } else {
                Add-Result -Check "Power Automate connections" -Status "FAIL" -Detail "Missing connections. Run validate-connections.ps1 for details"
            }
        } catch {
            Add-Result -Check "Power Automate connections" -Status "WARN" -Detail "Validation script errored: $($_.Exception.Message)"
        }
    } else {
        Add-Result -Check "Power Automate connections" -Status "WARN" -Detail "validate-connections.ps1 not found"
    }
} else {
    Add-Result -Check "Power Automate connections" -Status "WARN" -Detail "Skipped (use -SkipConnections:$false to enable)"
}

# ─────────────────────────────────────
# 4. DLP Policies
# ─────────────────────────────────────
if (-not $SkipDlp) {
    Write-Host ""
    Write-Host "Checking DLP policies..." -ForegroundColor Cyan
    $dlpScript = Join-Path $scriptDir "validate-dlp-policy.ps1"
    if (Test-Path $dlpScript) {
        try {
            & $dlpScript -EnvironmentId $EnvironmentId 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Add-Result -Check "DLP policy compliance" -Status "PASS" -Detail ""
            } else {
                Add-Result -Check "DLP policy compliance" -Status "FAIL" -Detail "Connector conflicts detected. Run validate-dlp-policy.ps1 for details"
            }
        } catch {
            Add-Result -Check "DLP policy compliance" -Status "WARN" -Detail "Validation script errored: $($_.Exception.Message)"
        }
    } else {
        Add-Result -Check "DLP policy compliance" -Status "WARN" -Detail "validate-dlp-policy.ps1 not found"
    }
} else {
    Add-Result -Check "DLP policy compliance" -Status "WARN" -Detail "Skipped (use -SkipDlp:$false to enable)"
}

# ─────────────────────────────────────
# 5. Environment Variables
# ─────────────────────────────────────
Write-Host ""
Write-Host "Checking environment variables..." -ForegroundColor Cyan

$requiredEnvVars = @(
    "${PublisherPrefix}_AdminNotificationEmail",
    "${PublisherPrefix}_StalenessThresholdHours",
    "${PublisherPrefix}_ExpirationDays",
    "${PublisherPrefix}_SenderProfileMinSignals"
)

foreach ($varName in $requiredEnvVars) {
    try {
        $varResult = Invoke-RestMethod -Uri "$apiBase/environmentvariabledefinitions?`$filter=schemaname eq '$varName'&`$select=schemaname,displayname" -Headers $headers
        if ($varResult.value.Count -gt 0) {
            Add-Result -Check "Env var: $varName" -Status "PASS" -Detail ""
        } else {
            Add-Result -Check "Env var: $varName" -Status "WARN" -Detail "Not found. Run provision-env-variables.ps1"
        }
    } catch {
        Add-Result -Check "Env var: $varName" -Status "WARN" -Detail "Could not query"
    }
}

# ─────────────────────────────────────
# 6. Copilot Studio Agent
# ─────────────────────────────────────
Write-Host ""
Write-Host "Checking Copilot Studio agent..." -ForegroundColor Cyan

try {
    $bots = Invoke-RestMethod -Uri "$apiBase/bots?`$filter=contains(name,'Intelligent Work Layer') or contains(name,'enterpriseworkassistant')&`$select=name,botid,statecode" -Headers $headers
    if ($bots.value.Count -gt 0) {
        $bot = $bots.value[0]
        Add-Result -Check "Copilot Studio agent exists" -Status "PASS" -Detail "$($bot.name)"
        if ($bot.statecode -eq 0) {
            Add-Result -Check "Agent is active" -Status "PASS" -Detail ""
        } else {
            Add-Result -Check "Agent is active" -Status "WARN" -Detail "Agent state: $($bot.statecode). Verify it is published in Copilot Studio"
        }
    } else {
        Add-Result -Check "Copilot Studio agent exists" -Status "FAIL" -Detail "No IWL agent found. Run provision-copilot.ps1 or create manually"
    }
} catch {
    Add-Result -Check "Copilot Studio agent exists" -Status "WARN" -Detail "Could not query bots table"
}

# ─────────────────────────────────────
# 7. PCF Solution
# ─────────────────────────────────────
Write-Host ""
Write-Host "Checking PCF solution..." -ForegroundColor Cyan

try {
    $solutions = Invoke-RestMethod -Uri "$apiBase/solutions?`$filter=uniquename eq 'AssistantDashboard' or uniquename eq 'EnterpriseWorkAssistant'&`$select=uniquename,friendlyname,version" -Headers $headers
    if ($solutions.value.Count -gt 0) {
        $sol = $solutions.value[0]
        Add-Result -Check "PCF solution imported" -Status "PASS" -Detail "$($sol.friendlyname) v$($sol.version)"
    } else {
        Add-Result -Check "PCF solution imported" -Status "WARN" -Detail "Solution not found. Run deploy-solution.ps1"
    }
} catch {
    Add-Result -Check "PCF solution imported" -Status "WARN" -Detail "Could not query solutions"
}

# ─────────────────────────────────────
# Summary
# ─────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " VALIDATION SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ✅ Passed: $passCount" -ForegroundColor Green
if ($warnCount -gt 0) { Write-Host "  ⚠️  Warnings: $warnCount" -ForegroundColor Yellow }
if ($failCount -gt 0) { Write-Host "  ❌ Failed: $failCount" -ForegroundColor Red }
Write-Host ""

if ($failCount -eq 0 -and $warnCount -eq 0) {
    Write-Host "  🎉 Environment is DEMO READY!" -ForegroundColor Green
} elseif ($failCount -eq 0) {
    Write-Host "  ✅ Environment is likely demo ready (review warnings above)." -ForegroundColor Yellow
} else {
    Write-Host "  ❌ Environment is NOT demo ready. Fix the $failCount failure(s) above." -ForegroundColor Red
}

Write-Host ""
exit $failCount
