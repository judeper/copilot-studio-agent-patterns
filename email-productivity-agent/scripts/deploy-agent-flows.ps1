<#
.SYNOPSIS
    Deploys Power Automate flows for the Email Productivity Agent.

.DESCRIPTION
    Creates all flows programmatically via the Flow Management API, then adds them
    to a Dataverse solution:
      - Flow 1: Sent Items Tracker (event-driven)
      - Flow 2: Response Detection & Nudge Delivery (daily 9 AM)
      - Flow 2b: Card Action Handler (event-driven)
      - Flow 3: Snooze Detection (every 15 min)
      - Flow 4: Auto-Unsnooze (event-driven)
      - Flow 5: Data Retention Cleanup (weekly)
      - Flow 6: Snooze Cleanup (weekly)

    The script:
      1. Creates (or reuses) an "EmailProductivityAgent" Dataverse solution
      2. Creates connection references in the solution (for ALM export/import)
      3. Discovers connections in the target environment
      4. Creates flows via the Flow Management API with connection bindings
      5. Adds each flow to the solution

    IMPORTANT: Flows MUST be created via the Flow Management API (not Dataverse
    workflows entity) with connectionName bindings. The Dataverse API accepts any
    definition but connections never bind at the Flow runtime level, making flows
    impossible to activate without manual designer interaction.

.PARAMETER OrgUrl
    Dataverse organization URL (e.g., https://emailproductivityagent.crm.dynamics.com)

.PARAMETER EnvironmentId
    Power Platform environment ID (GUID). Found in admin.powerplatform.microsoft.com.

.PARAMETER PublisherPrefix
    Dataverse publisher prefix. Default: "cr"

.PARAMETER TimeZone
    Time zone for scheduled triggers. Default: "Eastern Standard Time"
    Common values: "Pacific Standard Time", "Central Standard Time", "UTC"

.PARAMETER FlowsToCreate
    Which flows to create. Default: all.
    Valid values: "All", "Phase1" (Flow1,2,2b,5), "Phase2" (Flow3,4,6),
    or individual: "Flow1", "Flow2", "Flow2b", "Flow3", "Flow4", "Flow5", "Flow6"

.EXAMPLE
    .\deploy-agent-flows.ps1 `
        -OrgUrl "https://emailproductivityagent.crm.dynamics.com" `
        -EnvironmentId "fd0c6bc5-17f6-eb9d-9620-f7ea65f9c11d"

.EXAMPLE
    .\deploy-agent-flows.ps1 `
        -OrgUrl "https://..." -EnvironmentId "..." `
        -FlowsToCreate "Flow1" -TimeZone "Pacific Standard Time"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$OrgUrl,

    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [string]$PublisherPrefix = "cr",

    [string]$TimeZone = "Eastern Standard Time",

    [ValidateSet("All", "Phase1", "Phase2", "Flow1", "Flow2", "Flow2b", "Flow3", "Flow4", "Flow5", "Flow6")]
    [string]$FlowsToCreate = "All"
)

$ErrorActionPreference = "Stop"
$OrgUrl = $OrgUrl.TrimEnd('/')

# ─────────────────────────────────────
# Flow definition file map
# ─────────────────────────────────────
$flowMap = [ordered]@{
    Flow5  = @{
        File        = "flow-5-data-retention.json"
        DisplayName = "EPA - Flow 5: Data Retention Cleanup"
        ConnRefs    = @("shared_commondataserviceforapps")
    }
    Flow1  = @{
        File        = "flow-1-sent-items-tracker.json"
        DisplayName = "EPA - Flow 1: Sent Items Tracker"
        ConnRefs    = @("shared_office365", "shared_office365users", "shared_commondataserviceforapps")
    }
    Flow2  = @{
        File        = "flow-2-response-detection.json"
        DisplayName = "EPA - Flow 2: Response Detection"
        ConnRefs    = @("shared_office365users", "shared_commondataserviceforapps", "shared_webcontents", "shared_teams")
    }
    Flow2b = @{
        File        = "flow-2b-card-action-handler.json"
        DisplayName = "EPA - Flow 2b: Card Action Handler"
        ConnRefs    = @("shared_teams", "shared_commondataserviceforapps")
    }
    Flow3  = @{
        File        = "flow-3-snooze-detection.json"
        DisplayName = "EPA - Flow 3: Snooze Detection"
        ConnRefs    = @("shared_office365users", "shared_commondataserviceforapps", "shared_webcontents")
    }
    Flow4  = @{
        File        = "flow-4-auto-unsnooze.json"
        DisplayName = "EPA - Flow 4: Auto-Unsnooze"
        ConnRefs    = @("shared_office365", "shared_commondataserviceforapps", "shared_webcontents", "shared_teams")
    }
    Flow6  = @{
        File        = "flow-6-snooze-cleanup.json"
        DisplayName = "EPA - Flow 6: Snooze Cleanup"
        ConnRefs    = @("shared_commondataserviceforapps")
    }
}

# Connection reference definitions (for Dataverse solution layer)
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
# 1. Acquire Tokens
# ─────────────────────────────────────
Write-Host "[1/6] Acquiring tokens..." -ForegroundColor Cyan

try {
    $dvToken = az account get-access-token --resource "$OrgUrl" --query accessToken -o tsv 2>$null
    if (-not $dvToken) { throw "Empty token" }
    Write-Host "  ✓ Dataverse token acquired" -ForegroundColor Green
}
catch {
    throw "Cannot acquire Dataverse token. Run: az login --tenant <tenantId>"
}

try {
    $flowToken = az account get-access-token --resource "https://service.flow.microsoft.com/" --query accessToken -o tsv 2>$null
    if (-not $flowToken) { throw "Empty token" }
    Write-Host "  ✓ Flow Management API token acquired" -ForegroundColor Green
}
catch {
    throw "Cannot acquire Flow API token. Ensure az login succeeded."
}

try {
    $paToken = az account get-access-token --resource "https://service.powerapps.com/" --query accessToken -o tsv 2>$null
    if (-not $paToken) { throw "Empty token" }
    Write-Host "  ✓ PowerApps API token acquired" -ForegroundColor Green
}
catch {
    throw "Cannot acquire PowerApps token. Ensure az login succeeded."
}

$dvHeaders = @{
    "Authorization"    = "Bearer $dvToken"
    "Content-Type"     = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
}
$flowHeaders = @{
    "Authorization" = "Bearer $flowToken"
    "Content-Type"  = "application/json"
}
$paHeaders = @{ "Authorization" = "Bearer $paToken" }

$solutionHeaders = $dvHeaders.Clone()
$solutionHeaders["MSCRM.SolutionUniqueName"] = "EmailProductivityAgent"

$flowApiBase = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentId"

# ─────────────────────────────────────
# 2. Create or Find Solution
# ─────────────────────────────────────
Write-Host "`n[2/6] Setting up solution..." -ForegroundColor Cyan

$pubs = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/publishers?`$filter=customizationprefix eq '$PublisherPrefix'&`$select=publisherid,friendlyname" -Headers $dvHeaders
if ($pubs.value.Count -eq 0) { throw "No publisher found with prefix '$PublisherPrefix'" }
$publisherId = $pubs.value[0].publisherid
Write-Host "  Publisher: $($pubs.value[0].friendlyname)" -ForegroundColor Gray

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
# 3. Create Connection References & Discover Connections
# ─────────────────────────────────────
Write-Host "`n[3/6] Setting up connection references..." -ForegroundColor Cyan

$flowsToProcess = switch ($FlowsToCreate) {
    "All"    { $flowMap.Keys }
    "Phase1" { @("Flow5", "Flow1", "Flow2", "Flow2b") }
    "Phase2" { @("Flow6", "Flow3", "Flow4") }
    default  { @($FlowsToCreate) }
}

$neededConnectors = @()
foreach ($flowKey in $flowsToProcess) { $neededConnectors += $flowMap[$flowKey].ConnRefs }
$neededConnectors = $neededConnectors | Sort-Object -Unique

foreach ($connKey in $neededConnectors) {
    $def = $connRefDefs[$connKey]
    $logicalName = $def.LogicalName

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
        Write-Host "  ⚠ $($def.DisplayName): $($_.ErrorDetails.Message)" -ForegroundColor Yellow
    }
}

# Discover connections in the environment
Write-Host "`n  Discovering connections in environment..." -ForegroundColor White
$connUrl = "https://api.powerapps.com/providers/Microsoft.PowerApps/connections?api-version=2016-11-01&`$filter=environment eq '$EnvironmentId'"
$connections = Invoke-RestMethod -Uri $connUrl -Headers $paHeaders

# Build connector → connectionName map (first Connected connection wins)
$connNameMap = @{}
foreach ($conn in $connections.value) {
    $apiName = $conn.properties.apiId -replace '.*/apis/', ''
    $status = ($conn.properties.statuses | Select-Object -First 1).status
    if ($status -eq "Connected" -and -not $connNameMap.ContainsKey($apiName)) {
        $connNameMap[$apiName] = $conn.name
    }
}

$missingConns = @()
foreach ($connKey in $neededConnectors) {
    if ($connNameMap.ContainsKey($connKey)) {
        Write-Host "  ✓ Connection: $connKey → $($connNameMap[$connKey])" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ Connection: $connKey — NOT FOUND" -ForegroundColor Red
        $missingConns += $connKey
    }
}

if ($missingConns.Count -gt 0) {
    Write-Host "`n  ⚠ Missing connections. Create them in Power Automate before running this script:" -ForegroundColor Yellow
    foreach ($mc in $missingConns) { Write-Host "    - $($connRefDefs[$mc].DisplayName) ($mc)" -ForegroundColor Yellow }
    throw "Cannot proceed without all required connections."
}

# ─────────────────────────────────────
# 4. Helper Functions
# ─────────────────────────────────────

function Prepare-FlowDefinition([object]$Definition) {
    # Add $connections and $authentication parameters (required by Flow Management API)
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

    # Patch time zone on recurrence triggers
    foreach ($tName in $Definition.triggers.PSObject.Properties.Name) {
        $t = $Definition.triggers.$tName
        if ($t.recurrence -and $t.recurrence.timeZone) {
            $t.recurrence.timeZone = $TimeZone
        }
    }

    # NOTE: Do NOT add authentication to individual actions — Flow Management API
    # flows handle auth via connectionName bindings, not per-action auth tokens.
    # Adding authentication to actions causes WorkflowRunActionInputsInvalidProperty.

    return $Definition
}

# ─────────────────────────────────────
# 5. Create Flows via Flow Management API
# ─────────────────────────────────────
Write-Host "`n[4/6] Creating flows via Flow Management API..." -ForegroundColor Cyan

$createdFlows = @()
$failedFlows = @()

# Check existing flows
$existingFlows = @{}
try {
    $epaFlows = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/workflows?`$filter=startswith(name,'EPA')&`$select=name,workflowid,statecode" -Headers $dvHeaders
    foreach ($ef in $epaFlows.value) { $existingFlows[$ef.name] = @{ id = $ef.workflowid; state = $ef.statecode } }
} catch {}

foreach ($flowKey in $flowsToProcess) {
    $flow = $flowMap[$flowKey]
    $filePath = Join-Path $srcDir $flow.File

    if (-not (Test-Path $filePath)) {
        Write-Host "  ✗ $($flow.DisplayName) — file not found: $filePath" -ForegroundColor Red
        $failedFlows += $flowKey
        continue
    }

    if ($existingFlows.ContainsKey($flow.DisplayName)) {
        $existInfo = $existingFlows[$flow.DisplayName]
        $state = if ($existInfo.state -eq 1) { "ON" } else { "Draft" }
        Write-Host "  ⊘ $($flow.DisplayName) — already exists ($state)" -ForegroundColor Yellow
        $createdFlows += [PSCustomObject]@{ Key = $flowKey; DisplayName = $flow.DisplayName; FlowId = $existInfo.id; Status = "Existing ($state)" }
        continue
    }

    Write-Host "  Creating: $($flow.DisplayName)..." -ForegroundColor White

    $flowJson = Get-Content $filePath -Raw | ConvertFrom-Json
    $definition = Prepare-FlowDefinition $flowJson.definition

    # Build connection references with connectionName for proper runtime binding
    $connRefs = @{}
    foreach ($connKey in $flow.ConnRefs) {
        $connRefs[$connKey] = @{
            connectionName = $connNameMap[$connKey]
            id = "/providers/Microsoft.PowerApps/apis/$connKey"
        }
    }

    # Create via Flow Management API with state=Started for immediate activation.
    # state=Started bypasses the "unpublished solution flow" issue that blocks
    # post-creation activation via the /start endpoint.
    $createBody = @{
        properties = @{
            displayName          = $flow.DisplayName
            definition           = $definition
            state                = "Started"
            connectionReferences = $connRefs
        }
    } | ConvertTo-Json -Depth 50 -Compress

    try {
        $result = Invoke-RestMethod -Uri "$flowApiBase/flows?api-version=2016-11-01" `
            -Headers $flowHeaders -Method Post -Body $createBody -ErrorAction Stop
        $flowApiId = $result.name

        Write-Host "  ✓ $($flow.DisplayName) — Created & Started" -ForegroundColor Green
        Write-Host "    Flow API ID: $flowApiId" -ForegroundColor Gray

        # Wait for Dataverse to sync, then find the workflow ID
        Start-Sleep -Seconds 3
        $wf = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/workflows?`$filter=name eq '$($flow.DisplayName)'&`$select=workflowid" -Headers $dvHeaders
        if ($wf.value.Count -gt 0) {
            $wfId = $wf.value[0].workflowid
            Write-Host "    Dataverse ID: $wfId" -ForegroundColor Gray
            $createdFlows += [PSCustomObject]@{ Key = $flowKey; DisplayName = $flow.DisplayName; FlowId = $wfId; FlowApiId = $flowApiId; Status = "Created (ON)" }
        }
        else {
            $createdFlows += [PSCustomObject]@{ Key = $flowKey; DisplayName = $flow.DisplayName; FlowId = $null; FlowApiId = $flowApiId; Status = "Created (ON, no DV sync)" }
        }
    }
    catch {
        $errMsg = $_.ErrorDetails.Message
        Write-Host "  ✗ $($flow.DisplayName)" -ForegroundColor Red
        if ($errMsg) {
            $decoded = $errMsg -replace '\\u0022','"' -replace '\\u0027',"'"
            if ($decoded -match "Flow save failed with code '([^']+)' and message '([^']*)'") {
                Write-Host "    Code: $($matches[1])" -ForegroundColor Red
                Write-Host "    Message: $($matches[2])" -ForegroundColor Red
            }
            else {
                try { Write-Host "    Error: $(($errMsg | ConvertFrom-Json).error.message)" -ForegroundColor Red }
                catch { Write-Host "    Error: $($errMsg.Substring(0, [Math]::Min($errMsg.Length, 400)))" -ForegroundColor Red }
            }
        }
        else { Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red }
        $failedFlows += $flowKey
    }
}

# ─────────────────────────────────────
# 6. Add Flows to Solution
# ─────────────────────────────────────
Write-Host "`n[5/6] Adding flows to solution..." -ForegroundColor Cyan

foreach ($cf in $createdFlows) {
    $wfId = $cf.FlowId
    if (-not $wfId) {
        # Retry finding the workflow in Dataverse
        Start-Sleep -Seconds 2
        $wf = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/workflows?`$filter=name eq '$($cf.DisplayName)'&`$select=workflowid" -Headers $dvHeaders
        if ($wf.value.Count -gt 0) { $wfId = $wf.value[0].workflowid }
    }
    if (-not $wfId) {
        Write-Host "  ⚠ $($cf.DisplayName) — cannot find in Dataverse" -ForegroundColor Yellow
        continue
    }

    $addBody = @{
        ComponentId          = $wfId
        ComponentType        = 29
        SolutionUniqueName   = "EmailProductivityAgent"
        AddRequiredComponents = $false
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/AddSolutionComponent" -Headers $dvHeaders -Method Post -Body $addBody -ErrorAction Stop | Out-Null
        Write-Host "  ✓ $($cf.DisplayName)" -ForegroundColor Green
    }
    catch {
        $msg = ($_.ErrorDetails.Message | ConvertFrom-Json).error.message
        if ($msg -match "already exists") {
            Write-Host "  ✓ $($cf.DisplayName) (already in solution)" -ForegroundColor Green
        }
        else {
            Write-Host "  ⚠ $($cf.DisplayName): $($msg.Substring(0, [Math]::Min($msg.Length, 200)))" -ForegroundColor Yellow
        }
    }
}

# ─────────────────────────────────────
# 7. Summary
# ─────────────────────────────────────
Write-Host "`n[6/6] Deployment Summary" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────────" -ForegroundColor Gray

if ($createdFlows.Count -gt 0) {
    Write-Host "  ✓ Ready: $($createdFlows.Count) flow(s)" -ForegroundColor Green
    foreach ($f in $createdFlows) {
        Write-Host "    • $($f.DisplayName) [$($f.Status)]" -ForegroundColor Green
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
    1. Verify flows are ON in Power Automate → Solutions → EmailProductivityAgent
    2. Send a test email to trigger Flow 1 (Sent Items Tracker)
    3. Associate flows with Copilot Studio agent:
       Agent → Settings → Flows → Add
    4. Publish the agent

  Environment: $OrgUrl
  Environment ID: $EnvironmentId
  Solution: EmailProductivityAgent
  Deployed at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@ -ForegroundColor Gray

Write-Host "✅ Flow deployment complete.`n" -ForegroundColor Green
