<#
.SYNOPSIS
    Deploys Power Automate flows for the Enterprise Work Assistant.

.DESCRIPTION
    Creates all 20 flows (10 tool flows + 10 main flows) programmatically via the
    Flow Management API, then adds them to a Dataverse solution:

    Tool Flows (agent research/action tools):
      - EWA - SearchUserEmail          (tool-search-user-email.json)
      - EWA - SearchSentItems          (tool-search-sent-items.json)
      - EWA - SearchTeamsMessages      (tool-search-teams-messages.json)
      - EWA - SearchSharePoint         (tool-search-sharepoint.json)
      - EWA - SearchPlannerTasks       (tool-search-planner-tasks.json)
      - EWA - QueryCards               (tool-query-cards.json)
      - EWA - QuerySenderProfile       (tool-query-sender-profile.json)
      - EWA - UpdateCard               (tool-update-card.json)
      - EWA - CreateCard               (tool-create-card.json)
      - EWA - RefineDraft              (tool-refine-draft.json)

    Main Flows (triggers, orchestration, scheduled):
      - EWA - Flow 1: EMAIL Trigger
      - EWA - Flow 2: TEAMS_MESSAGE Trigger
      - EWA - Flow 3: CALENDAR_SCAN Trigger
      - EWA - Flow 4: Send Email
      - EWA - Flow 5: Card Outcome Tracker
      - EWA - Flow 6: Daily Briefing
      - EWA - Flow 7: Staleness Monitor
      - EWA - Flow 8: Command Execution
      - EWA - Flow 9: Sender Profile Analyzer
      - EWA - Flow 10: Reminder Firing

    The script:
      1. Creates (or reuses) an "EnterpriseWorkAssistant" Dataverse solution
      2. Creates connection references in the solution (for ALM export/import)
      3. Discovers connections in the target environment
      4. Creates flows via the Flow Management API with connection bindings
      5. Adds each flow to the solution

    IMPORTANT: Flows MUST be created via the Flow Management API (not Dataverse
    workflows entity) with connectionName bindings. The Dataverse API accepts any
    definition but connections never bind at the Flow runtime level, making flows
    impossible to activate without manual designer interaction.

.PARAMETER EnvironmentId
    Power Platform environment ID (GUID). Found in admin.powerplatform.microsoft.com.

.PARAMETER OrgUrl
    Dataverse organization URL (e.g., https://enterpriseworkassistant.crm.dynamics.com).
    If omitted, derived from the current az login context.

.PARAMETER SolutionName
    Dataverse solution unique name. Default: "EnterpriseWorkAssistant"

.PARAMETER PublisherPrefix
    Dataverse publisher prefix. Default: "cr"

.PARAMETER TimeZone
    Time zone for scheduled triggers. Default: "Eastern Standard Time"
    Common values: "Pacific Standard Time", "Central Standard Time", "UTC"

.PARAMETER FlowsToCreate
    Which flows to create. Default: "All"
    Valid values: "All", "ToolFlows" (10 agent tool flows), "MainFlows" (10 main flows)

.PARAMETER WhatIf
    Dry-run mode. Validates JSON definitions without creating flows.

.EXAMPLE
    .\deploy-agent-flows.ps1 `
        -EnvironmentId "fd0c6bc5-17f6-eb9d-9620-f7ea65f9c11d" `
        -OrgUrl "https://enterpriseworkassistant.crm.dynamics.com"

.EXAMPLE
    .\deploy-agent-flows.ps1 `
        -EnvironmentId "..." `
        -OrgUrl "https://..." `
        -FlowsToCreate "ToolFlows"
    # Deploy tool flows first, then use the printed GUIDs to update topic YAML flowId placeholders.

.EXAMPLE
    .\deploy-agent-flows.ps1 `
        -EnvironmentId "..." `
        -OrgUrl "https://..." `
        -WhatIf
    # Validate all JSON definitions without creating anything.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [string]$OrgUrl,

    [string]$SolutionName = "EnterpriseWorkAssistant",

    [string]$PublisherPrefix = "cr",

    [string]$TimeZone = "Eastern Standard Time",

    [ValidateSet("All", "ToolFlows", "MainFlows")]
    [string]$FlowsToCreate = "All",

    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# ─────────────────────────────────────
# Flow definition file map
# ─────────────────────────────────────
# Tool flows first (agent depends on these), then main flows.
$flowMap = [ordered]@{
    # ── Tool Flows ──
    ToolSearchUserEmail    = @{
        File        = "tool-search-user-email.json"
        DisplayName = "EWA - SearchUserEmail"
        ConnRefs    = @("shared_office365", "shared_commondataserviceforapps")
        Group       = "ToolFlows"
    }
    ToolSearchSentItems    = @{
        File        = "tool-search-sent-items.json"
        DisplayName = "EWA - SearchSentItems"
        ConnRefs    = @("shared_office365", "shared_commondataserviceforapps")
        Group       = "ToolFlows"
    }
    ToolSearchTeamsMessages = @{
        File        = "tool-search-teams-messages.json"
        DisplayName = "EWA - SearchTeamsMessages"
        ConnRefs    = @("shared_teams", "shared_commondataserviceforapps")
        Group       = "ToolFlows"
    }
    ToolSearchSharePoint   = @{
        File        = "tool-search-sharepoint.json"
        DisplayName = "EWA - SearchSharePoint"
        ConnRefs    = @("shared_webcontents", "shared_commondataserviceforapps")
        Group       = "ToolFlows"
    }
    ToolSearchPlannerTasks = @{
        File        = "tool-search-planner-tasks.json"
        DisplayName = "EWA - SearchPlannerTasks"
        ConnRefs    = @("shared_webcontents", "shared_commondataserviceforapps")
        Group       = "ToolFlows"
    }
    ToolQueryCards         = @{
        File        = "tool-query-cards.json"
        DisplayName = "EWA - QueryCards"
        ConnRefs    = @("shared_commondataserviceforapps")
        Group       = "ToolFlows"
    }
    ToolQuerySenderProfile = @{
        File        = "tool-query-sender-profile.json"
        DisplayName = "EWA - QuerySenderProfile"
        ConnRefs    = @("shared_office365users", "shared_commondataserviceforapps")
        Group       = "ToolFlows"
    }
    ToolUpdateCard         = @{
        File        = "tool-update-card.json"
        DisplayName = "EWA - UpdateCard"
        ConnRefs    = @("shared_commondataserviceforapps")
        Group       = "ToolFlows"
    }
    ToolCreateCard         = @{
        File        = "tool-create-card.json"
        DisplayName = "EWA - CreateCard"
        ConnRefs    = @("shared_commondataserviceforapps")
        Group       = "ToolFlows"
    }
    ToolRefineDraft        = @{
        File        = "tool-refine-draft.json"
        DisplayName = "EWA - RefineDraft"
        ConnRefs    = @("shared_microsoftcopilotstudio", "shared_commondataserviceforapps")
        Group       = "ToolFlows"
    }
    # ── Main Flows ──
    Flow1  = @{
        File        = "flow-1-email-trigger.json"
        DisplayName = "EWA - Flow 1: EMAIL Trigger"
        ConnRefs    = @("shared_office365", "shared_office365users", "shared_commondataserviceforapps", "shared_microsoftcopilotstudio")
        Group       = "MainFlows"
    }
    Flow2  = @{
        File        = "flow-2-teams-trigger.json"
        DisplayName = "EWA - Flow 2: TEAMS_MESSAGE Trigger"
        ConnRefs    = @("shared_teams", "shared_office365users", "shared_commondataserviceforapps", "shared_microsoftcopilotstudio")
        Group       = "MainFlows"
    }
    Flow3  = @{
        File        = "flow-3-calendar-trigger.json"
        DisplayName = "EWA - Flow 3: CALENDAR_SCAN Trigger"
        ConnRefs    = @("shared_office365", "shared_office365users", "shared_commondataserviceforapps", "shared_microsoftcopilotstudio")
        Group       = "MainFlows"
    }
    Flow4  = @{
        File        = "flow-4-send-email.json"
        DisplayName = "EWA - Flow 4: Send Email"
        ConnRefs    = @("shared_office365", "shared_commondataserviceforapps")
        Group       = "MainFlows"
    }
    Flow5  = @{
        File        = "flow-5-card-outcome-tracker.json"
        DisplayName = "EWA - Flow 5: Card Outcome Tracker"
        ConnRefs    = @("shared_commondataserviceforapps")
        Group       = "MainFlows"
    }
    Flow6  = @{
        File        = "flow-6-daily-briefing.json"
        DisplayName = "EWA - Flow 6: Daily Briefing"
        ConnRefs    = @("shared_commondataserviceforapps", "shared_teams", "shared_microsoftcopilotstudio")
        Group       = "MainFlows"
    }
    Flow7  = @{
        File        = "flow-7-staleness-monitor.json"
        DisplayName = "EWA - Flow 7: Staleness Monitor"
        ConnRefs    = @("shared_commondataserviceforapps")
        Group       = "MainFlows"
    }
    Flow8  = @{
        File        = "flow-8-command-execution.json"
        DisplayName = "EWA - Flow 8: Command Execution"
        ConnRefs    = @("shared_commondataserviceforapps", "shared_microsoftcopilotstudio")
        Group       = "MainFlows"
    }
    Flow9  = @{
        File        = "flow-9-sender-profile-analyzer.json"
        DisplayName = "EWA - Flow 9: Sender Profile Analyzer"
        ConnRefs    = @("shared_office365users", "shared_commondataserviceforapps", "shared_webcontents")
        Group       = "MainFlows"
    }
    Flow10 = @{
        File        = "flow-10-reminder-firing.json"
        DisplayName = "EWA - Flow 10: Reminder Firing"
        ConnRefs    = @("shared_commondataserviceforapps", "shared_teams")
        Group       = "MainFlows"
    }
}

# Connection reference definitions (for Dataverse solution layer)
$connRefDefs = @{
    shared_office365                = @{ LogicalName = "cr_sharedoffice365_ewa";      DisplayName = "EWA - Office 365 Outlook" }
    shared_office365users           = @{ LogicalName = "cr_sharedoffice365users_ewa"; DisplayName = "EWA - Office 365 Users" }
    shared_teams                    = @{ LogicalName = "cr_sharedteams_ewa";          DisplayName = "EWA - Microsoft Teams" }
    shared_commondataserviceforapps = @{ LogicalName = "cr_shareddataverse_ewa";      DisplayName = "EWA - Microsoft Dataverse" }
    shared_webcontents              = @{ LogicalName = "cr_sharedwebcontents_ewa";    DisplayName = "EWA - HTTP with Entra ID" }
    shared_microsoftcopilotstudio   = @{ LogicalName = "cr_sharedcopilotstudio_ewa";  DisplayName = "EWA - Microsoft Copilot Studio" }
}

# ─────────────────────────────────────
# 0. Prerequisite Checks
# ─────────────────────────────────────
Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Enterprise Work Assistant — Flow Deployment         ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "  ⚡ DRY-RUN MODE — validating JSON only, no flows will be created`n" -ForegroundColor Yellow
}

if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    throw "Azure CLI not found. Install: winget install Microsoft.AzureCLI"
}

$srcDir = Join-Path $PSScriptRoot "..\src"
if (-not (Test-Path $srcDir)) {
    throw "Source directory not found: $srcDir"
}

# Resolve OrgUrl from az CLI if not supplied
if (-not $OrgUrl) {
    Write-Host "  OrgUrl not provided — you must supply -OrgUrl for Dataverse operations." -ForegroundColor Yellow
    throw "OrgUrl is required. Example: -OrgUrl 'https://enterpriseworkassistant.crm.dynamics.com'"
}
$OrgUrl = $OrgUrl.TrimEnd('/')

# Determine which flows to process
$flowsToProcess = switch ($FlowsToCreate) {
    "All"       { $flowMap.Keys }
    "ToolFlows" { $flowMap.Keys | Where-Object { $flowMap[$_].Group -eq "ToolFlows" } }
    "MainFlows" { $flowMap.Keys | Where-Object { $flowMap[$_].Group -eq "MainFlows" } }
}
$totalFlowCount = @($flowsToProcess).Count

Write-Host "  Deploying: $FlowsToCreate ($totalFlowCount flows)" -ForegroundColor White
Write-Host "  Solution:  $SolutionName" -ForegroundColor White
Write-Host "  TimeZone:  $TimeZone`n" -ForegroundColor White

# ─────────────────────────────────────
# WhatIf: Validate JSON only
# ─────────────────────────────────────
if ($WhatIf) {
    Write-Host "[DRY-RUN] Validating flow JSON definitions..." -ForegroundColor Cyan
    $validCount = 0
    $invalidCount = 0
    $idx = 0

    foreach ($flowKey in $flowsToProcess) {
        $idx++
        $flow = $flowMap[$flowKey]
        $filePath = Join-Path $srcDir $flow.File
        $label = "[$idx/$totalFlowCount]"

        if (-not (Test-Path $filePath)) {
            Write-Host "  $label ✗ $($flow.DisplayName) — file not found: $($flow.File)" -ForegroundColor Red
            $invalidCount++
            continue
        }

        try {
            $json = Get-Content $filePath -Raw | ConvertFrom-Json -ErrorAction Stop
            if (-not $json.definition) {
                Write-Host "  $label ⚠ $($flow.DisplayName) — missing 'definition' property" -ForegroundColor Yellow
                $invalidCount++
            }
            elseif (-not $json.definition.triggers) {
                Write-Host "  $label ⚠ $($flow.DisplayName) — missing 'definition.triggers'" -ForegroundColor Yellow
                $invalidCount++
            }
            else {
                Write-Host "  $label ✓ $($flow.DisplayName)" -ForegroundColor Green
                $validCount++
            }
        }
        catch {
            Write-Host "  $label ✗ $($flow.DisplayName) — invalid JSON: $($_.Exception.Message)" -ForegroundColor Red
            $invalidCount++
        }
    }

    Write-Host "`n  Summary: $validCount valid, $invalidCount invalid out of $totalFlowCount definitions" -ForegroundColor $(if ($invalidCount -eq 0) { "Green" } else { "Yellow" })
    Write-Host "  Re-run without -WhatIf to deploy.`n" -ForegroundColor Gray
    return
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
$solutionHeaders["MSCRM.SolutionUniqueName"] = $SolutionName

$flowApiBase = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentId"

# ─────────────────────────────────────
# 2. Create or Find Solution
# ─────────────────────────────────────
Write-Host "`n[2/6] Setting up solution..." -ForegroundColor Cyan

$pubs = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/publishers?`$filter=customizationprefix eq '$PublisherPrefix'&`$select=publisherid,friendlyname" -Headers $dvHeaders
if ($pubs.value.Count -eq 0) { throw "No publisher found with prefix '$PublisherPrefix'" }
$publisherId = $pubs.value[0].publisherid
Write-Host "  Publisher: $($pubs.value[0].friendlyname)" -ForegroundColor Gray

$solCheck = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/solutions?`$filter=uniquename eq '$SolutionName'&`$select=solutionid" -Headers $dvHeaders
if ($solCheck.value.Count -gt 0) {
    $solutionId = $solCheck.value[0].solutionid
    Write-Host "  ✓ Solution exists: $solutionId" -ForegroundColor Green
}
else {
    $solBody = @{
        uniquename   = $SolutionName
        friendlyname = "Enterprise Work Assistant"
        description  = "Enterprise Work Assistant - flows, connection references, and components"
        version      = "1.0.0.0"
        "publisherid@odata.bind" = "/publishers($publisherId)"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/solutions" -Headers $dvHeaders -Method Post -Body $solBody | Out-Null
    $solCheck = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/solutions?`$filter=uniquename eq '$SolutionName'&`$select=solutionid" -Headers $dvHeaders
    $solutionId = $solCheck.value[0].solutionid
    Write-Host "  ✓ Solution created: $solutionId" -ForegroundColor Green
}

# ─────────────────────────────────────
# 3. Create Connection References & Discover Connections
# ─────────────────────────────────────
Write-Host "`n[3/6] Setting up connection references..." -ForegroundColor Cyan

# Dependency guard: warn if deploying main flows without tool flows
if ($FlowsToCreate -eq "MainFlows") {
    $toolFlows = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/workflows?`$filter=startswith(name,'EWA - Search') or startswith(name,'EWA - Query') or startswith(name,'EWA - Update') or startswith(name,'EWA - Create') or startswith(name,'EWA - Refine')&`$select=name,workflowid" -Headers $dvHeaders
    if ($toolFlows.value.Count -eq 0) {
        Write-Warning "No tool flows found in the environment. Main flows may reference tool flow GUIDs. Deploy ToolFlows first."
    }
    else {
        Write-Host "  Found $($toolFlows.value.Count) existing tool flow(s)" -ForegroundColor Gray
    }
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
$skippedFlows = @()

# Check existing flows
$existingFlows = @{}
try {
    $ewaFlows = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/workflows?`$filter=startswith(name,'EWA')&`$select=name,workflowid,statecode" -Headers $dvHeaders
    foreach ($ef in $ewaFlows.value) { $existingFlows[$ef.name] = @{ id = $ef.workflowid; state = $ef.statecode } }
} catch {}

$idx = 0
foreach ($flowKey in $flowsToProcess) {
    $idx++
    $flow = $flowMap[$flowKey]
    $filePath = Join-Path $srcDir $flow.File
    $label = "[$idx/$totalFlowCount]"

    if (-not (Test-Path $filePath)) {
        Write-Host "  $label ✗ $($flow.DisplayName) — file not found: $($flow.File)" -ForegroundColor Red
        $failedFlows += $flowKey
        continue
    }

    if ($existingFlows.ContainsKey($flow.DisplayName)) {
        $existInfo = $existingFlows[$flow.DisplayName]
        $state = if ($existInfo.state -eq 1) { "ON" } else { "Draft" }
        Write-Host "  $label ⊘ $($flow.DisplayName) — already exists ($state)" -ForegroundColor Yellow
        $createdFlows += [PSCustomObject]@{ Key = $flowKey; DisplayName = $flow.DisplayName; FlowId = $existInfo.id; Status = "Existing ($state)"; Group = $flow.Group }
        $skippedFlows += $flowKey
        continue
    }

    Write-Host "  $label Creating: $($flow.DisplayName)..." -ForegroundColor White

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

        Write-Host "  $label ✓ $($flow.DisplayName) — Created & Started" -ForegroundColor Green
        Write-Host "    Flow API ID: $flowApiId" -ForegroundColor Gray

        # Poll for Dataverse sync (can take 10-30s in fresh environments)
        $wfId = $null
        $syncAttempts = 0
        $syncMaxAttempts = 10
        do {
            Start-Sleep -Seconds 3
            $syncAttempts++
            $wf = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/workflows?`$filter=name eq '$($flow.DisplayName)'&`$select=workflowid" -Headers $dvHeaders
            if ($wf.value.Count -gt 0) {
                $wfId = $wf.value[0].workflowid
                break
            }
            Write-Host "    Waiting for Dataverse sync... ($syncAttempts/$syncMaxAttempts)" -ForegroundColor Gray
        } while ($syncAttempts -lt $syncMaxAttempts)

        if ($wfId) {
            Write-Host "    Dataverse ID: $wfId" -ForegroundColor Gray
            $createdFlows += [PSCustomObject]@{ Key = $flowKey; DisplayName = $flow.DisplayName; FlowId = $wfId; FlowApiId = $flowApiId; Status = "Created (ON)"; Group = $flow.Group }
        }
        else {
            $createdFlows += [PSCustomObject]@{ Key = $flowKey; DisplayName = $flow.DisplayName; FlowId = $null; FlowApiId = $flowApiId; Status = "Created (ON, no DV sync)"; Group = $flow.Group }
        }
    }
    catch {
        $errMsg = $_.ErrorDetails.Message
        $statusCode = $_.Exception.Response.StatusCode.value__

        # Handle 409 Conflict (flow already exists at the API layer)
        if ($statusCode -eq 409) {
            Write-Host "  $label ⊘ $($flow.DisplayName) — already exists (409 Conflict, skipped)" -ForegroundColor Yellow
            $skippedFlows += $flowKey
            continue
        }

        Write-Host "  $label ✗ $($flow.DisplayName)" -ForegroundColor Red
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
        SolutionUniqueName   = $SolutionName
        AddRequiredComponents = $false
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/AddSolutionComponent" -Headers $dvHeaders -Method Post -Body $addBody -ErrorAction Stop | Out-Null
        Write-Host "  ✓ $($cf.DisplayName)" -ForegroundColor Green
    }
    catch {
        $msg = $null
        if ($_.ErrorDetails.Message) {
            try { $msg = ($_.ErrorDetails.Message | ConvertFrom-Json).error.message } catch {}
        }
        if (-not $msg) { $msg = $_.Exception.Message }
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

if ($skippedFlows.Count -gt 0) {
    Write-Host "  ⊘ Skipped: $($skippedFlows.Count) flow(s) (already exist)" -ForegroundColor Yellow
}

if ($failedFlows.Count -gt 0) {
    Write-Host "  ✗ Failed: $($failedFlows.Count) flow(s)" -ForegroundColor Red
    foreach ($fk in $failedFlows) {
        Write-Host "    • $($flowMap[$fk].DisplayName)" -ForegroundColor Red
    }
}

# Print tool flow GUIDs for topic YAML flowId placeholders
$toolFlowResults = $createdFlows | Where-Object { $_.Group -eq "ToolFlows" -and $_.FlowId }
if ($toolFlowResults.Count -gt 0) {
    Write-Host "`n  ── Tool Flow GUIDs (for topic YAML flowId placeholders) ──" -ForegroundColor Cyan
    foreach ($tf in $toolFlowResults) {
        Write-Host "    $($tf.DisplayName): $($tf.FlowId)" -ForegroundColor White
    }
}

Write-Host @"

  Next steps:
    1. Verify flows are ON in Power Automate → Solutions → $SolutionName
    2. If you deployed ToolFlows separately, update topic YAML flowId placeholders
       with the GUIDs printed above, then deploy MainFlows
    3. Associate flows with Copilot Studio agent:
       Agent → Settings → Flows → Add
    4. Publish the agent
    5. Send a test email to trigger Flow 1 (EMAIL Trigger)

  Environment: $OrgUrl
  Environment ID: $EnvironmentId
  Solution: $SolutionName
  Deployed at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@ -ForegroundColor Gray

Write-Host "✅ Flow deployment complete.`n" -ForegroundColor Green
