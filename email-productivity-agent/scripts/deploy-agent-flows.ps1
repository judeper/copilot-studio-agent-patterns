<#
.SYNOPSIS
    Deploys Power Automate flows for the Email Productivity Agent as solution-aware components.

.DESCRIPTION
    Creates all agent flows programmatically via the Dataverse Web API:
      - Flow 1: Sent Items Tracker (event-driven)
      - Flow 2: Response Detection & Nudge Delivery (daily 9 AM)
      - Flow 2b: Card Action Handler (event-driven)
      - Flow 5: Data Retention Cleanup (weekly)

    Flows are created inside a Dataverse solution with proper connection references,
    making them compatible with the new Power Automate designer and ALM (solution export/import).

    The script:
      1. Creates (or reuses) an "EmailProductivityAgent" solution
      2. Creates 5 connection references in the solution
      3. Reads flow JSON definitions from ../src/
      4. Injects required $connections/$authentication parameters for API compatibility
      5. Creates each flow as a solution-aware workflow via the Dataverse API

.PARAMETER OrgUrl
    Dataverse organization URL (e.g., https://emailproductivityagent.crm.dynamics.com)

.PARAMETER PublisherPrefix
    Dataverse publisher prefix. Default: "cr"

.PARAMETER TimeZone
    Time zone for scheduled triggers. Default: "Eastern Standard Time"
    Common values: "Pacific Standard Time", "Central Standard Time", "UTC"

.PARAMETER FlowsToCreate
    Which flows to create. Default: all.
    Valid values: "All", "Flow1", "Flow2", "Flow2b", "Flow5"

.EXAMPLE
    .\deploy-agent-flows.ps1 -OrgUrl "https://emailproductivityagent.crm.dynamics.com"

.EXAMPLE
    .\deploy-agent-flows.ps1 -OrgUrl "https://..." -FlowsToCreate "Flow1" -TimeZone "Pacific Standard Time"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$OrgUrl,

    [string]$PublisherPrefix = "cr",

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
        ConnRefs    = @("shared_office365", "shared_office365users", "shared_commondataserviceforapps")
    }
    Flow2  = @{
        File        = "flow-2-response-detection.json"
        DisplayName = "EPA - Flow 2: Response Detection and Nudge Delivery"
        ConnRefs    = @("shared_office365users", "shared_commondataserviceforapps", "shared_webcontents", "shared_teams")
    }
    Flow2b = @{
        File        = "flow-2b-card-action-handler.json"
        DisplayName = "EPA - Flow 2b: Card Action Handler"
        ConnRefs    = @("shared_teams", "shared_commondataserviceforapps")
    }
    Flow5  = @{
        File        = "flow-5-data-retention.json"
        DisplayName = "EPA - Flow 5: Data Retention Cleanup"
        ConnRefs    = @("shared_commondataserviceforapps")
    }
}

# Connection reference definitions
$connRefDefs = @{
    shared_office365                = @{ LogicalName = "${PublisherPrefix}_sharedoffice365";      DisplayName = "EPA - Office 365 Outlook" }
    shared_office365users           = @{ LogicalName = "${PublisherPrefix}_sharedoffice365users"; DisplayName = "EPA - Office 365 Users" }
    shared_commondataserviceforapps = @{ LogicalName = "${PublisherPrefix}_shareddataverse";      DisplayName = "EPA - Microsoft Dataverse" }
    shared_teams                    = @{ LogicalName = "${PublisherPrefix}_sharedteams";          DisplayName = "EPA - Microsoft Teams" }
    shared_webcontents              = @{ LogicalName = "${PublisherPrefix}_sharedhttpentra";      DisplayName = "EPA - HTTP with Microsoft Entra ID" }
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
# 1. Acquire Dataverse Token
# ─────────────────────────────────────
Write-Host "[1/5] Acquiring Dataverse token..." -ForegroundColor Cyan

try {
    $dvToken = az account get-access-token --resource "$OrgUrl" --query accessToken -o tsv 2>$null
    if (-not $dvToken) { throw "Empty token" }
    Write-Host "  ✓ Dataverse token acquired" -ForegroundColor Green
}
catch {
    throw "Cannot acquire Dataverse token. Run: az login --tenant <tenantId>"
}

$dvHeaders = @{
    "Authorization"  = "Bearer $dvToken"
    "Content-Type"   = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"  = "4.0"
}

$solutionHeaders = $dvHeaders.Clone()
$solutionHeaders["MSCRM.SolutionUniqueName"] = "EmailProductivityAgent"

# ─────────────────────────────────────
# 2. Create or Find Solution
# ─────────────────────────────────────
Write-Host "`n[2/5] Setting up solution..." -ForegroundColor Cyan

# Find publisher
$pubs = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/publishers?`$filter=customizationprefix eq '$PublisherPrefix'&`$select=publisherid,friendlyname" -Headers $dvHeaders
if ($pubs.value.Count -eq 0) { throw "No publisher found with prefix '$PublisherPrefix'" }
$publisherId = $pubs.value[0].publisherid
Write-Host "  Publisher: $($pubs.value[0].friendlyname)" -ForegroundColor Gray

# Check if solution exists
$solCheck = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/solutions?`$filter=uniquename eq 'EmailProductivityAgent'&`$select=solutionid" -Headers $dvHeaders
if ($solCheck.value.Count -gt 0) {
    $solutionId = $solCheck.value[0].solutionid
    Write-Host "  ✓ Solution exists: $solutionId" -ForegroundColor Green
}
else {
    $solBody = @{
        uniquename   = "EmailProductivityAgent"
        friendlyname = "Email Productivity Agent"
        description  = "Email Productivity Agent - flows, connection references, and components"
        version      = "1.0.0.0"
        "publisherid@odata.bind" = "/publishers($publisherId)"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/solutions" -Headers $dvHeaders -Method Post -Body $solBody | Out-Null
    $solCheck = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/solutions?`$filter=uniquename eq 'EmailProductivityAgent'&`$select=solutionid" -Headers $dvHeaders
    $solutionId = $solCheck.value[0].solutionid
    Write-Host "  ✓ Solution created: $solutionId" -ForegroundColor Green
}

# ─────────────────────────────────────
# 3. Create Connection References
# ─────────────────────────────────────
Write-Host "`n[3/5] Creating connection references..." -ForegroundColor Cyan

$flowsToProcess = if ($FlowsToCreate -eq "All") { $flowMap.Keys } else { @($FlowsToCreate) }

# Collect all needed connectors
$neededConnectors = @()
foreach ($flowKey in $flowsToProcess) { $neededConnectors += $flowMap[$flowKey].ConnRefs }
$neededConnectors = $neededConnectors | Sort-Object -Unique

foreach ($connKey in $neededConnectors) {
    $def = $connRefDefs[$connKey]
    $logicalName = $def.LogicalName

    # Check if already exists
    $existing = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/connectionreferences?`$filter=connectionreferencelogicalname eq '$logicalName'&`$select=connectionreferenceid" -Headers $dvHeaders
    if ($existing.value.Count -gt 0) {
        Write-Host "  ✓ $($def.DisplayName) (exists)" -ForegroundColor Green
        continue
    }

    $crBody = @{
        connectionreferencelogicalname = $logicalName
        connectionreferencedisplayname = $def.DisplayName
        connectorid = "/providers/Microsoft.PowerApps/apis/$connKey"
        statecode = 0; statuscode = 1
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/connectionreferences" -Headers $solutionHeaders -Method Post -Body $crBody | Out-Null
        Write-Host "  ✓ $($def.DisplayName)" -ForegroundColor Green
    }
    catch {
        $err = $_.ErrorDetails.Message
        Write-Host "  ⚠ $($def.DisplayName): $err" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────
# 4. Helper Functions
# ─────────────────────────────────────

# Recursively add authentication to all OpenApiConnection actions
function Add-AuthToActions([object]$Actions) {
    if (-not $Actions) { return }
    foreach ($n in @($Actions.PSObject.Properties.Name)) {
        $a = $Actions.$n
        if ($a.type -in @("OpenApiConnection", "OpenApiConnectionNotification") -and $a.inputs -and -not $a.inputs.authentication) {
            $a.inputs | Add-Member -NotePropertyName "authentication" -NotePropertyValue "@parameters('`$authentication')" -Force
        }
        if ($a.actions) { Add-AuthToActions $a.actions }
        if ($a.else -and $a.else.actions) { Add-AuthToActions $a.else.actions }
        if ($a.cases) { foreach ($cn in @($a.cases.PSObject.Properties.Name)) { if ($a.cases.$cn.actions) { Add-AuthToActions $a.cases.$cn.actions } } }
        if ($a.default -and $a.default.actions) { Add-AuthToActions $a.default.actions }
    }
}

function Prepare-FlowDefinition([object]$Definition) {
    # Add $connections and $authentication parameters
    if (-not $Definition.parameters) {
        $Definition | Add-Member -NotePropertyName "parameters" -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    if (-not $Definition.parameters.'$connections') {
        $Definition.parameters | Add-Member -NotePropertyName '$connections' -NotePropertyValue ([PSCustomObject]@{
            defaultValue = [PSCustomObject]@{}; type = "Object"
        }) -Force
    }
    if (-not $Definition.parameters.'$authentication') {
        $Definition.parameters | Add-Member -NotePropertyName '$authentication' -NotePropertyValue ([PSCustomObject]@{
            defaultValue = [PSCustomObject]@{}; type = "SecureObject"
        }) -Force
    }

    # Add auth to triggers
    foreach ($tName in $Definition.triggers.PSObject.Properties.Name) {
        $t = $Definition.triggers.$tName
        if ($t.type -in @("OpenApiConnectionNotification", "OpenApiConnection") -and $t.inputs -and -not $t.inputs.authentication) {
            $t.inputs | Add-Member -NotePropertyName "authentication" -NotePropertyValue "@parameters('`$authentication')" -Force
        }
        # Patch time zone
        if ($t.recurrence -and $t.recurrence.timeZone) {
            $t.recurrence.timeZone = $TimeZone
        }
    }

    # Add auth to all actions
    Add-AuthToActions $Definition.actions

    return $Definition
}

# ─────────────────────────────────────
# 5. Create Flows
# ─────────────────────────────────────
Write-Host "`n[4/5] Creating solution-aware flows..." -ForegroundColor Cyan

$createdFlows = @()
$failedFlows = @()

# Pre-load all existing EPA flows to avoid per-flow OData queries with special characters
$existingFlows = @{}
try {
    $epaFlows = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/workflows?`$filter=startswith(name,'EPA')&`$select=name,workflowid" -Headers $dvHeaders
    foreach ($ef in $epaFlows.value) { $existingFlows[$ef.name] = $ef.workflowid }
} catch {}

foreach ($flowKey in $flowsToProcess) {
    $flow = $flowMap[$flowKey]
    $filePath = Join-Path $srcDir $flow.File

    if (-not (Test-Path $filePath)) {
        Write-Host "  ✗ $($flow.DisplayName) — file not found: $filePath" -ForegroundColor Red
        $failedFlows += $flowKey
        continue
    }

    # Check if flow already exists
    if ($existingFlows.ContainsKey($flow.DisplayName)) {
        $existId = $existingFlows[$flow.DisplayName]
        Write-Host "  ⊘ $($flow.DisplayName) — already exists [$existId]" -ForegroundColor Yellow
        $createdFlows += [PSCustomObject]@{ Key = $flowKey; DisplayName = $flow.DisplayName; FlowId = $existId; Status = "Existing" }
        continue
    }

    Write-Host "  Creating: $($flow.DisplayName)..." -ForegroundColor White

    # Read, parse, and prepare definition
    $flowJson = Get-Content $filePath -Raw | ConvertFrom-Json
    $definition = Prepare-FlowDefinition $flowJson.definition

    # Build connection references for clientdata
    $connRefs = @{}
    foreach ($connKey in $flow.ConnRefs) {
        $connRefs[$connKey] = @{
            connectionReferenceLogicalName = $connRefDefs[$connKey].LogicalName
            id = "/providers/Microsoft.PowerApps/apis/$connKey"
        }
    }

    # Build clientdata with schemaVersion (required by Dataverse workflow API)
    $clientData = @{
        schemaVersion = "1.0.0.0"
        properties = @{
            definition = $definition
            connectionReferences = $connRefs
        }
    } | ConvertTo-Json -Depth 50 -Compress

    # Create workflow in solution
    $body = @{
        name         = $flow.DisplayName
        type         = 1
        category     = 5
        primaryentity = "none"
        statecode    = 0
        statuscode   = 1
        clientdata   = $clientData
    } | ConvertTo-Json -Depth 5

    try {
        Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/workflows" -Headers $solutionHeaders -Method Post -Body $body -ErrorAction Stop | Out-Null

        # Get the workflow ID
        $created = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/workflows?`$filter=name eq '$($flow.DisplayName)'&`$select=workflowid" -Headers $dvHeaders
        $flowId = $created.value[0].workflowid

        Write-Host "  ✓ $($flow.DisplayName)" -ForegroundColor Green
        Write-Host "    Flow ID: $flowId" -ForegroundColor Gray
        $createdFlows += [PSCustomObject]@{ Key = $flowKey; DisplayName = $flow.DisplayName; FlowId = $flowId; Status = "Created" }
    }
    catch {
        $errMsg = $_.ErrorDetails.Message
        Write-Host "  ✗ $($flow.DisplayName)" -ForegroundColor Red
        if ($errMsg) {
            try { Write-Host "    Error: $(($errMsg | ConvertFrom-Json).error.message)" -ForegroundColor Red }
            catch { Write-Host "    Error: $($errMsg.Substring(0, [Math]::Min($errMsg.Length, 400)))" -ForegroundColor Red }
        }
        else { Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red }
        $failedFlows += $flowKey
    }
}

# ─────────────────────────────────────
# 6. Summary
# ─────────────────────────────────────
Write-Host "`n[5/5] Deployment Summary" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────" -ForegroundColor Gray

if ($createdFlows.Count -gt 0) {
    Write-Host "  ✓ Ready: $($createdFlows.Count) flow(s)" -ForegroundColor Green
    foreach ($f in $createdFlows) {
        Write-Host "    • $($f.DisplayName) [$($f.Status)]" -ForegroundColor Green
        Write-Host "      ID: $($f.FlowId)" -ForegroundColor Gray
    }
}

if ($failedFlows.Count -gt 0) {
    Write-Host "  ✗ Failed: $($failedFlows.Count) flow(s)" -ForegroundColor Red
    foreach ($fk in $failedFlows) {
        Write-Host "    • $($flowMap[$fk].DisplayName)" -ForegroundColor Red
    }
}

Write-Host @"

  Next steps:
    1. Open Power Automate → Solutions → Email Productivity Agent
    2. For each flow, click Edit → configure connection references
       (map each EPA connection reference to an actual connection)
    3. Turn on each flow
    4. To associate with Copilot Studio: agent → Settings → Flows → Add

  Environment: $OrgUrl
  Solution: EmailProductivityAgent
  Deployed at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@ -ForegroundColor Gray

Write-Host "✅ Flow deployment complete.`n" -ForegroundColor Green
