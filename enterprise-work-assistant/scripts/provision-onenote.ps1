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

.PARAMETER OrgUrl
    The Dataverse organization URL (e.g., https://org12345.crm.dynamics.com).
    Required for provisioning OneNote-specific columns on the AssistantCards table.

.PARAMETER PublisherPrefix
    Dataverse publisher prefix for custom columns. Defaults to "cr".

.PARAMETER GroupDisplayName
    Display name for the M365 Group. Defaults to "Enterprise Work Assistant - OneNote".

.PARAMETER NotebookDisplayName
    Display name for the OneNote notebook. Defaults to "Work Assistant".

.PARAMETER SkipGroupCreation
    If set, skips M365 Group creation and uses the GroupId parameter instead.

.PARAMETER GroupId
    Existing M365 Group ID. Required when -SkipGroupCreation is set.

.EXAMPLE
    .\provision-onenote.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000" -OrgUrl "https://org12345.crm.dynamics.com"

.EXAMPLE
    .\provision-onenote.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000" -OrgUrl "https://org12345.crm.dynamics.com" -SkipGroupCreation -GroupId "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [Parameter(Mandatory = $true)]
    [string]$OrgUrl,

    [string]$PublisherPrefix = "cr",

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

# ── Step 6: Provision OneNote Columns on AssistantCards Table ────────────────────

Write-Host "`n[6/6] OneNote Dataverse Columns" -ForegroundColor Yellow
Write-Host "  Adding OneNote-specific columns to the AssistantCards table..."

$dvOrgUrl = $OrgUrl.TrimEnd('/')
$dvToken = az account get-access-token --resource $dvOrgUrl --query accessToken -o tsv
if (-not $dvToken) {
    Write-Warning "  Failed to get Dataverse access token. Run 'az login' first."
    Write-Warning "  Skipping Dataverse column provisioning — create columns manually per schemas/dataverse-table.json."
} else {
    $dvHeaders = @{
        "Authorization"    = "Bearer $dvToken"
        "Content-Type"     = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
    }
    $dvApiBase = "$dvOrgUrl/api/data/v9.2"

    # Look up the AssistantCards entity metadata ID
    try {
        $entityMeta = Invoke-RestMethod -Uri "$dvApiBase/EntityDefinitions(LogicalName='${PublisherPrefix}_assistantcard')" -Headers $dvHeaders
        $dvEntityId = $entityMeta.MetadataId
    } catch {
        Write-Warning "  AssistantCards table not found. Run provision-environment.ps1 first."
        Write-Warning "  Skipping Dataverse column provisioning."
        $dvEntityId = $null
    }

    if ($dvEntityId) {
        # cr_onenotepageid — Text, max 500
        $pageIdCol = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            SchemaName    = "${PublisherPrefix}_onenotepageid"
            RequiredLevel = @{ Value = "None" }
            MaxLength     = 500
            DisplayName   = @{
                "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label         = "OneNote Page ID"
                    LanguageCode  = 1033
                })
            }
            Description = @{
                "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label         = "OneNote page ID for the corresponding knowledge page. Populated by flows that write to OneNote."
                    LanguageCode  = 1033
                })
            }
        } | ConvertTo-Json -Depth 20

        try {
            Invoke-RestMethod -Uri "$dvApiBase/EntityDefinitions($dvEntityId)/Attributes" -Method Post -Headers $dvHeaders -Body $pageIdCol
            Write-Host "  Column 'OneNote Page ID' created." -ForegroundColor Green
        } catch {
            Write-Warning "  Column 'OneNote Page ID' failed (may already exist): $($_.Exception.Message)"
        }

        # cr_onenotesyncstatus — Choice: SYNCED, FAILED, PENDING
        $syncStatusCol = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
            SchemaName    = "${PublisherPrefix}_onenotesyncstatus"
            RequiredLevel = @{ Value = "None" }
            DisplayName   = @{
                "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label         = "OneNote Sync Status"
                    LanguageCode  = 1033
                })
            }
            Description = @{
                "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label         = "Sync status for the OneNote page linked to this card. Canvas app displays a warning badge when FAILED."
                    LanguageCode  = 1033
                })
            }
            OptionSet = @{
                "@odata.type"   = "Microsoft.Dynamics.CRM.OptionSetMetadata"
                IsGlobal        = $false
                OptionSetType   = "Picklist"
                Options         = @(
                    @{
                        Value = 100000000
                        Label = @{
                            "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                            LocalizedLabels = @(@{
                                "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                                Label         = "SYNCED"
                                LanguageCode  = 1033
                            })
                        }
                    },
                    @{
                        Value = 100000001
                        Label = @{
                            "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                            LocalizedLabels = @(@{
                                "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                                Label         = "FAILED"
                                LanguageCode  = 1033
                            })
                        }
                    },
                    @{
                        Value = 100000002
                        Label = @{
                            "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                            LocalizedLabels = @(@{
                                "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                                Label         = "PENDING"
                                LanguageCode  = 1033
                            })
                        }
                    }
                )
            }
        } | ConvertTo-Json -Depth 20

        try {
            Invoke-RestMethod -Uri "$dvApiBase/EntityDefinitions($dvEntityId)/Attributes" -Method Post -Headers $dvHeaders -Body $syncStatusCol
            Write-Host "  Column 'OneNote Sync Status' created." -ForegroundColor Green
        } catch {
            Write-Warning "  Column 'OneNote Sync Status' failed (may already exist): $($_.Exception.Message)"
        }

        # cr_onenoteenabled — Boolean (org-level feature flag)
        $enabledCol = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
            SchemaName    = "${PublisherPrefix}_onenoteenabled"
            RequiredLevel = @{ Value = "None" }
            DisplayName   = @{
                "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label         = "OneNote Enabled"
                    LanguageCode  = 1033
                })
            }
            Description = @{
                "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label         = "Feature flag for OneNote integration. When false, all OneNote writes are skipped."
                    LanguageCode  = 1033
                })
            }
            OptionSet = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.BooleanOptionSetMetadata"
                TrueOption    = @{
                    Value = 1
                    Label = @{
                        "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                        LocalizedLabels = @(@{
                            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                            Label         = "Yes"
                            LanguageCode  = 1033
                        })
                    }
                }
                FalseOption = @{
                    Value = 0
                    Label = @{
                        "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                        LocalizedLabels = @(@{
                            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                            Label         = "No"
                            LanguageCode  = 1033
                        })
                    }
                }
            }
        } | ConvertTo-Json -Depth 20

        try {
            Invoke-RestMethod -Uri "$dvApiBase/EntityDefinitions($dvEntityId)/Attributes" -Method Post -Headers $dvHeaders -Body $enabledCol
            Write-Host "  Column 'OneNote Enabled' created." -ForegroundColor Green
        } catch {
            Write-Warning "  Column 'OneNote Enabled' failed (may already exist): $($_.Exception.Message)"
        }

        # cr_onenoteoptout — Boolean (per-user opt-out)
        $optOutCol = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
            SchemaName    = "${PublisherPrefix}_onenoteoptout"
            RequiredLevel = @{ Value = "None" }
            DisplayName   = @{
                "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label         = "OneNote Opt-Out"
                    LanguageCode  = 1033
                })
            }
            Description = @{
                "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label         = "Per-user preference to disable OneNote sync. When true, OneNote writes for this user are skipped."
                    LanguageCode  = 1033
                })
            }
            OptionSet = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.BooleanOptionSetMetadata"
                TrueOption    = @{
                    Value = 1
                    Label = @{
                        "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                        LocalizedLabels = @(@{
                            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                            Label         = "Yes"
                            LanguageCode  = 1033
                        })
                    }
                }
                FalseOption = @{
                    Value = 0
                    Label = @{
                        "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                        LocalizedLabels = @(@{
                            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                            Label         = "No"
                            LanguageCode  = 1033
                        })
                    }
                }
            }
        } | ConvertTo-Json -Depth 20

        try {
            Invoke-RestMethod -Uri "$dvApiBase/EntityDefinitions($dvEntityId)/Attributes" -Method Post -Headers $dvHeaders -Body $optOutCol
            Write-Host "  Column 'OneNote Opt-Out' created." -ForegroundColor Green
        } catch {
            Write-Warning "  Column 'OneNote Opt-Out' failed (may already exist): $($_.Exception.Message)"
        }

        Write-Host "  OneNote Dataverse columns provisioned." -ForegroundColor Green
    }
}

Write-Host "`n━━━ Provisioning Complete ━━━" -ForegroundColor Cyan
Write-Host "Next steps:"
Write-Host "  1. Configure these values as Power Automate environment variables"
Write-Host "  2. Set cr_onenoteenabled = true in the Dataverse config entity"
Write-Host "  3. See docs/onenote-integration.md for flow enhancement details`n"
