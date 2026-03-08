<#
.SYNOPSIS
    Erases all user data from the Enterprise Work Assistant for GDPR right-to-erasure compliance.

.DESCRIPTION
    Deletes all Dataverse records owned by (or associated with) a specific user across all
    Enterprise Work Assistant tables. Optionally purges the user's OneNote sections if OneNote
    integration is enabled. Designed to satisfy GDPR Article 17 (Right to Erasure) and CCPA
    deletion requests within the 72-hour SLA.

    Tables purged (in dependency-safe order):
    1. cr_semanticepisodic    (junction records referencing episodic + semantic)
    2. cr_errorlogs           (rows where cr_affectedcardid references the user's cards)
    3. cr_assistantcards      (primary card table)
    4. cr_senderprofiles      (sender intelligence profiles)
    5. cr_episodicmemories    (decision history / episodic memory)
    6. cr_semanticknowledges  (long-term knowledge graph)
    7. cr_userpersonas        (behavioral persona snapshots)
    8. cr_skillregistries     (registered skill definitions)
    9. cr_briefingschedules   (daily briefing preferences)

    See docs/data-governance.md for the full erasure procedure and compliance context.

.PARAMETER OrgUrl
    Dataverse organization URL (required). Example: https://orgname.crm.dynamics.com

.PARAMETER UserEmail
    Email address of the user whose data should be erased (required).

.PARAMETER PublisherPrefix
    Dataverse publisher prefix for custom tables. Default: "cr"

.PARAMETER WhatIf
    Dry-run mode. Reports what WOULD be deleted without actually deleting any records.

.PARAMETER Force
    Skips the interactive confirmation prompt. Use in automated pipelines.

.EXAMPLE
    .\user-data-erasure.ps1 -OrgUrl "https://myorg.crm.dynamics.com" -UserEmail "jane@example.com" -WhatIf

.EXAMPLE
    .\user-data-erasure.ps1 -OrgUrl "https://myorg.crm.dynamics.com" -UserEmail "jane@example.com" -Force
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$OrgUrl,

    [Parameter(Mandatory = $true)]
    [string]$UserEmail,

    [string]$PublisherPrefix = "cr",

    [switch]$WhatIf,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

# ─────────────────────────────────────
# 0. Validate Prerequisites
# ─────────────────────────────────────
Write-Host "`n━━━ GDPR Right-to-Erasure ━━━" -ForegroundColor Cyan
Write-Host "Target user : $UserEmail"
Write-Host "Org URL     : $OrgUrl"
Write-Host "Mode        : $(if ($WhatIf) { 'DRY RUN (no records will be deleted)' } else { 'LIVE — records will be permanently deleted' })"
Write-Host ""

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) is not installed. Install from https://aka.ms/installazurecli"
}

$azAccount = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI is not authenticated. Run 'az login --tenant <tenant-id>' first."
}
Write-Host "  Azure CLI auth: OK" -ForegroundColor Green

# ─────────────────────────────────────
# 1. Authenticate & Build Headers
# ─────────────────────────────────────
Write-Host "Acquiring access token..." -ForegroundColor Cyan
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
if (-not $token) { throw "Failed to get access token. Ensure Azure CLI is authenticated (az login)." }

$headers = @{
    "Authorization"    = "Bearer $token"
    "Content-Type"     = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
    "Prefer"           = "odata.maxpagesize=5000"
}

$apiBase = "$OrgUrl/api/data/v9.2"

# ─────────────────────────────────────
# 2. Resolve User (SystemUser ID)
# ─────────────────────────────────────
Write-Host "Resolving user: $UserEmail..." -ForegroundColor Cyan

$userResult = Invoke-RestMethod -Uri "$apiBase/systemusers?`$filter=internalemailaddress eq '$UserEmail'&`$select=systemuserid,fullname" -Headers $headers
if ($userResult.value.Count -eq 0) {
    throw "No Dataverse system user found with email '$UserEmail'. Verify the email address."
}

$userId = $userResult.value[0].systemuserid
$userName = $userResult.value[0].fullname
Write-Host "  Resolved: $userName ($userId)" -ForegroundColor Green

# ─────────────────────────────────────
# 3. Confirmation Prompt
# ─────────────────────────────────────
if (-not $WhatIf -and -not $Force) {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║  WARNING: This will PERMANENTLY DELETE all data for:    ║" -ForegroundColor Red
    Write-Host "║  $($userName.PadRight(55))║" -ForegroundColor Red
    Write-Host "║  ($($UserEmail.PadRight(52)))║" -ForegroundColor Red
    Write-Host "║  This action CANNOT be undone.                         ║" -ForegroundColor Red
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    $confirm = Read-Host "Type 'DELETE' to confirm, or anything else to abort"
    if ($confirm -ne "DELETE") {
        Write-Host "Aborted by user." -ForegroundColor Yellow
        exit 0
    }
}

# ─────────────────────────────────────
# Helper: Query & Delete Records
# ─────────────────────────────────────
$totalDeleted = 0

function Remove-UserRecords {
    param(
        [string]$TableLogicalName,
        [string]$TableDisplayName,
        [string]$FilterQuery,
        [string]$PrimaryKeyField
    )

    Write-Host "`n  [$TableDisplayName] Querying..." -ForegroundColor Yellow

    try {
        $result = Invoke-RestMethod -Uri "$apiBase/${TableLogicalName}s?`$filter=$FilterQuery&`$select=$PrimaryKeyField" -Headers $headers -ErrorAction Stop
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 404) {
            Write-Host "    Table not provisioned — skipping." -ForegroundColor Gray
            return 0
        }
        throw
    }

    $records = $result.value
    $count = $records.Count

    if ($count -eq 0) {
        Write-Host "    No records found." -ForegroundColor Gray
        return 0
    }

    if ($WhatIf) {
        Write-Host "    WOULD DELETE: $count record(s)" -ForegroundColor Magenta
        return $count
    }

    Write-Host "    Deleting $count record(s)..." -ForegroundColor Red
    $deleted = 0
    foreach ($record in $records) {
        $recordId = $record.$PrimaryKeyField
        try {
            Invoke-RestMethod -Uri "$apiBase/${TableLogicalName}s($recordId)" -Method Delete -Headers $headers | Out-Null
            $deleted++
        } catch {
            Write-Warning "    Failed to delete $recordId : $($_.Exception.Message)"
        }
    }

    Write-Host "    Deleted: $deleted / $count" -ForegroundColor $(if ($deleted -eq $count) { "Green" } else { "Yellow" })
    return $deleted
}

# ─────────────────────────────────────
# 4. Collect User's Card IDs (needed for error log cleanup)
# ─────────────────────────────────────
Write-Host "`nPhase 1: Collecting card IDs for cross-reference cleanup..." -ForegroundColor Cyan

$userCardIds = @()
try {
    $cardResult = Invoke-RestMethod -Uri "$apiBase/${PublisherPrefix}_assistantcards?`$filter=_ownerid_value eq '$userId'&`$select=${PublisherPrefix}_assistantcardid" -Headers $headers
    $userCardIds = $cardResult.value | ForEach-Object { $_."${PublisherPrefix}_assistantcardid" }
    Write-Host "  Found $($userCardIds.Count) card(s) owned by user." -ForegroundColor Green
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 404) {
        Write-Host "  AssistantCards table not provisioned — skipping card collection." -ForegroundColor Gray
    } else {
        throw
    }
}

# ─────────────────────────────────────
# 5. Delete Records (dependency-safe order)
# ─────────────────────────────────────
Write-Host "`nPhase 2: Deleting records..." -ForegroundColor Cyan
$actionLabel = if ($WhatIf) { "Scanning" } else { "Deleting" }
Write-Host "  $actionLabel across all Enterprise Work Assistant tables..." -ForegroundColor Yellow

# 5a. Junction table first (references both episodic + semantic)
$totalDeleted += (Remove-UserRecords `
    -TableLogicalName "${PublisherPrefix}_semanticepisodic" `
    -TableDisplayName "Semantic-Episodic Junctions" `
    -FilterQuery "_ownerid_value eq '$userId'" `
    -PrimaryKeyField "${PublisherPrefix}_semanticepisodicid")

# 5b. Error logs referencing user's cards
if ($userCardIds.Count -gt 0) {
    Write-Host "`n  [Error Logs] Querying by affected card IDs..." -ForegroundColor Yellow
    $errorLogDeleted = 0
    foreach ($cardId in $userCardIds) {
        try {
            $errorResult = Invoke-RestMethod -Uri "$apiBase/${PublisherPrefix}_errorlogs?`$filter=${PublisherPrefix}_affectedcardid eq '$cardId'&`$select=${PublisherPrefix}_errorlogid" -Headers $headers -ErrorAction Stop
            foreach ($errorRecord in $errorResult.value) {
                $errorId = $errorRecord."${PublisherPrefix}_errorlogid"
                if ($WhatIf) {
                    $errorLogDeleted++
                } else {
                    try {
                        Invoke-RestMethod -Uri "$apiBase/${PublisherPrefix}_errorlogs($errorId)" -Method Delete -Headers $headers | Out-Null
                        $errorLogDeleted++
                    } catch {
                        Write-Warning "    Failed to delete error log $errorId : $($_.Exception.Message)"
                    }
                }
            }
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -eq 404) {
                Write-Host "    Error Logs table not provisioned — skipping." -ForegroundColor Gray
                break
            }
        }
    }
    if ($WhatIf) {
        Write-Host "    WOULD DELETE: $errorLogDeleted error log record(s)" -ForegroundColor Magenta
    } else {
        Write-Host "    Deleted: $errorLogDeleted error log record(s)" -ForegroundColor Green
    }
    $totalDeleted += $errorLogDeleted
} else {
    Write-Host "`n  [Error Logs] No card IDs to cross-reference — skipping." -ForegroundColor Gray
}

# 5c. Primary tables (ownership-based filter)
$ownershipTables = @(
    @{ Logical = "${PublisherPrefix}_assistantcard";    Display = "Assistant Cards";       PK = "${PublisherPrefix}_assistantcardid" },
    @{ Logical = "${PublisherPrefix}_senderprofile";    Display = "Sender Profiles";       PK = "${PublisherPrefix}_senderprofileid" },
    @{ Logical = "${PublisherPrefix}_episodicmemory";   Display = "Episodic Memories";     PK = "${PublisherPrefix}_episodicmemoryid" },
    @{ Logical = "${PublisherPrefix}_semanticknowledge";Display = "Semantic Knowledge";    PK = "${PublisherPrefix}_semanticknowledgeid" },
    @{ Logical = "${PublisherPrefix}_userpersona";      Display = "User Personas";         PK = "${PublisherPrefix}_userpersonaid" },
    @{ Logical = "${PublisherPrefix}_skillregistry";    Display = "Skill Registries";      PK = "${PublisherPrefix}_skillregistryid" },
    @{ Logical = "${PublisherPrefix}_briefingschedule"; Display = "Briefing Schedules";    PK = "${PublisherPrefix}_briefingscheduleid" }
)

foreach ($table in $ownershipTables) {
    $totalDeleted += (Remove-UserRecords `
        -TableLogicalName $table.Logical `
        -TableDisplayName $table.Display `
        -FilterQuery "_ownerid_value eq '$userId'" `
        -PrimaryKeyField $table.PK)
}

# ─────────────────────────────────────
# 6. OneNote Purge (if enabled)
# ─────────────────────────────────────
Write-Host "`nPhase 3: OneNote data purge..." -ForegroundColor Cyan

$oneNoteEnabled = $false
try {
    $configResult = Invoke-RestMethod -Uri "$apiBase/${PublisherPrefix}_assistantcards?`$filter=${PublisherPrefix}_onenoteenabled eq true&`$top=1&`$select=${PublisherPrefix}_assistantcardid" -Headers $headers -ErrorAction Stop
    if ($configResult.value.Count -gt 0) {
        $oneNoteEnabled = $true
    }
} catch {
    Write-Host "  Could not check OneNote feature flag — skipping OneNote purge." -ForegroundColor Gray
}

if ($oneNoteEnabled) {
    Write-Host "  OneNote integration is enabled. Attempting section purge via Graph API..." -ForegroundColor Yellow

    try {
        $graphToken = az account get-access-token --resource "https://graph.microsoft.com" --query accessToken -o tsv
        if (-not $graphToken) { throw "Failed to acquire Graph token." }

        $graphHeaders = @{
            "Authorization" = "Bearer $graphToken"
            "Content-Type"  = "application/json"
        }

        # Find notebooks in groups that match the EWA pattern
        $groupsResult = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=startswith(displayName,'Enterprise Work Assistant')&`$select=id,displayName" -Headers $graphHeaders
        $oneNoteSectionsDeleted = 0

        foreach ($group in $groupsResult.value) {
            $notebooks = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/groups/$($group.id)/onenote/notebooks?`$select=id,displayName" -Headers $graphHeaders -ErrorAction SilentlyContinue

            foreach ($notebook in $notebooks.value) {
                # Find sections whose name contains the user's name or email
                $sections = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/groups/$($group.id)/onenote/notebooks/$($notebook.id)/sections?`$select=id,displayName" -Headers $graphHeaders -ErrorAction SilentlyContinue

                foreach ($section in $sections.value) {
                    $userNameLower = $userName.ToLower()
                    $userEmailLower = $UserEmail.ToLower()
                    $sectionNameLower = $section.displayName.ToLower()

                    if ($sectionNameLower -like "*$userNameLower*" -or $sectionNameLower -like "*$userEmailLower*") {
                        if ($WhatIf) {
                            Write-Host "    WOULD DELETE section: '$($section.displayName)' in notebook '$($notebook.displayName)'" -ForegroundColor Magenta
                            $oneNoteSectionsDeleted++
                        } else {
                            try {
                                Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/groups/$($group.id)/onenote/sections/$($section.id)" -Method Delete -Headers $graphHeaders | Out-Null
                                Write-Host "    Deleted section: '$($section.displayName)'" -ForegroundColor Green
                                $oneNoteSectionsDeleted++
                            } catch {
                                Write-Warning "    Failed to delete section '$($section.displayName)': $($_.Exception.Message)"
                            }
                        }
                    }
                }
            }
        }

        if ($oneNoteSectionsDeleted -eq 0) {
            Write-Host "  No user-specific OneNote sections found." -ForegroundColor Gray
        } else {
            $verb = if ($WhatIf) { "would be deleted" } else { "deleted" }
            Write-Host "  $oneNoteSectionsDeleted OneNote section(s) $verb." -ForegroundColor Green
        }
    } catch {
        Write-Warning "  OneNote purge failed: $($_.Exception.Message)"
        Write-Warning "  Manual cleanup may be required. See docs/data-governance.md for instructions."
    }
} else {
    Write-Host "  OneNote integration not enabled — skipping." -ForegroundColor Gray
}

# ─────────────────────────────────────
# 7. Summary
# ─────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
if ($WhatIf) {
    Write-Host " DRY RUN COMPLETE" -ForegroundColor Yellow
} else {
    Write-Host " DATA ERASURE COMPLETE" -ForegroundColor Green
}
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "User     : $userName ($UserEmail)" -ForegroundColor White
Write-Host "Records  : $totalDeleted $(if ($WhatIf) { 'would be deleted' } else { 'deleted' })" -ForegroundColor White
Write-Host ""

if ($WhatIf) {
    Write-Host "NEXT STEP:" -ForegroundColor Yellow
    Write-Host "  Re-run without -WhatIf to perform the actual deletion." -ForegroundColor White
    Write-Host "  .\user-data-erasure.ps1 -OrgUrl `"$OrgUrl`" -UserEmail `"$UserEmail`"" -ForegroundColor Gray
} else {
    Write-Host "RECORD KEEPING:" -ForegroundColor Yellow
    Write-Host "  1. Document this erasure in your GDPR data subject request log." -ForegroundColor White
    Write-Host "  2. Retain proof of deletion (this console output) for audit purposes." -ForegroundColor White
    Write-Host "  3. Confirm completion to the data subject within the 72-hour SLA." -ForegroundColor White
}
Write-Host ""
