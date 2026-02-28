<#
.SYNOPSIS
    Provisions the Power Platform environment and Dataverse table for the Enterprise Work Assistant.

.DESCRIPTION
    Creates a Power Platform environment, provisions the AssistantCards Dataverse table
    with all required columns, and enables PCF components for Canvas apps.

.PARAMETER TenantId
    Azure AD Tenant ID (required).

.PARAMETER EnvironmentName
    Display name for the new environment. Default: "EnterpriseWorkAssistant-Dev"

.PARAMETER EnvironmentType
    Environment type: Sandbox or Production. Default: "Sandbox"

.PARAMETER Region
    Deployment region. Default: "unitedstates"

.PARAMETER AdminEmail
    Admin email to assign as environment admin (optional).

.PARAMETER PublisherPrefix
    Dataverse publisher prefix for custom columns. Default: "cr"

.EXAMPLE
    .\provision-environment.ps1 -TenantId "abc-123" -AdminEmail "admin@contoso.com"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [string]$EnvironmentName = "EnterpriseWorkAssistant-Dev",

    [ValidateSet("Sandbox", "Production")]
    [string]$EnvironmentType = "Sandbox",

    [string]$Region = "unitedstates",

    [string]$AdminEmail,

    [string]$PublisherPrefix = "cr"
)

$ErrorActionPreference = "Stop"

# ─────────────────────────────────────
# 0. Prerequisite Validation
# ─────────────────────────────────────
if (-not (Get-Command "pac" -ErrorAction SilentlyContinue)) { throw "PAC CLI not found. Install with: dotnet tool install --global Microsoft.PowerApps.CLI.Tool" }
if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) { throw "Azure CLI not found. Install with: brew install azure-cli (macOS) or winget install Microsoft.AzureCLI (Windows)" }

# ─────────────────────────────────────
# 1. Authenticate with PAC CLI
# ─────────────────────────────────────
Write-Host "Authenticating with Power Platform..." -ForegroundColor Cyan
pac auth create --tenant $TenantId
if ($LASTEXITCODE -ne 0) { throw "Authentication failed." }

# ─────────────────────────────────────
# 2. Create Environment
# ─────────────────────────────────────
Write-Host "Creating environment: $EnvironmentName..." -ForegroundColor Cyan
$envResult = pac admin create `
    --name $EnvironmentName `
    --type $EnvironmentType `
    --region $Region `
    --currency USD `
    --language 1033 `
    --domain (($EnvironmentName -replace '[^a-zA-Z0-9]', '').ToLower().Substring(0, [Math]::Min(($EnvironmentName -replace '[^a-zA-Z0-9]', '').Length, 22))) `
    --async

# Poll for environment readiness
Write-Host "Waiting for environment provisioning..." -ForegroundColor Yellow
$maxAttempts = 30
$attempt = 0
do {
    Start-Sleep -Seconds 10
    $attempt++
    $envListRaw = pac admin list --json 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "  pac admin list failed, retrying..." -ForegroundColor Yellow; continue }
    $envList = $envListRaw | ConvertFrom-Json
    $env = $envList | Where-Object { $_.DisplayName -eq $EnvironmentName }
    if ($env -and $env.EnvironmentUrl) {
        Write-Host "Environment ready." -ForegroundColor Green
        break
    }
    Write-Host "  Attempt $attempt/$maxAttempts - Waiting for environment..."
} while ($attempt -lt $maxAttempts)

if ($attempt -ge $maxAttempts) { throw "Environment provisioning timed out after $($maxAttempts * 10) seconds." }

$OrgUrl = $env.EnvironmentUrl.TrimEnd('/')
$EnvironmentId = $env.EnvironmentId
Write-Host "Environment URL: $OrgUrl" -ForegroundColor Green
Write-Host "Environment ID: $EnvironmentId" -ForegroundColor Green

# Select the new environment
pac org select --environment $EnvironmentId

# ─────────────────────────────────────
# 3. Create AssistantCards Table via Dataverse Web API
# ─────────────────────────────────────
Write-Host "Creating AssistantCards Dataverse table..." -ForegroundColor Cyan

# Authenticate Azure CLI (required for Dataverse API token — separate from PAC CLI auth)
Write-Host "Authenticating Azure CLI for Dataverse API access..." -ForegroundColor Cyan
az login --tenant $TenantId
if ($LASTEXITCODE -ne 0) { throw "Azure CLI login failed. Ensure Azure CLI is installed ('az --version') and try 'az login --tenant $TenantId' manually." }

# Get access token for Dataverse via Azure CLI (pac auth token does not exist)
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
if (-not $token) { throw "Failed to get access token. Verify 'az login' succeeded and you have access to the Dataverse environment." }
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version" = "4.0"
}

$apiBase = "$OrgUrl/api/data/v9.2"

# ─────────────────────────────────────
# 2a. Validate/Create Publisher Prefix
# ─────────────────────────────────────
Write-Host "Validating publisher prefix '$PublisherPrefix'..." -ForegroundColor Cyan

try {
    $publisherResult = Invoke-RestMethod -Uri "$apiBase/publishers?`$filter=customizationprefix eq '$PublisherPrefix'&`$select=publisherid,uniquename,friendlyname,customizationprefix" -Headers $headers
    if ($publisherResult.value.Count -gt 0) {
        $existingPublisher = $publisherResult.value[0]
        Write-Host "  Publisher '$PublisherPrefix' already exists: $($existingPublisher.friendlyname) ($($existingPublisher.uniquename))" -ForegroundColor Green
    } else {
        Write-Host "  Publisher '$PublisherPrefix' not found. Creating..." -ForegroundColor Yellow
        $publisherDef = @{
            uniquename = "${PublisherPrefix}publisher"
            friendlyname = "Enterprise Work Assistant Publisher"
            customizationprefix = $PublisherPrefix
            customizationoptionvalueprefix = 10000
            description = "Publisher for the Enterprise Work Assistant solution."
        } | ConvertTo-Json

        Invoke-RestMethod -Uri "$apiBase/publishers" -Method Post -Headers $headers -Body $publisherDef
        Write-Host "  Publisher '$PublisherPrefix' created successfully." -ForegroundColor Green
    }
} catch {
    throw "Failed to validate/create publisher prefix '$PublisherPrefix': $($_.Exception.Message). Ensure the authenticated user has System Administrator or System Customizer role."
}

# Create the entity (table)
$entityDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "${PublisherPrefix}_assistantcard"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Assistant Card"
            LanguageCode = 1033
        })
    }
    DisplayCollectionName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Assistant Cards"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Stores structured output from the Enterprise Work Assistant agent."
            LanguageCode = 1033
        })
    }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    PrimaryNameAttribute = "${PublisherPrefix}_itemsummary"
    Attributes = @(
        # Primary Name (Item Summary) - Text 300 chars
        @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            SchemaName = "${PublisherPrefix}_itemsummary"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            MaxLength = 300
            DisplayName = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Item Summary"
                    LanguageCode = 1033
                })
            }
            Description = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "1-2 sentence summary of the triggering item."
                    LanguageCode = 1033
                })
            }
        }
    )
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" -Method Post -Headers $headers -Body $entityDef
    Write-Host "  Table created." -ForegroundColor Green
} catch {
    Write-Warning "  Table creation failed (may already exist): $($_.Exception.Message)"
}

# Helper to get entity metadata ID
$entityMetadata = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='${PublisherPrefix}_assistantcard')" -Headers $headers
$entityId = $entityMetadata.MetadataId

# ─────────────────────────────────────
# 3a. Add Choice Columns
# ─────────────────────────────────────
function New-ChoiceColumn {
    param(
        [string]$SchemaName,
        [string]$DisplayName,
        [string]$Description,
        [array]$Options,
        [bool]$Required = $true
    )

    $optionSet = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        SchemaName = $SchemaName
        RequiredLevel = @{ Value = if ($Required) { "ApplicationRequired" } else { "None" } }
        DisplayName = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.Label"
            LocalizedLabels = @(@{
                "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                Label = $DisplayName
                LanguageCode = 1033
            })
        }
        Description = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.Label"
            LocalizedLabels = @(@{
                "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                Label = $Description
                LanguageCode = 1033
            })
        }
        OptionSet = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
            IsGlobal = $false
            OptionSetType = "Picklist"
            Options = @($Options | ForEach-Object {
                @{
                    Value = $_.Value
                    Label = @{
                        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                        LocalizedLabels = @(@{
                            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                            Label = $_.Label
                            LanguageCode = 1033
                        })
                    }
                }
            })
        }
    } | ConvertTo-Json -Depth 20

    try {
        Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($entityId)/Attributes" -Method Post -Headers $headers -Body $optionSet
        Write-Host "  Column '$DisplayName' created." -ForegroundColor Green
    } catch {
        Write-Warning "  Column '$DisplayName' failed: $($_.Exception.Message)"
    }
}

# Triage Tier
New-ChoiceColumn -SchemaName "${PublisherPrefix}_triagetier" -DisplayName "Triage Tier" `
    -Description "Classification tier assigned during triage." `
    -Options @(
        @{ Label = "SKIP"; Value = 100000000 },
        @{ Label = "LIGHT"; Value = 100000001 },
        @{ Label = "FULL"; Value = 100000002 }
    )

# Trigger Type
New-ChoiceColumn -SchemaName "${PublisherPrefix}_triggertype" -DisplayName "Trigger Type" `
    -Description "The type of incoming signal." `
    -Options @(
        @{ Label = "EMAIL"; Value = 100000000 },
        @{ Label = "TEAMS_MESSAGE"; Value = 100000001 },
        @{ Label = "CALENDAR_SCAN"; Value = 100000002 },
        @{ Label = "DAILY_BRIEFING"; Value = 100000003 },
        @{ Label = "SELF_REMINDER"; Value = 100000004 },
        @{ Label = "COMMAND_RESULT"; Value = 100000005 }
    )

# Priority
New-ChoiceColumn -SchemaName "${PublisherPrefix}_priority" -DisplayName "Priority" `
    -Description "Priority level assigned during triage." `
    -Options @(
        @{ Label = "High"; Value = 100000000 },
        @{ Label = "Medium"; Value = 100000001 },
        @{ Label = "Low"; Value = 100000002 },
        @{ Label = "N/A"; Value = 100000003 }
    )

# Card Status
New-ChoiceColumn -SchemaName "${PublisherPrefix}_cardstatus" -DisplayName "Card Status" `
    -Description "Processing status of the card." `
    -Options @(
        @{ Label = "READY"; Value = 100000000 },
        @{ Label = "LOW_CONFIDENCE"; Value = 100000001 },
        @{ Label = "SUMMARY_ONLY"; Value = 100000002 },
        @{ Label = "NO_OUTPUT"; Value = 100000003 },
        @{ Label = "NUDGE"; Value = 100000004 }
    )

# Temporal Horizon
New-ChoiceColumn -SchemaName "${PublisherPrefix}_temporalhorizon" -DisplayName "Temporal Horizon" `
    -Description "Temporal horizon for calendar items." `
    -Required $false `
    -Options @(
        @{ Label = "TODAY"; Value = 100000000 },
        @{ Label = "THIS_WEEK"; Value = 100000001 },
        @{ Label = "NEXT_WEEK"; Value = 100000002 },
        @{ Label = "BEYOND"; Value = 100000003 },
        @{ Label = "N/A"; Value = 100000004 }
    )

# ─────────────────────────────────────
# 3a-2. Sprint 1A — Card Outcome Choice Column
# ─────────────────────────────────────

New-ChoiceColumn -SchemaName "${PublisherPrefix}_cardoutcome" -DisplayName "Card Outcome" `
    -Description "What the user did with this card." `
    -Required $false `
    -Options @(
        @{ Label = "PENDING"; Value = 100000000 },
        @{ Label = "SENT_AS_IS"; Value = 100000001 },
        @{ Label = "SENT_EDITED"; Value = 100000002 },
        @{ Label = "DISMISSED"; Value = 100000003 },
        @{ Label = "EXPIRED"; Value = 100000004 }
    )

# ─────────────────────────────────────
# 3b. Add Numeric and Text Columns
# ─────────────────────────────────────

# Confidence Score (WholeNumber)
$confidenceCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
    SchemaName = "${PublisherPrefix}_confidencescore"
    RequiredLevel = @{ Value = "None" }
    MinValue = 0
    MaxValue = 100
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Confidence Score"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Confidence score 0-100."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($entityId)/Attributes" -Method Post -Headers $headers -Body $confidenceCol
    Write-Host "  Column 'Confidence Score' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Confidence Score' failed: $($_.Exception.Message)"
}

# Full JSON (Multiline Text, 1M chars)
$fullJsonCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
    SchemaName = "${PublisherPrefix}_fulljson"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    MaxLength = 1048576
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Full JSON Output"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Complete JSON output from the agent."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($entityId)/Attributes" -Method Post -Headers $headers -Body $fullJsonCol
    Write-Host "  Column 'Full JSON Output' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Full JSON Output' failed: $($_.Exception.Message)"
}

# Humanized Draft (Multiline Text)
$humanizedCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
    SchemaName = "${PublisherPrefix}_humanizeddraft"
    RequiredLevel = @{ Value = "None" }
    MaxLength = 100000
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Humanized Draft"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Polished draft from the Humanizer Agent."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($entityId)/Attributes" -Method Post -Headers $headers -Body $humanizedCol
    Write-Host "  Column 'Humanized Draft' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Humanized Draft' failed: $($_.Exception.Message)"
}

# ─────────────────────────────────────
# 3c. Sprint 1A — Outcome Tracking & Send Audit Columns
# ─────────────────────────────────────

# Helper function for creating simple text columns (DRY pattern for Sprint 1A+ columns)
function New-TextColumn {
    param(
        [string]$SchemaName,
        [string]$DisplayName,
        [string]$Description,
        [int]$MaxLength = 200
    )

    $colDef = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        SchemaName = $SchemaName
        RequiredLevel = @{ Value = "None" }
        MaxLength = $MaxLength
        DisplayName = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.Label"
            LocalizedLabels = @(@{
                "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                Label = $DisplayName
                LanguageCode = 1033
            })
        }
        Description = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.Label"
            LocalizedLabels = @(@{
                "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                Label = $Description
                LanguageCode = 1033
            })
        }
    } | ConvertTo-Json -Depth 20

    try {
        Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($entityId)/Attributes" -Method Post -Headers $headers -Body $colDef
        Write-Host "  Column '$DisplayName' created." -ForegroundColor Green
    } catch {
        Write-Warning "  Column '$DisplayName' failed: $($_.Exception.Message)"
    }
}

# Helper function for creating DateTime columns
function New-DateTimeColumn {
    param(
        [string]$SchemaName,
        [string]$DisplayName,
        [string]$Description
    )

    $colDef = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        SchemaName = $SchemaName
        RequiredLevel = @{ Value = "None" }
        Format = "DateAndTime"
        DisplayName = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.Label"
            LocalizedLabels = @(@{
                "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                Label = $DisplayName
                LanguageCode = 1033
            })
        }
        Description = @{
            "@odata.type" = "Microsoft.Dynamics.CRM.Label"
            LocalizedLabels = @(@{
                "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                Label = $Description
                LanguageCode = 1033
            })
        }
    } | ConvertTo-Json -Depth 20

    try {
        Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($entityId)/Attributes" -Method Post -Headers $headers -Body $colDef
        Write-Host "  Column '$DisplayName' created." -ForegroundColor Green
    } catch {
        Write-Warning "  Column '$DisplayName' failed: $($_.Exception.Message)"
    }
}

# Outcome Timestamp
New-DateTimeColumn -SchemaName "${PublisherPrefix}_outcometimestamp" `
    -DisplayName "Outcome Timestamp" `
    -Description "When the user acted on this card."

# Sent Timestamp (audit)
New-DateTimeColumn -SchemaName "${PublisherPrefix}_senttimestamp" `
    -DisplayName "Sent Timestamp" `
    -Description "When the email was sent via the Send flow (audit trail)."

# Sent Recipient (audit)
New-TextColumn -SchemaName "${PublisherPrefix}_sentrecipient" `
    -DisplayName "Sent Recipient" -MaxLength 320 `
    -Description "Email address the draft was sent to (audit trail)."

# Original Sender Email
New-TextColumn -SchemaName "${PublisherPrefix}_originalsenderemail" `
    -DisplayName "Original Sender Email" -MaxLength 320 `
    -Description "Parsed email address of the original signal sender."

# Original Sender Display Name
New-TextColumn -SchemaName "${PublisherPrefix}_originalsenderdisplay" `
    -DisplayName "Original Sender Display" -MaxLength 200 `
    -Description "Display name of the original signal sender."

# Original Subject
New-TextColumn -SchemaName "${PublisherPrefix}_originalsubject" `
    -DisplayName "Original Subject" -MaxLength 400 `
    -Description "Subject line of the original signal."

# ─────────────────────────────────────
# 3d. Sprint 1B — Clustering & Source Signal Columns
# ─────────────────────────────────────

# Conversation Cluster ID
New-TextColumn -SchemaName "${PublisherPrefix}_conversationclusterid" `
    -DisplayName "Conversation Cluster ID" -MaxLength 200 `
    -Description "Groups related signals. EMAIL: conversationId. TEAMS: threadId. CALENDAR: seriesMasterId or normalized subject|organizer."

# Source Signal ID
New-TextColumn -SchemaName "${PublisherPrefix}_sourcesignalid" `
    -DisplayName "Source Signal ID" -MaxLength 500 `
    -Description "Unique ID of the original signal. EMAIL: internetMessageId. TEAMS: messageId. CALENDAR: eventId."

# ─────────────────────────────────────
# 4. Sprint 1B — Create Sender Profile Table
# ─────────────────────────────────────
Write-Host "Creating SenderProfile Dataverse table..." -ForegroundColor Cyan

$senderEntityDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "${PublisherPrefix}_senderprofile"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Sender Profile"
            LanguageCode = 1033
        })
    }
    DisplayCollectionName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Sender Profiles"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Aggregated sender intelligence built from signal history."
            LanguageCode = 1033
        })
    }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    PrimaryNameAttribute = "${PublisherPrefix}_senderemail"
    Attributes = @(
        # Primary Name — Sender Email (unique per user)
        @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            SchemaName = "${PublisherPrefix}_senderemail"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            MaxLength = 320
            DisplayName = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Sender Email"
                    LanguageCode = 1033
                })
            }
            Description = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Primary column — email address of the sender."
                    LanguageCode = 1033
                })
            }
        }
    )
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" -Method Post -Headers $headers -Body $senderEntityDef
    Write-Host "  SenderProfile table created." -ForegroundColor Green
} catch {
    Write-Warning "  SenderProfile table creation failed (may already exist): $($_.Exception.Message)"
}

# Get entity metadata ID for sender profile
$senderMetadata = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='${PublisherPrefix}_senderprofile')" -Headers $headers
$senderEntityId = $senderMetadata.MetadataId

# Add columns to SenderProfile table (reuse helper functions from section 3)

# Sender Display Name
$senderDisplayCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
    SchemaName = "${PublisherPrefix}_senderdisplayname"
    RequiredLevel = @{ Value = "None" }
    MaxLength = 200
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Sender Display Name"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Last known display name of the sender."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($senderEntityId)/Attributes" -Method Post -Headers $headers -Body $senderDisplayCol
    Write-Host "  Column 'Sender Display Name' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Sender Display Name' failed: $($_.Exception.Message)"
}

# Signal Count (WholeNumber)
$signalCountCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
    SchemaName = "${PublisherPrefix}_signalcount"
    RequiredLevel = @{ Value = "None" }
    MinValue = 0
    MaxValue = 2147483647
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Signal Count"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Total signals received from this sender."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($senderEntityId)/Attributes" -Method Post -Headers $headers -Body $signalCountCol
    Write-Host "  Column 'Signal Count' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Signal Count' failed: $($_.Exception.Message)"
}

# Response Count (WholeNumber)
$responseCountCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
    SchemaName = "${PublisherPrefix}_responsecount"
    RequiredLevel = @{ Value = "None" }
    MinValue = 0
    MaxValue = 2147483647
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Response Count"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Times user responded to this sender (SENT_AS_IS + SENT_EDITED)."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($senderEntityId)/Attributes" -Method Post -Headers $headers -Body $responseCountCol
    Write-Host "  Column 'Response Count' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Response Count' failed: $($_.Exception.Message)"
}

# Average Response Hours (Decimal)
$avgResponseCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
    SchemaName = "${PublisherPrefix}_avgresponsehours"
    RequiredLevel = @{ Value = "None" }
    MinValue = 0
    MaxValue = 99999
    Precision = 2
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Average Response Hours"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Mean hours between signal arrival and user action."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($senderEntityId)/Attributes" -Method Post -Headers $headers -Body $avgResponseCol
    Write-Host "  Column 'Average Response Hours' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Average Response Hours' failed: $($_.Exception.Message)"
}

# Last Signal Date (DateTime)
$lastSignalCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
    SchemaName = "${PublisherPrefix}_lastsignaldate"
    RequiredLevel = @{ Value = "None" }
    Format = "DateAndTime"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Last Signal Date"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Most recent signal from this sender."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($senderEntityId)/Attributes" -Method Post -Headers $headers -Body $lastSignalCol
    Write-Host "  Column 'Last Signal Date' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Last Signal Date' failed: $($_.Exception.Message)"
}

# Sender Category (Choice)
$senderCategoryCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    SchemaName = "${PublisherPrefix}_sendercategory"
    RequiredLevel = @{ Value = "None" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Sender Category"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Importance classification — auto-calculated or user-overridden."
            LanguageCode = 1033
        })
    }
    OptionSet = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
        IsGlobal = $false
        OptionSetType = "Picklist"
        Options = @(
            @{
                Value = 100000000
                Label = @{
                    "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                    LocalizedLabels = @(@{
                        "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                        Label = "AUTO_HIGH"
                        LanguageCode = 1033
                    })
                }
            },
            @{
                Value = 100000001
                Label = @{
                    "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                    LocalizedLabels = @(@{
                        "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                        Label = "AUTO_MEDIUM"
                        LanguageCode = 1033
                    })
                }
            },
            @{
                Value = 100000002
                Label = @{
                    "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                    LocalizedLabels = @(@{
                        "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                        Label = "AUTO_LOW"
                        LanguageCode = 1033
                    })
                }
            },
            @{
                Value = 100000003
                Label = @{
                    "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                    LocalizedLabels = @(@{
                        "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                        Label = "USER_OVERRIDE"
                        LanguageCode = 1033
                    })
                }
            }
        )
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($senderEntityId)/Attributes" -Method Post -Headers $headers -Body $senderCategoryCol
    Write-Host "  Column 'Sender Category' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Sender Category' failed: $($_.Exception.Message)"
}

# Is Internal (Boolean)
$isInternalCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
    SchemaName = "${PublisherPrefix}_isinternal"
    RequiredLevel = @{ Value = "None" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Is Internal"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Whether the sender is within the tenant."
            LanguageCode = 1033
        })
    }
    OptionSet = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.BooleanOptionSetMetadata"
        TrueOption = @{
            Value = 1
            Label = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Yes"
                    LanguageCode = 1033
                })
            }
        }
        FalseOption = @{
            Value = 0
            Label = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "No"
                    LanguageCode = 1033
                })
            }
        }
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($senderEntityId)/Attributes" -Method Post -Headers $headers -Body $isInternalCol
    Write-Host "  Column 'Is Internal' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Is Internal' failed: $($_.Exception.Message)"
}

# Sprint 4: Dismiss Count (WholeNumber)
$dismissCountCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
    SchemaName = "${PublisherPrefix}_dismisscount"
    RequiredLevel = @{ Value = "None" }
    MinValue = 0
    MaxValue = 100000
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Dismiss Count"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Times the user dismissed cards from this sender."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($senderEntityId)/Attributes" -Method Post -Headers $headers -Body $dismissCountCol
    Write-Host "  Column 'Dismiss Count' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Dismiss Count' failed: $($_.Exception.Message)"
}

# Sprint 4: Average Edit Distance (WholeNumber 0-100)
$avgEditDistCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
    SchemaName = "${PublisherPrefix}_avgeditdistance"
    RequiredLevel = @{ Value = "None" }
    MinValue = 0
    MaxValue = 100
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Average Edit Distance"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Average draft edit distance (0-100). Computed by Sender Profile Analyzer."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($senderEntityId)/Attributes" -Method Post -Headers $headers -Body $avgEditDistCol
    Write-Host "  Column 'Average Edit Distance' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Average Edit Distance' failed: $($_.Exception.Message)"
}

# Sprint 4: Response Rate (Decimal 0.0000 - 1.0000)
$responseRateCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
    SchemaName = "${PublisherPrefix}_responserate"
    RequiredLevel = @{ Value = "None" }
    Precision = 4
    MinValue = 0
    MaxValue = 1
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Response Rate"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Ratio of responded-to vs total signals. Computed by Sender Profile Analyzer."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($senderEntityId)/Attributes" -Method Post -Headers $headers -Body $responseRateCol
    Write-Host "  Column 'Response Rate' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Response Rate' failed: $($_.Exception.Message)"
}

# Sprint 4: Dismiss Rate (Decimal 0.0000 - 1.0000)
$dismissRateCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
    SchemaName = "${PublisherPrefix}_dismissrate"
    RequiredLevel = @{ Value = "None" }
    Precision = 4
    MinValue = 0
    MaxValue = 1
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Dismiss Rate"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Ratio of dismissed vs total signals. Computed by Sender Profile Analyzer."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($senderEntityId)/Attributes" -Method Post -Headers $headers -Body $dismissRateCol
    Write-Host "  Column 'Dismiss Rate' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Dismiss Rate' failed: $($_.Exception.Message)"
}

# ─────────────────────────────────────
# 4a. Create Alternate Key on SenderProfile (for upsert support)
# ─────────────────────────────────────
Write-Host "Creating alternate key on SenderProfile (cr_senderemail)..." -ForegroundColor Cyan

$altKeyDef = @{
    SchemaName = "${PublisherPrefix}_senderemail_key"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Sender Email Key"
            LanguageCode = 1033
        })
    }
    KeyAttributes = @("${PublisherPrefix}_senderemail")
} | ConvertTo-Json -Depth 20

try {
    $keyResult = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($senderEntityId)/Keys" -Method Post -Headers $headers -Body $altKeyDef
    Write-Host "  Alternate key creation initiated." -ForegroundColor Yellow

    # Poll for key activation (async operation)
    $keyId = $keyResult.MetadataId
    $keyAttempts = 0
    $keyMaxAttempts = 12  # 30s timeout (12 x 2.5s)
    do {
        Start-Sleep -Seconds 2.5
        $keyAttempts++
        $keyStatus = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($senderEntityId)/Keys($keyId)" -Headers $headers
        if ($keyStatus.EntityKeyIndexStatus -eq "Active") {
            Write-Host "  Alternate key active." -ForegroundColor Green
            break
        }
        Write-Host "  Key indexing... attempt $keyAttempts/$keyMaxAttempts (status: $($keyStatus.EntityKeyIndexStatus))"
    } while ($keyAttempts -lt $keyMaxAttempts)

    if ($keyAttempts -ge $keyMaxAttempts) {
        Write-Warning "  Alternate key not yet active after 30s. Check manually in Admin Center."
    }
} catch {
    Write-Warning "  Alternate key creation failed (may already exist): $($_.Exception.Message)"
}

# ─────────────────────────────────────
# 6. Enable PCF Components for Canvas Apps
# ─────────────────────────────────────
Write-Host "Enabling PCF components for Canvas apps..." -ForegroundColor Cyan
Write-Host "  Note: This requires Power Platform Admin API access." -ForegroundColor Yellow
Write-Host "  If this step fails, enable manually:" -ForegroundColor Yellow
Write-Host "    Admin Center → Environments → $EnvironmentName → Settings → Features → PCF for Canvas apps → ON" -ForegroundColor Yellow

# PCF for Canvas apps must be enabled manually — there is no CLI command for this.
Write-Warning "  MANUAL STEP: Enable PCF for Canvas apps in the Admin Center:"
Write-Host "    Admin Center → Environments → $EnvironmentName → Settings → Features → 'Allow publishing of canvas apps with code components' → ON" -ForegroundColor Yellow

# ─────────────────────────────────────
# 5. Print Manual Steps
# ─────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " PROVISIONING COMPLETE" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Environment: $EnvironmentName" -ForegroundColor White
Write-Host "URL: $OrgUrl" -ForegroundColor White
Write-Host "ID: $EnvironmentId" -ForegroundColor White
Write-Host ""
Write-Host "MANUAL STEPS REQUIRED:" -ForegroundColor Yellow
Write-Host "1. Create connection references in Power Automate for:" -ForegroundColor White
Write-Host "   - Office 365 Outlook (email triggers and actions)" -ForegroundColor Gray
Write-Host "   - Microsoft Teams (message triggers)" -ForegroundColor Gray
Write-Host "   - Office 365 Users (user profile lookup)" -ForegroundColor Gray
Write-Host "   - Microsoft Graph (calendar, people, search)" -ForegroundColor Gray
Write-Host "   - SharePoint (internal knowledge search)" -ForegroundColor Gray
Write-Host "2. Run create-security-roles.ps1 to set up RLS" -ForegroundColor White
Write-Host "3. Configure Copilot Studio agent (see deployment-guide.md)" -ForegroundColor White
Write-Host ""
