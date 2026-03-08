<#
.SYNOPSIS
    Creates ownership-based security roles for the Enterprise Work Assistant.

.DESCRIPTION
    Creates an "Enterprise Work Assistant User" security role granting Basic (user-level)
    depth on the AssistantCards table. Each user sees only their own rows.

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
$azVer = az version --query '"azure-cli"' -o tsv 2>&1
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
Write-Host "Creating 'Enterprise Work Assistant User' security role..." -ForegroundColor Cyan

$roleDef = @{
    name = "Enterprise Work Assistant User"
    description = "Grants Basic (user-level) CRUD access to AssistantCards table. Users see only their own rows."
    "businessunitid@odata.bind" = "/businessunits($rootBuId)"
} | ConvertTo-Json

try {
    $roleResult = Invoke-RestMethod -Uri "$apiBase/roles" -Method Post -Headers $headers -Body $roleDef
    $roleId = $roleResult.roleid
    Write-Host "  Role created: $roleId" -ForegroundColor Green
} catch {
    # Role may already exist
    $existing = Invoke-RestMethod -Uri "$apiBase/roles?`$filter=name eq 'Enterprise Work Assistant User'&`$select=roleid" -Headers $headers
    if ($existing.value.Count -gt 0) {
        $roleId = $existing.value[0].roleid
        Write-Host "  Role already exists: $roleId" -ForegroundColor Yellow
    } else {
        throw "Failed to create security role: $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────
# 4. Add Privileges for AssistantCards
# ─────────────────────────────────────
Write-Host "Configuring privileges on AssistantCards table..." -ForegroundColor Cyan

# Get the entity metadata to find the object type code and actual SchemaName
$entityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='${PublisherPrefix}_assistantcard')?`$select=ObjectTypeCode,SchemaName" -Headers $headers
$objectTypeCode = $entityMeta.ObjectTypeCode

# Privilege names follow the pattern: prv{Action}{EntitySchemaName}
# Query the actual SchemaName from metadata rather than hardcoding case
$entitySchemaName = $entityMeta.SchemaName
$privilegeNames = @(
    "prvCreate${entitySchemaName}",
    "prvRead${entitySchemaName}",
    "prvWrite${entitySchemaName}",
    "prvDelete${entitySchemaName}",
    "prvAppend${entitySchemaName}",
    "prvAppendTo${entitySchemaName}"
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
            throw "Privilege '$privName' not found. The ${PublisherPrefix}_AssistantCard table may not be published yet. Import the solution first, then re-run this script."
        }
    } catch {
        throw "Failed to assign privilege '$privName': $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────
# 5. Add Privileges for SenderProfile (Sprint 1B)
# ─────────────────────────────────────
Write-Host "Configuring privileges on SenderProfile table..." -ForegroundColor Cyan

$senderLogicalName = "${PublisherPrefix}_senderprofile"
# Query actual SchemaName from metadata for correct privilege naming
try {
    $senderEntityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='$senderLogicalName')?`$select=ObjectTypeCode,SchemaName" -Headers $headers
    $senderObjectTypeCode = $senderEntityMeta.ObjectTypeCode
    $senderSchemaName = $senderEntityMeta.SchemaName

    $senderPrivilegeNames = @(
        "prvCreate${senderSchemaName}",
        "prvRead${senderSchemaName}",
        "prvWrite${senderSchemaName}",
        "prvDelete${senderSchemaName}",
        "prvAppend${senderSchemaName}",
        "prvAppendTo${senderSchemaName}"
    )

    foreach ($privName in $senderPrivilegeNames) {
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
    Write-Warning "  SenderProfile table not found — skipping. Run provision-environment.ps1 with Sprint 1B to create it."
}

# ─────────────────────────────────────
# 6. Add Privileges for BriefingSchedule
# ─────────────────────────────────────
Write-Host "Configuring privileges on BriefingSchedule table..." -ForegroundColor Cyan

$briefingLogicalName = "${PublisherPrefix}_briefingschedule"

# Check if table exists before configuring privileges
try {
    $briefingEntityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='$briefingLogicalName')?`$select=ObjectTypeCode,SchemaName" -Headers $headers
    $briefingObjectTypeCode = $briefingEntityMeta.ObjectTypeCode
    $briefingSchemaName = $briefingEntityMeta.SchemaName

    $briefingPrivilegeNames = @(
        "prvCreate${briefingSchemaName}",
        "prvRead${briefingSchemaName}",
        "prvWrite${briefingSchemaName}",
        "prvDelete${briefingSchemaName}",
        "prvAppend${briefingSchemaName}",
        "prvAppendTo${briefingSchemaName}"
    )

    foreach ($privName in $briefingPrivilegeNames) {
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
    Write-Warning "  BriefingSchedule table not found — skipping. Run provision-environment.ps1 with Phase 15 to create it."
}

# ─────────────────────────────────────
# 7. Add Privileges for EpisodicMemory
# ─────────────────────────────────────
Write-Host "Configuring privileges on EpisodicMemory table..." -ForegroundColor Cyan

$episodicLogicalName = "${PublisherPrefix}_episodicmemory"

# Check if table exists before configuring privileges
try {
    $episodicEntityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='$episodicLogicalName')?`$select=ObjectTypeCode,SchemaName" -Headers $headers
    $episodicObjectTypeCode = $episodicEntityMeta.ObjectTypeCode
    $episodicSchemaName = $episodicEntityMeta.SchemaName

    $episodicPrivilegeNames = @(
        "prvCreate${episodicSchemaName}",
        "prvRead${episodicSchemaName}",
        "prvWrite${episodicSchemaName}",
        "prvDelete${episodicSchemaName}",
        "prvAppend${episodicSchemaName}",
        "prvAppendTo${episodicSchemaName}"
    )

    foreach ($privName in $episodicPrivilegeNames) {
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
    Write-Warning "  EpisodicMemory table not found — skipping. Run provision-environment.ps1 to create it."
}

# ─────────────────────────────────────
# 8. Add Privileges for SemanticKnowledge
# ─────────────────────────────────────
Write-Host "Configuring privileges on SemanticKnowledge table..." -ForegroundColor Cyan

$semanticLogicalName = "${PublisherPrefix}_semanticknowledge"

# Check if table exists before configuring privileges
try {
    $semanticEntityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='$semanticLogicalName')?`$select=ObjectTypeCode,SchemaName" -Headers $headers
    $semanticObjectTypeCode = $semanticEntityMeta.ObjectTypeCode
    $semanticSchemaName = $semanticEntityMeta.SchemaName

    $semanticPrivilegeNames = @(
        "prvCreate${semanticSchemaName}",
        "prvRead${semanticSchemaName}",
        "prvWrite${semanticSchemaName}",
        "prvDelete${semanticSchemaName}",
        "prvAppend${semanticSchemaName}",
        "prvAppendTo${semanticSchemaName}"
    )

    foreach ($privName in $semanticPrivilegeNames) {
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
    Write-Warning "  SemanticKnowledge table not found — skipping. Run provision-environment.ps1 to create it."
}

# ─────────────────────────────────────
# 9. Add Privileges for UserPersona
# ─────────────────────────────────────
Write-Host "Configuring privileges on UserPersona table..." -ForegroundColor Cyan

$personaLogicalName = "${PublisherPrefix}_userpersona"

# Check if table exists before configuring privileges
try {
    $personaEntityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='$personaLogicalName')?`$select=ObjectTypeCode,SchemaName" -Headers $headers
    $personaObjectTypeCode = $personaEntityMeta.ObjectTypeCode
    $personaSchemaName = $personaEntityMeta.SchemaName

    $personaPrivilegeNames = @(
        "prvCreate${personaSchemaName}",
        "prvRead${personaSchemaName}",
        "prvWrite${personaSchemaName}",
        "prvDelete${personaSchemaName}",
        "prvAppend${personaSchemaName}",
        "prvAppendTo${personaSchemaName}"
    )

    foreach ($privName in $personaPrivilegeNames) {
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
    Write-Warning "  UserPersona table not found — skipping. Run provision-environment.ps1 to create it."
}

# ─────────────────────────────────────
# 10. Add Privileges for SkillRegistry
# ─────────────────────────────────────
Write-Host "Configuring privileges on SkillRegistry table..." -ForegroundColor Cyan

$skillLogicalName = "${PublisherPrefix}_skillregistry"

# Check if table exists before configuring privileges
try {
    $skillEntityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='$skillLogicalName')?`$select=ObjectTypeCode,SchemaName" -Headers $headers
    $skillObjectTypeCode = $skillEntityMeta.ObjectTypeCode
    $skillSchemaName = $skillEntityMeta.SchemaName

    $skillPrivilegeNames = @(
        "prvCreate${skillSchemaName}",
        "prvRead${skillSchemaName}",
        "prvWrite${skillSchemaName}",
        "prvDelete${skillSchemaName}",
        "prvAppend${skillSchemaName}",
        "prvAppendTo${skillSchemaName}"
    )

    foreach ($privName in $skillPrivilegeNames) {
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
    Write-Warning "  SkillRegistry table not found — skipping. Run provision-environment.ps1 to create it."
}

# ─────────────────────────────────────
# 11. Add Privileges for ErrorLog
# ─────────────────────────────────────
Write-Host "Configuring privileges on ErrorLog table..." -ForegroundColor Cyan

$errorLogLogicalName = "${PublisherPrefix}_errorlog"

# Check if table exists before configuring privileges
try {
    $errorLogEntityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='$errorLogLogicalName')?`$select=ObjectTypeCode,SchemaName" -Headers $headers
    $errorLogObjectTypeCode = $errorLogEntityMeta.ObjectTypeCode
    $errorLogSchemaName = $errorLogEntityMeta.SchemaName

    $errorLogPrivilegeNames = @(
        "prvCreate${errorLogSchemaName}",
        "prvRead${errorLogSchemaName}",
        "prvWrite${errorLogSchemaName}",
        "prvDelete${errorLogSchemaName}",
        "prvAppend${errorLogSchemaName}",
        "prvAppendTo${errorLogSchemaName}"
    )

    foreach ($privName in $errorLogPrivilegeNames) {
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
    Write-Warning "  ErrorLog table not found — skipping. Run provision-environment.ps1 to create it."
}

# ─────────────────────────────────────
# 12. Summary
# ─────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " SECURITY ROLES CONFIGURED" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Role: Enterprise Work Assistant User" -ForegroundColor White
Write-Host "Tables:" -ForegroundColor White
Write-Host "  - ${PublisherPrefix}_assistantcard (Assistant Cards)" -ForegroundColor White
Write-Host "  - ${PublisherPrefix}_senderprofile (Sender Profiles) — if provisioned" -ForegroundColor White
Write-Host "  - ${PublisherPrefix}_briefingschedule (Briefing Schedules) — if provisioned" -ForegroundColor White
Write-Host "  - ${PublisherPrefix}_episodicmemory (Episodic Memory) — if provisioned" -ForegroundColor White
Write-Host "  - ${PublisherPrefix}_semanticknowledge (Semantic Knowledge) — if provisioned" -ForegroundColor White
Write-Host "  - ${PublisherPrefix}_userpersona (User Persona) — if provisioned" -ForegroundColor White
Write-Host "  - ${PublisherPrefix}_skillregistry (Skill Registry) — if provisioned" -ForegroundColor White
Write-Host "  - ${PublisherPrefix}_errorlog (Error Log) — if provisioned" -ForegroundColor White
Write-Host "Depth: Basic (User-level) — each user sees only their own rows" -ForegroundColor White
Write-Host ""
Write-Host "NEXT STEP:" -ForegroundColor Yellow
Write-Host "  Assign this role to users who will use the Enterprise Work Assistant." -ForegroundColor White
Write-Host "  Admin Center → Environments → Settings → Users → [User] → Manage Roles" -ForegroundColor Gray
Write-Host ""
