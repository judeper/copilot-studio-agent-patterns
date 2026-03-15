<#
.SYNOPSIS
    Provisions Intelligent Work Layer environment variables in Dataverse.

.DESCRIPTION
    Creates the four Intelligent Work Layer environment variable definitions documented in the
    deployment guide and optionally sets current values for them in the target Dataverse
    environment. The script authenticates through Azure CLI, uses the Dataverse Web API, adds
    the components to the specified unmanaged solution, and is safe to re-run.

.PARAMETER OrgUrl
    Dataverse organization URL (for example, https://orgname.crm.dynamics.com).

.PARAMETER SolutionName
    Dataverse solution unique name to add the environment variables to.
    Default: EnterpriseWorkAssistant

.PARAMETER PublisherPrefix
    Publisher prefix used when building environment variable schema names.
    Default: cr

.PARAMETER AdminNotificationEmail
    Email address for error and monitoring notifications.

.PARAMETER StalenessThresholdHours
    Hours before a High-priority PENDING card triggers a NUDGE.
    Default: 24

.PARAMETER ExpirationDays
    Days before a PENDING card expires.
    Default: 7

.PARAMETER SenderProfileMinSignals
    Minimum signal count before sender categorization activates.
    Default: 5

.EXAMPLE
    .\provision-env-variables.ps1 -OrgUrl "https://orgname.crm.dynamics.com" -AdminNotificationEmail "admin@contoso.com"

.EXAMPLE
    .\provision-env-variables.ps1 `
        -OrgUrl "https://orgname.crm.dynamics.com" `
        -SolutionName "EnterpriseWorkAssistant" `
        -PublisherPrefix "cr" `
        -StalenessThresholdHours 24 `
        -ExpirationDays 7 `
        -SenderProfileMinSignals 5
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$OrgUrl,

    [string]$SolutionName = "EnterpriseWorkAssistant",

    [string]$PublisherPrefix = "cr",

    [string]$AdminNotificationEmail,

    [int]$StalenessThresholdHours = 24,

    [int]$ExpirationDays = 7,

    [int]$SenderProfileMinSignals = 5
)

$ErrorActionPreference = "Stop"

# ─────────────────────────────────────
# 0. Prerequisite Validation
# ─────────────────────────────────────
if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    throw "Azure CLI not found. Install with: winget install Microsoft.AzureCLI"
}

$OrgUrl = $OrgUrl.TrimEnd('/')
if ($OrgUrl -notmatch '^https://[^\s]+$') {
    throw "OrgUrl must be a valid Dataverse URL such as https://orgname.crm.dynamics.com"
}

if ($AdminNotificationEmail -and $AdminNotificationEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
    throw "AdminNotificationEmail must be a valid email address."
}

if ($StalenessThresholdHours -lt 1) { throw "StalenessThresholdHours must be 1 or greater." }
if ($ExpirationDays -lt 1) { throw "ExpirationDays must be 1 or greater." }
if ($SenderProfileMinSignals -lt 1) { throw "SenderProfileMinSignals must be 1 or greater." }

# ─────────────────────────────────────
# 1. Dataverse Authentication
# ─────────────────────────────────────
$script:apiBase = "$OrgUrl/api/data/v9.2"
$script:apiCallCounter = 0
$script:accessToken = $null

function Get-DataverseHeaders {
    param([switch]$IncludeSolutionHeader)

    $headers = @{
        "Authorization"    = "Bearer $script:accessToken"
        "Content-Type"     = "application/json"
        "Accept"           = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
    }

    if ($IncludeSolutionHeader) {
        $headers["MSCRM.SolutionUniqueName"] = $SolutionName
    }

    return $headers
}

function Get-AccessToken {
    Write-Host "Acquiring Dataverse API token via Azure CLI..." -ForegroundColor Cyan
    $token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Failed to get Dataverse access token. Run 'az login' first and confirm access to $OrgUrl."
    }

    $script:accessToken = $token.Trim()
}

function Refresh-TokenIfNeeded {
    $script:apiCallCounter++
    if (-not $script:accessToken -or $script:apiCallCounter % 20 -eq 0) {
        if ($script:apiCallCounter -gt 1) {
            Write-Host "  Refreshing access token (after $($script:apiCallCounter) API calls)..." -ForegroundColor Yellow
        }
        Get-AccessToken
    }
}

function Resolve-DataverseErrorMessage {
    param([Parameter(Mandatory = $true)]$ErrorRecord)

    if ($ErrorRecord.ErrorDetails.Message) {
        try {
            return (($ErrorRecord.ErrorDetails.Message | ConvertFrom-Json).error.message)
        } catch {
            return $ErrorRecord.ErrorDetails.Message
        }
    }

    return $ErrorRecord.Exception.Message
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Get", "Post", "Patch")]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [object]$Body,

        [switch]$IncludeSolutionHeader
    )

    $attempt = 0
    do {
        $attempt++
        Refresh-TokenIfNeeded
        $headers = Get-DataverseHeaders -IncludeSolutionHeader:$IncludeSolutionHeader
        $bodyJson = $null
        if ($PSBoundParameters.ContainsKey('Body')) {
            $bodyJson = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 }
        }

        try {
            if ($null -ne $bodyJson) {
                return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $headers -Body $bodyJson -ErrorAction Stop
            }

            return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $headers -ErrorAction Stop
        } catch {
            $statusCode = $null
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
            if ($statusCode -eq 401 -and $attempt -lt 2) {
                Write-Host "  Access token expired — retrying with a fresh token..." -ForegroundColor Yellow
                Get-AccessToken
                continue
            }

            throw
        }
    } while ($attempt -lt 2)
}

function ConvertTo-ODataLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)
    return $Value.Replace("'", "''")
}

Get-AccessToken

# ─────────────────────────────────────
# 2. Create or Find Solution
# ─────────────────────────────────────
Write-Host "Setting up solution '$SolutionName'..." -ForegroundColor Cyan

$publisherQuery = ConvertTo-ODataLiteral -Value $PublisherPrefix
$publishers = Invoke-DataverseRequest -Method Get -Uri "$script:apiBase/publishers?`$filter=customizationprefix eq '$publisherQuery'&`$select=publisherid,friendlyname,customizationprefix"
if ($publishers.value.Count -eq 0) {
    throw "No publisher found with prefix '$PublisherPrefix'. Run provision-environment.ps1 first or create the publisher manually."
}

$publisher = $publishers.value[0]
Write-Host "  Publisher: $($publisher.friendlyname)" -ForegroundColor Green

$solutionQuery = ConvertTo-ODataLiteral -Value $SolutionName
$solutionResult = Invoke-DataverseRequest -Method Get -Uri "$script:apiBase/solutions?`$filter=uniquename eq '$solutionQuery'&`$select=solutionid,uniquename,friendlyname"
if ($solutionResult.value.Count -gt 0) {
    $solution = $solutionResult.value[0]
    Write-Host "  Solution already exists: $($solution.uniquename)" -ForegroundColor Green
} else {
    Write-Host "  Creating solution '$SolutionName'..." -ForegroundColor Yellow
    $solutionBody = @{
        uniquename                = $SolutionName
        friendlyname              = if ($SolutionName -eq "EnterpriseWorkAssistant") { "Intelligent Work Layer" } else { $SolutionName }
        description               = "Intelligent Work Layer environment variables"
        version                   = "1.0.0.0"
        "publisherid@odata.bind" = "/publishers($($publisher.publisherid))"
    }

    Invoke-DataverseRequest -Method Post -Uri "$script:apiBase/solutions" -Body $solutionBody | Out-Null
    $solutionResult = Invoke-DataverseRequest -Method Get -Uri "$script:apiBase/solutions?`$filter=uniquename eq '$solutionQuery'&`$select=solutionid,uniquename,friendlyname"
    if ($solutionResult.value.Count -eq 0) {
        throw "Solution '$SolutionName' could not be created or retrieved."
    }

    $solution = $solutionResult.value[0]
    Write-Host "  Solution created: $($solution.uniquename)" -ForegroundColor Green
}

function Ensure-SolutionComponent {
    param(
        [Parameter(Mandatory = $true)][Guid]$ComponentId,
        [Parameter(Mandatory = $true)][int]$ComponentType,
        [Parameter(Mandatory = $true)][string]$DisplayName
    )

    $body = @{
        ComponentId           = $ComponentId
        ComponentType         = $ComponentType
        SolutionUniqueName    = $SolutionName
        AddRequiredComponents = $false
    }

    try {
        Invoke-DataverseRequest -Method Post -Uri "$script:apiBase/AddSolutionComponent" -Body $body | Out-Null
        Write-Host "    Added to solution: $DisplayName" -ForegroundColor Green
    } catch {
        $message = Resolve-DataverseErrorMessage -ErrorRecord $_
        if ($message -match 'already exists|already added|target solution|Cannot add a Root Component') {
            Write-Host "    Already in solution: $DisplayName" -ForegroundColor Yellow
            return
        }

        throw "Failed to add '$DisplayName' to solution '$SolutionName': $message"
    }
}

function Get-DefinitionBySchemaName {
    param([Parameter(Mandatory = $true)][string]$SchemaName)

    $schemaQuery = ConvertTo-ODataLiteral -Value $SchemaName
    $result = Invoke-DataverseRequest -Method Get -Uri "$script:apiBase/environmentvariabledefinitions?`$select=environmentvariabledefinitionid,schemaname,displayname,description,defaultvalue,type&`$filter=schemaname eq '$schemaQuery'"
    if ($result.value.Count -gt 0) {
        return $result.value[0]
    }

    return $null
}

function Get-DefinitionValues {
    param([Parameter(Mandatory = $true)][Guid]$DefinitionId)

    $definition = Invoke-DataverseRequest -Method Get -Uri "$script:apiBase/environmentvariabledefinitions($DefinitionId)?`$select=environmentvariabledefinitionid,schemaname&`$expand=environmentvariabledefinition_environmentvariablevalue(`$select=environmentvariablevalueid,value)"
    return @($definition.environmentvariabledefinition_environmentvariablevalue | Where-Object { $null -ne $_ })
}

function Ensure-EnvironmentVariable {
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Variable
    )

    Write-Host "  $($Variable.DisplayName)" -ForegroundColor Cyan

    $definition = Get-DefinitionBySchemaName -SchemaName $Variable.SchemaName
    if ($definition) {
        if ([int]$definition.type -ne $Variable.TypeCode) {
            throw "Environment variable '$($Variable.SchemaName)' already exists with type $($definition.type); expected $($Variable.TypeCode)."
        }

        $definitionUpdates = @{}
        if ($definition.displayname -ne $Variable.DisplayName) {
            $definitionUpdates.displayname = $Variable.DisplayName
        }
        if ($definition.description -ne $Variable.Description) {
            $definitionUpdates.description = $Variable.Description
        }

        $currentDefault = if ($null -eq $definition.defaultvalue) { "" } else { [string]$definition.defaultvalue }
        $expectedDefault = if ($null -eq $Variable.DefaultValue) { "" } else { [string]$Variable.DefaultValue }
        if ($currentDefault -ne $expectedDefault) {
            if ($null -eq $Variable.DefaultValue) {
                $definitionUpdates.defaultvalue = $null
            } else {
                $definitionUpdates.defaultvalue = [string]$Variable.DefaultValue
            }
        }

        if ($definitionUpdates.Count -gt 0) {
            Invoke-DataverseRequest -Method Patch -Uri "$script:apiBase/environmentvariabledefinitions($($definition.environmentvariabledefinitionid))" -Body $definitionUpdates | Out-Null
            Write-Host "    Updated definition" -ForegroundColor Green
        } else {
            Write-Host "    Definition already exists" -ForegroundColor Green
        }
    } else {
        $definitionBody = @{
            schemaname  = $Variable.SchemaName
            displayname = $Variable.DisplayName
            description = $Variable.Description
            type        = $Variable.TypeCode
        }
        if ($null -ne $Variable.DefaultValue) {
            $definitionBody.defaultvalue = [string]$Variable.DefaultValue
        }

        Invoke-DataverseRequest -Method Post -Uri "$script:apiBase/environmentvariabledefinitions" -Body $definitionBody -IncludeSolutionHeader | Out-Null
        $definition = Get-DefinitionBySchemaName -SchemaName $Variable.SchemaName
        if (-not $definition) {
            throw "Environment variable definition '$($Variable.SchemaName)' was created but could not be retrieved."
        }

        Write-Host "    Created definition" -ForegroundColor Green
    }

    Ensure-SolutionComponent -ComponentId ([Guid]$definition.environmentvariabledefinitionid) -ComponentType 380 -DisplayName $Variable.DisplayName

    $existingValues = Get-DefinitionValues -DefinitionId ([Guid]$definition.environmentvariabledefinitionid)
    if ($existingValues.Count -gt 1) {
        Write-Host "    Multiple current values found; updating the first one only" -ForegroundColor Yellow
    }

    if (-not $Variable.HasCurrentValue) {
        if ($existingValues.Count -gt 0) {
            Write-Host "    Current value already exists — leaving unchanged" -ForegroundColor Green
            Ensure-SolutionComponent -ComponentId ([Guid]$existingValues[0].environmentvariablevalueid) -ComponentType 381 -DisplayName "$($Variable.DisplayName) value"
        } else {
            Write-Host "    No current value supplied — definition created without a value" -ForegroundColor Yellow
        }
        return
    }

    $desiredValue = [string]$Variable.CurrentValue
    if ($existingValues.Count -gt 0) {
        $existingValue = $existingValues[0]
        $currentValue = if ($null -eq $existingValue.value) { "" } else { [string]$existingValue.value }
        if ($currentValue -eq $desiredValue) {
            Write-Host "    Current value already set to '$desiredValue'" -ForegroundColor Green
        } else {
            Invoke-DataverseRequest -Method Patch -Uri "$script:apiBase/environmentvariablevalues($($existingValue.environmentvariablevalueid))" -Body @{ value = $desiredValue } | Out-Null
            Write-Host "    Updated current value to '$desiredValue'" -ForegroundColor Green
        }

        Ensure-SolutionComponent -ComponentId ([Guid]$existingValue.environmentvariablevalueid) -ComponentType 381 -DisplayName "$($Variable.DisplayName) value"
        return
    }

    $valueBody = @{
        value = $desiredValue
        "EnvironmentVariableDefinitionId@odata.bind" = "/environmentvariabledefinitions($($definition.environmentvariabledefinitionid))"
    }

    Invoke-DataverseRequest -Method Post -Uri "$script:apiBase/environmentvariablevalues" -Body $valueBody -IncludeSolutionHeader | Out-Null
    $createdValue = (Get-DefinitionValues -DefinitionId ([Guid]$definition.environmentvariabledefinitionid) | Select-Object -First 1)
    if (-not $createdValue) {
        throw "Environment variable value for '$($Variable.SchemaName)' was created but could not be retrieved."
    }

    Write-Host "    Created current value '$desiredValue'" -ForegroundColor Green
    Ensure-SolutionComponent -ComponentId ([Guid]$createdValue.environmentvariablevalueid) -ComponentType 381 -DisplayName "$($Variable.DisplayName) value"
}

# ─────────────────────────────────────
# 3. Provision Environment Variables
# ─────────────────────────────────────
Write-Host "Provisioning environment variables..." -ForegroundColor Cyan

$variables = @(
    [pscustomobject]@{
        SchemaName      = "${PublisherPrefix}_AdminNotificationEmail"
        DisplayName     = "AdminNotificationEmail"
        Description     = "Email address for error and monitoring notifications"
        TypeCode        = 100000000
        DefaultValue    = $null
        HasCurrentValue = -not [string]::IsNullOrWhiteSpace($AdminNotificationEmail)
        CurrentValue    = $AdminNotificationEmail
    },
    [pscustomobject]@{
        SchemaName      = "${PublisherPrefix}_StalenessThresholdHours"
        DisplayName     = "StalenessThresholdHours"
        Description     = "Hours before High-priority PENDING card triggers NUDGE"
        TypeCode        = 100000001
        DefaultValue    = [string]$StalenessThresholdHours
        HasCurrentValue = $true
        CurrentValue    = [string]$StalenessThresholdHours
    },
    [pscustomobject]@{
        SchemaName      = "${PublisherPrefix}_ExpirationDays"
        DisplayName     = "ExpirationDays"
        Description     = "Days before PENDING card expires"
        TypeCode        = 100000001
        DefaultValue    = [string]$ExpirationDays
        HasCurrentValue = $true
        CurrentValue    = [string]$ExpirationDays
    },
    [pscustomobject]@{
        SchemaName      = "${PublisherPrefix}_SenderProfileMinSignals"
        DisplayName     = "SenderProfileMinSignals"
        Description     = "Minimum signal count before sender categorization"
        TypeCode        = 100000001
        DefaultValue    = [string]$SenderProfileMinSignals
        HasCurrentValue = $true
        CurrentValue    = [string]$SenderProfileMinSignals
    }
)

foreach ($variable in $variables) {
    Ensure-EnvironmentVariable -Variable $variable
}

# ─────────────────────────────────────
# 4. Summary
# ─────────────────────────────────────
Write-Host "`nEnvironment variable provisioning complete." -ForegroundColor Green
Write-Host "Solution: $SolutionName" -ForegroundColor Green
Write-Host "Organization URL: $OrgUrl" -ForegroundColor Green
Write-Host "Variables provisioned:" -ForegroundColor Green
foreach ($variable in $variables) {
    $currentValueDisplay = if ($variable.HasCurrentValue) { [string]$variable.CurrentValue } else { "(not set)" }
    Write-Host "  - $($variable.SchemaName) = $currentValueDisplay" -ForegroundColor Green
}
