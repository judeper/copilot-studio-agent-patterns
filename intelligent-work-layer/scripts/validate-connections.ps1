<#
.SYNOPSIS
    Validates that required Power Automate connections exist in the target Power Platform environment.

.DESCRIPTION
    Authenticates to the target environment using PAC CLI, acquires a bearer token with
    Azure CLI for the Power Automate Flow Management API, and checks that the required
    connector connections exist and are in Connected status. Optional connectors are
    reported but do not affect the exit code.

.PARAMETER EnvironmentId
    Power Platform environment ID (required).

.PARAMETER OrgUrl
    Dataverse organization URL (optional). If supplied, it is used as a PAC authentication
    fallback and included in the validation summary.

.EXAMPLE
    .\validate-connections.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    .\validate-connections.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000" -OrgUrl "https://contoso.crm.dynamics.com"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [string]$OrgUrl
)

$ErrorActionPreference = "Stop"

function Get-FirstNonEmptyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string[]]$PropertyNames
    )

    foreach ($propertyName in $PropertyNames) {
        if ($InputObject.PSObject.Properties.Name -contains $propertyName) {
            $value = $InputObject.$propertyName
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                return [string]$value
            }
        }
    }

    return $null
}

function Resolve-PacEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentId
    )

    $pacListCommands = @(
        @("env", "list", "--json"),
        @("org", "list", "--json")
    )

    foreach ($pacListArgs in $pacListCommands) {
        try {
            $raw = & pac @pacListArgs 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $raw) {
                continue
            }

            $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
            $items = if ($parsed -is [System.Array]) {
                @($parsed)
            }
            elseif ($parsed.PSObject.Properties.Name -contains "value") {
                @($parsed.value)
            }
            else {
                @($parsed)
            }

            foreach ($item in $items) {
                $candidateId = Get-FirstNonEmptyValue -InputObject $item -PropertyNames @(
                    "EnvironmentId",
                    "environmentId",
                    "Id",
                    "id"
                )

                if ($candidateId -eq $EnvironmentId) {
                    return $item
                }
            }
        }
        catch {
            continue
        }
    }

    return $null
}

function Get-ConnectionApiName {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Connection
    )

    if (-not $Connection.properties) {
        return $null
    }

    $apiId = Get-FirstNonEmptyValue -InputObject $Connection.properties -PropertyNames @("apiId", "ApiId")
    if (-not $apiId) {
        return $null
    }

    return ($apiId -replace '^.*?/apis/', '')
}

function Get-ConnectionStatus {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Connection
    )

    if ($Connection.properties) {
        $status = Get-FirstNonEmptyValue -InputObject $Connection.properties -PropertyNames @("status", "Status")
        if ($status) {
            return $status
        }

        if ($Connection.properties.PSObject.Properties.Name -contains "statuses" -and $Connection.properties.statuses) {
            $firstStatus = $Connection.properties.statuses | Select-Object -First 1
            if ($firstStatus) {
                $nestedStatus = Get-FirstNonEmptyValue -InputObject $firstStatus -PropertyNames @("status", "Status")
                if ($nestedStatus) {
                    return $nestedStatus
                }
            }
        }
    }

    return "Unknown"
}

function Get-ConnectionDisplayName {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Connection
    )

    if ($Connection.properties) {
        $displayName = Get-FirstNonEmptyValue -InputObject $Connection.properties -PropertyNames @(
            "displayName",
            "DisplayName",
            "connectionDisplayName",
            "ConnectionDisplayName"
        )

        if ($displayName) {
            return $displayName
        }
    }

    return (Get-FirstNonEmptyValue -InputObject $Connection -PropertyNames @("displayName", "DisplayName", "name", "Name", "id", "Id"))
}

function Get-FlowConnections {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
    )

    $connections = @()
    $nextUri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentId/connections?api-version=2016-11-01"

    do {
        $response = Invoke-RestMethod -Uri $nextUri -Headers $Headers -Method Get -ErrorAction Stop

        if ($response.PSObject.Properties.Name -contains "value") {
            $connections += @($response.value)
        }
        elseif ($response) {
            $connections += @($response)
        }

        if ($response.PSObject.Properties.Name -contains "nextLink" -and $response.nextLink) {
            $nextUri = $response.nextLink
        }
        elseif ($response.PSObject.Properties.Name -contains "@odata.nextLink" -and $response.'@odata.nextLink') {
            $nextUri = $response.'@odata.nextLink'
        }
        else {
            $nextUri = $null
        }
    } while ($nextUri)

    return $connections
}

function Select-BestConnection {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Connections
    )

    if (-not $Connections -or $Connections.Count -eq 0) {
        return $null
    }

    return @(
        $Connections |
            Sort-Object @{ Expression = { if ((Get-ConnectionStatus -Connection $_) -eq "Connected") { 0 } else { 1 } } }, @{ Expression = { Get-ConnectionDisplayName -Connection $_ } }
    )[0]
}

$requiredConnections = @(
    [PSCustomObject]@{ ApiName = "shared_office365"; DisplayName = "Office 365 Outlook"; Required = $true },
    [PSCustomObject]@{ ApiName = "shared_teams"; DisplayName = "Microsoft Teams"; Required = $true },
    [PSCustomObject]@{ ApiName = "shared_office365users"; DisplayName = "Office 365 Users"; Required = $true },
    [PSCustomObject]@{ ApiName = "shared_commondataserviceforapps"; DisplayName = "Microsoft Dataverse"; Required = $true },
    [PSCustomObject]@{ ApiName = "shared_microsoftcopilotstudio"; DisplayName = "Microsoft Copilot Studio"; Required = $true }
)

$optionalConnections = @(
    [PSCustomObject]@{ ApiName = "shared_sharepointonline"; DisplayName = "SharePoint"; Required = $false },
    [PSCustomObject]@{ ApiName = "shared_webcontents"; DisplayName = "HTTP / Web Contents"; Required = $false }
)

# ─────────────────────────────────────
# 0. Prerequisite Validation
# ─────────────────────────────────────
Write-Host "Validating prerequisites..." -ForegroundColor Cyan

if (-not (Get-Command "pac" -ErrorAction SilentlyContinue)) {
    throw "PAC CLI not found. Install with: dotnet tool install --global Microsoft.PowerApps.CLI.Tool"
}
if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    throw "Azure CLI not found. Install with: winget install Microsoft.AzureCLI"
}

Write-Host "  PAC CLI: OK" -ForegroundColor Green
Write-Host "  Azure CLI: OK" -ForegroundColor Green

if ($OrgUrl) {
    $OrgUrl = $OrgUrl.TrimEnd('/')
}

# ─────────────────────────────────────
# 1. Authenticate with PAC CLI
# ─────────────────────────────────────
Write-Host "Authenticating with Power Platform..." -ForegroundColor Cyan

$pacAuthenticated = $false
pac auth create --environment $EnvironmentId
if ($LASTEXITCODE -eq 0) {
    $pacAuthenticated = $true
}
elseif ($OrgUrl) {
    Write-Host "  PAC auth with EnvironmentId failed — retrying with OrgUrl..." -ForegroundColor Yellow
    pac auth create --url $OrgUrl
    if ($LASTEXITCODE -eq 0) {
        $pacAuthenticated = $true
    }
}

if (-not $pacAuthenticated) {
    throw "PAC authentication failed. Re-run after completing the PAC sign-in flow."
}

Write-Host "  PAC authentication profile created" -ForegroundColor Green

$environmentSelected = $false
& pac env select --environment $EnvironmentId 2>$null
if ($LASTEXITCODE -eq 0) {
    $environmentSelected = $true
}
else {
    & pac org select --environment $EnvironmentId 2>$null
    if ($LASTEXITCODE -eq 0) {
        $environmentSelected = $true
    }
}

if ($environmentSelected) {
    Write-Host "  Environment selected: $EnvironmentId" -ForegroundColor Green
}
else {
    Write-Host "  Environment selection command unavailable — continuing with authenticated profile" -ForegroundColor Yellow
}

if (-not $OrgUrl) {
    $resolvedEnvironment = Resolve-PacEnvironment -EnvironmentId $EnvironmentId
    if ($resolvedEnvironment) {
        $OrgUrl = Get-FirstNonEmptyValue -InputObject $resolvedEnvironment -PropertyNames @(
            "EnvironmentUrl",
            "environmentUrl",
            "Url",
            "url"
        )

        if ($OrgUrl) {
            $OrgUrl = $OrgUrl.TrimEnd('/')
        }
    }
}

# ─────────────────────────────────────
# 2. Acquire Flow Management API Token
# ─────────────────────────────────────
Write-Host "Acquiring Flow Management API token..." -ForegroundColor Cyan

$flowToken = az account get-access-token --resource "https://service.flow.microsoft.com/" --query accessToken -o tsv 2>$null
if (-not $flowToken) {
    throw "Failed to get Flow Management API token. Run 'az login' and try again."
}

Write-Host "  Azure CLI token acquired" -ForegroundColor Green

$flowHeaders = @{
    "Authorization" = "Bearer $flowToken"
    "Content-Type"  = "application/json"
}

# ─────────────────────────────────────
# 3. Query Environment Connections
# ─────────────────────────────────────
Write-Host "Querying Power Automate connections..." -ForegroundColor Cyan

$connections = Get-FlowConnections -EnvironmentId $EnvironmentId -Headers $flowHeaders
Write-Host "  Connections discovered: $($connections.Count)" -ForegroundColor Green

# ─────────────────────────────────────
# 4. Validate Required Connections
# ─────────────────────────────────────
Write-Host "`nRequired connections:" -ForegroundColor Cyan

$requiredConnectedCount = 0
$allRequiredConnected = $true

foreach ($definition in $requiredConnections) {
    $matchingConnections = @($connections | Where-Object { (Get-ConnectionApiName -Connection $_) -eq $definition.ApiName })
    $selectedConnection = Select-BestConnection -Connections $matchingConnections

    if (-not $selectedConnection) {
        Write-Host "  ❌ $($definition.DisplayName) [$($definition.ApiName)] — Missing" -ForegroundColor Red
        $allRequiredConnected = $false
        continue
    }

    $connectionStatus = Get-ConnectionStatus -Connection $selectedConnection
    $connectionDisplayName = Get-ConnectionDisplayName -Connection $selectedConnection

    if ($connectionStatus -eq "Connected") {
        Write-Host "  ✅ $($definition.DisplayName) [$($definition.ApiName)] — $connectionDisplayName (status: $connectionStatus)" -ForegroundColor Green
        $requiredConnectedCount++
    }
    else {
        Write-Host "  ⚠ $($definition.DisplayName) [$($definition.ApiName)] — $connectionDisplayName (status: $connectionStatus)" -ForegroundColor Yellow
        $allRequiredConnected = $false
    }
}

# ─────────────────────────────────────
# 5. Report Optional Connections
# ─────────────────────────────────────
Write-Host "`nOptional connections:" -ForegroundColor Cyan

$optionalConnectedCount = 0

foreach ($definition in $optionalConnections) {
    $matchingConnections = @($connections | Where-Object { (Get-ConnectionApiName -Connection $_) -eq $definition.ApiName })
    $selectedConnection = Select-BestConnection -Connections $matchingConnections

    if (-not $selectedConnection) {
        Write-Host "  ❌ $($definition.DisplayName) [$($definition.ApiName)] — Missing" -ForegroundColor Red
        continue
    }

    $connectionStatus = Get-ConnectionStatus -Connection $selectedConnection
    $connectionDisplayName = Get-ConnectionDisplayName -Connection $selectedConnection

    if ($connectionStatus -eq "Connected") {
        Write-Host "  ✅ $($definition.DisplayName) [$($definition.ApiName)] — $connectionDisplayName (status: $connectionStatus)" -ForegroundColor Green
        $optionalConnectedCount++
    }
    else {
        Write-Host "  ⚠ $($definition.DisplayName) [$($definition.ApiName)] — $connectionDisplayName (status: $connectionStatus)" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────
# 6. Summary
# ─────────────────────────────────────
Write-Host "`nConnection validation summary" -ForegroundColor Cyan
Write-Host "  Environment ID: $EnvironmentId" -ForegroundColor Green
if ($OrgUrl) {
    Write-Host "  Org URL: $OrgUrl" -ForegroundColor Green
}
else {
    Write-Host "  Org URL: Not provided/resolved" -ForegroundColor Yellow
}

$requiredSummaryColor = if ($allRequiredConnected) { "Green" } else { "Red" }
$optionalSummaryColor = if ($optionalConnectedCount -eq $optionalConnections.Count) { "Green" } else { "Yellow" }

Write-Host "  Required connected: $requiredConnectedCount/$($requiredConnections.Count)" -ForegroundColor $requiredSummaryColor
Write-Host "  Optional connected: $optionalConnectedCount/$($optionalConnections.Count)" -ForegroundColor $optionalSummaryColor

if ($allRequiredConnected) {
    Write-Host "`nAll required connections are present and connected." -ForegroundColor Green
    exit 0
}

Write-Host "`nOne or more required connections are missing or not Connected." -ForegroundColor Red
exit 1
