<#
.SYNOPSIS
    Deploys Power Automate flows for the Email Productivity Agent via the Power Automate Management API.

.DESCRIPTION
    Creates all agent flows programmatically:
      - Flow 1: Sent Items Tracker (event-driven)
      - Flow 2: Response Detection & Nudge Delivery (daily 9 AM)
      - Flow 2b: Card Action Handler (event-driven)
      - Flow 5: Data Retention Cleanup (weekly)

    Uses the Power Automate Management API to create flows with proper connection bindings.
    Flows are created in the target environment and can be associated with a Copilot Studio agent.

.PARAMETER EnvironmentId
    Power Platform Environment ID (GUID). Find via: pac env list

.PARAMETER OrgUrl
    Dataverse organization URL (e.g., https://emailproductivityagent.crm.dynamics.com)

.PARAMETER TimeZone
    Time zone for scheduled triggers. Default: "Eastern Standard Time"
    Common values: "Pacific Standard Time", "Central Standard Time", "UTC"

.PARAMETER FlowsToCreate
    Which flows to create. Default: all.
    Valid values: "All", "Flow1", "Flow2", "Flow2b", "Flow5"

.EXAMPLE
    .\deploy-agent-flows.ps1 -EnvironmentId "fd0c6bc5-17f6-eb9d-9620-f7ea65f9c11d" -OrgUrl "https://emailproductivityagent.crm.dynamics.com"

.EXAMPLE
    .\deploy-agent-flows.ps1 -EnvironmentId "fd0c6bc5-..." -OrgUrl "https://..." -FlowsToCreate "Flow1"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [Parameter(Mandatory = $true)]
    [string]$OrgUrl,

    [string]$TimeZone = "Eastern Standard Time",

    [ValidateSet("All", "Flow1", "Flow2", "Flow2b", "Flow5")]
    [string]$FlowsToCreate = "All"
)

$ErrorActionPreference = "Stop"
$OrgUrl = $OrgUrl.TrimEnd('/')

# ─────────────────────────────────────
# Flow definition file map
# ─────────────────────────────────────
$flowMap = @{
    Flow1  = @{
        File        = "flow-1-sent-items-tracker.json"
        DisplayName = "EPA - Flow 1: Sent Items Tracker"
        Connections = @("shared_office365", "shared_office365users", "shared_commondataserviceforapps")
    }
    Flow2  = @{
        File        = "flow-2-response-detection.json"
        DisplayName = "EPA - Flow 2: Response Detection & Nudge Delivery"
        Connections = @("shared_office365users", "shared_commondataserviceforapps", "shared_webcontents", "shared_teams")
    }
    Flow2b = @{
        File        = "flow-2b-card-action-handler.json"
        DisplayName = "EPA - Flow 2b: Card Action Handler"
        Connections = @("shared_teams", "shared_commondataserviceforapps")
    }
    Flow5  = @{
        File        = "flow-5-data-retention.json"
        DisplayName = "EPA - Flow 5: Data Retention Cleanup"
        Connections = @("shared_commondataserviceforapps")
    }
}

# ─────────────────────────────────────
# Connector display names (for user messaging)
# ─────────────────────────────────────
$connectorNames = @{
    shared_office365                 = "Office 365 Outlook"
    shared_office365users            = "Office 365 Users"
    shared_commondataserviceforapps  = "Microsoft Dataverse"
    shared_webcontents               = "HTTP with Microsoft Entra ID (preauthorized)"
    shared_teams                     = "Microsoft Teams"
}

# ─────────────────────────────────────
# 0. Prerequisite Checks
# ─────────────────────────────────────
Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Email Productivity Agent — Flow Deployment Script   ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    throw "Azure CLI not found. Install: winget install Microsoft.AzureCLI"
}

$srcDir = Join-Path $PSScriptRoot "..\src"
if (-not (Test-Path $srcDir)) {
    throw "Source directory not found: $srcDir"
}

# ─────────────────────────────────────
# 1. Acquire Tokens
# ─────────────────────────────────────
Write-Host "[1/5] Acquiring API tokens..." -ForegroundColor Cyan

# Token for Power Automate Management API
try {
    $flowToken = az account get-access-token --resource "https://service.flow.microsoft.com/" --query accessToken -o tsv 2>$null
    if (-not $flowToken) { throw "Empty token" }
    Write-Host "  ✓ Power Automate API token acquired" -ForegroundColor Green
}
catch {
    Write-Host "  ⚠ Power Automate API token failed. Trying alternate resource..." -ForegroundColor Yellow
    try {
        $flowToken = az account get-access-token --resource "https://api.flow.microsoft.com" --query accessToken -o tsv 2>$null
        if (-not $flowToken) { throw "Empty token" }
        Write-Host "  ✓ Power Automate API token acquired (alternate)" -ForegroundColor Green
    }
    catch {
        throw "Cannot acquire Power Automate API token. Ensure you are logged in: az login --tenant <tenantId>"
    }
}

# Token for Dataverse (for connection discovery fallback)
try {
    $dvToken = az account get-access-token --resource "$OrgUrl" --query accessToken -o tsv 2>$null
    if (-not $dvToken) { throw "Empty token" }
    Write-Host "  ✓ Dataverse API token acquired" -ForegroundColor Green
}
catch {
    Write-Host "  ⚠ Dataverse token not available — connection discovery may be limited" -ForegroundColor Yellow
    $dvToken = $null
}

$flowHeaders = @{
    "Authorization" = "Bearer $flowToken"
    "Content-Type"  = "application/json"
}

# ─────────────────────────────────────
# 2. Discover Existing Connections
# ─────────────────────────────────────
Write-Host "`n[2/5] Discovering connections in environment..." -ForegroundColor Cyan

$connectionsUrl = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentId/connections?api-version=2016-11-01&`$top=100"
try {
    $connectionsResponse = Invoke-RestMethod -Uri $connectionsUrl -Headers $flowHeaders -Method Get
    $connections = $connectionsResponse.value
    Write-Host "  Found $($connections.Count) connection(s)" -ForegroundColor Green
}
catch {
    Write-Host "  ⚠ Could not list connections via Flow API (HTTP $($_.Exception.Response.StatusCode.value__))." -ForegroundColor Yellow
    Write-Host "    Will create flows without connection bindings — you must configure connections in the Power Automate designer." -ForegroundColor Yellow
    $connections = @()
}

# Map connector API IDs to connection names
$connectionMap = @{}
foreach ($conn in $connections) {
    $apiId = $conn.properties.apiId
    # Extract the connector name from the apiId path
    $connectorKey = ($apiId -split '/')[-1]
    if (-not $connectionMap.ContainsKey($connectorKey)) {
        $connectionMap[$connectorKey] = $conn.name
        $status = if ($conn.properties.statuses -and $conn.properties.statuses[0].status -eq "Connected") { "Connected" } else { "Unknown" }
        Write-Host "  ✓ $connectorKey → $($conn.name) [$status]" -ForegroundColor Green
    }
}

# Check for missing connections
$allNeededConnectors = @()
$flowsToProcess = if ($FlowsToCreate -eq "All") { $flowMap.Keys } else { @($FlowsToCreate) }
foreach ($flowKey in $flowsToProcess) {
    $allNeededConnectors += $flowMap[$flowKey].Connections
}
$allNeededConnectors = $allNeededConnectors | Sort-Object -Unique

$missingConnectors = @()
foreach ($connector in $allNeededConnectors) {
    if (-not $connectionMap.ContainsKey($connector)) {
        $missingConnectors += $connector
        $displayName = $connectorNames[$connector]
        Write-Host "  ✗ $connector ($displayName) — NOT FOUND" -ForegroundColor Red
    }
}

if ($missingConnectors.Count -gt 0) {
    Write-Host "`n  Missing connections detected. Flows will be created but may need manual connection setup." -ForegroundColor Yellow
    Write-Host "  Create missing connections in Power Automate → Connections before activating flows.`n" -ForegroundColor Yellow
}

# ─────────────────────────────────────
# 3. Build Connection References
# ─────────────────────────────────────
function Build-ConnectionReferences {
    param([string[]]$RequiredConnectors)

    $refs = @{}
    foreach ($connector in $RequiredConnectors) {
        $ref = @{
            id     = "/providers/Microsoft.PowerApps/apis/$connector"
            source = "Invoker"
            tier   = "NotSpecified"
        }
        if ($connectionMap.ContainsKey($connector)) {
            $ref["connectionName"] = $connectionMap[$connector]
        }
        $refs[$connector] = $ref
    }
    return $refs
}

# ─────────────────────────────────────
# 4. Patch Definition for API Compatibility
# ─────────────────────────────────────

# The Power Automate Management API requires:
#   - $connections + $authentication parameters in the definition
#   - "authentication": "@parameters('$authentication')" in each OpenApiConnection input
# This function injects those if missing, so the source JSON files stay readable.

function Patch-DefinitionForApi {
    param([object]$Definition)

    # Ensure parameters section exists with $connections and $authentication
    if (-not $Definition.parameters) {
        $Definition | Add-Member -NotePropertyName "parameters" -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $params = $Definition.parameters
    if (-not $params.'$connections') {
        $params | Add-Member -NotePropertyName '$connections' -NotePropertyValue ([PSCustomObject]@{
            defaultValue = [PSCustomObject]@{}
            type         = "Object"
        }) -Force
    }
    if (-not $params.'$authentication') {
        $params | Add-Member -NotePropertyName '$authentication' -NotePropertyValue ([PSCustomObject]@{
            defaultValue = [PSCustomObject]@{}
            type         = "SecureObject"
        }) -Force
    }

    # Add authentication to every OpenApiConnection / OpenApiConnectionNotification action
    function Add-AuthToActions {
        param([object]$Actions)
        if (-not $Actions) { return }

        foreach ($actionName in $Actions.PSObject.Properties.Name) {
            $action = $Actions.$actionName
            $actionType = $action.type

            # Add authentication to OpenApiConnection actions
            if ($actionType -in @("OpenApiConnection", "OpenApiConnectionNotification")) {
                if ($action.inputs -and -not $action.inputs.authentication) {
                    $action.inputs | Add-Member -NotePropertyName "authentication" -NotePropertyValue "@parameters('`$authentication')" -Force
                }
            }

            # Recurse into nested structures
            if ($action.actions) { Add-AuthToActions -Actions $action.actions }
            if ($action.else -and $action.else.actions) { Add-AuthToActions -Actions $action.else.actions }
            if ($action.cases) {
                foreach ($caseName in $action.cases.PSObject.Properties.Name) {
                    $case = $action.cases.$caseName
                    if ($case.actions) { Add-AuthToActions -Actions $case.actions }
                }
            }
            if ($action.default -and $action.default.actions) { Add-AuthToActions -Actions $action.default.actions }
        }
    }

    # Add authentication to trigger if it's an OpenApiConnection type
    foreach ($triggerName in $Definition.triggers.PSObject.Properties.Name) {
        $trigger = $Definition.triggers.$triggerName
        if ($trigger.type -in @("OpenApiConnectionNotification", "OpenApiConnection")) {
            if ($trigger.inputs -and -not $trigger.inputs.authentication) {
                $trigger.inputs | Add-Member -NotePropertyName "authentication" -NotePropertyValue "@parameters('`$authentication')" -Force
            }
        }
    }

    Add-AuthToActions -Actions $Definition.actions

    return $Definition
}

function Set-FlowTimeZone {
    param([object]$Definition, [string]$TargetTimeZone)

    foreach ($triggerName in $Definition.triggers.PSObject.Properties.Name) {
        $trigger = $Definition.triggers.$triggerName
        if ($trigger.recurrence -and $trigger.recurrence.timeZone) {
            $trigger.recurrence.timeZone = $TargetTimeZone
        }
    }
    return $Definition
}

# ─────────────────────────────────────
# 5. Create Flows
# ─────────────────────────────────────
Write-Host "`n[3/5] Creating flows..." -ForegroundColor Cyan

$createUrl = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentId/flows?api-version=2016-11-01"
$createdFlows = @()
$failedFlows = @()

foreach ($flowKey in $flowsToProcess) {
    $flow = $flowMap[$flowKey]
    $filePath = Join-Path $srcDir $flow.File

    if (-not (Test-Path $filePath)) {
        Write-Host "  ✗ $($flow.DisplayName) — file not found: $filePath" -ForegroundColor Red
        $failedFlows += $flowKey
        continue
    }

    Write-Host "  Creating: $($flow.DisplayName)..." -ForegroundColor White

    # Read and parse flow definition
    $flowJson = Get-Content $filePath -Raw | ConvertFrom-Json
    $definition = $flowJson.definition

    # Patch for API compatibility (inject $connections, $authentication, auth on each action)
    $definition = Patch-DefinitionForApi -Definition $definition

    # Patch time zone
    $definition = Set-FlowTimeZone -Definition $definition -TargetTimeZone $TimeZone

    # Build connection references
    $connRefs = Build-ConnectionReferences -RequiredConnectors $flow.Connections

    # Build API payload
    $payload = @{
        properties = @{
            displayName          = $flow.DisplayName
            definition           = $definition
            connectionReferences = $connRefs
            state                = "Stopped"
        }
    }

    $payloadJson = $payload | ConvertTo-Json -Depth 50 -Compress

    try {
        $result = Invoke-RestMethod -Method Post -Uri $createUrl -Headers $flowHeaders -Body $payloadJson -ErrorAction Stop
        $flowId = $result.name
        $state = $result.properties.state
        Write-Host "  ✓ $($flow.DisplayName)" -ForegroundColor Green
        Write-Host "    Flow ID: $flowId" -ForegroundColor Gray
        Write-Host "    State:   $state" -ForegroundColor Gray
        $createdFlows += [PSCustomObject]@{
            Key         = $flowKey
            DisplayName = $flow.DisplayName
            FlowId      = $flowId
            State       = $state
        }
    }
    catch {
        $errMsg = $_.ErrorDetails.Message
        Write-Host "  ✗ $($flow.DisplayName)" -ForegroundColor Red
        if ($errMsg) {
            try {
                $errorObj = $errMsg | ConvertFrom-Json
                Write-Host "    Error: $($errorObj.error.message)" -ForegroundColor Red
            }
            catch {
                Write-Host "    Error: $errMsg" -ForegroundColor Red
            }
        }
        else {
            Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        $failedFlows += $flowKey
    }
}

# ─────────────────────────────────────
# 6. Summary
# ─────────────────────────────────────
Write-Host "`n[4/5] Deployment Summary" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────" -ForegroundColor Gray

if ($createdFlows.Count -gt 0) {
    Write-Host "  ✓ Created: $($createdFlows.Count) flow(s)" -ForegroundColor Green
    foreach ($f in $createdFlows) {
        Write-Host "    • $($f.DisplayName) [$($f.State)]" -ForegroundColor Green
        Write-Host "      ID: $($f.FlowId)" -ForegroundColor Gray
    }
}

if ($failedFlows.Count -gt 0) {
    Write-Host "  ✗ Failed: $($failedFlows.Count) flow(s)" -ForegroundColor Red
    foreach ($fk in $failedFlows) {
        Write-Host "    • $($flowMap[$fk].DisplayName)" -ForegroundColor Red
    }
}

# ─────────────────────────────────────
# 7. Post-Deployment Instructions
# ─────────────────────────────────────
Write-Host "`n[5/5] Next Steps" -ForegroundColor Cyan

if ($missingConnectors.Count -gt 0) {
    Write-Host "  1. Create missing connections in Power Automate → Connections:" -ForegroundColor Yellow
    foreach ($mc in $missingConnectors) {
        Write-Host "     • $($connectorNames[$mc]) ($mc)" -ForegroundColor Yellow
    }
    Write-Host "  2. Open each flow in Power Automate and update connection references" -ForegroundColor Yellow
}

Write-Host @"

  To associate flows with your Copilot Studio agent:
    1. Open Copilot Studio → your agent → Settings → Flows
    2. Click "Add a flow" for each created flow
    3. Publish the agent

  To verify flows are running:
    1. Power Automate → My flows → check status is "On"
    2. Send a test email to trigger Flow 1
    3. Check Dataverse table for new row

  Environment: $OrgUrl
  Flows created at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@ -ForegroundColor Gray

# Output flow IDs for scripting
if ($createdFlows.Count -gt 0) {
    Write-Host "`n  Flow IDs (for reference):" -ForegroundColor Cyan
    $createdFlows | ForEach-Object {
        Write-Host "    $($_.Key)=$($_.FlowId)" -ForegroundColor Gray
    }
}

Write-Host "`n✅ Flow deployment complete.`n" -ForegroundColor Green
