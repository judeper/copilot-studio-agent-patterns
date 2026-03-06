<#
.SYNOPSIS
    Assigns the "Email Productivity Agent User" security role to one or more users.

.DESCRIPTION
    Looks up the security role by name and assigns it to the specified user(s).
    If no UserEmails are provided, assigns the role to the currently authenticated user.

.PARAMETER OrgUrl
    Dataverse organization URL (required). Example: https://orgname.crm.dynamics.com

.PARAMETER UserEmails
    One or more user email addresses to assign the role to. If omitted, assigns to
    the currently authenticated user (caller of az login).

.EXAMPLE
    .\assign-security-role.ps1 -OrgUrl "https://myorg.crm.dynamics.com"
    .\assign-security-role.ps1 -OrgUrl "https://myorg.crm.dynamics.com" -UserEmails "user1@contoso.com","user2@contoso.com"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$OrgUrl,

    [string[]]$UserEmails
)

$ErrorActionPreference = "Stop"

# ─────────────────────────────────────
# 1. Authenticate
# ─────────────────────────────────────
Write-Host "Authenticating..." -ForegroundColor Cyan
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
if (-not $token) { throw "Failed to get access token. Run 'az login' first." }
$headers = @{
    "Authorization"    = "Bearer $token"
    "Content-Type"     = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
}
$apiBase = "$OrgUrl/api/data/v9.2"

# ─────────────────────────────────────
# 2. Find the security role
# ─────────────────────────────────────
Write-Host "Looking up security role..." -ForegroundColor Cyan
$roleResult = Invoke-RestMethod -Uri "$apiBase/roles?`$filter=name eq 'Email Productivity Agent User'&`$select=roleid,name" -Headers $headers
if ($roleResult.value.Count -eq 0) {
    throw "Security role 'Email Productivity Agent User' not found. Run create-security-roles.ps1 first."
}
$roleId = $roleResult.value[0].roleid
Write-Host "  Role: $($roleResult.value[0].name) ($roleId)" -ForegroundColor Green

# ─────────────────────────────────────
# 3. Resolve users
# ─────────────────────────────────────
$userIds = @()

if (-not $UserEmails -or $UserEmails.Count -eq 0) {
    # Assign to current user
    $whoami = Invoke-RestMethod -Uri "$apiBase/WhoAmI" -Headers $headers
    $userIds += $whoami.UserId
    Write-Host "  No UserEmails specified — assigning to current user ($($whoami.UserId))" -ForegroundColor Yellow
} else {
    foreach ($email in $UserEmails) {
        $userResult = Invoke-RestMethod -Uri "$apiBase/systemusers?`$filter=internalemailaddress eq '$email'&`$select=systemuserid,fullname" -Headers $headers
        if ($userResult.value.Count -gt 0) {
            $userIds += $userResult.value[0].systemuserid
            Write-Host "  Found: $($userResult.value[0].fullname) ($email) -> $($userResult.value[0].systemuserid)" -ForegroundColor Green
        } else {
            Write-Warning "  User '$email' not found in Dataverse. Skipping."
        }
    }
}

# ─────────────────────────────────────
# 4. Assign role to each user
# ─────────────────────────────────────
Write-Host "`nAssigning role..." -ForegroundColor Cyan
foreach ($uid in $userIds) {
    try {
        Invoke-RestMethod -Uri "$apiBase/systemusers($uid)/systemuserroles_association/`$ref" -Method Post -Headers $headers -Body (@{
            "@odata.id" = "$apiBase/roles($roleId)"
        } | ConvertTo-Json)
        Write-Host "  Assigned to $uid" -ForegroundColor Green
    } catch {
        $errMsg = $null
        if ($_.ErrorDetails.Message) {
            try { $errMsg = ($_.ErrorDetails.Message | ConvertFrom-Json).error.message } catch {}
        }
        if (-not $errMsg) { $errMsg = $_.Exception.Message }
        if ($errMsg -match "Cannot insert duplicate key") {
            Write-Host "  Already assigned to $uid" -ForegroundColor Yellow
        } else {
            Write-Warning "  Failed for $uid : $errMsg"
        }
    }
}

Write-Host "`n═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " ROLE ASSIGNMENT COMPLETE" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
