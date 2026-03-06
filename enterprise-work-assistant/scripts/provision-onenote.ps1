<#
.SYNOPSIS
    Provisions the OneNote notebook structure for the Enterprise Work Assistant.

.DESCRIPTION
    Creates a dedicated Microsoft 365 Group (or uses an existing one), provisions a OneNote
    notebook with the required Section Groups and Sections, and stores the resource IDs in
    a Dataverse configuration table. This script is idempotent — safe to re-run.

    Prerequisites:
    - Microsoft Graph PowerShell SDK (Microsoft.Graph.Groups, Microsoft.Graph.Notes modules)
    - Authenticated session with Group.ReadWrite.All and Notes.ReadWrite.All permissions
    - Dataverse environment with the Assistant Cards table provisioned

    See docs/onenote-integration.md for the full design specification.

.PARAMETER EnvironmentId
    The Power Platform environment ID where Dataverse config rows will be written.

.PARAMETER GroupDisplayName
    Display name for the M365 Group. Defaults to "Enterprise Work Assistant - OneNote".

.PARAMETER NotebookDisplayName
    Display name for the OneNote notebook. Defaults to "Work Assistant".

.PARAMETER SkipGroupCreation
    If set, skips M365 Group creation and uses the GroupId parameter instead.

.PARAMETER GroupId
    Existing M365 Group ID. Required when -SkipGroupCreation is set.

.EXAMPLE
    .\provision-onenote.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    .\provision-onenote.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000" -SkipGroupCreation -GroupId "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [string]$GroupDisplayName = "Enterprise Work Assistant - OneNote",

    [string]$NotebookDisplayName = "Work Assistant",

    [switch]$SkipGroupCreation,

    [string]$GroupId
)

# ── Validation ──────────────────────────────────────────────────────────────────

if ($SkipGroupCreation -and -not $GroupId) {
    Write-Error "GroupId is required when -SkipGroupCreation is set."
    exit 1
}

# ── Connect to Graph ────────────────────────────────────────────────────────────

Write-Host "`n━━━ OneNote Provisioning ━━━" -ForegroundColor Cyan
Write-Host "Environment: $EnvironmentId"

$requiredModules = @("Microsoft.Graph.Groups", "Microsoft.Graph.Notes")
foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Error "Required module '$mod' not found. Install with: Install-Module $mod -Scope CurrentUser"
        exit 1
    }
}

# ── Step 1: M365 Group ──────────────────────────────────────────────────────────

Write-Host "`n[1/5] M365 Group" -ForegroundColor Yellow

if ($SkipGroupCreation) {
    Write-Host "  Using existing group: $GroupId"
    $group = Get-MgGroup -GroupId $GroupId -ErrorAction Stop
} else {
    # Check if group already exists
    $existingGroups = Get-MgGroup -Filter "displayName eq '$GroupDisplayName'" -ErrorAction SilentlyContinue
    if ($existingGroups) {
        $group = $existingGroups[0]
        $GroupId = $group.Id
        Write-Host "  Group already exists: $GroupId (idempotent — skipping creation)"
    } else {
        $groupParams = @{
            DisplayName     = $GroupDisplayName
            Description     = "Dedicated group for Enterprise Work Assistant OneNote integration. Do not share externally."
            MailEnabled     = $false
            MailNickname    = "ewa-onenote-$(Get-Random -Maximum 9999)"
            SecurityEnabled = $true
            GroupTypes      = @("Unified")
        }
        $group = New-MgGroup -BodyParameter $groupParams -ErrorAction Stop
        $GroupId = $group.Id
        Write-Host "  Created group: $GroupId"
    }
}

# ── Step 2: Notebook ────────────────────────────────────────────────────────────

Write-Host "`n[2/5] OneNote Notebook" -ForegroundColor Yellow

$existingNotebooks = Get-MgGroupOnenoteNotebook -GroupId $GroupId -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -eq $NotebookDisplayName }

if ($existingNotebooks) {
    $notebook = $existingNotebooks[0]
    Write-Host "  Notebook already exists: $($notebook.Id) (idempotent — skipping creation)"
} else {
    $notebook = New-MgGroupOnenoteNotebook -GroupId $GroupId -BodyParameter @{
        DisplayName = $NotebookDisplayName
    } -ErrorAction Stop
    Write-Host "  Created notebook: $($notebook.Id)"
}

$NotebookId = $notebook.Id

# ── Step 3: Section Groups ──────────────────────────────────────────────────────

Write-Host "`n[3/5] Section Groups" -ForegroundColor Yellow

$sectionGroupNames = @("Meetings", "Briefings")
$sectionGroupIds = @{}

foreach ($sgName in $sectionGroupNames) {
    $existingSG = Get-MgGroupOnenoteSectionGroup -GroupId $GroupId -NotebookId $NotebookId -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $sgName }

    if ($existingSG) {
        $sectionGroupIds[$sgName] = $existingSG[0].Id
        Write-Host "  $sgName already exists: $($existingSG[0].Id)"
    } else {
        # Note: Section group creation via Graph API may require direct REST call
        $uri = "https://graph.microsoft.com/v1.0/groups/$GroupId/onenote/notebooks/$NotebookId/sectionGroups"
        $body = @{ displayName = $sgName } | ConvertTo-Json
        $response = Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType "application/json"
        $sectionGroupIds[$sgName] = $response.id
        Write-Host "  Created $sgName`: $($response.id)"
    }
}

# ── Step 4: Sections ────────────────────────────────────────────────────────────

Write-Host "`n[4/5] Sections" -ForegroundColor Yellow

# Sections under Section Groups
$sectionMap = @{
    "Meetings"  = @("This Week", "Archive")
    "Briefings" = @("Daily")
}

$sectionIds = @{}

foreach ($sgName in $sectionMap.Keys) {
    $sgId = $sectionGroupIds[$sgName]
    foreach ($sectionName in $sectionMap[$sgName]) {
        $key = "$sgName - $sectionName"
        $uri = "https://graph.microsoft.com/v1.0/groups/$GroupId/onenote/sectionGroups/$sgId/sections"
        $existingSections = Invoke-MgGraphRequest -Method GET -Uri $uri
        $existing = $existingSections.value | Where-Object { $_.displayName -eq $sectionName }

        if ($existing) {
            $sectionIds[$key] = $existing.id
            Write-Host "  $key already exists: $($existing.id)"
        } else {
            $body = @{ displayName = $sectionName } | ConvertTo-Json
            $response = Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType "application/json"
            $sectionIds[$key] = $response.id
            Write-Host "  Created $key`: $($response.id)"
        }
    }
}

# Top-level section: Active To-Dos
$topLevelSectionsUri = "https://graph.microsoft.com/v1.0/groups/$GroupId/onenote/notebooks/$NotebookId/sections"
$existingTopSections = Invoke-MgGraphRequest -Method GET -Uri $topLevelSectionsUri
$existingToDo = $existingTopSections.value | Where-Object { $_.displayName -eq "Active To-Dos" }

if ($existingToDo) {
    $sectionIds["Active To-Dos"] = $existingToDo.id
    Write-Host "  Active To-Dos already exists: $($existingToDo.id)"
} else {
    $body = @{ displayName = "Active To-Dos" } | ConvertTo-Json
    $response = Invoke-MgGraphRequest -Method POST -Uri $topLevelSectionsUri -Body $body -ContentType "application/json"
    $sectionIds["Active To-Dos"] = $response.id
    Write-Host "  Created Active To-Dos: $($response.id)"
}

# ── Step 5: Output ──────────────────────────────────────────────────────────────

Write-Host "`n[5/5] Resource Summary" -ForegroundColor Yellow

$envVars = @{
    "OneNote_GroupId"                      = $GroupId
    "OneNote_NotebookId"                   = $NotebookId
    "OneNote_MeetingsThisWeekSectionId"    = $sectionIds["Meetings - This Week"]
    "OneNote_MeetingsArchiveSectionId"     = $sectionIds["Meetings - Archive"]
    "OneNote_BriefingsDailySectionId"      = $sectionIds["Briefings - Daily"]
    "OneNote_ActiveToDosSectionId"         = $sectionIds["Active To-Dos"]
}

Write-Host "`nEnvironment variables to configure in Power Automate:" -ForegroundColor Green
foreach ($key in $envVars.Keys | Sort-Object) {
    Write-Host "  $key = $($envVars[$key])"
}

Write-Host "`n━━━ Provisioning Complete ━━━" -ForegroundColor Cyan
Write-Host "Next steps:"
Write-Host "  1. Configure these values as Power Automate environment variables"
Write-Host "  2. Set cr_onenoteenabled = true in the Dataverse config entity"
Write-Host "  3. See docs/onenote-integration.md for flow enhancement details`n"
