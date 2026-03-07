<#
.SYNOPSIS
    Verifies whether an Email Productivity Agent environment is ready for manual testing.

.DESCRIPTION
    Checks the target environment for the assets required to manually test both Email
    Productivity Agent feature areas:
      - Follow-Up Nudges
      - Snooze Auto-Removal

    The script validates:
      - Dataverse tables and alternate keys
      - Email Productivity Agent solution
      - EPA security role and pilot-user assignment
      - Seeded NudgeConfiguration row for the pilot user
      - Connection references in the solution
      - Environment-scoped Power Automate connections
      - Copilot Studio agent
      - Settings Canvas App
      - Deployed EPA flows and activation state

    The script exits with code 0 only when every required prerequisite is present.
    If anything is missing, it prints a blocking summary and exits with code 1.

.PARAMETER OrgUrl
    Dataverse organization URL (for example: https://epatest.crm.dynamics.com)

.PARAMETER EnvironmentId
    Power Platform environment ID (GUID)

.PARAMETER PilotUserEmail
    Email address of the pilot user who will manually test the solution. If omitted,
    the script uses the currently signed-in Azure CLI account.

.PARAMETER PublisherPrefix
    Dataverse publisher prefix. Default: cr

.EXAMPLE
    .\check-test-readiness.ps1 `
        -OrgUrl "https://epatest.crm.dynamics.com" `
        -EnvironmentId "00000000-0000-0000-0000-000000000000" `
        -PilotUserEmail "admin@example.com"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$OrgUrl,

    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [string]$PilotUserEmail,

    [string]$PublisherPrefix = "cr"
)

$ErrorActionPreference = "Stop"
$OrgUrl = $OrgUrl.TrimEnd('/')

$expectedTables = @(
    @{
        LogicalName = "${PublisherPrefix}_followuptracking"
        DisplayName = "FollowUpTracking"
        KeySchemaName = "${PublisherPrefix}_followup_message_recipient_key"
    },
    @{
        LogicalName = "${PublisherPrefix}_nudgeconfiguration"
        DisplayName = "NudgeConfiguration"
        KeySchemaName = "${PublisherPrefix}_nudgeconfig_owner_key"
    },
    @{
        LogicalName = "${PublisherPrefix}_snoozedconversation"
        DisplayName = "SnoozedConversation"
        KeySchemaName = "${PublisherPrefix}_snoozed_conversation_owner_key"
    }
)

$expectedConnectionReferences = [ordered]@{
    shared_office365                = @{ LogicalName = "${PublisherPrefix}_sharedoffice365";      DisplayName = "EPA - Office 365 Outlook" }
    shared_office365users           = @{ LogicalName = "${PublisherPrefix}_sharedoffice365users"; DisplayName = "EPA - Office 365 Users" }
    shared_commondataserviceforapps = @{ LogicalName = "${PublisherPrefix}_shareddataverse";      DisplayName = "EPA - Microsoft Dataverse" }
    shared_teams                    = @{ LogicalName = "${PublisherPrefix}_sharedteams";          DisplayName = "EPA - Microsoft Teams" }
    shared_webcontents              = @{ LogicalName = "${PublisherPrefix}_sharedhttpentra";      DisplayName = "EPA - HTTP with Microsoft Entra ID" }
    shared_microsoftcopilotstudio   = @{ LogicalName = "${PublisherPrefix}_sharedcopilotstudio"; DisplayName = "EPA - Microsoft Copilot Studio" }
}

$expectedFlows = @(
    "EPA - Flow 1: Sent Items Tracker",
    "EPA - Flow 2: Response Detection",
    "EPA - Flow 2b: Card Action Handler",
    "EPA - Flow 3: Snooze Detection",
    "EPA - Flow 4: Auto-Unsnooze",
    "EPA - Flow 5: Data Retention Cleanup",
    "EPA - Flow 6: Snooze Cleanup",
    "EPA - Flow 7: Settings Card",
    "EPA - Flow 7b: Settings Card Handler"
)

$results = [System.Collections.Generic.List[object]]::new()

function Write-Banner {
    Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Email Productivity Agent — Test Readiness Check    ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
}

function Add-CheckResult {
    param(
        [string]$Category,
        [ValidateSet("PASS", "FAIL")]
        [string]$Status,
        [string]$Details
    )

    $results.Add([PSCustomObject]@{
        Category = $Category
        Status = $Status
        Details = $Details
    }) | Out-Null

    $symbol = if ($Status -eq "PASS") { "✓" } else { "✗" }
    $color = if ($Status -eq "PASS") { "Green" } else { "Red" }
    Write-Host ("  {0} [{1}] {2}" -f $symbol, $Category, $Details) -ForegroundColor $color
}

function Escape-ODataString {
    param([string]$Value)
    return $Value.Replace("'", "''")
}

function Get-AzureAccessToken {
    param(
        [string]$Resource,
        [string]$Label
    )

    try {
        $token = az account get-access-token --resource $Resource --query accessToken -o tsv 2>$null
        if (-not $token) {
            throw "Empty token"
        }

        return $token
    }
    catch {
        throw "Cannot acquire $Label token. Run: az login --tenant <tenantId>"
    }
}

function Invoke-PacCommand {
    param([string[]]$Arguments)

    $output = & pac @Arguments 2>&1 | Out-String
    $exitCode = $LASTEXITCODE

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output = $output.Trim()
    }
}

function Get-EntityMetadata {
    param([string]$LogicalName)

    $escapedLogicalName = Escape-ODataString $LogicalName
    $uri = "$OrgUrl/api/data/v9.2/EntityDefinitions(LogicalName='$escapedLogicalName')?`$select=LogicalName,MetadataId"

    try {
        return Invoke-RestMethod -Uri $uri -Headers $dvHeaders -Method Get
    }
    catch {
        $response = $_.Exception.Response
        if ($response -and [int]$response.StatusCode -eq 404) {
            return $null
        }

        throw
    }
}

function Get-EntityKeys {
    param([string]$LogicalName)

    $escapedLogicalName = Escape-ODataString $LogicalName
    $uri = "$OrgUrl/api/data/v9.2/EntityDefinitions(LogicalName='$escapedLogicalName')?`$select=LogicalName&`$expand=Keys(`$select=SchemaName,EntityKeyIndexStatus)"
    $result = Invoke-RestMethod -Uri $uri -Headers $dvHeaders -Method Get

    return @($result.Keys)
}

Write-Banner

if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    throw "Azure CLI not found. Install: winget install Microsoft.AzureCLI"
}

if (-not (Get-Command "pac" -ErrorAction SilentlyContinue)) {
    throw "PAC CLI not found. Install: dotnet tool install --global Microsoft.PowerApps.CLI.Tool"
}

if (-not $PilotUserEmail) {
    $PilotUserEmail = az account show --query user.name -o tsv 2>$null
    if (-not $PilotUserEmail) {
        throw "Cannot determine pilot user email from Azure CLI. Pass -PilotUserEmail explicitly."
    }
}

Write-Host "Target environment: $EnvironmentId" -ForegroundColor Gray
Write-Host "Target org URL:    $OrgUrl" -ForegroundColor Gray
Write-Host "Pilot user:        $PilotUserEmail`n" -ForegroundColor Gray

Write-Host "[1/7] Acquiring access tokens..." -ForegroundColor Cyan
$dvToken = Get-AzureAccessToken -Resource $OrgUrl -Label "Dataverse"
$paToken = Get-AzureAccessToken -Resource "https://service.powerapps.com/" -Label "Power Apps"

$dvHeaders = @{
    "Authorization" = "Bearer $dvToken"
    "Content-Type" = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version" = "4.0"
}
$paHeaders = @{
    "Authorization" = "Bearer $paToken"
}

Write-Host "  ✓ Tokens acquired`n" -ForegroundColor Green

Write-Host "[2/7] Checking Dataverse solution, tables, and alternate keys..." -ForegroundColor Cyan

try {
    $solutionCheck = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/solutions?`$filter=uniquename eq 'EmailProductivityAgent'&`$select=solutionid" -Headers $dvHeaders -Method Get
    if ($solutionCheck.value.Count -gt 0) {
        Add-CheckResult -Category "Solution" -Status "PASS" -Details "EmailProductivityAgent exists ($($solutionCheck.value[0].solutionid))"
    }
    else {
        Add-CheckResult -Category "Solution" -Status "FAIL" -Details "EmailProductivityAgent solution is missing"
    }
}
catch {
    Add-CheckResult -Category "Solution" -Status "FAIL" -Details "Could not query solution: $($_.Exception.Message)"
}

foreach ($table in $expectedTables) {
    try {
        $metadata = Get-EntityMetadata -LogicalName $table.LogicalName
        if (-not $metadata) {
            Add-CheckResult -Category "Table" -Status "FAIL" -Details "$($table.DisplayName) ($($table.LogicalName)) is missing"
            continue
        }

        Add-CheckResult -Category "Table" -Status "PASS" -Details "$($table.DisplayName) exists"

        $keys = Get-EntityKeys -LogicalName $table.LogicalName
        $key = $keys | Where-Object { $_.SchemaName -eq $table.KeySchemaName } | Select-Object -First 1

        if (-not $key) {
            Add-CheckResult -Category "Alternate Key" -Status "FAIL" -Details "$($table.KeySchemaName) is missing on $($table.DisplayName)"
            continue
        }

        if ($key.EntityKeyIndexStatus -eq "Active") {
            Add-CheckResult -Category "Alternate Key" -Status "PASS" -Details "$($table.KeySchemaName) is active"
        }
        else {
            Add-CheckResult -Category "Alternate Key" -Status "FAIL" -Details "$($table.KeySchemaName) exists but is not active (status: $($key.EntityKeyIndexStatus))"
        }
    }
    catch {
        Add-CheckResult -Category "Table" -Status "FAIL" -Details "Could not inspect $($table.DisplayName): $($_.Exception.Message)"
    }
}

Write-Host "`n[3/7] Checking EPA role assignment and pilot-user configuration..." -ForegroundColor Cyan

$escapedPilotEmail = Escape-ODataString $PilotUserEmail
$pilotUser = $null
$epaRole = $null

try {
    $userCheck = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/systemusers?`$filter=internalemailaddress eq '$escapedPilotEmail'&`$select=systemuserid,fullname,internalemailaddress" -Headers $dvHeaders -Method Get
    if ($userCheck.value.Count -gt 0) {
        $pilotUser = $userCheck.value[0]
        Add-CheckResult -Category "Pilot User" -Status "PASS" -Details "$($pilotUser.fullname) found ($($pilotUser.systemuserid))"
    }
    else {
        Add-CheckResult -Category "Pilot User" -Status "FAIL" -Details "No Dataverse user found for $PilotUserEmail"
    }
}
catch {
    Add-CheckResult -Category "Pilot User" -Status "FAIL" -Details "Could not query pilot user: $($_.Exception.Message)"
}

try {
    $roleCheck = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/roles?`$filter=name eq 'Email Productivity Agent User'&`$select=roleid,name" -Headers $dvHeaders -Method Get
    if ($roleCheck.value.Count -gt 0) {
        $epaRole = $roleCheck.value[0]
        Add-CheckResult -Category "Security Role" -Status "PASS" -Details "Email Productivity Agent User exists ($($epaRole.roleid))"
    }
    else {
        Add-CheckResult -Category "Security Role" -Status "FAIL" -Details "Email Productivity Agent User role is missing"
    }
}
catch {
    Add-CheckResult -Category "Security Role" -Status "FAIL" -Details "Could not query security role: $($_.Exception.Message)"
}

if ($pilotUser -and $epaRole) {
    try {
        $userWithRoles = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/systemusers($($pilotUser.systemuserid))?`$select=systemuserid&`$expand=systemuserroles_association(`$select=roleid,name)" -Headers $dvHeaders -Method Get
        $assignedRole = @($userWithRoles.systemuserroles_association) | Where-Object { $_.roleid -eq $epaRole.roleid } | Select-Object -First 1

        if ($assignedRole) {
            Add-CheckResult -Category "Role Assignment" -Status "PASS" -Details "Pilot user has Email Productivity Agent User role"
        }
        else {
            Add-CheckResult -Category "Role Assignment" -Status "FAIL" -Details "Pilot user is missing the Email Productivity Agent User role"
        }
    }
    catch {
        Add-CheckResult -Category "Role Assignment" -Status "FAIL" -Details "Could not verify role assignment: $($_.Exception.Message)"
    }
}
else {
    Add-CheckResult -Category "Role Assignment" -Status "FAIL" -Details "Skipped because the pilot user or EPA role could not be resolved"
}

if ($pilotUser) {
    try {
        $configCheck = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/${PublisherPrefix}_nudgeconfigurations?`$filter=${PublisherPrefix}_owneruserid eq '$($pilotUser.systemuserid)'&`$select=${PublisherPrefix}_nudgeconfigurationid,${PublisherPrefix}_internaldays,${PublisherPrefix}_externaldays,${PublisherPrefix}_prioritydays,${PublisherPrefix}_generaldays" -Headers $dvHeaders -Method Get
        if ($configCheck.value.Count -gt 0) {
            $config = $configCheck.value[0]
            $configSummary = "Internal=$($config."${PublisherPrefix}_internaldays"), External=$($config."${PublisherPrefix}_externaldays"), Priority=$($config."${PublisherPrefix}_prioritydays"), General=$($config."${PublisherPrefix}_generaldays")"
            Add-CheckResult -Category "Pilot Config" -Status "PASS" -Details "Default NudgeConfiguration exists ($configSummary)"
        }
        else {
            Add-CheckResult -Category "Pilot Config" -Status "FAIL" -Details "No NudgeConfiguration row exists for the pilot user"
        }
    }
    catch {
        Add-CheckResult -Category "Pilot Config" -Status "FAIL" -Details "Could not query NudgeConfiguration: $($_.Exception.Message)"
    }
}
else {
    Add-CheckResult -Category "Pilot Config" -Status "FAIL" -Details "Skipped because the pilot user could not be resolved"
}

Write-Host "`n[4/7] Checking connection references and Power Automate connections..." -ForegroundColor Cyan

foreach ($connKey in $expectedConnectionReferences.Keys) {
    $connDef = $expectedConnectionReferences[$connKey]
    try {
        $refCheck = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/connectionreferences?`$filter=connectionreferencelogicalname eq '$($connDef.LogicalName)'&`$select=connectionreferenceid" -Headers $dvHeaders -Method Get
        if ($refCheck.value.Count -gt 0) {
            Add-CheckResult -Category "Connection Reference" -Status "PASS" -Details "$($connDef.DisplayName) exists"
        }
        else {
            Add-CheckResult -Category "Connection Reference" -Status "FAIL" -Details "$($connDef.DisplayName) connection reference is missing"
        }
    }
    catch {
        Add-CheckResult -Category "Connection Reference" -Status "FAIL" -Details "Could not query $($connDef.DisplayName): $($_.Exception.Message)"
    }
}

try {
    $connUrl = "https://api.powerapps.com/providers/Microsoft.PowerApps/connections?api-version=2016-11-01&`$filter=environment eq '$EnvironmentId'"
    $connections = Invoke-RestMethod -Uri $connUrl -Headers $paHeaders -Method Get

    $connectionsByApi = @{}
    foreach ($connection in @($connections.value)) {
        $apiName = $connection.properties.apiId -replace '.*/apis/', ''
        $status = ($connection.properties.statuses | Select-Object -First 1).status
        if ([string]::IsNullOrWhiteSpace($status)) {
            $status = "Unknown"
        }

        $connectionName = if ([string]::IsNullOrWhiteSpace($connection.name)) {
            "(unnamed)"
        }
        else {
            $connection.name
        }

        if (-not $connectionsByApi.ContainsKey($apiName)) {
            $connectionsByApi[$apiName] = @()
        }

        $connectionsByApi[$apiName] += [PSCustomObject]@{
            ConnectionName = $connectionName
            DisplayName = $connection.properties.displayName
            Status = $status
        }
    }

    foreach ($connKey in $expectedConnectionReferences.Keys) {
        $connDef = $expectedConnectionReferences[$connKey]
        $matchingConnections = @($connectionsByApi[$connKey]) | Where-Object { $null -ne $_ }

        if ($matchingConnections.Count -eq 0) {
            Add-CheckResult -Category "Connection" -Status "FAIL" -Details "$($connDef.DisplayName) connection is missing"
            continue
        }

        $connected = $matchingConnections | Where-Object { $_.Status -eq "Connected" } | Select-Object -First 1
        if ($connected) {
            Add-CheckResult -Category "Connection" -Status "PASS" -Details "$($connDef.DisplayName) is connected ($($connected.ConnectionName))"
        }
        else {
            $statusSummary = ($matchingConnections | ForEach-Object { "$($_.ConnectionName):$($_.Status)" }) -join ", "
            Add-CheckResult -Category "Connection" -Status "FAIL" -Details "$($connDef.DisplayName) exists but is not connected ($statusSummary)"
        }
    }
}
catch {
    Add-CheckResult -Category "Connection" -Status "FAIL" -Details "Could not query Power Apps connections: $($_.Exception.Message)"
}

Write-Host "`n[5/7] Checking Copilot Studio agent..." -ForegroundColor Cyan

$copilotResult = Invoke-PacCommand -Arguments @("copilot", "list", "--environment", $EnvironmentId)
if ($copilotResult.ExitCode -ne 0) {
    Add-CheckResult -Category "Copilot" -Status "FAIL" -Details "PAC could not query copilots: $($copilotResult.Output)"
}
elseif ($copilotResult.Output -match "(?im)^\s*Email Productivity Agent\s+(?<id>[0-9a-fA-F-]{36})\s+") {
    $copilotId = $Matches["id"]
    Add-CheckResult -Category "Copilot" -Status "PASS" -Details "Email Productivity Agent copilot exists ($copilotId)"

    $copilotValidationDir = Join-Path $env:TEMP ("epa-readiness-copilot-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $copilotValidationDir | Out-Null

    try {
        $copilotTemplatePath = Join-Path $copilotValidationDir "copilot-template.yaml"
        Push-Location $copilotValidationDir
        try {
            $extractResult = Invoke-PacCommand -Arguments @(
                "copilot", "extract-template",
                "--environment", $EnvironmentId,
                "--bot", $copilotId,
                "--templateFileName", $copilotTemplatePath,
                "--overwrite"
            )
        }
        finally {
            Pop-Location
        }

        if ($extractResult.ExitCode -ne 0 -or -not (Test-Path $copilotTemplatePath)) {
            Add-CheckResult -Category "Copilot Topics" -Status "FAIL" -Details "Could not extract the copilot template to verify EPA topics"
        }
        else {
            $copilotTemplate = Get-Content -Path $copilotTemplatePath -Raw
            $expectedCopilotMarkers = @(
                "displayName: Follow-Up Nudge",
                "displayName: Snooze Auto-Removal",
                "displayName: AgentResponseJSON"
            )

            $missingMarkers = @()
            foreach ($marker in $expectedCopilotMarkers) {
                if ($copilotTemplate -notmatch [regex]::Escape($marker)) {
                    $missingMarkers += $marker
                }
            }

            if ($missingMarkers.Count -eq 0) {
                Add-CheckResult -Category "Copilot Topics" -Status "PASS" -Details "Follow-Up Nudge and Snooze Auto-Removal topics with AgentResponseJSON outputs are present"
            }
            else {
                Add-CheckResult -Category "Copilot Topics" -Status "FAIL" -Details "Copilot exists but is missing expected topic markers: $($missingMarkers -join ', ')"
            }
        }
    }
    finally {
        if (Test-Path $copilotValidationDir) {
            Remove-Item -Path $copilotValidationDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
else {
    Add-CheckResult -Category "Copilot" -Status "FAIL" -Details "Email Productivity Agent copilot is missing"
}

Write-Host "`n[6/7] Checking Settings UI..." -ForegroundColor Cyan

# The settings UI is delivered via Teams Adaptive Card flows (Flow 7 + 7b).
# The Canvas App is optional — check for it but don't block on it.
$canvasResult = Invoke-PacCommand -Arguments @("canvas", "list", "--environment", $EnvironmentId)
if ($canvasResult.ExitCode -eq 0 -and $canvasResult.Output -match "(?im)Email Productivity Agent Settings") {
    Add-CheckResult -Category "Settings UI" -Status "PASS" -Details "Email Productivity Agent Settings canvas app exists (optional)"
}
else {
    Add-CheckResult -Category "Settings UI" -Status "PASS" -Details "Settings delivered via Teams Adaptive Card (Flow 7 + 7b)"
}

Write-Host "`n[7/7] Checking deployed EPA flows..." -ForegroundColor Cyan

try {
    $flowCheck = Invoke-RestMethod -Uri "$OrgUrl/api/data/v9.2/workflows?`$filter=startswith(name,'EPA - Flow')&`$select=name,workflowid,statecode" -Headers $dvHeaders -Method Get
    $flowsByName = @{}
    foreach ($flow in @($flowCheck.value)) {
        $flowsByName[$flow.name] = $flow
    }

    foreach ($expectedFlow in $expectedFlows) {
        if (-not $flowsByName.ContainsKey($expectedFlow)) {
            Add-CheckResult -Category "Flow" -Status "FAIL" -Details "$expectedFlow is missing"
            continue
        }

        $stateCode = $flowsByName[$expectedFlow].statecode
        if ($stateCode -eq 1) {
            Add-CheckResult -Category "Flow" -Status "PASS" -Details "$expectedFlow is ON"
        }
        else {
            Add-CheckResult -Category "Flow" -Status "FAIL" -Details "$expectedFlow exists but is not ON (statecode: $stateCode)"
        }
    }
}
catch {
    Add-CheckResult -Category "Flow" -Status "FAIL" -Details "Could not query EPA flows: $($_.Exception.Message)"
}

$passCount = @($results | Where-Object Status -eq "PASS").Count
$failCount = @($results | Where-Object Status -eq "FAIL").Count

Write-Host "`n──────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "Passed checks: $passCount" -ForegroundColor Green
Write-Host "Failed checks: $failCount" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })

if ($failCount -eq 0) {
    Write-Host "`nEnvironment is ready for manual EPA testing." -ForegroundColor Green
    exit 0
}

$blockingCategories = $results |
    Where-Object Status -eq "FAIL" |
    Select-Object -ExpandProperty Category -Unique

Write-Host "`nEnvironment is NOT ready for manual EPA testing." -ForegroundColor Red
Write-Host "Blocking areas: $($blockingCategories -join ', ')" -ForegroundColor Yellow
exit 1
