<#
.SYNOPSIS
    Provisions the Power Platform environment and Dataverse tables for the Email Productivity Agent.

.DESCRIPTION
    Creates a Power Platform environment, provisions the FollowUpTracking, NudgeConfiguration,
    and SnoozedConversation Dataverse tables with all required columns and alternate keys.

.PARAMETER TenantId
    Azure AD Tenant ID (required).

.PARAMETER EnvironmentName
    Display name for the new environment. Default: "EmailProductivityAgent-Dev"

.PARAMETER EnvironmentType
    Environment type: Sandbox or Production. Default: "Sandbox"

.PARAMETER Region
    Deployment region. Default: "unitedstates"

.PARAMETER PublisherPrefix
    Dataverse publisher prefix for custom columns. Default: "cr"

.EXAMPLE
    .\provision-environment.ps1 -TenantId "abc-123"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [string]$EnvironmentName = "EmailProductivityAgent-Dev",

    [ValidateSet("Sandbox", "Production")]
    [string]$EnvironmentType = "Sandbox",

    [string]$Region = "unitedstates",

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
if ($LASTEXITCODE -ne 0) {
    throw "Environment creation failed. Check PAC CLI output above for details."
}

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
# 3. Authenticate Azure CLI & Prepare Dataverse API
# ─────────────────────────────────────
Write-Host "Authenticating Azure CLI for Dataverse API access..." -ForegroundColor Cyan
az login --tenant $TenantId
if ($LASTEXITCODE -ne 0) { throw "Azure CLI login failed. Ensure Azure CLI is installed ('az --version') and try 'az login --tenant $TenantId' manually." }

# Get access token for Dataverse via Azure CLI
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
# 3a. Validate/Create Publisher Prefix
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
            friendlyname = "Email Productivity Agent Publisher"
            customizationprefix = $PublisherPrefix
            customizationoptionvalueprefix = 10000
            description = "Publisher for the Email Productivity Agent solution."
        } | ConvertTo-Json

        Invoke-RestMethod -Uri "$apiBase/publishers" -Method Post -Headers $headers -Body $publisherDef
        Write-Host "  Publisher '$PublisherPrefix' created successfully." -ForegroundColor Green
    }
} catch {
    throw "Failed to validate/create publisher prefix '$PublisherPrefix': $($_.Exception.Message). Ensure the authenticated user has System Administrator or System Customizer role."
}

# ─────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────

function New-TextColumn {
    param(
        [string]$EntityId,
        [string]$SchemaName,
        [string]$DisplayName,
        [string]$Description,
        [int]$MaxLength = 200,
        [bool]$Required = $false
    )

    $colDef = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        SchemaName = $SchemaName
        RequiredLevel = @{ Value = if ($Required) { "ApplicationRequired" } else { "None" } }
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
        Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($EntityId)/Attributes" -Method Post -Headers $headers -Body $colDef
        Write-Host "  Column '$DisplayName' created." -ForegroundColor Green
    } catch {
        Write-Warning "  Column '$DisplayName' failed: $($_.Exception.Message)"
    }
}

function New-MultilineTextColumn {
    param(
        [string]$EntityId,
        [string]$SchemaName,
        [string]$DisplayName,
        [string]$Description,
        [int]$MaxLength = 10000,
        [bool]$Required = $false
    )

    $colDef = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
        SchemaName = $SchemaName
        RequiredLevel = @{ Value = if ($Required) { "ApplicationRequired" } else { "None" } }
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
        Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($EntityId)/Attributes" -Method Post -Headers $headers -Body $colDef
        Write-Host "  Column '$DisplayName' created." -ForegroundColor Green
    } catch {
        Write-Warning "  Column '$DisplayName' failed: $($_.Exception.Message)"
    }
}

function New-DateTimeColumn {
    param(
        [string]$EntityId,
        [string]$SchemaName,
        [string]$DisplayName,
        [string]$Description,
        [bool]$Required = $false
    )

    $colDef = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        SchemaName = $SchemaName
        RequiredLevel = @{ Value = if ($Required) { "ApplicationRequired" } else { "None" } }
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
        Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($EntityId)/Attributes" -Method Post -Headers $headers -Body $colDef
        Write-Host "  Column '$DisplayName' created." -ForegroundColor Green
    } catch {
        Write-Warning "  Column '$DisplayName' failed: $($_.Exception.Message)"
    }
}

function New-BooleanColumn {
    param(
        [string]$EntityId,
        [string]$SchemaName,
        [string]$DisplayName,
        [string]$Description,
        [bool]$DefaultValue = $false,
        [bool]$Required = $false
    )

    $colDef = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
        SchemaName = $SchemaName
        RequiredLevel = @{ Value = if ($Required) { "ApplicationRequired" } else { "None" } }
        DefaultValue = $DefaultValue
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
        Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($EntityId)/Attributes" -Method Post -Headers $headers -Body $colDef
        Write-Host "  Column '$DisplayName' created." -ForegroundColor Green
    } catch {
        Write-Warning "  Column '$DisplayName' failed: $($_.Exception.Message)"
    }
}

function New-WholeNumberColumn {
    param(
        [string]$EntityId,
        [string]$SchemaName,
        [string]$DisplayName,
        [string]$Description,
        [int]$MinValue = 0,
        [int]$MaxValue = 2147483647,
        [bool]$Required = $false,
        $DefaultValue = $null
    )

    $colProps = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
        SchemaName = $SchemaName
        RequiredLevel = @{ Value = if ($Required) { "ApplicationRequired" } else { "None" } }
        MinValue = $MinValue
        MaxValue = $MaxValue
        Format = "None"
    }
    if ($null -ne $DefaultValue) {
        $colProps["DefaultFormValue"] = [int]$DefaultValue
    }

    $colDef = $colProps + @{
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
        Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($EntityId)/Attributes" -Method Post -Headers $headers -Body $colDef
        Write-Host "  Column '$DisplayName' created." -ForegroundColor Green
    } catch {
        Write-Warning "  Column '$DisplayName' failed: $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────
# 4. Create FollowUpTracking Table
# ─────────────────────────────────────
Write-Host "Creating FollowUpTracking Dataverse table..." -ForegroundColor Cyan

$followUpEntityDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "${PublisherPrefix}_followuptracking"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Follow-Up Tracking"
            LanguageCode = 1033
        })
    }
    DisplayCollectionName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Follow-Up Trackings"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Tracks sent emails awaiting follow-up responses for the Email Productivity Agent."
            LanguageCode = 1033
        })
    }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    PrimaryNameAttribute = "${PublisherPrefix}_originalsubject"
    Attributes = @(
        # Primary Name — Original Subject (Text 400 chars)
        # IsPrimaryName and FormatName are required by the Dataverse CreateEntity API
        @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            IsPrimaryName = $true
            SchemaName = "${PublisherPrefix}_originalsubject"
            RequiredLevel = @{ Value = "ApplicationRequired"; CanBeChanged = $true }
            MaxLength = 400
            FormatName = @{ Value = "Text" }
            DisplayName = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Original Subject"
                    LanguageCode = 1033
                })
            }
            Description = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Subject line of the original sent email."
                    LanguageCode = 1033
                })
            }
        }
    )
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" -Method Post -Headers $headers -Body $followUpEntityDef
    Write-Host "  FollowUpTracking table created." -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 409 -or $_.Exception.Message -match "already exists|duplicate") {
        Write-Host "  FollowUpTracking table already exists — skipping creation." -ForegroundColor Yellow
    } else {
        throw "FollowUpTracking table creation failed: $($_.Exception.Message)"
    }
}

# Get entity metadata ID
$followUpMetadata = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='${PublisherPrefix}_followuptracking')" -Headers $headers
$followUpEntityId = $followUpMetadata.MetadataId

# ─────────────────────────────────────
# 4a. Add Columns to FollowUpTracking
# ─────────────────────────────────────
Write-Host "Adding columns to FollowUpTracking..." -ForegroundColor Cyan

# Source Signal ID
New-TextColumn -EntityId $followUpEntityId `
    -SchemaName "${PublisherPrefix}_sourcesignalid" `
    -DisplayName "Source Signal ID" `
    -Description "Unique ID of the original sent email (internetMessageId)." `
    -MaxLength 200 -Required $true

# Conversation ID
New-TextColumn -EntityId $followUpEntityId `
    -SchemaName "${PublisherPrefix}_conversationid" `
    -DisplayName "Conversation ID" `
    -Description "Exchange conversation ID for threading follow-up detection." `
    -MaxLength 500 -Required $true

# Internet Message Headers
New-MultilineTextColumn -EntityId $followUpEntityId `
    -SchemaName "${PublisherPrefix}_internetmessageheaders" `
    -DisplayName "Internet Message Headers" `
    -Description "Serialized internet message headers from the original sent email." `
    -MaxLength 2000

# Sent Date Time
New-DateTimeColumn -EntityId $followUpEntityId `
    -SchemaName "${PublisherPrefix}_sentdatetime" `
    -DisplayName "Sent Date Time" `
    -Description "When the original email was sent." `
    -Required $true

# Recipient Email
New-TextColumn -EntityId $followUpEntityId `
    -SchemaName "${PublisherPrefix}_recipientemail" `
    -DisplayName "Recipient Email" `
    -Description "Email address of the recipient being tracked for follow-up." `
    -MaxLength 250 -Required $true

# Recipient Type
New-TextColumn -EntityId $followUpEntityId `
    -SchemaName "${PublisherPrefix}_recipienttype" `
    -DisplayName "Recipient Type" `
    -Description "Type of recipient (e.g., to, cc, bcc)." `
    -MaxLength 20 -Required $true

# Follow-Up Date
New-DateTimeColumn -EntityId $followUpEntityId `
    -SchemaName "${PublisherPrefix}_followupdate" `
    -DisplayName "Follow-Up Date" `
    -Description "Date when the follow-up nudge should be triggered." `
    -Required $true

# Response Received
New-BooleanColumn -EntityId $followUpEntityId `
    -SchemaName "${PublisherPrefix}_responsereceived" `
    -DisplayName "Response Received" `
    -Description "Whether a response has been received from this recipient." `
    -DefaultValue $false `
    -Required $true

# Nudge Sent
New-BooleanColumn -EntityId $followUpEntityId `
    -SchemaName "${PublisherPrefix}_nudgesent" `
    -DisplayName "Nudge Sent" `
    -Description "Whether a nudge reminder has been sent for this follow-up." `
    -DefaultValue $false `
    -Required $true

# Dismissed By User
New-BooleanColumn -EntityId $followUpEntityId `
    -SchemaName "${PublisherPrefix}_dismissedbyuser" `
    -DisplayName "Dismissed By User" `
    -Description "Whether the user dismissed this follow-up tracking." `
    -DefaultValue $false `
    -Required $true

# Last Checked
New-DateTimeColumn -EntityId $followUpEntityId `
    -SchemaName "${PublisherPrefix}_lastchecked" `
    -DisplayName "Last Checked" `
    -Description "When the system last checked for a response to this follow-up."

# Distribution List Source (nullable — set when row created via DL expansion)
New-TextColumn -EntityId $followUpEntityId `
    -SchemaName "${PublisherPrefix}_dlsourceemail" `
    -DisplayName "Distribution List Source" `
    -Description "Original DL email address when this row was created via distribution list expansion. Null for direct recipients." `
    -MaxLength 250

# ─────────────────────────────────────
# 4b. Create Alternate Key on FollowUpTracking
# ─────────────────────────────────────
Write-Host "Creating alternate key on FollowUpTracking (cr_sourcesignalid, cr_recipientemail)..." -ForegroundColor Cyan

$followUpAltKeyDef = @{
    SchemaName = "${PublisherPrefix}_followup_message_recipient_key"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Follow-Up Message Recipient Key"
            LanguageCode = 1033
        })
    }
    KeyAttributes = @("${PublisherPrefix}_sourcesignalid", "${PublisherPrefix}_recipientemail")
} | ConvertTo-Json -Depth 20

try {
    $keyResult = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($followUpEntityId)/Keys" -Method Post -Headers $headers -Body $followUpAltKeyDef
    Write-Host "  Alternate key creation initiated." -ForegroundColor Yellow

    # Poll for key activation (async operation)
    $keyId = $keyResult.MetadataId
    $keyAttempts = 0
    $keyMaxAttempts = 12  # 30s timeout (12 x 2.5s)
    do {
        Start-Sleep -Seconds 2.5
        $keyAttempts++
        $keyStatus = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($followUpEntityId)/Keys($keyId)" -Headers $headers
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
# 5. Create NudgeConfiguration Table
# ─────────────────────────────────────
Write-Host "`n--- Creating NudgeConfiguration Table ---" -ForegroundColor Cyan

$nudgeEntityDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "${PublisherPrefix}_nudgeconfiguration"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Nudge Configuration"
            LanguageCode = 1033
        })
    }
    DisplayCollectionName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Nudge Configurations"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Per-user nudge timing and preference settings for the Email Productivity Agent."
            LanguageCode = 1033
        })
    }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    PrimaryNameAttribute = "${PublisherPrefix}_configlabel"
    Attributes = @(
        # Primary Name — Config Label (Text 100 chars)
        # IsPrimaryName and FormatName are required by the Dataverse CreateEntity API
        @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            IsPrimaryName = $true
            SchemaName = "${PublisherPrefix}_configlabel"
            RequiredLevel = @{ Value = "ApplicationRequired"; CanBeChanged = $true }
            MaxLength = 100
            FormatName = @{ Value = "Text" }
            DisplayName = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Config Label"
                    LanguageCode = 1033
                })
            }
            Description = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Descriptive label for this nudge configuration (e.g., user display name or 'Default')."
                    LanguageCode = 1033
                })
            }
        }
    )
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" -Method Post -Headers $headers -Body $nudgeEntityDef
    Write-Host "  NudgeConfiguration table created." -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 409 -or $_.Exception.Message -match "already exists|duplicate") {
        Write-Host "  NudgeConfiguration table already exists — skipping creation." -ForegroundColor Yellow
    } else {
        throw "NudgeConfiguration table creation failed: $($_.Exception.Message)"
    }
}

# Get entity metadata ID for nudge configuration
$nudgeMetadata = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='${PublisherPrefix}_nudgeconfiguration')" -Headers $headers
$nudgeEntityId = $nudgeMetadata.MetadataId

# ─────────────────────────────────────
# 5a. Add Columns to NudgeConfiguration
# ─────────────────────────────────────
Write-Host "Adding columns to NudgeConfiguration..." -ForegroundColor Cyan

# Internal Days (WholeNumber, default 3)
New-WholeNumberColumn -EntityId $nudgeEntityId `
    -SchemaName "${PublisherPrefix}_internaldays" `
    -DisplayName "Internal Days" `
    -Description "Number of days to wait before nudging for internal recipients." `
    -MinValue 1 -MaxValue 30 -DefaultValue 3 `
    -Required $true

# External Days (WholeNumber, default 5)
New-WholeNumberColumn -EntityId $nudgeEntityId `
    -SchemaName "${PublisherPrefix}_externaldays" `
    -DisplayName "External Days" `
    -Description "Number of days to wait before nudging for external recipients." `
    -MinValue 1 -MaxValue 30 -DefaultValue 5 `
    -Required $true

# Priority Days (WholeNumber, default 1)
New-WholeNumberColumn -EntityId $nudgeEntityId `
    -SchemaName "${PublisherPrefix}_prioritydays" `
    -DisplayName "Priority Days" `
    -Description "Number of days to wait before nudging for priority emails." `
    -MinValue 1 -MaxValue 30 -DefaultValue 1 `
    -Required $true

# General Days (WholeNumber, default 7)
New-WholeNumberColumn -EntityId $nudgeEntityId `
    -SchemaName "${PublisherPrefix}_generaldays" `
    -DisplayName "General Days" `
    -Description "Number of days to wait before nudging for general emails." `
    -MinValue 1 -MaxValue 30 -DefaultValue 7 `
    -Required $true

# Nudges Enabled (Boolean, default true)
New-BooleanColumn -EntityId $nudgeEntityId `
    -SchemaName "${PublisherPrefix}_nudgesenabled" `
    -DisplayName "Nudges Enabled" `
    -Description "Whether follow-up nudge reminders are enabled for this user." `
    -DefaultValue $true `
    -Required $true

# Snooze Folder ID
New-TextColumn -EntityId $nudgeEntityId `
    -SchemaName "${PublisherPrefix}_snoozefolderid" `
    -DisplayName "Snooze Folder ID" `
    -Description "Exchange folder ID used for snoozing follow-up items." `
    -MaxLength 200

# Owner User ID
New-TextColumn -EntityId $nudgeEntityId `
    -SchemaName "${PublisherPrefix}_owneruserid" `
    -DisplayName "Owner User ID" `
    -Description "The systemuserid GUID of the owning user" `
    -MaxLength 36 -Required $true

# Digest Mode (default false — individual cards)
New-BooleanColumn -EntityId $nudgeEntityId `
    -SchemaName "${PublisherPrefix}_digestmode" `
    -DisplayName "Digest Mode" `
    -Description "When true, nudges are delivered as a single daily digest card instead of individual cards." `
    -DefaultValue $false `
    -Required $true

# Skip Holiday Nudges (default true — suppress nudges on holidays)
New-BooleanColumn -EntityId $nudgeEntityId `
    -SchemaName "${PublisherPrefix}_skipholidaynudges" `
    -DisplayName "Skip Holiday Nudges" `
    -Description "When true, the daily nudge scan skips delivery if today is a holiday." `
    -DefaultValue $true `
    -Required $true

# Default Snooze Hours (default 48 = 2 days)
New-WholeNumberColumn -EntityId $nudgeEntityId `
    -SchemaName "${PublisherPrefix}_defaultsnoozehours" `
    -DisplayName "Default Snooze Hours" `
    -Description "Default snooze duration in hours when a user snoozes a nudge. Maximum 720 hours (30 days)." `
    -MinValue 1 -MaxValue 720 -DefaultValue 48 `
    -Required $true

# ─────────────────────────────────────
# 5b. Create Alternate Key on NudgeConfiguration
# ─────────────────────────────────────
Write-Host "Creating alternate key on NudgeConfiguration (cr_owneruserid)..." -ForegroundColor Cyan

$nudgeAltKeyDef = @{
    SchemaName = "${PublisherPrefix}_nudgeconfig_owner_key"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Nudge Config Owner Key"
            LanguageCode = 1033
        })
    }
    KeyAttributes = @("${PublisherPrefix}_owneruserid")
} | ConvertTo-Json -Depth 20

try {
    $keyResult = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($nudgeEntityId)/Keys" -Method Post -Headers $headers -Body $nudgeAltKeyDef
    Write-Host "  Alternate key creation initiated." -ForegroundColor Yellow

    # Poll for key activation (async operation)
    $keyId = $keyResult.MetadataId
    $keyAttempts = 0
    $keyMaxAttempts = 12  # 30s timeout (12 x 2.5s)
    do {
        Start-Sleep -Seconds 2.5
        $keyAttempts++
        $keyStatus = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($nudgeEntityId)/Keys($keyId)" -Headers $headers
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
# 6. Create SnoozedConversation Table
# ─────────────────────────────────────
Write-Host "`n--- Creating SnoozedConversation Table ---" -ForegroundColor Cyan

$snoozedEntityDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "${PublisherPrefix}_snoozedconversation"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Snoozed Conversation"
            LanguageCode = 1033
        })
    }
    DisplayCollectionName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Snoozed Conversations"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Tracks email conversations that the user has snoozed (moved to the managed EPA-Snoozed folder)."
            LanguageCode = 1033
        })
    }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    EntitySetName = "${PublisherPrefix}_snoozedconversations"
    PrimaryNameAttribute = "${PublisherPrefix}_originalsubject"
    Attributes = @(
        # Primary Name — Original Subject (Text 400 chars)
        # IsPrimaryName and FormatName are required by the Dataverse CreateEntity API
        @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            IsPrimaryName = $true
            SchemaName = "${PublisherPrefix}_originalsubject"
            RequiredLevel = @{ Value = "None"; CanBeChanged = $true }
            MaxLength = 400
            FormatName = @{ Value = "Text" }
            DisplayName = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Original Subject"
                    LanguageCode = 1033
                })
            }
            Description = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Subject line of the snoozed email. Used for display in Teams notifications when auto-unsnoozing."
                    LanguageCode = 1033
                })
            }
        }
    )
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" -Method Post -Headers $headers -Body $snoozedEntityDef
    Write-Host "  SnoozedConversation table created." -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 409 -or $_.Exception.Message -match "already exists|duplicate") {
        Write-Host "  SnoozedConversation table already exists — skipping creation." -ForegroundColor Yellow
    } else {
        throw "SnoozedConversation table creation failed: $($_.Exception.Message)"
    }
}

# Get entity metadata ID for snoozed conversation
$snoozedMetadata = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='${PublisherPrefix}_snoozedconversation')" -Headers $headers
$snoozedEntityId = $snoozedMetadata.MetadataId

# ─────────────────────────────────────
# 6a. Add Columns to SnoozedConversation
# ─────────────────────────────────────
Write-Host "Adding columns to SnoozedConversation..." -ForegroundColor Cyan

# Conversation ID
New-TextColumn -EntityId $snoozedEntityId `
    -SchemaName "${PublisherPrefix}_conversationid" `
    -DisplayName "Conversation ID" `
    -Description "Graph conversationId of the snoozed thread. Part of the composite alternate key." `
    -MaxLength 255 -Required $true

# Original Message ID
New-TextColumn -EntityId $snoozedEntityId `
    -SchemaName "${PublisherPrefix}_originalmessageid" `
    -DisplayName "Original Message ID" `
    -Description "Graph message ID of the snoozed email. Invalidated when moved via Graph API." `
    -MaxLength 500 -Required $true

# Snooze Until
New-DateTimeColumn -EntityId $snoozedEntityId `
    -SchemaName "${PublisherPrefix}_snoozeuntil" `
    -DisplayName "Snooze Until" `
    -Description "When the snooze should expire and the message should return to Inbox automatically."

# Current Folder
New-TextColumn -EntityId $snoozedEntityId `
    -SchemaName "${PublisherPrefix}_currentfolder" `
    -DisplayName "Current Folder" `
    -Description "Graph folder ID where the snoozed message currently resides." `
    -MaxLength 200 -Required $true

# Unsnoozed By Agent
New-BooleanColumn -EntityId $snoozedEntityId `
    -SchemaName "${PublisherPrefix}_unsnoozedbyagent" `
    -DisplayName "Unsnoozed By Agent" `
    -Description "Whether the agent automatically moved this message back to Inbox because a new reply was detected." `
    -DefaultValue $false `
    -Required $true

# Unsnoozed Date Time
New-DateTimeColumn -EntityId $snoozedEntityId `
    -SchemaName "${PublisherPrefix}_unsnoozeddatetime" `
    -DisplayName "Unsnoozed Date Time" `
    -Description "Timestamp when the auto-unsnooze occurred. Null if still snoozed."

# Owner User ID
New-TextColumn -EntityId $snoozedEntityId `
    -SchemaName "${PublisherPrefix}_owneruserid" `
    -DisplayName "Owner User ID" `
    -Description "The systemuserid GUID of the owning user" `
    -MaxLength 36 -Required $true

# Unsnoozed By Timer (default false)
New-BooleanColumn -EntityId $snoozedEntityId `
    -SchemaName "${PublisherPrefix}_unsnoozebytimer" `
    -DisplayName "Unsnoozed By Timer" `
    -Description "Whether the Snooze Timer flow moved this message back to Inbox because the snooze-until timestamp expired." `
    -DefaultValue $false `
    -Required $true

# ─────────────────────────────────────
# 6b. Create Alternate Key on SnoozedConversation
# ─────────────────────────────────────
Write-Host "Creating alternate key on SnoozedConversation (cr_conversationid, cr_owneruserid)..." -ForegroundColor Cyan

$snoozedAltKeyDef = @{
    SchemaName = "${PublisherPrefix}_snoozed_conversation_owner_key"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Conversation + Owner Key"
            LanguageCode = 1033
        })
    }
    KeyAttributes = @("${PublisherPrefix}_conversationid", "${PublisherPrefix}_owneruserid")
} | ConvertTo-Json -Depth 20

try {
    $keyResult = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($snoozedEntityId)/Keys" -Method Post -Headers $headers -Body $snoozedAltKeyDef
    Write-Host "  Alternate key creation initiated." -ForegroundColor Yellow

    # Poll for key activation (async operation)
    $keyId = $keyResult.MetadataId
    $keyAttempts = 0
    $keyMaxAttempts = 12  # 30s timeout (12 x 2.5s)
    do {
        Start-Sleep -Seconds 2.5
        $keyAttempts++
        $keyStatus = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($snoozedEntityId)/Keys($keyId)" -Headers $headers
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
# Helper: Decimal Column
# ─────────────────────────────────────
function New-DecimalColumn {
    param(
        [string]$EntityId,
        [string]$SchemaName,
        [string]$DisplayName,
        [string]$Description,
        [int]$Precision = 2,
        [bool]$Required = $false
    )

    $colDef = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
        SchemaName = $SchemaName
        RequiredLevel = @{ Value = if ($Required) { "ApplicationRequired" } else { "None" } }
        Precision = $Precision
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
        Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($EntityId)/Attributes" -Method Post -Headers $headers -Body $colDef
        Write-Host "  Column '$DisplayName' created." -ForegroundColor Green
    } catch {
        Write-Warning "  Column '$DisplayName' failed: $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────
# Helper: DateOnly Column
# ─────────────────────────────────────
function New-DateOnlyColumn {
    param(
        [string]$EntityId,
        [string]$SchemaName,
        [string]$DisplayName,
        [string]$Description,
        [bool]$Required = $false
    )

    $colDef = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        SchemaName = $SchemaName
        RequiredLevel = @{ Value = if ($Required) { "ApplicationRequired" } else { "None" } }
        Format = "DateOnly"
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
        Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($EntityId)/Attributes" -Method Post -Headers $headers -Body $colDef
        Write-Host "  Column '$DisplayName' created." -ForegroundColor Green
    } catch {
        Write-Warning "  Column '$DisplayName' failed: $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────
# 7. Create PriorityContact Table
# ─────────────────────────────────────
Write-Host "`n--- Creating PriorityContact Table ---" -ForegroundColor Cyan

$priorityContactDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "${PublisherPrefix}_prioritycontact"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Priority Contact"
            LanguageCode = 1033
        })
    }
    DisplayCollectionName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Priority Contacts"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Per-user priority contact list. Recipients on this list receive the shortest follow-up delay."
            LanguageCode = 1033
        })
    }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    PrimaryNameAttribute = "${PublisherPrefix}_contactemail"
    Attributes = @(
        @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            IsPrimaryName = $true
            SchemaName = "${PublisherPrefix}_contactemail"
            RequiredLevel = @{ Value = "ApplicationRequired"; CanBeChanged = $true }
            MaxLength = 250
            FormatName = @{ Value = "Text" }
            DisplayName = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Contact Email"
                    LanguageCode = 1033
                })
            }
            Description = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Email address of the priority contact."
                    LanguageCode = 1033
                })
            }
        }
    )
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" -Method Post -Headers $headers -Body $priorityContactDef
    Write-Host "  PriorityContact table created." -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 409 -or $_.Exception.Message -match "already exists|duplicate") {
        Write-Host "  PriorityContact table already exists — skipping creation." -ForegroundColor Yellow
    } else {
        throw "PriorityContact table creation failed: $($_.Exception.Message)"
    }
}

$priorityContactMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='${PublisherPrefix}_prioritycontact')" -Headers $headers
$priorityContactEntityId = $priorityContactMeta.MetadataId

Write-Host "Adding columns to PriorityContact..." -ForegroundColor Cyan

New-TextColumn -EntityId $priorityContactEntityId `
    -SchemaName "${PublisherPrefix}_contactname" `
    -DisplayName "Contact Name" `
    -Description "Display name of the priority contact." `
    -MaxLength 200

New-TextColumn -EntityId $priorityContactEntityId `
    -SchemaName "${PublisherPrefix}_owneruserid" `
    -DisplayName "Owner User ID" `
    -Description "The Azure AD object ID of the owning user." `
    -MaxLength 36 -Required $true

New-TextColumn -EntityId $priorityContactEntityId `
    -SchemaName "${PublisherPrefix}_notes" `
    -DisplayName "Notes" `
    -Description "Optional notes about why this contact is priority." `
    -MaxLength 500

# Alternate Key: contactemail + owneruserid
Write-Host "Creating alternate key on PriorityContact..." -ForegroundColor Cyan
$priorityAltKeyDef = @{
    SchemaName = "${PublisherPrefix}_priority_contact_email_owner_key"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Contact Email + Owner Key"
            LanguageCode = 1033
        })
    }
    KeyAttributes = @("${PublisherPrefix}_contactemail", "${PublisherPrefix}_owneruserid")
} | ConvertTo-Json -Depth 20

try {
    $keyResult = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($priorityContactEntityId)/Keys" -Method Post -Headers $headers -Body $priorityAltKeyDef
    $keyId = $keyResult.MetadataId
    $keyAttempts = 0; $keyMaxAttempts = 12
    do {
        Start-Sleep -Seconds 2.5; $keyAttempts++
        $keyStatus = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($priorityContactEntityId)/Keys($keyId)" -Headers $headers
        if ($keyStatus.EntityKeyIndexStatus -eq "Active") { Write-Host "  Alternate key active." -ForegroundColor Green; break }
        Write-Host "  Key indexing... attempt $keyAttempts/$keyMaxAttempts (status: $($keyStatus.EntityKeyIndexStatus))"
    } while ($keyAttempts -lt $keyMaxAttempts)
    if ($keyAttempts -ge $keyMaxAttempts) { Write-Warning "  Alternate key not yet active after 30s." }
} catch { Write-Warning "  Alternate key creation failed (may already exist): $($_.Exception.Message)" }

# ─────────────────────────────────────
# 8. Create HolidayCalendar Table
# ─────────────────────────────────────
Write-Host "`n--- Creating HolidayCalendar Table ---" -ForegroundColor Cyan

$holidayCalendarDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "${PublisherPrefix}_holidaycalendar"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Holiday Calendar"
            LanguageCode = 1033
        })
    }
    DisplayCollectionName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Holiday Calendars"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Organization and per-user holiday dates for business day calculations and nudge suppression."
            LanguageCode = 1033
        })
    }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    PrimaryNameAttribute = "${PublisherPrefix}_holidayname"
    Attributes = @(
        @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            IsPrimaryName = $true
            SchemaName = "${PublisherPrefix}_holidayname"
            RequiredLevel = @{ Value = "ApplicationRequired"; CanBeChanged = $true }
            MaxLength = 200
            FormatName = @{ Value = "Text" }
            DisplayName = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Holiday Name"
                    LanguageCode = 1033
                })
            }
            Description = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Name of the holiday."
                    LanguageCode = 1033
                })
            }
        }
    )
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" -Method Post -Headers $headers -Body $holidayCalendarDef
    Write-Host "  HolidayCalendar table created." -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 409 -or $_.Exception.Message -match "already exists|duplicate") {
        Write-Host "  HolidayCalendar table already exists — skipping creation." -ForegroundColor Yellow
    } else {
        throw "HolidayCalendar table creation failed: $($_.Exception.Message)"
    }
}

$holidayMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='${PublisherPrefix}_holidaycalendar')" -Headers $headers
$holidayEntityId = $holidayMeta.MetadataId

Write-Host "Adding columns to HolidayCalendar..." -ForegroundColor Cyan

New-DateOnlyColumn -EntityId $holidayEntityId `
    -SchemaName "${PublisherPrefix}_holidaydate" `
    -DisplayName "Holiday Date" `
    -Description "The date of the holiday." `
    -Required $true

New-TextColumn -EntityId $holidayEntityId `
    -SchemaName "${PublisherPrefix}_owneruserid" `
    -DisplayName "Owner User ID" `
    -Description "The Azure AD object ID of the owning user." `
    -MaxLength 36 -Required $true

New-BooleanColumn -EntityId $holidayEntityId `
    -SchemaName "${PublisherPrefix}_isorgwide" `
    -DisplayName "Organization Wide" `
    -Description "When true, this holiday applies to all users in the organization." `
    -DefaultValue $false `
    -Required $true

# Alternate Key: holidaydate + owneruserid
Write-Host "Creating alternate key on HolidayCalendar..." -ForegroundColor Cyan
$holidayAltKeyDef = @{
    SchemaName = "${PublisherPrefix}_holiday_date_owner_key"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Holiday Date + Owner Key"
            LanguageCode = 1033
        })
    }
    KeyAttributes = @("${PublisherPrefix}_holidaydate", "${PublisherPrefix}_owneruserid")
} | ConvertTo-Json -Depth 20

try {
    $keyResult = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($holidayEntityId)/Keys" -Method Post -Headers $headers -Body $holidayAltKeyDef
    $keyId = $keyResult.MetadataId
    $keyAttempts = 0; $keyMaxAttempts = 12
    do {
        Start-Sleep -Seconds 2.5; $keyAttempts++
        $keyStatus = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($holidayEntityId)/Keys($keyId)" -Headers $headers
        if ($keyStatus.EntityKeyIndexStatus -eq "Active") { Write-Host "  Alternate key active." -ForegroundColor Green; break }
        Write-Host "  Key indexing... attempt $keyAttempts/$keyMaxAttempts (status: $($keyStatus.EntityKeyIndexStatus))"
    } while ($keyAttempts -lt $keyMaxAttempts)
    if ($keyAttempts -ge $keyMaxAttempts) { Write-Warning "  Alternate key not yet active after 30s." }
} catch { Write-Warning "  Alternate key creation failed (may already exist): $($_.Exception.Message)" }

# ─────────────────────────────────────
# 9. Create NudgeAnalytics Table
# ─────────────────────────────────────
Write-Host "`n--- Creating NudgeAnalytics Table ---" -ForegroundColor Cyan

$analyticsDef = @{
    "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
    SchemaName = "${PublisherPrefix}_nudgeanalytics"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Nudge Analytics"
            LanguageCode = 1033
        })
    }
    DisplayCollectionName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Nudge Analytics"
            LanguageCode = 1033
        })
    }
    Description = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Weekly aggregated analytics for nudge effectiveness tracking."
            LanguageCode = 1033
        })
    }
    OwnershipType = "UserOwned"
    HasNotes = $false
    HasActivities = $false
    PrimaryNameAttribute = "${PublisherPrefix}_periodlabel"
    Attributes = @(
        @{
            "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            IsPrimaryName = $true
            SchemaName = "${PublisherPrefix}_periodlabel"
            RequiredLevel = @{ Value = "ApplicationRequired"; CanBeChanged = $true }
            MaxLength = 50
            FormatName = @{ Value = "Text" }
            DisplayName = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Period Label"
                    LanguageCode = 1033
                })
            }
            Description = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(@{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label = "Human-readable period label (e.g., 'Week of 2026-03-16')."
                    LanguageCode = 1033
                })
            }
        }
    )
} | ConvertTo-Json -Depth 20

try {
    Invoke-RestMethod -Uri "$apiBase/EntityDefinitions" -Method Post -Headers $headers -Body $analyticsDef
    Write-Host "  NudgeAnalytics table created." -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 409 -or $_.Exception.Message -match "already exists|duplicate") {
        Write-Host "  NudgeAnalytics table already exists — skipping creation." -ForegroundColor Yellow
    } else {
        throw "NudgeAnalytics table creation failed: $($_.Exception.Message)"
    }
}

$analyticsMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='${PublisherPrefix}_nudgeanalytics')" -Headers $headers
$analyticsEntityId = $analyticsMeta.MetadataId

Write-Host "Adding columns to NudgeAnalytics..." -ForegroundColor Cyan

New-TextColumn -EntityId $analyticsEntityId `
    -SchemaName "${PublisherPrefix}_owneruserid" `
    -DisplayName "Owner User ID" `
    -Description "The Azure AD object ID of the owning user." `
    -MaxLength 36 -Required $true

New-DateTimeColumn -EntityId $analyticsEntityId `
    -SchemaName "${PublisherPrefix}_periodstart" `
    -DisplayName "Period Start" `
    -Description "Start of the analytics period (Sunday 00:00 UTC)." `
    -Required $true

New-WholeNumberColumn -EntityId $analyticsEntityId `
    -SchemaName "${PublisherPrefix}_totaltracked" `
    -DisplayName "Total Tracked" `
    -Description "Total follow-up tracking rows created during this period." `
    -DefaultValue 0 -Required $true

New-WholeNumberColumn -EntityId $analyticsEntityId `
    -SchemaName "${PublisherPrefix}_totalreplied" `
    -DisplayName "Total Replied" `
    -Description "Total tracking rows where a reply was detected during this period." `
    -DefaultValue 0 -Required $true

New-WholeNumberColumn -EntityId $analyticsEntityId `
    -SchemaName "${PublisherPrefix}_totalnudged" `
    -DisplayName "Total Nudged" `
    -Description "Total nudge cards delivered during this period." `
    -DefaultValue 0 -Required $true

New-WholeNumberColumn -EntityId $analyticsEntityId `
    -SchemaName "${PublisherPrefix}_totaldismissed" `
    -DisplayName "Total Dismissed" `
    -Description "Total nudges dismissed during this period." `
    -DefaultValue 0 -Required $true

New-DecimalColumn -EntityId $analyticsEntityId `
    -SchemaName "${PublisherPrefix}_avgreplydays" `
    -DisplayName "Average Reply Days" `
    -Description "Average calendar days between sent date and reply detection." `
    -Precision 2

# Alternate Key: periodstart + owneruserid
Write-Host "Creating alternate key on NudgeAnalytics..." -ForegroundColor Cyan
$analyticsAltKeyDef = @{
    SchemaName = "${PublisherPrefix}_analytics_period_owner_key"
    DisplayName = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels = @(@{
            "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
            Label = "Period Start + Owner Key"
            LanguageCode = 1033
        })
    }
    KeyAttributes = @("${PublisherPrefix}_periodstart", "${PublisherPrefix}_owneruserid")
} | ConvertTo-Json -Depth 20

try {
    $keyResult = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($analyticsEntityId)/Keys" -Method Post -Headers $headers -Body $analyticsAltKeyDef
    $keyId = $keyResult.MetadataId
    $keyAttempts = 0; $keyMaxAttempts = 12
    do {
        Start-Sleep -Seconds 2.5; $keyAttempts++
        $keyStatus = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($analyticsEntityId)/Keys($keyId)" -Headers $headers
        if ($keyStatus.EntityKeyIndexStatus -eq "Active") { Write-Host "  Alternate key active." -ForegroundColor Green; break }
        Write-Host "  Key indexing... attempt $keyAttempts/$keyMaxAttempts (status: $($keyStatus.EntityKeyIndexStatus))"
    } while ($keyAttempts -lt $keyMaxAttempts)
    if ($keyAttempts -ge $keyMaxAttempts) { Write-Warning "  Alternate key not yet active after 30s." }
} catch { Write-Warning "  Alternate key creation failed (may already exist): $($_.Exception.Message)" }

# ─────────────────────────────────────
# 10. Publish All Customizations
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
# 8. Print Summary & Manual Steps
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
Write-Host "Tables created:" -ForegroundColor White
Write-Host "  - ${PublisherPrefix}_followuptracking (Follow-Up Tracking)" -ForegroundColor Gray
Write-Host "  - ${PublisherPrefix}_nudgeconfiguration (Nudge Configuration)" -ForegroundColor Gray
Write-Host "  - ${PublisherPrefix}_snoozedconversation (Snoozed Conversation)" -ForegroundColor Gray
Write-Host "  - ${PublisherPrefix}_prioritycontact (Priority Contact)" -ForegroundColor Gray
Write-Host "  - ${PublisherPrefix}_holidaycalendar (Holiday Calendar)" -ForegroundColor Gray
Write-Host "  - ${PublisherPrefix}_nudgeanalytics (Nudge Analytics)" -ForegroundColor Gray
Write-Host ""
Write-Host "MANUAL STEPS REQUIRED:" -ForegroundColor Yellow
Write-Host "1. Create connection references in Power Automate for:" -ForegroundColor White
Write-Host "   - Office 365 Outlook (email triggers and actions)" -ForegroundColor Gray
Write-Host "   - Microsoft Graph (mail and calendar access)" -ForegroundColor Gray
Write-Host "2. Seed default NudgeConfiguration row (internaldays=3, externaldays=5, prioritydays=1, generaldays=7)" -ForegroundColor White
Write-Host "3. Configure Copilot Studio agent (see deployment guide)" -ForegroundColor White
Write-Host ""
