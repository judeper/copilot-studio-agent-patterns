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
        @{ Label = "CALENDAR_SCAN"; Value = 100000002 }
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
        @{ Label = "NO_OUTPUT"; Value = 100000003 }
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
# 4. Enable PCF Components for Canvas Apps
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
