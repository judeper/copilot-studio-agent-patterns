<#
.SYNOPSIS
    Provisions the Dataverse table and environment variable for the Copilot Agent Debug Logger.

.DESCRIPTION
    Selects an existing Power Platform environment, creates or reuses the Copilot Agent Debug Logger
    unmanaged solution, provisions the cr_agenttrace Dataverse table from schemas\agenttrace-table.json,
    and provisions the cr_DebugLoggerEnabled Boolean environment variable from
    schemas\debugloggerenabled-envvar.json. All Dataverse writes use idempotent GET-or-CREATE checks.

.PARAMETER EnvironmentId
    Power Platform environment ID to provision. Required.

.PARAMETER PublisherPrefix
    Dataverse publisher customization prefix. Default: "cr".

.PARAMETER SolutionUniqueName
    Unique name for the unmanaged solution that owns the created components. Default: "CopilotAgentDebugLogger".

.PARAMETER TableSchemaPath
    Path to the agent trace table schema JSON. Default: "..\schemas\agenttrace-table.json".

.PARAMETER EnvVarSchemaPath
    Path to the debug logger environment variable schema JSON. Default: "..\schemas\debugloggerenabled-envvar.json".

.EXAMPLE
    pwsh .\provision-environment.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "EnvironmentId is required.")]
    [string]$EnvironmentId,
    [string]$PublisherPrefix = "cr",
    [string]$SolutionUniqueName = "CopilotAgentDebugLogger",
    [string]$TableSchemaPath = "$PSScriptRoot\..\schemas\agenttrace-table.json",
    [string]$EnvVarSchemaPath = "$PSScriptRoot\..\schemas\debugloggerenabled-envvar.json"
)
$ErrorActionPreference = "Stop"
function New-DvLabel {
    param([AllowEmptyString()][string]$Text)
    return @{ "@odata.type" = "Microsoft.Dynamics.CRM.Label"; LocalizedLabels = @(@{ "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"; Label = $Text; LanguageCode = 1033 }) }
}
function Get-JsonPropertyValue { param($Object, [string]$Name, $DefaultValue) if ($Object.PSObject.Properties.Name -contains $Name -and $null -ne $Object.$Name) { return $Object.$Name }; return $DefaultValue }
function New-RequiredLevel { param([bool]$Required) return @{ Value = if ($Required) { "ApplicationRequired" } else { "None" } } }
function ConvertTo-EnvVarString { param($Value) if ($null -eq $Value) { return "" }; if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }; return [string]$Value }
function ConvertTo-ODataString { param([string]$Value) return $Value.Replace("'", "''") }
function Get-ObjectValue {
    param($Object, [string[]]$Names)
    foreach ($name in $Names) { if ($Object.PSObject.Properties.Name -contains $name -and $Object.$name) { return $Object.$name } }
    return $null
}
function New-AttributeMetadata {
    param($Column, [bool]$IsPrimaryName = $false)
    $logicalName = [string]$Column.logicalName
    $displayName = [string]$Column.displayName
    $description = [string](Get-JsonPropertyValue -Object $Column -Name "description" -DefaultValue "")
    $required = [bool](Get-JsonPropertyValue -Object $Column -Name "required" -DefaultValue $false)
    $attribute = @{
        SchemaName = $logicalName
        RequiredLevel = New-RequiredLevel -Required $required
        DisplayName = New-DvLabel -Text $displayName
        Description = New-DvLabel -Text $description
    }
    switch ([string]$Column.type) {
        "Text" {
            $attribute["@odata.type"] = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
            $attribute.MaxLength = [int](Get-JsonPropertyValue -Object $Column -Name "maxLength" -DefaultValue 100)
            if ($IsPrimaryName) { $attribute.IsPrimaryName = $true }
        }
        "MultilineText" {
            $attribute["@odata.type"] = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
            $attribute.MaxLength = [int](Get-JsonPropertyValue -Object $Column -Name "maxLength" -DefaultValue 2000)
        }
        "WholeNumber" {
            $attribute["@odata.type"] = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
            $attribute.Format = "None"
            $attribute.MinValue = [int](Get-JsonPropertyValue -Object $Column -Name "minValue" -DefaultValue -2147483648)
            $attribute.MaxValue = [int](Get-JsonPropertyValue -Object $Column -Name "maxValue" -DefaultValue 2147483647)
        }
        "Choice" {
            $attribute["@odata.type"] = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
            $attribute.OptionSet = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
                IsGlobal = $false
                OptionSetType = "Picklist"
                Options = @($Column.options | ForEach-Object {
                    @{
                        Value = [int]$_.value
                        Label = New-DvLabel -Text ([string]$_.label)
                    }
                })
            }
        }
        "Boolean" {
            $attribute["@odata.type"] = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
            $attribute.DefaultValue = [bool](Get-JsonPropertyValue -Object $Column -Name "defaultValue" -DefaultValue $false)
            $attribute.OptionSet = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.BooleanOptionSetMetadata"
                TrueOption = @{ Value = 1; Label = New-DvLabel -Text "Yes" }
                FalseOption = @{ Value = 0; Label = New-DvLabel -Text "No" }
            }
        }
        "UniqueIdentifier" {
            $attribute["@odata.type"] = "Microsoft.Dynamics.CRM.UniqueIdentifierAttributeMetadata"
        }
        default { throw "Unsupported column type '$($Column.type)' for column '$logicalName'." }
    }
    return $attribute
}
# ─────────────────────────────────────
# 0. Prerequisite Validation
# ─────────────────────────────────────
Write-Host "`n0. Prerequisite Validation" -ForegroundColor Cyan
if (-not (Get-Command "pac" -ErrorAction SilentlyContinue)) { throw "PAC CLI not found. Install with: dotnet tool install --global Microsoft.PowerApps.CLI.Tool" }
if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) { throw "Azure CLI not found. Install with: winget install Microsoft.AzureCLI" }
$pacVer = (pac --version | Select-String -Pattern '(\d+\.\d+)' | ForEach-Object { $_.Matches[0].Value } | Select-Object -First 1)
if (-not $pacVer) { throw "Unable to determine PAC CLI version from 'pac --version'." }
if ([Version]$pacVer -lt [Version]"1.32") { throw "PAC CLI >= 1.32 required (found $pacVer). Update with: dotnet tool update --global Microsoft.PowerApps.CLI.Tool" }
Write-Host "  PAC CLI version $pacVer OK." -ForegroundColor Green
if (-not (Test-Path $TableSchemaPath)) { throw "Table schema not found: $TableSchemaPath" }
if (-not (Test-Path $EnvVarSchemaPath)) { throw "Environment variable schema not found: $EnvVarSchemaPath" }
$tableSchema = Get-Content -Raw $TableSchemaPath | ConvertFrom-Json
$envVarSchema = Get-Content -Raw $EnvVarSchemaPath | ConvertFrom-Json
Write-Host "  Schema files loaded: agenttrace-table.json, debugloggerenabled-envvar.json." -ForegroundColor Green
# ─────────────────────────────────────
# 1. Auth + Environment Selection
# ─────────────────────────────────────
Write-Host "`n1. Auth + Environment Selection" -ForegroundColor Cyan
pac auth select --environment $EnvironmentId | Out-Null
if ($LASTEXITCODE -ne 0) { throw "PAC auth select failed for environment '$EnvironmentId'. Run 'pac auth create' first, then retry." }
Write-Host "  PAC auth selected environment $EnvironmentId." -ForegroundColor Green
# PAC CLI 2.x dropped `pac admin list-environments` (returns "Not a valid command" with
# exit code 0 — must also sniff for JSON-like output, not just exit code).
function Test-LooksLikeJson {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $trimmed = $Text.TrimStart()
    return ($trimmed.StartsWith('[') -or $trimmed.StartsWith('{'))
}
$envListRaw = pac admin list-environments --json 2>$null
$envListText = ($envListRaw | Out-String)
if ($LASTEXITCODE -ne 0 -or -not $envListRaw -or -not (Test-LooksLikeJson -Text $envListText)) {
    $envListRaw = pac admin list --json 2>$null
    $envListText = ($envListRaw | Out-String)
}
if ($LASTEXITCODE -ne 0 -or -not $envListRaw -or -not (Test-LooksLikeJson -Text $envListText)) {
    throw "Unable to list Power Platform environments with PAC CLI."
}
$envList = $envListText | ConvertFrom-Json
$environment = @($envList | Where-Object {
    (Get-ObjectValue -Object $_ -Names @("EnvironmentId", "Environment ID", "EnvironmentName", "Name", "environmentid", "id")) -eq $EnvironmentId
}) | Select-Object -First 1
if (-not $environment) { throw "Environment '$EnvironmentId' was not found in 'pac admin list-environments'." }
Write-Host "  Environment found in PAC admin list." -ForegroundColor Green
# ─────────────────────────────────────
# 2. Resolve Environment URL
# ─────────────────────────────────────
Write-Host "`n2. Resolve Environment URL" -ForegroundColor Cyan
$envUrl = Get-ObjectValue -Object $environment -Names @("EnvironmentUrl", "Environment URL", "Url", "OrganizationUrl", "DataverseUrl", "LinkedEnvironmentUrl")
if (-not $envUrl) {
    $authListRaw = pac auth list --json 2>$null
    if ($LASTEXITCODE -eq 0 -and $authListRaw) {
        $authList = $authListRaw | Out-String | ConvertFrom-Json
        $selectedAuth = @($authList | Where-Object {
            (Get-ObjectValue -Object $_ -Names @("EnvironmentId", "Environment ID", "environmentid", "ActiveEnvironment")) -eq $EnvironmentId -or
            (Get-ObjectValue -Object $_ -Names @("Selected", "IsActive", "Active")) -eq $true
        }) | Select-Object -First 1
        if ($selectedAuth) { $envUrl = Get-ObjectValue -Object $selectedAuth -Names @("EnvironmentUrl", "Environment URL", "Url", "OrganizationUrl", "DataverseUrl") }
    }
}
if (-not $envUrl) {
    $envShowRaw = pac admin show --environment $EnvironmentId --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $envShowRaw) { $envShowRaw = pac admin details --environment $EnvironmentId --json 2>$null }
    if ($LASTEXITCODE -eq 0 -and $envShowRaw) {
        $envShow = $envShowRaw | Out-String | ConvertFrom-Json
        $envUrl = Get-ObjectValue -Object $envShow -Names @("EnvironmentUrl", "Environment URL", "Url", "OrganizationUrl", "DataverseUrl")
    }
}
if (-not $envUrl) { throw "Unable to resolve Dataverse environment URL for '$EnvironmentId'." }
$envUrl = ([string]$envUrl).TrimEnd("/")
Write-Host "  Environment URL: $envUrl" -ForegroundColor Green
# ─────────────────────────────────────
# 3. Acquire Dataverse Web API Token
# ─────────────────────────────────────
Write-Host "`n3. Acquire Dataverse Web API Token" -ForegroundColor Cyan
$token = az account get-access-token --resource $envUrl --query accessToken -o tsv 2>$null
if (-not $token) {
    Write-Host "  WARNING: Azure CLI has no cached Dataverse token for this environment." -ForegroundColor Red
    throw "Failed to acquire Dataverse token. Run 'az login' with an account that can customize the target environment, then retry."
}
Write-Host "  Dataverse access token acquired." -ForegroundColor Green
# ─────────────────────────────────────
# 4. Build `$headers and `$apiBase
# ─────────────────────────────────────
Write-Host "`n4. Build headers and apiBase" -ForegroundColor Cyan
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version" = "4.0"
}
$solutionHeaders = $headers.Clone()
$solutionHeaders["MSCRM.SolutionUniqueName"] = $SolutionUniqueName
$apiBase = "$envUrl/api/data/v9.2"
Write-Host "  API base: $apiBase" -ForegroundColor Green
$script:apiCallCounter = 0
function Refresh-TokenIfNeeded {
    $script:apiCallCounter++
    if ($script:apiCallCounter % 20 -eq 0) {
        Write-Host "  Refreshing Dataverse token after $($script:apiCallCounter) API calls..." -ForegroundColor Yellow
        $freshToken = az account get-access-token --resource $envUrl --query accessToken -o tsv 2>$null
        if (-not $freshToken) { throw "Failed to refresh Dataverse token." }
        $headers["Authorization"] = "Bearer $freshToken"
        $solutionHeaders["Authorization"] = "Bearer $freshToken"
    }
}
function Invoke-DvGet {
    param([string]$Uri)
    Refresh-TokenIfNeeded
    return Invoke-RestMethod -Uri $Uri -Headers $headers -Method Get
}
function Invoke-DvPost {
    param([string]$Uri, [string]$Body, [switch]$InSolution)
    Refresh-TokenIfNeeded
    $postHeaders = if ($InSolution) { $solutionHeaders } else { $headers }
    return Invoke-RestMethod -Uri $Uri -Headers $postHeaders -Method Post -Body $Body
}
function Get-EntityMetadataWithRetry {
    param([string]$LogicalName, [int]$MaxAttempts = 6, [int]$DelaySeconds = 10)
    $escapedName = ConvertTo-ODataString -Value $LogicalName
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try { return Invoke-DvGet -Uri "$apiBase/EntityDefinitions(LogicalName='$escapedName')" }
        catch {
            if ($i -eq $MaxAttempts) { throw "Entity '$LogicalName' not found after $MaxAttempts attempts: $($_.Exception.Message)" }
            Write-Host "  Waiting for '$LogicalName' metadata to propagate... attempt $i/$MaxAttempts" -ForegroundColor Yellow
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}
function Test-AttributeExists {
    param([string]$EntityId, [string]$LogicalName)
    $escapedName = ConvertTo-ODataString -Value $LogicalName
    try {
        $null = Invoke-DvGet -Uri "$apiBase/EntityDefinitions($EntityId)/Attributes(LogicalName='$escapedName')?`$select=MetadataId,LogicalName"
        return $true
    } catch { return $false }
}
# ─────────────────────────────────────
# 5. Ensure Publisher cr Exists
# ─────────────────────────────────────
Write-Host "`n5. Ensure Publisher $PublisherPrefix Exists" -ForegroundColor Cyan
$createdCount = 0
$reusedCount = 0
$publisherPrefixFilter = ConvertTo-ODataString -Value $PublisherPrefix
$publisherResult = Invoke-DvGet -Uri "$apiBase/publishers?`$filter=customizationprefix eq '$publisherPrefixFilter'&`$select=publisherid,uniquename,friendlyname,customizationprefix"
if (@($publisherResult.value).Count -gt 0) {
    $publisher = $publisherResult.value[0]
    $reusedCount++
    Write-Host "  Publisher '$PublisherPrefix' already exists — reusing $($publisher.publisherid)." -ForegroundColor Yellow
} else {
    $publisherBody = @{
        uniquename = $PublisherPrefix
        friendlyname = "Copilot Agent Debug Logger Publisher"
        customizationprefix = $PublisherPrefix
        customizationoptionvalueprefix = 10000
        description = "Publisher for the Copilot Agent Debug Logger solution."
    } | ConvertTo-Json -Depth 10
    Invoke-DvPost -Uri "$apiBase/publishers" -Body $publisherBody | Out-Null
    $publisherResult = Invoke-DvGet -Uri "$apiBase/publishers?`$filter=customizationprefix eq '$publisherPrefixFilter'&`$select=publisherid,uniquename,friendlyname,customizationprefix"
    $publisher = $publisherResult.value[0]
    $createdCount++
    Write-Host "  Publisher '$PublisherPrefix' created: $($publisher.publisherid)." -ForegroundColor Green
}
$publisherId = $publisher.publisherid
# ─────────────────────────────────────
# 6. Ensure Solution CopilotAgentDebugLogger Exists
# ─────────────────────────────────────
Write-Host "`n6. Ensure Solution $SolutionUniqueName Exists" -ForegroundColor Cyan
$solutionNameFilter = ConvertTo-ODataString -Value $SolutionUniqueName
$solutionResult = Invoke-DvGet -Uri "$apiBase/solutions?`$filter=uniquename eq '$solutionNameFilter'&`$select=solutionid,uniquename,friendlyname"
if (@($solutionResult.value).Count -gt 0) {
    $solution = $solutionResult.value[0]
    $reusedCount++
    Write-Host "  Solution '$SolutionUniqueName' already exists — reusing $($solution.solutionid)." -ForegroundColor Yellow
} else {
    $solutionBody = @{
        uniquename = $SolutionUniqueName
        friendlyname = "Copilot Agent Debug Logger"
        description = "Copilot Agent Debug Logger - trace table, environment variable, flows, and app components."
        version = "1.0.0.0"
        "publisherid@odata.bind" = "/publishers($publisherId)"
    } | ConvertTo-Json -Depth 10
    Invoke-DvPost -Uri "$apiBase/solutions" -Body $solutionBody | Out-Null
    $solutionResult = Invoke-DvGet -Uri "$apiBase/solutions?`$filter=uniquename eq '$solutionNameFilter'&`$select=solutionid,uniquename,friendlyname"
    $solution = $solutionResult.value[0]
    $createdCount++
    Write-Host "  Unmanaged solution '$SolutionUniqueName' created: $($solution.solutionid)." -ForegroundColor Green
}
# ─────────────────────────────────────
# 7. Create cr_agenttrace Table
# ─────────────────────────────────────
Write-Host "`n7. Create cr_agenttrace Table" -ForegroundColor Cyan
$tableLogicalName = [string]$tableSchema.tableName
$primaryColumnName = [string]$tableSchema.primaryColumn
$primaryColumn = @($tableSchema.columns | Where-Object { $_.logicalName -eq $primaryColumnName }) | Select-Object -First 1
if (-not $primaryColumn) { throw "Primary column '$primaryColumnName' was not found in $TableSchemaPath." }
try {
    $entityMetadata = Invoke-DvGet -Uri "$apiBase/EntityDefinitions(LogicalName='$tableLogicalName')"
    $reusedCount++
    Write-Host "  Table '$tableLogicalName' already exists — reusing $($entityMetadata.MetadataId)." -ForegroundColor Yellow
} catch {
    $entityDef = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName = $tableLogicalName
        DisplayName = New-DvLabel -Text ([string]$tableSchema.displayName)
        DisplayCollectionName = New-DvLabel -Text ([string]$tableSchema.pluralName)
        Description = New-DvLabel -Text ([string]$tableSchema.description)
        OwnershipType = [string]$tableSchema.ownershipType
        HasNotes = $false
        HasActivities = $false
        PrimaryNameAttribute = $primaryColumnName
        Attributes = @(New-AttributeMetadata -Column $primaryColumn -IsPrimaryName $true)
    } | ConvertTo-Json -Depth 20
    Invoke-DvPost -Uri "$apiBase/EntityDefinitions" -Body $entityDef -InSolution | Out-Null
    $entityMetadata = Get-EntityMetadataWithRetry -LogicalName $tableLogicalName
    $createdCount++
    Write-Host "  Table '$tableLogicalName' created: $($entityMetadata.MetadataId)." -ForegroundColor Green
}
$entityId = $entityMetadata.MetadataId
foreach ($column in $tableSchema.columns) {
    $logicalName = [string]$column.logicalName
    if (Test-AttributeExists -EntityId $entityId -LogicalName $logicalName) {
        $reusedCount++
        Write-Host "  Column '$logicalName' already exists — reusing." -ForegroundColor Yellow
        continue
    }
    if ($logicalName -eq $primaryColumnName) { throw "Primary name attribute '$logicalName' is missing; recreate the table so it can be set during EntityDefinitions POST." }
    # Dataverse auto-creates the primary key (<tablename>id) as a UniqueIdentifier when the
    # table is created (CreateRequest API). Custom UniqueIdentifier columns CANNOT be added
    # via the SDK / Web API (Dataverse rejects with 0x80040203). Skip the schema-documented
    # PK entry; the platform-managed PK is queryable via the auto-created <tablename>id
    # attribute (e.g. cr_agenttraceid).
    if ([string]$column.type -eq "UniqueIdentifier") {
        Write-Host "  Column '$logicalName' (UniqueIdentifier) skipped — Dataverse manages the PK as $($tableLogicalName)id automatically." -ForegroundColor DarkGray
        continue
    }
    $columnBody = New-AttributeMetadata -Column $column | ConvertTo-Json -Depth 20
    Invoke-DvPost -Uri "$apiBase/EntityDefinitions($entityId)/Attributes" -Body $columnBody -InSolution | Out-Null
    $createdCount++
    Write-Host "  Column '$logicalName' created." -ForegroundColor Green
}
# ─────────────────────────────────────
# 8. Create cr_DebugLoggerEnabled Environment Variable
# ─────────────────────────────────────
Write-Host "`n8. Create cr_DebugLoggerEnabled Environment Variable" -ForegroundColor Cyan
$envVarSchemaName = [string]$envVarSchema.schemaName
$envVarNameFilter = ConvertTo-ODataString -Value $envVarSchemaName
$envVarType = switch ([string]$envVarSchema.type) {
    "String" { 100000000 }
    "Number" { 100000001 }
    "Boolean" { 100000002 }
    "JSON" { 100000003 }
    "DataSource" { 100000004 }
    "Secret" { 100000005 }
    default { throw "Unsupported environment variable type '$($envVarSchema.type)'." }
}
$defaultValue = ConvertTo-EnvVarString -Value $envVarSchema.defaultValue
$currentValue = ConvertTo-EnvVarString -Value (Get-JsonPropertyValue -Object $envVarSchema -Name "currentValue" -DefaultValue $envVarSchema.defaultValue)
$isRequired = [bool](Get-JsonPropertyValue -Object $envVarSchema -Name "isRequired" -DefaultValue $false)
$definitionResult = Invoke-DvGet -Uri "$apiBase/environmentvariabledefinitions?`$filter=schemaname eq '$envVarNameFilter'&`$select=environmentvariabledefinitionid,schemaname,defaultvalue,type"
if (@($definitionResult.value).Count -gt 0) {
    $definition = $definitionResult.value[0]
    $reusedCount++
    Write-Host "  Environment variable definition '$envVarSchemaName' already exists — reusing $($definition.environmentvariabledefinitionid)." -ForegroundColor Yellow
} else {
    $definitionBody = @{
        schemaname = $envVarSchemaName
        displayname = [string]$envVarSchema.displayName
        description = [string]$envVarSchema.description
        type = $envVarType
        defaultvalue = $defaultValue
        isrequired = $isRequired
    } | ConvertTo-Json -Depth 10
    Invoke-DvPost -Uri "$apiBase/environmentvariabledefinitions" -Body $definitionBody -InSolution | Out-Null
    $definitionResult = Invoke-DvGet -Uri "$apiBase/environmentvariabledefinitions?`$filter=schemaname eq '$envVarNameFilter'&`$select=environmentvariabledefinitionid,schemaname,defaultvalue,type"
    $definition = $definitionResult.value[0]
    $createdCount++
    Write-Host "  Environment variable definition '$envVarSchemaName' created: $($definition.environmentvariabledefinitionid)." -ForegroundColor Green
}
$definitionId = $definition.environmentvariabledefinitionid
$valueResult = Invoke-DvGet -Uri "$apiBase/environmentvariablevalues?`$filter=_environmentvariabledefinitionid_value eq $definitionId&`$select=environmentvariablevalueid,value"
if (@($valueResult.value).Count -gt 0) {
    $valueRow = $valueResult.value[0]
    $reusedCount++
    Write-Host "  Environment variable current value already exists — reusing $($valueRow.environmentvariablevalueid)." -ForegroundColor Yellow
} else {
    $valueBody = @{
        "EnvironmentVariableDefinitionId@odata.bind" = "/environmentvariabledefinitions($definitionId)"
        value = $currentValue
    } | ConvertTo-Json -Depth 10
    Invoke-DvPost -Uri "$apiBase/environmentvariablevalues" -Body $valueBody -InSolution | Out-Null
    $valueResult = Invoke-DvGet -Uri "$apiBase/environmentvariablevalues?`$filter=_environmentvariabledefinitionid_value eq $definitionId&`$select=environmentvariablevalueid,value"
    $valueRow = $valueResult.value[0]
    $createdCount++
    Write-Host "  Environment variable current value created: $($valueRow.environmentvariablevalueid)." -ForegroundColor Green
}
$envVarCurrentValue = if ($valueRow -and $null -ne $valueRow.value) { $valueRow.value } else { $definition.defaultvalue }
# ─────────────────────────────────────
# 9. Summary Output
# ─────────────────────────────────────
Write-Host "`n9. Summary Output" -ForegroundColor Cyan
Write-Host "  Environment URL: $envUrl" -ForegroundColor Green
Write-Host "  Table ID ($tableLogicalName): $entityId" -ForegroundColor Green
Write-Host "  Environment variable ID ($envVarSchemaName): $definitionId" -ForegroundColor Green
Write-Host "  Environment variable current value: $envVarCurrentValue" -ForegroundColor Green
Write-Host "  Created components: $createdCount" -ForegroundColor Green
Write-Host "  Reused/skipped components: $reusedCount" -ForegroundColor Yellow
Write-Host "`nProvisioning complete. Run pwsh scripts\deploy-solution.ps1 -EnvironmentId $EnvironmentId next." -ForegroundColor Green
Write-Host "To enable the logger, flip cr_DebugLoggerEnabled to true in Power Apps maker portal → Solutions → Copilot Agent Debug Logger → Environment variables." -ForegroundColor Green
Write-Host "See docs\deployment-guide.md for the full deployment walkthrough." -ForegroundColor Green
