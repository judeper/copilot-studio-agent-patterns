<#
.SYNOPSIS
    Creates ownership-based security roles for the Email Productivity Agent.

.DESCRIPTION
    Creates an "Email Productivity Agent User" security role granting Basic (user-level)
    depth on the FollowUpTracking, NudgeConfiguration, and SnoozedConversation tables.
    Each user sees only their own rows.

.PARAMETER OrgUrl
    Dataverse organization URL (required). Example: https://orgname.crm.dynamics.com

.PARAMETER PublisherPrefix
    Dataverse publisher prefix. Must match the prefix used in provision-environment.ps1. Default: "cr"

.EXAMPLE
    .\create-security-roles.ps1 -OrgUrl "https://myorg.crm.dynamics.com"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$OrgUrl,

    [string]$PublisherPrefix = "cr"
)

$ErrorActionPreference = "Stop"

# ─────────────────────────────────────
# 0. Validate Prerequisites
# ─────────────────────────────────────
Write-Host "Validating prerequisites..." -ForegroundColor Cyan

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) is not installed. Install from https://aka.ms/installazurecli"
}
$azVer = (az version 2>&1 | ConvertFrom-Json).'azure-cli'
Write-Host "  Azure CLI: $azVer" -ForegroundColor Green

$azAccount = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI is not authenticated. Run 'az login --tenant <tenant-id>' first."
}
Write-Host "  Azure CLI auth: OK" -ForegroundColor Green

# ─────────────────────────────────────
# 1. Get Access Token
# ─────────────────────────────────────
Write-Host "Authenticating..." -ForegroundColor Cyan
# Get access token via Azure CLI (pac auth token does not exist)
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
if (-not $token) { throw "Failed to get access token. Ensure Azure CLI is installed and authenticated (az login)." }
$headers = @{
    "Authorization"    = "Bearer $token"
    "Content-Type"     = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
}

$apiBase = "$OrgUrl/api/data/v9.2"

# ─────────────────────────────────────
# 2. Get the root Business Unit
# ─────────────────────────────────────
Write-Host "Retrieving root business unit..." -ForegroundColor Cyan
$buResult = Invoke-RestMethod -Uri "$apiBase/businessunits?`$filter=parentbusinessunitid eq null&`$select=businessunitid,name" -Headers $headers
$rootBuId = $buResult.value[0].businessunitid
Write-Host "  Root BU: $($buResult.value[0].name) ($rootBuId)" -ForegroundColor Green

# ─────────────────────────────────────
# 3. Create Security Role
# ─────────────────────────────────────
Write-Host "Creating 'Email Productivity Agent User' security role..." -ForegroundColor Cyan

$roleDef = @{
    name = "Email Productivity Agent User"
    description = "Grants Basic (user-level) CRUD access to FollowUpTracking, NudgeConfiguration, and SnoozedConversation tables. Users see only their own rows."
    "businessunitid@odata.bind" = "/businessunits($rootBuId)"
} | ConvertTo-Json

try {
    $createHeaders = $headers.Clone()
    $createHeaders["Prefer"] = "return=representation"
    $roleResult = Invoke-RestMethod -Uri "$apiBase/roles" -Method Post -Headers $createHeaders -Body $roleDef
    $roleId = $roleResult.roleid
    Write-Host "  Role created: $roleId" -ForegroundColor Green
} catch {
    # Role may already exist
    $existing = Invoke-RestMethod -Uri "$apiBase/roles?`$filter=name eq 'Email Productivity Agent User'&`$select=roleid" -Headers $headers
    if ($existing.value.Count -gt 0) {
        $roleId = $existing.value[0].roleid
        Write-Host "  Role already exists: $roleId" -ForegroundColor Yellow
    } else {
        throw "Failed to create security role: $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────
# 4. Add Privileges for FollowUpTracking
# ─────────────────────────────────────
Write-Host "Configuring privileges on FollowUpTracking table..." -ForegroundColor Cyan

# Get the entity metadata to find the object type code
$entityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='${PublisherPrefix}_followuptracking')?`$select=ObjectTypeCode" -Headers $headers
$objectTypeCode = $entityMeta.ObjectTypeCode

# Privilege names follow the pattern: prv{Action}{EntityLogicalName}
# IMPORTANT: Dataverse privileges use the entity LogicalName (lowercase), not SchemaName (PascalCase)
$entityLogicalName = "${PublisherPrefix}_followuptracking"
$privilegeNames = @(
    "prvCreate${entityLogicalName}",
    "prvRead${entityLogicalName}",
    "prvWrite${entityLogicalName}",
    "prvDelete${entityLogicalName}",
    "prvAppend${entityLogicalName}",
    "prvAppendTo${entityLogicalName}"
)

# Basic depth = 1 (User level - sees only own records)
$basicDepth = 1

foreach ($privName in $privilegeNames) {
    try {
        # Look up the privilege ID
        $privResult = Invoke-RestMethod -Uri "$apiBase/privileges?`$filter=name eq '$privName'&`$select=privilegeid" -Headers $headers
        if ($privResult.value.Count -gt 0) {
            $privId = $privResult.value[0].privilegeid

            # Add privilege to role with Basic depth
            Invoke-RestMethod -Uri "$apiBase/roles($roleId)/Microsoft.Dynamics.CRM.AddPrivilegesRole" -Method Post -Headers $headers -Body (@{
                Privileges = @(@{
                    Depth = "Basic"
                    PrivilegeId = $privId
                    BusinessUnitId = $rootBuId
                })
            } | ConvertTo-Json -Depth 5)

            Write-Host "  Granted: $privName (Basic depth)" -ForegroundColor Green
        } else {
            throw "Privilege '$privName' not found. The ${PublisherPrefix}_FollowUpTracking table may not be published yet. Import the solution first, then re-run this script."
        }
    } catch {
        throw "Failed to assign privilege '$privName': $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────
# 5. Add Privileges for NudgeConfiguration
# ─────────────────────────────────────
Write-Host "Configuring privileges on NudgeConfiguration table..." -ForegroundColor Cyan

$nudgeEntityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='${PublisherPrefix}_nudgeconfiguration')?`$select=ObjectTypeCode" -Headers $headers
$nudgeObjectTypeCode = $nudgeEntityMeta.ObjectTypeCode

# IMPORTANT: Dataverse privileges use the entity LogicalName (lowercase), not SchemaName (PascalCase)
$nudgeLogicalName = "${PublisherPrefix}_nudgeconfiguration"
$nudgePrivilegeNames = @(
    "prvCreate${nudgeLogicalName}",
    "prvRead${nudgeLogicalName}",
    "prvWrite${nudgeLogicalName}",
    "prvDelete${nudgeLogicalName}",
    "prvAppend${nudgeLogicalName}",
    "prvAppendTo${nudgeLogicalName}"
)

foreach ($privName in $nudgePrivilegeNames) {
    try {
        $privResult = Invoke-RestMethod -Uri "$apiBase/privileges?`$filter=name eq '$privName'&`$select=privilegeid" -Headers $headers
        if ($privResult.value.Count -gt 0) {
            $privId = $privResult.value[0].privilegeid

            Invoke-RestMethod -Uri "$apiBase/roles($roleId)/Microsoft.Dynamics.CRM.AddPrivilegesRole" -Method Post -Headers $headers -Body (@{
                Privileges = @(@{
                    Depth = "Basic"
                    PrivilegeId = $privId
                    BusinessUnitId = $rootBuId
                })
            } | ConvertTo-Json -Depth 5)

            Write-Host "  Granted: $privName (Basic depth)" -ForegroundColor Green
        } else {
            throw "Privilege '$privName' not found. The ${PublisherPrefix}_NudgeConfiguration table may not be published yet. Import the solution first, then re-run this script."
        }
    } catch {
        throw "Failed to assign privilege '$privName': $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────
# 6. Add Privileges for SnoozedConversation (Phase 2)
# ─────────────────────────────────────
Write-Host "Configuring privileges on SnoozedConversation table..." -ForegroundColor Cyan

$snoozedLogicalName = "${PublisherPrefix}_snoozedconversation"
# IMPORTANT: Dataverse privileges use the entity LogicalName (lowercase), not SchemaName (PascalCase)

# Check if table exists before configuring privileges
try {
    $snoozedEntityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='$snoozedLogicalName')?`$select=ObjectTypeCode" -Headers $headers
    $snoozedObjectTypeCode = $snoozedEntityMeta.ObjectTypeCode

    $snoozedPrivilegeNames = @(
        "prvCreate${snoozedLogicalName}",
        "prvRead${snoozedLogicalName}",
        "prvWrite${snoozedLogicalName}",
        "prvDelete${snoozedLogicalName}",
        "prvAppend${snoozedLogicalName}",
        "prvAppendTo${snoozedLogicalName}"
    )

    foreach ($privName in $snoozedPrivilegeNames) {
        try {
            $privResult = Invoke-RestMethod -Uri "$apiBase/privileges?`$filter=name eq '$privName'&`$select=privilegeid" -Headers $headers
            if ($privResult.value.Count -gt 0) {
                $privId = $privResult.value[0].privilegeid

                Invoke-RestMethod -Uri "$apiBase/roles($roleId)/Microsoft.Dynamics.CRM.AddPrivilegesRole" -Method Post -Headers $headers -Body (@{
                    Privileges = @(@{
                        Depth = "Basic"
                        PrivilegeId = $privId
                        BusinessUnitId = $rootBuId
                    })
                } | ConvertTo-Json -Depth 5)

                Write-Host "  Granted: $privName (Basic depth)" -ForegroundColor Green
            } else {
                Write-Warning "  Privilege '$privName' not found. Run provision-environment.ps1 first."
            }
        } catch {
            Write-Warning "  Failed to assign privilege '$privName': $($_.Exception.Message)"
        }
    }
} catch {
    Write-Warning "  SnoozedConversation table not found — skipping. This table is Phase 2; run provision-environment.ps1 with Phase 2 to create it."
}

# ─────────────────────────────────────
# 7. Add Privileges for PriorityContact
# ─────────────────────────────────────
Write-Host "Configuring privileges on PriorityContact table..." -ForegroundColor Cyan

$priorityLogicalName = "${PublisherPrefix}_prioritycontact"

try {
    $priorityEntityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='$priorityLogicalName')?`$select=ObjectTypeCode" -Headers $headers

    $priorityPrivilegeNames = @(
        "prvCreate${priorityLogicalName}",
        "prvRead${priorityLogicalName}",
        "prvWrite${priorityLogicalName}",
        "prvDelete${priorityLogicalName}",
        "prvAppend${priorityLogicalName}",
        "prvAppendTo${priorityLogicalName}"
    )

    foreach ($privName in $priorityPrivilegeNames) {
        try {
            $privResult = Invoke-RestMethod -Uri "$apiBase/privileges?`$filter=name eq '$privName'&`$select=privilegeid" -Headers $headers
            if ($privResult.value.Count -gt 0) {
                $privId = $privResult.value[0].privilegeid
                Invoke-RestMethod -Uri "$apiBase/roles($roleId)/Microsoft.Dynamics.CRM.AddPrivilegesRole" -Method Post -Headers $headers -Body (@{
                    Privileges = @(@{ Depth = "Basic"; PrivilegeId = $privId; BusinessUnitId = $rootBuId })
                } | ConvertTo-Json -Depth 5)
                Write-Host "  Granted: $privName (Basic depth)" -ForegroundColor Green
            } else {
                Write-Warning "  Privilege '$privName' not found. Run provision-environment.ps1 first."
            }
        } catch {
            Write-Warning "  Failed to assign privilege '$privName': $($_.Exception.Message)"
        }
    }
} catch {
    Write-Warning "  PriorityContact table not found — skipping. Run provision-environment.ps1 first."
}

# ─────────────────────────────────────
# 8. Add Privileges for HolidayCalendar
# ─────────────────────────────────────
Write-Host "Configuring privileges on HolidayCalendar table..." -ForegroundColor Cyan

$holidayLogicalName = "${PublisherPrefix}_holidaycalendar"

try {
    $holidayEntityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='$holidayLogicalName')?`$select=ObjectTypeCode" -Headers $headers

    $holidayPrivilegeNames = @(
        "prvCreate${holidayLogicalName}",
        "prvRead${holidayLogicalName}",
        "prvWrite${holidayLogicalName}",
        "prvDelete${holidayLogicalName}",
        "prvAppend${holidayLogicalName}",
        "prvAppendTo${holidayLogicalName}"
    )

    foreach ($privName in $holidayPrivilegeNames) {
        try {
            $privResult = Invoke-RestMethod -Uri "$apiBase/privileges?`$filter=name eq '$privName'&`$select=privilegeid" -Headers $headers
            if ($privResult.value.Count -gt 0) {
                $privId = $privResult.value[0].privilegeid
                Invoke-RestMethod -Uri "$apiBase/roles($roleId)/Microsoft.Dynamics.CRM.AddPrivilegesRole" -Method Post -Headers $headers -Body (@{
                    Privileges = @(@{ Depth = "Basic"; PrivilegeId = $privId; BusinessUnitId = $rootBuId })
                } | ConvertTo-Json -Depth 5)
                Write-Host "  Granted: $privName (Basic depth)" -ForegroundColor Green
            } else {
                Write-Warning "  Privilege '$privName' not found. Run provision-environment.ps1 first."
            }
        } catch {
            Write-Warning "  Failed to assign privilege '$privName': $($_.Exception.Message)"
        }
    }
} catch {
    Write-Warning "  HolidayCalendar table not found — skipping. Run provision-environment.ps1 first."
}

# ─────────────────────────────────────
# 9. Add Privileges for NudgeAnalytics
# ─────────────────────────────────────
Write-Host "Configuring privileges on NudgeAnalytics table..." -ForegroundColor Cyan

$analyticsLogicalName = "${PublisherPrefix}_nudgeanalytics"

try {
    $analyticsEntityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='$analyticsLogicalName')?`$select=ObjectTypeCode" -Headers $headers

    $analyticsPrivilegeNames = @(
        "prvCreate${analyticsLogicalName}",
        "prvRead${analyticsLogicalName}",
        "prvWrite${analyticsLogicalName}",
        "prvDelete${analyticsLogicalName}",
        "prvAppend${analyticsLogicalName}",
        "prvAppendTo${analyticsLogicalName}"
    )

    foreach ($privName in $analyticsPrivilegeNames) {
        try {
            $privResult = Invoke-RestMethod -Uri "$apiBase/privileges?`$filter=name eq '$privName'&`$select=privilegeid" -Headers $headers
            if ($privResult.value.Count -gt 0) {
                $privId = $privResult.value[0].privilegeid
                Invoke-RestMethod -Uri "$apiBase/roles($roleId)/Microsoft.Dynamics.CRM.AddPrivilegesRole" -Method Post -Headers $headers -Body (@{
                    Privileges = @(@{ Depth = "Basic"; PrivilegeId = $privId; BusinessUnitId = $rootBuId })
                } | ConvertTo-Json -Depth 5)
                Write-Host "  Granted: $privName (Basic depth)" -ForegroundColor Green
            } else {
                Write-Warning "  Privilege '$privName' not found. Run provision-environment.ps1 first."
            }
        } catch {
            Write-Warning "  Failed to assign privilege '$privName': $($_.Exception.Message)"
        }
    }
} catch {
    Write-Warning "  NudgeAnalytics table not found — skipping. Run provision-environment.ps1 first."
}

# ─────────────────────────────────────
# 10. Summary
# ─────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " SECURITY ROLES CONFIGURED" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Role: Email Productivity Agent User" -ForegroundColor White
Write-Host "Tables:" -ForegroundColor White
Write-Host "  - ${PublisherPrefix}_followuptracking (Follow-Up Tracking)" -ForegroundColor White
Write-Host "  - ${PublisherPrefix}_nudgeconfiguration (Nudge Configuration)" -ForegroundColor White
Write-Host "  - ${PublisherPrefix}_snoozedconversation (Snoozed Conversations) — if provisioned" -ForegroundColor White
Write-Host "  - ${PublisherPrefix}_prioritycontact (Priority Contacts) — if provisioned" -ForegroundColor White
Write-Host "  - ${PublisherPrefix}_holidaycalendar (Holiday Calendar) — if provisioned" -ForegroundColor White
Write-Host "  - ${PublisherPrefix}_nudgeanalytics (Nudge Analytics) — if provisioned" -ForegroundColor White
Write-Host "Depth: Basic (User-level) — each user sees only their own rows" -ForegroundColor White
Write-Host ""
Write-Host "NEXT STEP:" -ForegroundColor Yellow
Write-Host "  Assign this role to users who will use the Email Productivity Agent." -ForegroundColor White
Write-Host "  Admin Center → Environments → Settings → Users → [User] → Manage Roles" -ForegroundColor Gray
Write-Host ""
