<#
.SYNOPSIS
    Validates DLP policy compatibility for the Intelligent Work Layer.

.DESCRIPTION
    Queries Power Platform Data Loss Prevention (DLP) policies affecting a target environment
    and verifies that the Intelligent Work Layer's required connectors are all classified into
    the same DLP group (typically Business).

    The script authenticates with both PAC CLI and Azure CLI, calls the Power Platform Admin
    REST API on the Business Application Platform (BAP) endpoint, reports the resolved DLP
    group for each required connector, and exits with code 0 when the configuration is valid
    or 1 when a conflict is detected.

.PARAMETER EnvironmentId
    Power Platform environment ID to validate.

.PARAMETER TenantId
    Optional Microsoft Entra tenant ID used when interactive authentication is required.

.EXAMPLE
    .\validate-dlp-policy.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    .\validate-dlp-policy.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000" -TenantId "11111111-1111-1111-1111-111111111111"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [string]$TenantId
)

$ErrorActionPreference = "Stop"

$BapApiBase = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin"
$PowerPlatformAdminResource = "https://api.bap.microsoft.com"

$RequiredConnectors = [ordered]@{
    "Office 365 Outlook"      = "/providers/Microsoft.PowerApps/apis/shared_office365"
    "Microsoft Teams"         = "/providers/Microsoft.PowerApps/apis/shared_teams"
    "Office 365 Users"        = "/providers/Microsoft.PowerApps/apis/shared_office365users"
    "Microsoft Dataverse"     = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
    "Microsoft Copilot Studio" = "/providers/Microsoft.PowerApps/apis/shared_microsoftcopilotstudio"
    "SharePoint"              = "/providers/Microsoft.PowerApps/apis/shared_sharepointonline"
}

$ConnectorLookup = @{}
foreach ($connectorId in $RequiredConnectors.Values) {
    $normalizedId = $connectorId.Trim().ToLowerInvariant()
    $ConnectorLookup[$normalizedId] = $connectorId

    if ($connectorId -match '/apis/([^/]+)$') {
        $ConnectorLookup[$matches[1].ToLowerInvariant()] = $connectorId
    }
}

function Write-Section {
    param(
        [string]$Title,
        [int]$Step,
        [int]$Total
    )

    Write-Host "`n[$Step/$Total] $Title" -ForegroundColor Cyan
}

function Get-ObjectProperties {
    param([object]$Node)

    if ($null -eq $Node) {
        return @()
    }

    if ($Node -is [System.Collections.IDictionary]) {
        return @($Node.GetEnumerator() | ForEach-Object {
            [PSCustomObject]@{
                Name = [string]$_.Key
                Value = $_.Value
            }
        })
    }

    if ($Node -is [psobject]) {
        return @($Node.PSObject.Properties | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Value = $_.Value
            }
        })
    }

    return @()
}

function Get-PropertyValue {
    param(
        [object]$Node,
        [string[]]$Names
    )

    foreach ($property in Get-ObjectProperties -Node $Node) {
        foreach ($name in $Names) {
            if ($property.Name -ieq $name) {
                return $property.Value
            }
        }
    }

    return $null
}

function Convert-ToSimpleString {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string]) {
        return $Value.Trim()
    }

    if ($Value -is [ValueType]) {
        return ([string]$Value).Trim()
    }

    return $null
}

function Resolve-RequiredConnectorId {
    param([object]$Candidate)

    $text = Convert-ToSimpleString -Value $Candidate
    if (-not $text) {
        return $null
    }

    $normalized = $text.Trim().ToLowerInvariant()
    if ($ConnectorLookup.ContainsKey($normalized)) {
        return $ConnectorLookup[$normalized]
    }

    return $null
}

function Resolve-DlpGroupName {
    param([object]$Candidate)

    $text = Convert-ToSimpleString -Value $Candidate
    if (-not $text) {
        return $null
    }

    $normalized = $text.ToLowerInvariant()

    if ($normalized -match 'non[-_ ]?business' -or $normalized -match 'general') {
        return 'NonBusiness'
    }

    if ($normalized -match 'blocked') {
        return 'Blocked'
    }

    if ($normalized -match 'business' -or $normalized -match 'confidential') {
        return 'Business'
    }

    return $null
}

function Get-PolicyName {
    param([object]$Policy)

    $candidates = @(
        (Get-PropertyValue -Node $Policy -Names @('displayName', 'DisplayName', 'name', 'Name', 'policyName', 'PolicyName', 'id', 'Id')),
        (Get-PropertyValue -Node (Get-PropertyValue -Node $Policy -Names @('properties', 'Properties')) -Names @('displayName', 'DisplayName', 'name', 'Name', 'policyName', 'PolicyName', 'id', 'Id'))
    )

    foreach ($candidate in $candidates) {
        $text = Convert-ToSimpleString -Value $candidate
        if ($text) {
            return $text
        }
    }

    return 'Unnamed policy'
}

function Get-CollectionItems {
    param([object]$Response)

    if ($null -eq $Response) {
        return @()
    }

    foreach ($propertyName in @('value', 'Value', 'apiPolicies', 'ApiPolicies', 'policies', 'Policies')) {
        $propertyValue = Get-PropertyValue -Node $Response -Names @($propertyName)
        if ($null -ne $propertyValue) {
            return @($propertyValue)
        }
    }

    if ($Response -is [System.Collections.IEnumerable] -and -not ($Response -is [string]) -and -not ($Response -is [System.Collections.IDictionary])) {
        return @($Response)
    }

    if ($Response -is [array]) {
        return @($Response)
    }

    return @($Response)
}

function Get-PolicyDefaultGroup {
    param([object]$Policy)

    $defaultGroupNames = @(
        'defaultConnectorClassification',
        'defaultConnectorsClassification',
        'defaultApiGroup',
        'defaultDataGroup'
    )

    $queue = [System.Collections.Generic.Queue[object]]::new()
    $queue.Enqueue($Policy)

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if ($null -eq $current) {
            continue
        }

        $match = Get-PropertyValue -Node $current -Names $defaultGroupNames
        $group = Resolve-DlpGroupName -Candidate $match
        if ($group) {
            return $group
        }

        if ($current -is [System.Collections.IEnumerable] -and -not ($current -is [string]) -and -not ($current -is [System.Collections.IDictionary])) {
            foreach ($item in $current) {
                $queue.Enqueue($item)
            }

            continue
        }

        foreach ($property in Get-ObjectProperties -Node $current) {
            $queue.Enqueue($property.Value)
        }
    }

    return $null
}

function Add-ConnectorAssignment {
    param(
        [hashtable]$Assignments,
        [string]$ConnectorId,
        [string]$Group,
        [string]$PolicyName,
        [string]$Source
    )

    if (-not $ConnectorId -or -not $Group) {
        return
    }

    if (-not $Assignments.ContainsKey($ConnectorId)) {
        $Assignments[$ConnectorId] = [System.Collections.Generic.List[object]]::new()
    }

    $key = "$PolicyName|$Group|$Source"
    $exists = $Assignments[$ConnectorId] | Where-Object { $_.Key -eq $key } | Select-Object -First 1
    if (-not $exists) {
        $Assignments[$ConnectorId].Add([PSCustomObject]@{
            Key = $key
            PolicyName = $PolicyName
            Group = $Group
            Source = $Source
        }) | Out-Null
    }
}

function Collect-ConnectorAssignments {
    param(
        [object]$Node,
        [string]$CurrentGroup,
        [string]$Path,
        [string]$PolicyName,
        [hashtable]$Assignments
    )

    if ($null -eq $Node) {
        return
    }

    if ($Node -is [string] -or $Node -is [ValueType]) {
        $connectorId = Resolve-RequiredConnectorId -Candidate $Node
        if ($connectorId) {
            Add-ConnectorAssignment -Assignments $Assignments -ConnectorId $connectorId -Group $CurrentGroup -PolicyName $PolicyName -Source $Path
        }

        return
    }

    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string]) -and -not ($Node -is [System.Collections.IDictionary]) -and -not ($Node -is [psobject])) {
        $index = 0
        foreach ($item in $Node) {
            Collect-ConnectorAssignments -Node $item -CurrentGroup $CurrentGroup -Path "$Path[$index]" -PolicyName $PolicyName -Assignments $Assignments
            $index++
        }

        return
    }

    $effectiveGroup = $CurrentGroup
    $classification = Resolve-DlpGroupName -Candidate (Get-PropertyValue -Node $Node -Names @('classification', 'Classification', 'groupName', 'GroupName', 'dataGroup', 'DataGroup', 'apiGroup', 'ApiGroup', 'connectorGroup', 'ConnectorGroup'))
    if ($classification) {
        $effectiveGroup = $classification
    }

    foreach ($fieldName in @('id', 'Id', 'name', 'Name', 'api', 'Api', 'apiId', 'ApiId', 'apiName', 'ApiName', 'connector', 'Connector', 'connectorId', 'ConnectorId', 'connectorName', 'ConnectorName')) {
        $fieldValue = Get-PropertyValue -Node $Node -Names @($fieldName)
        if ($fieldValue) {
            $connectorId = Resolve-RequiredConnectorId -Candidate $fieldValue
            if ($connectorId) {
                Add-ConnectorAssignment -Assignments $Assignments -ConnectorId $connectorId -Group $effectiveGroup -PolicyName $PolicyName -Source "$Path.$fieldName"
            }
        }
    }

    foreach ($property in Get-ObjectProperties -Node $Node) {
        $propertyGroup = Resolve-DlpGroupName -Candidate $property.Name
        $nextGroup = if ($propertyGroup) { $propertyGroup } else { $effectiveGroup }

        $connectorIdFromKey = Resolve-RequiredConnectorId -Candidate $property.Name
        if ($connectorIdFromKey) {
            Add-ConnectorAssignment -Assignments $Assignments -ConnectorId $connectorIdFromKey -Group $nextGroup -PolicyName $PolicyName -Source "$Path.$($property.Name)"
        }

        $connectorIdFromValue = Resolve-RequiredConnectorId -Candidate $property.Value
        if ($connectorIdFromValue) {
            Add-ConnectorAssignment -Assignments $Assignments -ConnectorId $connectorIdFromValue -Group $nextGroup -PolicyName $PolicyName -Source "$Path.$($property.Name)"
        }

        Collect-ConnectorAssignments -Node $property.Value -CurrentGroup $nextGroup -Path "$Path.$($property.Name)" -PolicyName $PolicyName -Assignments $Assignments
    }
}

function Test-PolicyAppliesToEnvironment {
    param(
        [object]$Policy,
        [string]$TargetEnvironmentId
    )

    try {
        $policyJson = ($Policy | ConvertTo-Json -Depth 100 -Compress).ToLowerInvariant()
    }
    catch {
        return $true
    }

    $environmentMatch = [regex]::Escape($TargetEnvironmentId.ToLowerInvariant())

    if ($policyJson -match 'allenvironments') {
        return $true
    }

    if ($policyJson -match 'exceptenvironments') {
        return -not ($policyJson -match $environmentMatch)
    }

    if ($policyJson -match 'onlyenvironments' -or $policyJson -match 'singleenvironment') {
        return ($policyJson -match $environmentMatch)
    }

    if ($policyJson -match $environmentMatch) {
        return $true
    }

    return $true
}

function Invoke-PacCommand {
    param([string[]]$Arguments)

    $output = & pac @Arguments 2>&1 | Out-String
    return [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        Output = $output.Trim()
    }
}

function Ensure-PacAuthentication {
    if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
        throw 'PAC CLI not found. Install with: dotnet tool install --global Microsoft.PowerApps.CLI.Tool'
    }

    $authList = Invoke-PacCommand -Arguments @('auth', 'list')
    if ($authList.ExitCode -ne 0 -or $authList.Output -match 'No profiles') {
        Write-Host '  No PAC auth profile found — running pac auth create...' -ForegroundColor Yellow
        $authArgs = @('auth', 'create')
        if ($TenantId) {
            $authArgs += @('--tenant', $TenantId)
        }

        $authCreate = Invoke-PacCommand -Arguments $authArgs
        if ($authCreate.ExitCode -ne 0) {
            throw "PAC authentication failed: $($authCreate.Output)"
        }
    } else {
        Write-Host '  ✓ PAC authentication available' -ForegroundColor Green
    }

    $selectResult = Invoke-PacCommand -Arguments @('org', 'select', '--environment', $EnvironmentId)
    if ($selectResult.ExitCode -ne 0) {
        throw "PAC could not select environment '$EnvironmentId': $($selectResult.Output)"
    }

    Write-Host "  ✓ PAC environment selected: $EnvironmentId" -ForegroundColor Green
}

function Ensure-AzureAuthentication {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'Azure CLI not found. Install with: winget install Microsoft.AzureCLI'
    }

    $accountJson = az account show --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $accountJson) {
        Write-Host '  No Azure CLI session found — running az login...' -ForegroundColor Yellow
        $loginArgs = @('login')
        if ($TenantId) {
            $loginArgs += @('--tenant', $TenantId)
        }

        & az @loginArgs | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Azure CLI authentication failed.'
        }

        $accountJson = az account show --output json
    }

    $account = $accountJson | ConvertFrom-Json
    if ($TenantId -and $account.tenantId -and $account.tenantId -ne $TenantId) {
        Write-Host "  WARN: Azure CLI is authenticated to tenant $($account.tenantId), not requested tenant $TenantId" -ForegroundColor Yellow
    }

    Write-Host "  ✓ Azure CLI authentication available for $($account.user.name)" -ForegroundColor Green
}

function Get-PowerPlatformAdminHeaders {
    $token = az account get-access-token --resource $PowerPlatformAdminResource --query accessToken -o tsv 2>$null
    if (-not $token) {
        throw "Cannot acquire Power Platform Admin API token for $PowerPlatformAdminResource. Run 'az login' (optionally with --tenant)."
    }

    Write-Host '  ✓ Power Platform Admin API token acquired' -ForegroundColor Green

    return @{
        'Authorization' = "Bearer $token"
        'Content-Type' = 'application/json'
    }
}

function Get-ErrorBody {
    param([System.Exception]$Exception)

    if (-not $Exception.Response) {
        return $Exception.Message
    }

    try {
        $reader = New-Object System.IO.StreamReader($Exception.Response.GetResponseStream())
        $body = $reader.ReadToEnd()
        $reader.Dispose()
        return $body
    }
    catch {
        return $Exception.Message
    }
}

function Invoke-BapGet {
    param(
        [string]$Uri,
        [hashtable]$Headers
    )

    try {
        return Invoke-RestMethod -Uri $Uri -Method Get -Headers $Headers
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        $body = Get-ErrorBody -Exception $_.Exception
        $statusText = if ($statusCode) { "HTTP $statusCode" } else { 'request failure' }
        throw "GET $Uri failed ($statusText): $body"
    }
}

function Get-DlpPolicies {
    param([hashtable]$Headers)

    # NOTE: The legacy BAP DLP policy routes below are not prominently documented in current
    # Learn REST references. They are the most likely admin endpoints for reading effective
    # DLP policies for an environment and tenant on api.bap.microsoft.com.
    $environmentUri = "$BapApiBase/environments/$EnvironmentId/apiPolicies?api-version=2016-11-01"
    $tenantUri = "$BapApiBase/apiPolicies?api-version=2016-11-01"

    try {
        $environmentResponse = Invoke-BapGet -Uri $environmentUri -Headers $Headers
        $environmentPolicies = @(Get-CollectionItems -Response $environmentResponse)
        return [PSCustomObject]@{
            Source = 'environment'
            Uri = $environmentUri
            Policies = $environmentPolicies
        }
    }
    catch {
        Write-Host "  WARN: Environment-scoped endpoint failed. Falling back to tenant-level policies." -ForegroundColor Yellow
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    $tenantResponse = Invoke-BapGet -Uri $tenantUri -Headers $Headers
    $tenantPolicies = @(Get-CollectionItems -Response $tenantResponse | Where-Object {
        Test-PolicyAppliesToEnvironment -Policy $_ -TargetEnvironmentId $EnvironmentId
    })

    return [PSCustomObject]@{
        Source = 'tenant'
        Uri = $tenantUri
        Policies = $tenantPolicies
    }
}

Write-Host "`n━━━ Intelligent Work Layer DLP Policy Validation ━━━" -ForegroundColor Cyan
Write-Host "Environment ID: $EnvironmentId" -ForegroundColor Gray
if ($TenantId) {
    Write-Host "Tenant ID:      $TenantId" -ForegroundColor Gray
}

Write-Section -Title 'Validating prerequisites and PAC authentication' -Step 1 -Total 5
Ensure-PacAuthentication

Write-Section -Title 'Validating Azure CLI authentication' -Step 2 -Total 5
Ensure-AzureAuthentication

Write-Section -Title 'Acquiring Power Platform Admin API token' -Step 3 -Total 5
$adminHeaders = Get-PowerPlatformAdminHeaders

Write-Section -Title 'Querying DLP policies' -Step 4 -Total 5
$policyResult = Get-DlpPolicies -Headers $adminHeaders
$policies = @($policyResult.Policies)

if ($policies.Count -eq 0) {
    Write-Host "  ✅ No DLP policies apply to environment $EnvironmentId — no restrictions detected." -ForegroundColor Green
    exit 0
}

Write-Host "  Source: $($policyResult.Source)-scoped query" -ForegroundColor Green
Write-Host "  Policies returned: $($policies.Count)" -ForegroundColor Green

Write-Section -Title 'Evaluating required connector groups' -Step 5 -Total 5

$allAssignments = @{}
foreach ($policy in $policies) {
    $policyName = Get-PolicyName -Policy $policy
    $policyAssignments = @{}
    $defaultGroup = Get-PolicyDefaultGroup -Policy $policy

    Collect-ConnectorAssignments -Node $policy -CurrentGroup $null -Path '$' -PolicyName $policyName -Assignments $policyAssignments

    if ($defaultGroup) {
        foreach ($connectorId in $RequiredConnectors.Values) {
            if (-not $policyAssignments.ContainsKey($connectorId) -or $policyAssignments[$connectorId].Count -eq 0) {
                Add-ConnectorAssignment -Assignments $policyAssignments -ConnectorId $connectorId -Group $defaultGroup -PolicyName $policyName -Source 'defaultConnectorClassification'
            }
        }
    }

    foreach ($connectorId in $policyAssignments.Keys) {
        if (-not $allAssignments.ContainsKey($connectorId)) {
            $allAssignments[$connectorId] = [System.Collections.Generic.List[object]]::new()
        }

        foreach ($assignment in $policyAssignments[$connectorId]) {
            $allAssignments[$connectorId].Add($assignment) | Out-Null
        }
    }
}

$resolvedGroups = [System.Collections.Generic.List[string]]::new()
$hasConflict = $false
$hasUnresolvedConnector = $false

foreach ($connectorName in $RequiredConnectors.Keys) {
    $connectorId = $RequiredConnectors[$connectorName]
    $assignments = if ($allAssignments.ContainsKey($connectorId)) { @($allAssignments[$connectorId]) } else { @() }
    $groups = @($assignments | Select-Object -ExpandProperty Group -Unique)

    if ($groups.Count -eq 0) {
        $hasUnresolvedConnector = $true
        Write-Host "  ❌ $connectorName => Not found in returned policy payload" -ForegroundColor Red
        continue
    }

    foreach ($group in $groups) {
        if (-not $resolvedGroups.Contains($group)) {
            $resolvedGroups.Add($group) | Out-Null
        }
    }

    $color = if ($groups.Count -gt 1) { 'Red' } else { 'Green' }
    if ($groups.Count -gt 1) {
        $hasConflict = $true
    }

    $policySummary = ($assignments | ForEach-Object { "$($_.PolicyName): $($_.Group)" } | Sort-Object -Unique) -join '; '
    Write-Host "  • $connectorName => $($groups -join ', ')" -ForegroundColor $color
    if ($policySummary) {
        Write-Host "      $policySummary" -ForegroundColor Gray
    }
}

if (-not $hasUnresolvedConnector -and -not $hasConflict -and $resolvedGroups.Count -eq 1) {
    Write-Host "`n  ✅ All required connectors are in the same DLP group: $($resolvedGroups[0])" -ForegroundColor Green
    exit 0
}

if ($hasUnresolvedConnector) {
    Write-Host "`n  ❌ Conflict detected: one or more required connectors could not be resolved to a DLP group." -ForegroundColor Red
} else {
    Write-Host "`n  ❌ Conflict detected: required connectors are split across DLP groups ($($resolvedGroups -join ', '))." -ForegroundColor Red
}

exit 1
