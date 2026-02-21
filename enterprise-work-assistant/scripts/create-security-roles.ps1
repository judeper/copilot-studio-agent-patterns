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

# Get the entity metadata to find the object type code
$entityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='${PublisherPrefix}_assistantcard')?`$select=ObjectTypeCode" -Headers $headers
$objectTypeCode = $entityMeta.ObjectTypeCode

# Privilege names follow the pattern: prv{Action}{EntitySchemaName}
$entityName = "${PublisherPrefix}_assistantcard"
$privilegeNames = @(
    "prvCreate${entityName}",
    "prvRead${entityName}",
    "prvWrite${entityName}",
    "prvDelete${entityName}",
    "prvAppend${entityName}",
    "prvAppendTo${entityName}"
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
            Write-Warning "  Privilege '$privName' not found. Table may not be published yet."
        }
    } catch {
        Write-Warning "  Failed to assign '$privName': $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────
# 5. Summary
# ─────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " SECURITY ROLES CONFIGURED" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Role: Enterprise Work Assistant User" -ForegroundColor White
Write-Host "Table: ${PublisherPrefix}_assistantcard (Assistant Cards)" -ForegroundColor White
Write-Host "Depth: Basic (User-level) — each user sees only their own rows" -ForegroundColor White
Write-Host ""
Write-Host "NEXT STEP:" -ForegroundColor Yellow
Write-Host "  Assign this role to users who will use the Enterprise Work Assistant." -ForegroundColor White
Write-Host "  Admin Center → Environments → Settings → Users → [User] → Manage Roles" -ForegroundColor Gray
Write-Host ""
