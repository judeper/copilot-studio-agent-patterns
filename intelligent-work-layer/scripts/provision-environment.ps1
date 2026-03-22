<#
.SYNOPSIS
    Provisions the Power Platform environment and Dataverse table for the Intelligent Work Layer.

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
# 2. Create Environment (idempotent — reuses existing)
# ─────────────────────────────────────
Write-Host "Checking for existing environment: $EnvironmentName..." -ForegroundColor Cyan
$existingEnvRaw = pac admin list --json 2>&1
if ($LASTEXITCODE -eq 0) {
    $existingEnvList = $existingEnvRaw | ConvertFrom-Json
    $existingEnv = @($existingEnvList | Where-Object { $_.DisplayName -eq $EnvironmentName -and $_.EnvironmentUrl }) | Select-Object -First 1
}

if ($existingEnv) {
    Write-Host "  Environment '$EnvironmentName' already exists — reusing." -ForegroundColor Green
    $env = $existingEnv
} else {
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
        $envMatches = @($envList | Where-Object { $_.DisplayName -eq $EnvironmentName })
        $env = $envMatches | Select-Object -First 1
        if ($env -and $env.EnvironmentUrl) {
            Write-Host "Environment ready." -ForegroundColor Green
            break
        }
        Write-Host "  Attempt $attempt/$maxAttempts - Waiting for environment..."
    } while ($attempt -lt $maxAttempts)

    if ($attempt -ge $maxAttempts) { throw "Environment provisioning timed out after $($maxAttempts * 10) seconds." }
}

$OrgUrl = $env.EnvironmentUrl.TrimEnd('/')
$EnvironmentId = $env.EnvironmentId
Write-Host "Environment URL: $OrgUrl" -ForegroundColor Green
Write-Host "Environment ID: $EnvironmentId" -ForegroundColor Green

# Select the new environment
pac org select --environment $EnvironmentId

# ─────────────────────────────────────
# 2b. Enable PCF for Canvas Apps
# ─────────────────────────────────────
Write-Host "Enabling PCF for Canvas apps..." -ForegroundColor Cyan
try {
    $adminApiToken = az account get-access-token --resource "https://api.bap.microsoft.com/" --query accessToken -o tsv 2>$null
    if (-not $adminApiToken) {
        Write-Host "  No cached admin API token — running az login..." -ForegroundColor Yellow
        az login --tenant $TenantId | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Azure CLI login failed. Ensure Azure CLI is installed ('az --version') and try 'az login --tenant $TenantId' manually." }
        $adminApiToken = az account get-access-token --resource "https://api.bap.microsoft.com/" --query accessToken -o tsv
        if (-not $adminApiToken) { throw "Failed to get Power Platform Admin API token." }
    }

    $adminApiHeaders = @{
        "Authorization" = "Bearer $adminApiToken"
        "Content-Type"  = "application/json"
    }
    $adminApiUri = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$EnvironmentId?api-version=2021-04-01"
    $environmentSettings = Invoke-RestMethod -Uri $adminApiUri -Headers $adminApiHeaders -Method Get
    $pcfEnabled = $environmentSettings.properties.powerPlatform.powerApps.enableCodeComponentsForCanvasApps

    if ($pcfEnabled -eq $true) {
        Write-Host "  PCF for Canvas apps is already enabled." -ForegroundColor Green
    } else {
        $pcfEnableBody = @{
            properties = @{
                powerPlatform = @{
                    powerApps = @{
                        disableCreateFromFigma = $false
                        enableCodeComponentsForCanvasApps = $true
                    }
                }
            }
        } | ConvertTo-Json -Depth 10

        Invoke-RestMethod -Uri $adminApiUri -Headers $adminApiHeaders -Method Patch -Body $pcfEnableBody | Out-Null
        Write-Host "  PCF for Canvas apps enabled." -ForegroundColor Green
    }
} catch {
    Write-Host "  Automatic PCF enablement failed: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "  Please enable 'Allow publishing of canvas apps with code components' manually in Power Platform Admin Center." -ForegroundColor Yellow
}

# ─────────────────────────────────────
# 3. Create AssistantCards Table via Dataverse Web API
# ─────────────────────────────────────
Write-Host "Creating AssistantCards Dataverse table..." -ForegroundColor Cyan

# Get access token for Dataverse via Azure CLI (assumes az login was already run)
Write-Host "Acquiring Dataverse API token via Azure CLI..." -ForegroundColor Cyan
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv 2>$null
if (-not $token) {
    Write-Host "  No cached token — running az login..." -ForegroundColor Yellow
    az login --tenant $TenantId
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI login failed. Ensure Azure CLI is installed ('az --version') and try 'az login --tenant $TenantId' manually." }
    $token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
    if (-not $token) { throw "Failed to get access token. Verify 'az login' succeeded and you have access to the Dataverse environment." }
}
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version" = "4.0"
}

# Token refresh helper — re-acquires the token every 20 API calls to avoid expiration during long provisioning runs
$script:apiCallCounter = 0
function Refresh-TokenIfNeeded {
    $script:apiCallCounter++
    if ($script:apiCallCounter % 20 -eq 0) {
        Write-Host "  Refreshing access token (after $($script:apiCallCounter) API calls)..." -ForegroundColor Yellow
        $freshToken = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
        if ($freshToken) {
            $script:token = $freshToken
            $headers["Authorization"] = "Bearer $freshToken"
        } else {
            Write-Warning "  Token refresh failed — continuing with existing token."
        }
    }
}

# Retry helper — Dataverse entity metadata isn't immediately available after creation
function Get-EntityMetadataWithRetry {
    param([string]$LogicalName, [int]$MaxAttempts = 6, [int]$DelaySeconds = 10)
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            Refresh-TokenIfNeeded
            $result = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='$LogicalName')" -Headers $headers
            return $result
        } catch {
            if ($i -eq $MaxAttempts) { throw "Entity '$LogicalName' not found after $MaxAttempts attempts: $($_.Exception.Message)" }
            Write-Host "  Waiting for '$LogicalName' to propagate... attempt $i/$MaxAttempts" -ForegroundColor Yellow
            Start-Sleep -Seconds $DelaySeconds
        }
    }
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
            friendlyname = "Intelligent Work Layer Publisher"
            customizationprefix = $PublisherPrefix
            customizationoptionvalueprefix = 10000
            description = "Publisher for the Intelligent Work Layer solution."
        } | ConvertTo-Json

        Invoke-RestMethod -Uri "$apiBase/publishers" -Method Post -Headers $headers -Body $publisherDef
        Write-Host "  Publisher '$PublisherPrefix' created successfully." -ForegroundColor Green
    }
} catch {
    throw "Failed to validate/create publisher prefix '$PublisherPrefix': $($_.Exception.Message). Ensure the authenticated user has System Administrator or System Customizer role."
}

Refresh-TokenIfNeeded

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
            Label = "Stores structured output from the Intelligent Work Layer agent."
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
            IsPrimaryName = $true
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
$entityMetadata = Get-EntityMetadataWithRetry -LogicalName "${PublisherPrefix}_assistantcard"
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
# 3e. Sprint 3 — Reminder Due Column
# ─────────────────────────────────────

# Reminder Due (DateTime — for SELF_REMINDER cards)
$reminderDueDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
    SchemaName = "${PublisherPrefix}_ReminderDue"
    RequiredLevel = @{ Value = "None" }
    Format = "DateAndTime"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Reminder Due"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "When this reminder should fire. Only populated for SELF_REMINDER trigger type cards."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($entityId)/Attributes" -Method Post -Headers $headers -Body $reminderDueDef
    Write-Host "  Column 'Reminder Due' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Reminder Due' failed (may already exist): $($_.Exception.Message)"
}

# ─────────────────────────────────────
# 3f. Sprint 4 — Edit Distance Ratio Column (Phase 14)
# ─────────────────────────────────────

# Edit Distance Ratio (WholeNumber 0-100, nullable)
# Computed client-side by the PCF component (Levenshtein) and written by the Canvas App
# when processing the sendDraftAction output. Read by the Sender Profile Analyzer flow.
$editDistRatioCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
    SchemaName = "${PublisherPrefix}_editdistanceratio"
    RequiredLevel = @{ Value = "None" }
    MinValue = 0
    MaxValue = 100
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Edit Distance Ratio"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Levenshtein edit distance ratio (0-100) between the AI draft and the user-edited version. Written by Canvas App, read by Sender Profile Analyzer."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($entityId)/Attributes" -Method Post -Headers $headers -Body $editDistRatioCol
    Write-Host "  Column 'Edit Distance Ratio' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Edit Distance Ratio' failed (may already exist): $($_.Exception.Message)"
}

# ─────────────────────────────────────
# 3g. Flows 10-13 — Snooze, Triage Reasoning & Focus Shield Columns
# ─────────────────────────────────────

# Snoozed Until (DateTime — for snooze action, cleared by Flow 10)
New-DateTimeColumn -SchemaName "${PublisherPrefix}_snoozeduntil" `
    -DisplayName "Snoozed Until" `
    -Description "When a snoozed card should be re-activated. Set by snooze action, cleared by Flow 10."

# Triage Reasoning (Text 1000)
New-TextColumn -SchemaName "${PublisherPrefix}_triagereasoning" `
    -DisplayName "Triage Reasoning" -MaxLength 1000 `
    -Description "2-3 sentence explanation of why the agent assigned this priority and tier."

# Focus Shield Active (Boolean, default false)
$focusShieldActiveDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
    SchemaName = "${PublisherPrefix}_focusshieldactive"
    RequiredLevel = @{ Value = "None" }
    DefaultValue = $false
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Focus Shield Active"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "True when this signal was triaged during a calendar Focus Time event."
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
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($entityId)/Attributes" -Method Post -Headers $headers -Body $focusShieldActiveDef
    Write-Host "  Column 'Focus Shield Active' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Focus Shield Active' failed (may already exist): $($_.Exception.Message)"
}

# ─────────────────────────────────────
# 4. Sprint 1B — Create Sender Profile Table
# ─────────────────────────────────────
Refresh-TokenIfNeeded

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
            IsPrimaryName = $true
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
$senderMetadata = Get-EntityMetadataWithRetry -LogicalName "${PublisherPrefix}_senderprofile"
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
# 4b. Create Briefing Schedule Table (Phase 15)
# ─────────────────────────────────────
Refresh-TokenIfNeeded

Write-Host "`n--- Creating Briefing Schedules Table ---" -ForegroundColor Cyan

$briefingEntityDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "${PublisherPrefix}_BriefingSchedule"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Briefing Schedule"
            LanguageCode = 1033
        })
    }
    DisplayCollectionName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Briefing Schedules"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Per-user Daily Briefing schedule preferences"
            LanguageCode = 1033
        })
    }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    PrimaryNameAttribute = "${PublisherPrefix}_userdisplayname"
    Attributes = @(
        # Primary Name — User Display Name
        @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            IsPrimaryName = $true
            SchemaName = "${PublisherPrefix}_UserDisplayName"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            MaxLength = 200
            DisplayName = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "User Display Name"
                    LanguageCode = 1033
                })
            }
            Description = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Display name of the user. Primary column for readability."
                    LanguageCode = 1033
                })
            }
        }
    )
} | ConvertTo-Json -Depth 20

try {
    $briefingResult = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" -Method Post -Headers $headers -Body $briefingEntityDef
    $briefingEntityId = $briefingResult.MetadataId
    Write-Host "  BriefingSchedule table created." -ForegroundColor Green
} catch {
    Write-Warning "  BriefingSchedule table creation failed (may already exist): $($_.Exception.Message)"
    # Try to get existing entity ID for column creation
    try {
        $briefingEntityId = (Get-EntityMetadataWithRetry -LogicalName "${PublisherPrefix}_briefingschedule").MetadataId
    } catch {
        Write-Warning "  Could not retrieve BriefingSchedule entity ID. Column creation may fail."
    }
}

# Add columns to BriefingSchedule table

# Schedule Hour (WholeNumber 0-23)
$scheduleHourDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
    SchemaName = "${PublisherPrefix}_ScheduleHour"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    MinValue = 0
    MaxValue = 23
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Schedule Hour"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Hour of day (0-23) when the briefing should be generated."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($briefingEntityId)/Attributes" -Method Post -Headers $headers -Body $scheduleHourDef
    Write-Host "  Column 'Schedule Hour' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Schedule Hour' failed: $($_.Exception.Message)"
}

# Schedule Minute (WholeNumber 0-59)
$scheduleMinuteDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
    SchemaName = "${PublisherPrefix}_ScheduleMinute"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    MinValue = 0
    MaxValue = 59
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Schedule Minute"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Minute of hour (0-59) when the briefing should be generated."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($briefingEntityId)/Attributes" -Method Post -Headers $headers -Body $scheduleMinuteDef
    Write-Host "  Column 'Schedule Minute' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Schedule Minute' failed: $($_.Exception.Message)"
}

# Schedule Days (Text)
$scheduleDaysDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
    SchemaName = "${PublisherPrefix}_ScheduleDays"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    MaxLength = 100
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Schedule Days"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Comma-separated list of days when the briefing runs."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($briefingEntityId)/Attributes" -Method Post -Headers $headers -Body $scheduleDaysDef
    Write-Host "  Column 'Schedule Days' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Schedule Days' failed: $($_.Exception.Message)"
}

# Time Zone (Text)
$timezoneDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
    SchemaName = "${PublisherPrefix}_TimeZone"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    MaxLength = 100
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Time Zone"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "IANA timezone string for schedule evaluation (e.g., America/New_York)."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($briefingEntityId)/Attributes" -Method Post -Headers $headers -Body $timezoneDef
    Write-Host "  Column 'Time Zone' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Time Zone' failed: $($_.Exception.Message)"
}

# Is Enabled (TwoOption / Boolean)
$isEnabledDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
    SchemaName = "${PublisherPrefix}_IsEnabled"
    RequiredLevel = @{ Value = "ApplicationRequired" }
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
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Is Enabled"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Whether the daily briefing is active for this user."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($briefingEntityId)/Attributes" -Method Post -Headers $headers -Body $isEnabledDef
    Write-Host "  Column 'Is Enabled' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Is Enabled' failed: $($_.Exception.Message)"
}

# Heartbeat Frequency (Choice)
$heartbeatFreqDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    SchemaName = "${PublisherPrefix}_HeartbeatFrequency"
    RequiredLevel = @{ Value = "None" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Heartbeat Frequency"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "How often the heartbeat agent runs for this user."
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
                        Label = "Every 2 Hours"
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
                        Label = "Every 4 Hours"
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
                        Label = "Daily"
                        LanguageCode = 1033
                    })
                }
            }
        )
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($briefingEntityId)/Attributes" -Method Post -Headers $headers -Body $heartbeatFreqDef
    Write-Host "  Column 'Heartbeat Frequency' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Heartbeat Frequency' failed: $($_.Exception.Message)"
}

# Heartbeat Enabled (Boolean, default false)
$heartbeatEnabledDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
    SchemaName = "${PublisherPrefix}_HeartbeatEnabled"
    RequiredLevel = @{ Value = "None" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Heartbeat Enabled"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Whether heartbeat proactive scanning is enabled for this user."
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
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($briefingEntityId)/Attributes" -Method Post -Headers $headers -Body $heartbeatEnabledDef
    Write-Host "  Column 'Heartbeat Enabled' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Heartbeat Enabled' failed: $($_.Exception.Message)"
}

# Last Heartbeat Timestamp (DateTime)
$lastHeartbeatDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
    SchemaName = "${PublisherPrefix}_LastHeartbeatTimestamp"
    RequiredLevel = @{ Value = "None" }
    Format = "DateAndTime"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Last Heartbeat Timestamp"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Last time the heartbeat agent ran for this user. Used for deduplication."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($briefingEntityId)/Attributes" -Method Post -Headers $headers -Body $lastHeartbeatDef
    Write-Host "  Column 'Last Heartbeat Timestamp' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Last Heartbeat Timestamp' failed: $($_.Exception.Message)"
}

# Max Cards Per Run (WholeNumber 1-10)
$maxCardsPerRunDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
    SchemaName = "${PublisherPrefix}_MaxCardsPerRun"
    RequiredLevel = @{ Value = "None" }
    MinValue = 1
    MaxValue = 10
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Max Cards Per Run"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Maximum proactive cards generated per heartbeat run."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($briefingEntityId)/Attributes" -Method Post -Headers $headers -Body $maxCardsPerRunDef
    Write-Host "  Column 'Max Cards Per Run' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Max Cards Per Run' failed: $($_.Exception.Message)"
}

Write-Host "BriefingSchedule table provisioning complete." -ForegroundColor Green

# ─────────────────────────────────────
# 5. Create Error Log Table for Monitoring (I-18)
# ─────────────────────────────────────
Refresh-TokenIfNeeded

Write-Host "Creating Error Log Dataverse table for flow monitoring..." -ForegroundColor Cyan

$errorLogEntityDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "${PublisherPrefix}_ErrorLog"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Error Log"
            LanguageCode = 1033
        })
    }
    DisplayCollectionName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Error Logs"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Flow error monitoring log for the Intelligent Work Layer."
            LanguageCode = 1033
        })
    }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    PrimaryNameAttribute = "${PublisherPrefix}_flowname"
    Attributes = @(
        # Primary Name — Flow Name
        @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            IsPrimaryName = $true
            SchemaName = "${PublisherPrefix}_FlowName"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            MaxLength = 100
            DisplayName = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Flow Name"
                    LanguageCode = 1033
                })
            }
            Description = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Which flow failed."
                    LanguageCode = 1033
                })
            }
        }
    )
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" -Method Post -Headers $headers -Body $errorLogEntityDef
    Write-Host "  Error Log table created." -ForegroundColor Green
} catch {
    Write-Warning "  Error Log table creation failed (may already exist): $($_.Exception.Message)"
}

# Get entity metadata ID for error log
$errorLogMetadata = Get-EntityMetadataWithRetry -LogicalName "${PublisherPrefix}_errorlog"
$errorLogEntityId = $errorLogMetadata.MetadataId

# Error Message (Multiline Text)
$errorMsgCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
    SchemaName = "${PublisherPrefix}_ErrorMessage"
    RequiredLevel = @{ Value = "None" }
    MaxLength = 10000
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Error Message"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Error details from the failed flow step."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($errorLogEntityId)/Attributes" -Method Post -Headers $headers -Body $errorMsgCol
    Write-Host "  Column 'Error Message' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Error Message' failed: $($_.Exception.Message)"
}

# Error Step (Text)
$errorStepCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
    SchemaName = "${PublisherPrefix}_ErrorStep"
    RequiredLevel = @{ Value = "None" }
    MaxLength = 200
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Error Step"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Which step in the flow failed."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($errorLogEntityId)/Attributes" -Method Post -Headers $headers -Body $errorStepCol
    Write-Host "  Column 'Error Step' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Error Step' failed: $($_.Exception.Message)"
}

# Occurred On (DateTime)
$occurredOnCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
    SchemaName = "${PublisherPrefix}_OccurredOn"
    RequiredLevel = @{ Value = "None" }
    Format = "DateAndTime"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Occurred On"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "When the error occurred."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($errorLogEntityId)/Attributes" -Method Post -Headers $headers -Body $occurredOnCol
    Write-Host "  Column 'Occurred On' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Occurred On' failed: $($_.Exception.Message)"
}

# Severity (Choice: Info/Warning/Error)
$severityCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    SchemaName = "${PublisherPrefix}_Severity"
    RequiredLevel = @{ Value = "None" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Severity"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Error severity level."
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
                        Label = "Info"
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
                        Label = "Warning"
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
                        Label = "Error"
                        LanguageCode = 1033
                    })
                }
            }
        )
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($errorLogEntityId)/Attributes" -Method Post -Headers $headers -Body $severityCol
    Write-Host "  Column 'Severity' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Severity' failed: $($_.Exception.Message)"
}

# Is Resolved (Boolean, default false)
$isResolvedCol = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
    SchemaName = "${PublisherPrefix}_IsResolved"
    RequiredLevel = @{ Value = "None" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Is Resolved"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Whether the error has been investigated and resolved."
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
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($errorLogEntityId)/Attributes" -Method Post -Headers $headers -Body $isResolvedCol
    Write-Host "  Column 'Is Resolved' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Is Resolved' failed: $($_.Exception.Message)"
}

Write-Host "Error Log table provisioning complete." -ForegroundColor Green

# ─────────────────────────────────────
# 6. Create Episodic Memory Table (Memory System)
# ─────────────────────────────────────
Refresh-TokenIfNeeded

Write-Host "`n--- Creating Episodic Memory Table ---" -ForegroundColor Cyan

$episodicEntityDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "${PublisherPrefix}_EpisodicMemory"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Episodic Memory"
            LanguageCode = 1033
        })
    }
    DisplayCollectionName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Episodic Memories"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Episodic memory log storing user decision events for agent learning. 90-day retention."
            LanguageCode = 1033
        })
    }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    PrimaryNameAttribute = "${PublisherPrefix}_eventsummary"
    Attributes = @(
        # Primary Name — Event Summary
        @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            IsPrimaryName = $true
            SchemaName = "${PublisherPrefix}_EventSummary"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            MaxLength = 200
            DisplayName = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Event Summary"
                    LanguageCode = 1033
                })
            }
            Description = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Primary column — short summary of the decision event."
                    LanguageCode = 1033
                })
            }
        }
    )
} | ConvertTo-Json -Depth 20

try {
    $episodicResult = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" -Method Post -Headers $headers -Body $episodicEntityDef
    $episodicEntityId = $episodicResult.MetadataId
    Write-Host "  Episodic Memory table created." -ForegroundColor Green
} catch {
    Write-Warning "  Episodic Memory table creation failed (may already exist): $($_.Exception.Message)"
    try {
        $episodicEntityId = (Get-EntityMetadataWithRetry -LogicalName "${PublisherPrefix}_episodicmemory").MetadataId
    } catch {
        Write-Warning "  Could not retrieve Episodic Memory entity ID. Column creation may fail."
    }
}

# Event Type (Choice)
$eventTypeDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    SchemaName = "${PublisherPrefix}_EventType"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Event Type"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "The type of user decision event recorded."
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
                        Label = "DRAFT_SENT_AS_IS"
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
                        Label = "DRAFT_SENT_EDITED"
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
                        Label = "DISMISSED"
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
                        Label = "DELEGATED"
                        LanguageCode = 1033
                    })
                }
            },
            @{
                Value = 100000004
                Label = @{
                    "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                    LocalizedLabels = @(@{
                        "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                        Label = "TRIAGE_OVERRIDDEN"
                        LanguageCode = 1033
                    })
                }
            },
            @{
                Value = 100000005
                Label = @{
                    "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                    LocalizedLabels = @(@{
                        "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                        Label = "REMINDER_CREATED"
                        LanguageCode = 1033
                    })
                }
            },
            @{
                Value = 100000006
                Label = @{
                    "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                    LocalizedLabels = @(@{
                        "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                        Label = "DRAFT_REFINED"
                        LanguageCode = 1033
                    })
                }
            }
        )
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($episodicEntityId)/Attributes" -Method Post -Headers $headers -Body $eventTypeDef
    Write-Host "  Column 'Event Type' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Event Type' failed: $($_.Exception.Message)"
}

# Entity Reference (Text 200)
$entityRefDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
    SchemaName = "${PublisherPrefix}_EntityReference"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    MaxLength = 200
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Entity Reference"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Reference identifier for the related entity — card ID or sender email."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($episodicEntityId)/Attributes" -Method Post -Headers $headers -Body $entityRefDef
    Write-Host "  Column 'Entity Reference' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Entity Reference' failed: $($_.Exception.Message)"
}

# Event Detail (Text 500)
$eventDetailDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
    SchemaName = "${PublisherPrefix}_EventDetail"
    RequiredLevel = @{ Value = "None" }
    MaxLength = 500
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Event Detail"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Free-text description of the event providing additional context."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($episodicEntityId)/Attributes" -Method Post -Headers $headers -Body $eventDetailDef
    Write-Host "  Column 'Event Detail' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Event Detail' failed: $($_.Exception.Message)"
}

# Sender Email (Text 320)
$episodicSenderEmailDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
    SchemaName = "${PublisherPrefix}_SenderEmail"
    RequiredLevel = @{ Value = "None" }
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
            Label = "Email address of the sender involved in this event."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($episodicEntityId)/Attributes" -Method Post -Headers $headers -Body $episodicSenderEmailDef
    Write-Host "  Column 'Sender Email' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Sender Email' failed: $($_.Exception.Message)"
}

# Event Date (DateTime)
$eventDateDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
    SchemaName = "${PublisherPrefix}_EventDate"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    Format = "DateAndTime"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Event Date"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Timestamp when the decision event occurred."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($episodicEntityId)/Attributes" -Method Post -Headers $headers -Body $eventDateDef
    Write-Host "  Column 'Event Date' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Event Date' failed: $($_.Exception.Message)"
}

# Card Trigger Type (Choice)
$cardTriggerTypeDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    SchemaName = "${PublisherPrefix}_CardTriggerType"
    RequiredLevel = @{ Value = "None" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Card Trigger Type"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "The trigger type of the card associated with this event."
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
                        Label = "EMAIL"
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
                        Label = "TEAMS_MESSAGE"
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
                        Label = "CALENDAR_SCAN"
                        LanguageCode = 1033
                    })
                }
            }
        )
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($episodicEntityId)/Attributes" -Method Post -Headers $headers -Body $cardTriggerTypeDef
    Write-Host "  Column 'Card Trigger Type' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Card Trigger Type' failed: $($_.Exception.Message)"
}

# Target Context (Text 200)
$targetContextDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
    SchemaName = "${PublisherPrefix}_TargetContext"
    RequiredLevel = @{ Value = "None" }
    MaxLength = 200
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Target Context"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Delegation target or override reason. Only populated for DELEGATED or TRIAGE_OVERRIDDEN events."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($episodicEntityId)/Attributes" -Method Post -Headers $headers -Body $targetContextDef
    Write-Host "  Column 'Target Context' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Target Context' failed: $($_.Exception.Message)"
}

Write-Host "Episodic Memory table provisioning complete." -ForegroundColor Green

# ─────────────────────────────────────
# 7. Create Semantic Knowledge Table (Memory System)
# ─────────────────────────────────────
Refresh-TokenIfNeeded

Write-Host "`n--- Creating Semantic Knowledge Table ---" -ForegroundColor Cyan

$semanticEntityDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "${PublisherPrefix}_SemanticKnowledge"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Semantic Knowledge"
            LanguageCode = 1033
        })
    }
    DisplayCollectionName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Semantic Knowledges"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Semantic knowledge base storing durable facts promoted from episodic memory patterns."
            LanguageCode = 1033
        })
    }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    PrimaryNameAttribute = "${PublisherPrefix}_knowledgesummary"
    Attributes = @(
        # Primary Name — Knowledge Summary
        @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            IsPrimaryName = $true
            SchemaName = "${PublisherPrefix}_KnowledgeSummary"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            MaxLength = 200
            DisplayName = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Knowledge Summary"
                    LanguageCode = 1033
                })
            }
            Description = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Primary column — short human-readable summary of the knowledge fact."
                    LanguageCode = 1033
                })
            }
        }
    )
} | ConvertTo-Json -Depth 20

try {
    $semanticResult = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" -Method Post -Headers $headers -Body $semanticEntityDef
    $semanticEntityId = $semanticResult.MetadataId
    Write-Host "  Semantic Knowledge table created." -ForegroundColor Green
} catch {
    Write-Warning "  Semantic Knowledge table creation failed (may already exist): $($_.Exception.Message)"
    try {
        $semanticEntityId = (Get-EntityMetadataWithRetry -LogicalName "${PublisherPrefix}_semanticknowledge").MetadataId
    } catch {
        Write-Warning "  Could not retrieve Semantic Knowledge entity ID. Column creation may fail."
    }
}

# Fact Type (Choice)
$factTypeDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    SchemaName = "${PublisherPrefix}_FactType"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Fact Type"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Category of the knowledge fact."
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
                        Label = "DELEGATION"
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
                        Label = "AVOIDANCE"
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
                        Label = "TONE"
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
                        Label = "RESPONSE_SPEED"
                        LanguageCode = 1033
                    })
                }
            },
            @{
                Value = 100000004
                Label = @{
                    "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                    LocalizedLabels = @(@{
                        "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                        Label = "CUSTOM"
                        LanguageCode = 1033
                    })
                }
            }
        )
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($semanticEntityId)/Attributes" -Method Post -Headers $headers -Body $factTypeDef
    Write-Host "  Column 'Fact Type' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Fact Type' failed: $($_.Exception.Message)"
}

# Fact Statement (Multiline Text 500)
$factStatementDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
    SchemaName = "${PublisherPrefix}_FactStatement"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    MaxLength = 500
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Fact Statement"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Natural language statement of the knowledge fact."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($semanticEntityId)/Attributes" -Method Post -Headers $headers -Body $factStatementDef
    Write-Host "  Column 'Fact Statement' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Fact Statement' failed: $($_.Exception.Message)"
}

# Context Hash (Text 100)
$contextHashDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
    SchemaName = "${PublisherPrefix}_ContextHash"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    MaxLength = 100
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Context Hash"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Deterministic hash for upsert deduplication. Computed from fact type + key context attributes."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($semanticEntityId)/Attributes" -Method Post -Headers $headers -Body $contextHashDef
    Write-Host "  Column 'Context Hash' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Context Hash' failed: $($_.Exception.Message)"
}

# Confidence Score (Decimal 0.0000 - 1.0000)
$semanticConfidenceDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
    SchemaName = "${PublisherPrefix}_ConfidenceScore"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    Precision = 4
    MinValue = 0
    MaxValue = 1
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
            Label = "Confidence level (0.0-1.0) based on the number and consistency of supporting episodic events."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($semanticEntityId)/Attributes" -Method Post -Headers $headers -Body $semanticConfidenceDef
    Write-Host "  Column 'Confidence Score' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Confidence Score' failed: $($_.Exception.Message)"
}

# Event Count (WholeNumber)
$eventCountDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
    SchemaName = "${PublisherPrefix}_EventCount"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    MinValue = 0
    MaxValue = 2147483647
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Event Count"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Number of supporting episodic memory events that contributed to this fact."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($semanticEntityId)/Attributes" -Method Post -Headers $headers -Body $eventCountDef
    Write-Host "  Column 'Event Count' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Event Count' failed: $($_.Exception.Message)"
}

# Last Validated (DateTime)
$lastValidatedDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
    SchemaName = "${PublisherPrefix}_LastValidated"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    Format = "DateAndTime"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Last Validated"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Timestamp when this fact was last reinforced by a matching episodic event."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($semanticEntityId)/Attributes" -Method Post -Headers $headers -Body $lastValidatedDef
    Write-Host "  Column 'Last Validated' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Last Validated' failed: $($_.Exception.Message)"
}

# Valid Until (DateTime, nullable)
$validUntilDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
    SchemaName = "${PublisherPrefix}_ValidUntil"
    RequiredLevel = @{ Value = "None" }
    Format = "DateAndTime"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Valid Until"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Explicit expiry date for people-dependent facts. Null means no explicit expiry."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($semanticEntityId)/Attributes" -Method Post -Headers $headers -Body $validUntilDef
    Write-Host "  Column 'Valid Until' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Valid Until' failed: $($_.Exception.Message)"
}

# Is Active (Boolean, default true)
$isActiveDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
    SchemaName = "${PublisherPrefix}_IsActive"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Is Active"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Soft-delete flag for confidence decay. Set to false when confidence drops below threshold."
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
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($semanticEntityId)/Attributes" -Method Post -Headers $headers -Body $isActiveDef
    Write-Host "  Column 'Is Active' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Is Active' failed: $($_.Exception.Message)"
}

# Source Type (Choice)
$sourceTypeDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    SchemaName = "${PublisherPrefix}_SourceType"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Source Type"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "How this fact was created."
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
                        Label = "INFERRED"
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
                        Label = "USER_EXPLICIT"
                        LanguageCode = 1033
                    })
                }
            }
        )
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($semanticEntityId)/Attributes" -Method Post -Headers $headers -Body $sourceTypeDef
    Write-Host "  Column 'Source Type' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Source Type' failed: $($_.Exception.Message)"
}

# Created From Persona (Boolean, default false)
$createdFromPersonaDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
    SchemaName = "${PublisherPrefix}_CreatedFromPersona"
    RequiredLevel = @{ Value = "None" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Created From Persona"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Whether this fact was promoted from an explicit user persona rule."
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
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($semanticEntityId)/Attributes" -Method Post -Headers $headers -Body $createdFromPersonaDef
    Write-Host "  Column 'Created From Persona' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Created From Persona' failed: $($_.Exception.Message)"
}

# 7a. Create Alternate Key on Semantic Knowledge (cr_contexthash)
Write-Host "Creating alternate key on Semantic Knowledge (cr_contexthash)..." -ForegroundColor Cyan

$semanticAltKeyDef = @{
    SchemaName = "${PublisherPrefix}_contexthash_key"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Context Hash Key"
            LanguageCode = 1033
        })
    }
    KeyAttributes = @("${PublisherPrefix}_contexthash")
} | ConvertTo-Json -Depth 20

try {
    $semanticKeyResult = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($semanticEntityId)/Keys" -Method Post -Headers $headers -Body $semanticAltKeyDef
    Write-Host "  Alternate key creation initiated." -ForegroundColor Yellow

    # Poll for key activation
    $semanticKeyId = $semanticKeyResult.MetadataId
    $keyAttempts = 0
    $keyMaxAttempts = 12
    do {
        Start-Sleep -Seconds 2.5
        $keyAttempts++
        $keyStatus = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($semanticEntityId)/Keys($semanticKeyId)" -Headers $headers
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

Write-Host "Semantic Knowledge table provisioning complete." -ForegroundColor Green

# ─────────────────────────────────────
# 8. Create User Persona Table (Memory System)
# ─────────────────────────────────────
Refresh-TokenIfNeeded

Write-Host "`n--- Creating User Persona Table ---" -ForegroundColor Cyan

$personaEntityDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "${PublisherPrefix}_UserPersona"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "User Persona"
            LanguageCode = 1033
        })
    }
    DisplayCollectionName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "User Personas"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "User persona configuration for explicit communication style preferences."
            LanguageCode = 1033
        })
    }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    PrimaryNameAttribute = "${PublisherPrefix}_userdisplayname"
    Attributes = @(
        # Primary Name — User Display Name
        @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            IsPrimaryName = $true
            SchemaName = "${PublisherPrefix}_UserDisplayName"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            MaxLength = 200
            DisplayName = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "User Display Name"
                    LanguageCode = 1033
                })
            }
            Description = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Primary column — display name of the user. One row per user."
                    LanguageCode = 1033
                })
            }
        }
    )
} | ConvertTo-Json -Depth 20

try {
    $personaResult = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" -Method Post -Headers $headers -Body $personaEntityDef
    $personaEntityId = $personaResult.MetadataId
    Write-Host "  User Persona table created." -ForegroundColor Green
} catch {
    Write-Warning "  User Persona table creation failed (may already exist): $($_.Exception.Message)"
    try {
        $personaEntityId = (Get-EntityMetadataWithRetry -LogicalName "${PublisherPrefix}_userpersona").MetadataId
    } catch {
        Write-Warning "  Could not retrieve User Persona entity ID. Column creation may fail."
    }
}

# Preferred Tone (Choice)
$preferredToneDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    SchemaName = "${PublisherPrefix}_PreferredTone"
    RequiredLevel = @{ Value = "None" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Preferred Tone"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "User's preferred communication tone. Null means the agent infers tone from episodic memory."
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
                        Label = "FORMAL"
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
                        Label = "SEMI_FORMAL"
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
                        Label = "DIRECT"
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
                        Label = "COLLABORATIVE"
                        LanguageCode = 1033
                    })
                }
            }
        )
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($personaEntityId)/Attributes" -Method Post -Headers $headers -Body $preferredToneDef
    Write-Host "  Column 'Preferred Tone' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Preferred Tone' failed: $($_.Exception.Message)"
}

# Signature Preference (Text 200)
$signaturePrefDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
    SchemaName = "${PublisherPrefix}_SignaturePreference"
    RequiredLevel = @{ Value = "None" }
    MaxLength = 200
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Signature Preference"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Preferred email sign-off. Used by the Humanizer Agent for draft closing."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($personaEntityId)/Attributes" -Method Post -Headers $headers -Body $signaturePrefDef
    Write-Host "  Column 'Signature Preference' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Signature Preference' failed: $($_.Exception.Message)"
}

# Formatting Style (Choice)
$formattingStyleDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    SchemaName = "${PublisherPrefix}_FormattingStyle"
    RequiredLevel = @{ Value = "None" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Formatting Style"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Preferred response formatting style. Null means the agent infers from episodic memory."
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
                        Label = "PROSE"
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
                        Label = "BULLETS"
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
                        Label = "MIXED"
                        LanguageCode = 1033
                    })
                }
            }
        )
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($personaEntityId)/Attributes" -Method Post -Headers $headers -Body $formattingStyleDef
    Write-Host "  Column 'Formatting Style' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Formatting Style' failed: $($_.Exception.Message)"
}

# Custom Rules (Multiline Text 2000)
$customRulesDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
    SchemaName = "${PublisherPrefix}_CustomRules"
    RequiredLevel = @{ Value = "None" }
    MaxLength = 2000
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Custom Rules"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Free-text rules for the agent. Injected into the agent system prompt at runtime."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($personaEntityId)/Attributes" -Method Post -Headers $headers -Body $customRulesDef
    Write-Host "  Column 'Custom Rules' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Custom Rules' failed: $($_.Exception.Message)"
}

# Is Enabled (Boolean, default true)
$personaIsEnabledDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
    SchemaName = "${PublisherPrefix}_IsEnabled"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Is Enabled"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Master toggle for persona preferences. When false, the agent ignores all persona settings."
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
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($personaEntityId)/Attributes" -Method Post -Headers $headers -Body $personaIsEnabledDef
    Write-Host "  Column 'Is Enabled' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Is Enabled' failed: $($_.Exception.Message)"
}

# Autonomy Tier (Choice — OBSERVER / ASSIST / PARTNER)
$autonomyTierDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    SchemaName = "${PublisherPrefix}_AutonomyTier"
    RequiredLevel = @{ Value = "None" }
    DefaultFormValue = 100000000
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Autonomy Tier"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "User's current autonomy level for auto-actions."
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
                        Label = "OBSERVER"
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
                        Label = "ASSIST"
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
                        Label = "PARTNER"
                        LanguageCode = 1033
                    })
                }
            }
        )
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($personaEntityId)/Attributes" -Method Post -Headers $headers -Body $autonomyTierDef
    Write-Host "  Column 'Autonomy Tier' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Autonomy Tier' failed: $($_.Exception.Message)"
}

# Total Interactions (WholeNumber, default 0)
$totalInteractionsDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
    SchemaName = "${PublisherPrefix}_TotalInteractions"
    RequiredLevel = @{ Value = "None" }
    MinValue = 0
    MaxValue = 2147483647
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Total Interactions"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Count of card outcomes recorded. Incremented by Flow 5."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($personaEntityId)/Attributes" -Method Post -Headers $headers -Body $totalInteractionsDef
    Write-Host "  Column 'Total Interactions' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Total Interactions' failed: $($_.Exception.Message)"
}

# Acceptance Rate (Decimal 0.0-1.0, precision 4)
$acceptanceRateDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
    SchemaName = "${PublisherPrefix}_AcceptanceRate"
    RequiredLevel = @{ Value = "None" }
    MinValue = 0
    MaxValue = 1
    Precision = 4
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Acceptance Rate"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "EWMA acceptance rate. Recomputed by Flow 5 on each outcome."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($personaEntityId)/Attributes" -Method Post -Headers $headers -Body $acceptanceRateDef
    Write-Host "  Column 'Acceptance Rate' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Acceptance Rate' failed: $($_.Exception.Message)"
}

# Tone Baseline (Multiline Text 5000 — JSON blob)
$toneBaselineDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
    SchemaName = "${PublisherPrefix}_ToneBaseline"
    RequiredLevel = @{ Value = "None" }
    MaxLength = 5000
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Tone Baseline"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "JSON blob of user's writing style patterns from Graph bootstrap analysis."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($personaEntityId)/Attributes" -Method Post -Headers $headers -Body $toneBaselineDef
    Write-Host "  Column 'Tone Baseline' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Tone Baseline' failed: $($_.Exception.Message)"
}

Write-Host "User Persona table provisioning complete." -ForegroundColor Green

# ─────────────────────────────────────
# 9. Create Skill Registry Table (Extensibility)
# ─────────────────────────────────────
Refresh-TokenIfNeeded

Write-Host "`n--- Creating Skill Registry Table ---" -ForegroundColor Cyan

$skillEntityDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "${PublisherPrefix}_SkillRegistry"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Skill Registry"
            LanguageCode = 1033
        })
    }
    DisplayCollectionName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Skill Registries"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Skill registry for extensible agent capabilities. Power users define custom prompts or flow references."
            LanguageCode = 1033
        })
    }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    PrimaryNameAttribute = "${PublisherPrefix}_skillname"
    Attributes = @(
        # Primary Name — Skill Name
        @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            IsPrimaryName = $true
            SchemaName = "${PublisherPrefix}_SkillName"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            MaxLength = 100
            DisplayName = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Skill Name"
                    LanguageCode = 1033
                })
            }
            Description = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Primary column — unique human-readable name for the skill."
                    LanguageCode = 1033
                })
            }
        }
    )
} | ConvertTo-Json -Depth 20

try {
    $skillResult = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" -Method Post -Headers $headers -Body $skillEntityDef
    $skillEntityId = $skillResult.MetadataId
    Write-Host "  Skill Registry table created." -ForegroundColor Green
} catch {
    Write-Warning "  Skill Registry table creation failed (may already exist): $($_.Exception.Message)"
    try {
        $skillEntityId = (Get-EntityMetadataWithRetry -LogicalName "${PublisherPrefix}_skillregistry").MetadataId
    } catch {
        Write-Warning "  Could not retrieve Skill Registry entity ID. Column creation may fail."
    }
}

# Skill Description (Multiline Text 500)
$skillDescDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
    SchemaName = "${PublisherPrefix}_SkillDescription"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    MaxLength = 500
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Skill Description"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Natural language description of what the skill does. Used by the agent for skill selection."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($skillEntityId)/Attributes" -Method Post -Headers $headers -Body $skillDescDef
    Write-Host "  Column 'Skill Description' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Skill Description' failed: $($_.Exception.Message)"
}

# Skill Type (Choice)
$skillTypeDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    SchemaName = "${PublisherPrefix}_SkillType"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Skill Type"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Whether the skill is a prompt template or a reference to an external flow."
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
                        Label = "PROMPT_TEMPLATE"
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
                        Label = "FLOW_REFERENCE"
                        LanguageCode = 1033
                    })
                }
            }
        )
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($skillEntityId)/Attributes" -Method Post -Headers $headers -Body $skillTypeDef
    Write-Host "  Column 'Skill Type' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Skill Type' failed: $($_.Exception.Message)"
}

# Prompt Template (Multiline Text 10000)
$promptTemplateDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
    SchemaName = "${PublisherPrefix}_PromptTemplate"
    RequiredLevel = @{ Value = "None" }
    MaxLength = 10000
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Prompt Template"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Prompt text with {{PARAM_NAME}} substitution placeholders. Required when skill type is PROMPT_TEMPLATE."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($skillEntityId)/Attributes" -Method Post -Headers $headers -Body $promptTemplateDef
    Write-Host "  Column 'Prompt Template' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Prompt Template' failed: $($_.Exception.Message)"
}

# Parameter Schema (Multiline Text 2000)
$paramSchemaDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
    SchemaName = "${PublisherPrefix}_ParameterSchema"
    RequiredLevel = @{ Value = "None" }
    MaxLength = 2000
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Parameter Schema"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "JSON Schema defining input parameters for the skill."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($skillEntityId)/Attributes" -Method Post -Headers $headers -Body $paramSchemaDef
    Write-Host "  Column 'Parameter Schema' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Parameter Schema' failed: $($_.Exception.Message)"
}

# Flow ID (Text 500)
$flowIdDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
    SchemaName = "${PublisherPrefix}_FlowId"
    RequiredLevel = @{ Value = "None" }
    MaxLength = 500
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Flow ID"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Power Automate flow GUID or HTTP trigger URL. Required when skill type is FLOW_REFERENCE."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($skillEntityId)/Attributes" -Method Post -Headers $headers -Body $flowIdDef
    Write-Host "  Column 'Flow ID' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Flow ID' failed: $($_.Exception.Message)"
}

# Output Format (Choice)
$outputFormatDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
    SchemaName = "${PublisherPrefix}_OutputFormat"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Output Format"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "How the skill output should be rendered in the UI."
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
                        Label = "CARD"
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
                        Label = "BRIEFING_SECTION"
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
                        Label = "TEXT_RESPONSE"
                        LanguageCode = 1033
                    })
                }
            }
        )
    }
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($skillEntityId)/Attributes" -Method Post -Headers $headers -Body $outputFormatDef
    Write-Host "  Column 'Output Format' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Output Format' failed: $($_.Exception.Message)"
}

# Is Enabled (Boolean, default true)
$skillIsEnabledDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
    SchemaName = "${PublisherPrefix}_IsEnabled"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Is Enabled"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Toggle to enable or disable this skill."
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
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($skillEntityId)/Attributes" -Method Post -Headers $headers -Body $skillIsEnabledDef
    Write-Host "  Column 'Is Enabled' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Is Enabled' failed: $($_.Exception.Message)"
}

# Is Shared (Boolean, default false)
$isSharedDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
    SchemaName = "${PublisherPrefix}_IsShared"
    RequiredLevel = @{ Value = "None" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Is Shared"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Whether this skill is admin-shared and visible to all users."
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
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($skillEntityId)/Attributes" -Method Post -Headers $headers -Body $isSharedDef
    Write-Host "  Column 'Is Shared' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Is Shared' failed: $($_.Exception.Message)"
}

# Last Used (DateTime)
$lastUsedDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
    SchemaName = "${PublisherPrefix}_LastUsed"
    RequiredLevel = @{ Value = "None" }
    Format = "DateAndTime"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Last Used"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Timestamp of the most recent skill invocation."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($skillEntityId)/Attributes" -Method Post -Headers $headers -Body $lastUsedDef
    Write-Host "  Column 'Last Used' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Last Used' failed: $($_.Exception.Message)"
}

# Usage Count (WholeNumber)
$usageCountDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
    SchemaName = "${PublisherPrefix}_UsageCount"
    RequiredLevel = @{ Value = "None" }
    MinValue = 0
    MaxValue = 2147483647
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Usage Count"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Total number of times this skill has been invoked."
            LanguageCode = 1033
        })
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($skillEntityId)/Attributes" -Method Post -Headers $headers -Body $usageCountDef
    Write-Host "  Column 'Usage Count' created." -ForegroundColor Green
} catch {
    Write-Warning "  Column 'Usage Count' failed: $($_.Exception.Message)"
}

Write-Host "Skill Registry table provisioning complete." -ForegroundColor Green

# ─────────────────────────────────────
# 10. Create Semantic-Episodic Junction Table (Memory System)
# ─────────────────────────────────────
Refresh-TokenIfNeeded

Write-Host "`n--- Creating Semantic-Episodic Junction Table ---" -ForegroundColor Cyan

$junctionEntityDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "${PublisherPrefix}_SemanticEpisodic"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Semantic-Episodic Link"
            LanguageCode = 1033
        })
    }
    DisplayCollectionName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Semantic-Episodic Links"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Junction table linking semantic knowledge facts to their supporting episodic memory events."
            LanguageCode = 1033
        })
    }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    PrimaryNameAttribute = "${PublisherPrefix}_linkname"
    Attributes = @(
        # Primary Name — auto-populated link identifier
        @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            IsPrimaryName = $true
            SchemaName = "${PublisherPrefix}_LinkName"
            RequiredLevel = @{ Value = "ApplicationRequired" }
            MaxLength = 200
            DisplayName = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Link Name"
                    LanguageCode = 1033
                })
            }
            Description = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Primary column — auto-populated link identifier."
                    LanguageCode = 1033
                })
            }
        }
    )
} | ConvertTo-Json -Depth 20

try {
    $junctionResult = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" -Method Post -Headers $headers -Body $junctionEntityDef
    $junctionEntityId = $junctionResult.MetadataId
    Write-Host "  Semantic-Episodic junction table created." -ForegroundColor Green
} catch {
    Write-Warning "  Semantic-Episodic junction table creation failed (may already exist): $($_.Exception.Message)"
    try {
        $junctionEntityId = (Get-EntityMetadataWithRetry -LogicalName "${PublisherPrefix}_semanticepisodic").MetadataId
    } catch {
        Write-Warning "  Could not retrieve Semantic-Episodic entity ID. Relationship creation may fail."
    }
}

# Create lookup to Episodic Memory
Write-Host "  Creating lookup to Episodic Memory..." -ForegroundColor Cyan
$episodicLookupDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"
    SchemaName = "${PublisherPrefix}_EpisodicMemoryId"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Episodic Memory"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Lookup to the supporting episodic memory event."
            LanguageCode = 1033
        })
    }
    Targets = @("${PublisherPrefix}_episodicmemory")
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($junctionEntityId)/Attributes" -Method Post -Headers $headers -Body $episodicLookupDef
    Write-Host "  Lookup 'Episodic Memory' created." -ForegroundColor Green
} catch {
    Write-Warning "  Lookup 'Episodic Memory' failed: $($_.Exception.Message)"
}

# Create lookup to Semantic Knowledge
Write-Host "  Creating lookup to Semantic Knowledge..." -ForegroundColor Cyan
$semanticLookupDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"
    SchemaName = "${PublisherPrefix}_SemanticKnowledgeId"
    RequiredLevel = @{ Value = "ApplicationRequired" }
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Semantic Knowledge"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Lookup to the semantic knowledge fact."
            LanguageCode = 1033
        })
    }
    Targets = @("${PublisherPrefix}_semanticknowledge")
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($junctionEntityId)/Attributes" -Method Post -Headers $headers -Body $semanticLookupDef
    Write-Host "  Lookup 'Semantic Knowledge' created." -ForegroundColor Green
} catch {
    Write-Warning "  Lookup 'Semantic Knowledge' failed: $($_.Exception.Message)"
}

# Create composite alternate key on junction table (episodic + semantic)
Write-Host "Creating composite alternate key on Semantic-Episodic junction..." -ForegroundColor Cyan

$junctionAltKeyDef = @{
    SchemaName = "${PublisherPrefix}_episodic_semantic_key"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Episodic-Semantic Composite Key"
            LanguageCode = 1033
        })
    }
    KeyAttributes = @("${PublisherPrefix}_episodicmemoryid", "${PublisherPrefix}_semanticknowledgeid")
} | ConvertTo-Json -Depth 20

try {
    $junctionKeyResult = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($junctionEntityId)/Keys" -Method Post -Headers $headers -Body $junctionAltKeyDef
    Write-Host "  Composite alternate key creation initiated." -ForegroundColor Yellow

    # Poll for key activation
    $junctionKeyId = $junctionKeyResult.MetadataId
    $keyAttempts = 0
    $keyMaxAttempts = 12
    do {
        Start-Sleep -Seconds 2.5
        $keyAttempts++
        $keyStatus = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($junctionEntityId)/Keys($junctionKeyId)" -Headers $headers
        if ($keyStatus.EntityKeyIndexStatus -eq "Active") {
            Write-Host "  Composite alternate key active." -ForegroundColor Green
            break
        }
        Write-Host "  Key indexing... attempt $keyAttempts/$keyMaxAttempts (status: $($keyStatus.EntityKeyIndexStatus))"
    } while ($keyAttempts -lt $keyMaxAttempts)

    if ($keyAttempts -ge $keyMaxAttempts) {
        Write-Warning "  Composite alternate key not yet active after 30s. Check manually in Admin Center."
    }
} catch {
    Write-Warning "  Composite alternate key creation failed (may already exist): $($_.Exception.Message)"
}

Write-Host "Semantic-Episodic junction table provisioning complete." -ForegroundColor Green

# ─────────────────────────────────────
# 11. Publish All Customizations
# ─────────────────────────────────────
Write-Host "Publishing all customizations..." -ForegroundColor Cyan

try {
    # Refresh token in case it expired during provisioning
    $token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
    $headers["Authorization"] = "Bearer $token"

    Invoke-RestMethod -Uri "$apiBase/PublishAllXml" -Method Post -Headers $headers
    Write-Host "  All customizations published successfully." -ForegroundColor Green
} catch {
    Write-Warning "  PublishAllXml failed: $($_.Exception.Message)"
    Write-Host "  Fallback: Run 'pac org publish --all' manually after provisioning." -ForegroundColor Yellow
}

# ─────────────────────────────────────
# 6. Verify PCF Components for Canvas Apps
# ─────────────────────────────────────
Write-Host "Verifying PCF components for Canvas apps..." -ForegroundColor Cyan
Write-Host "  PCF enablement was attempted in step 2b above." -ForegroundColor Green
Write-Host "  If the API call failed, enable manually:" -ForegroundColor Yellow
Write-Host "    Admin Center → Environments → $EnvironmentName → Settings → Product → Features" -ForegroundColor Yellow
Write-Host "    Toggle 'Allow publishing of canvas apps with code components' → ON" -ForegroundColor Yellow

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
