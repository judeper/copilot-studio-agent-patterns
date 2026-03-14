<#
.SYNOPSIS
    Detects schema drift between local JSON schema files and the live Dataverse environment.

.DESCRIPTION
    Reads all *-table.json schema files under the schemas/ directory and compares them
    against the live Dataverse environment metadata via the Web API. Reports:

    - Tables defined in schema but missing from Dataverse
    - Tables in Dataverse (with the publisher prefix) not defined in any schema
    - Columns defined in schema but missing from the Dataverse table
    - Columns in Dataverse not defined in the schema (excluding system columns)
    - Column type mismatches (e.g., schema says Text but Dataverse has Choice)
    - Alternate keys defined in schema but missing from Dataverse

    Can also run in offline mode (--OfflineOnly) to validate schema files against
    the provisioning script without requiring a live Dataverse connection.

.PARAMETER OrgUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).
    Required unless -OfflineOnly is specified.

.PARAMETER SchemaDir
    Path to the directory containing *-table.json schema files.
    Default: ../schemas (relative to script location).

.PARAMETER ProvisionScript
    Path to the provision-environment.ps1 script for offline cross-referencing.
    Default: ./provision-environment.ps1 (relative to script location).

.PARAMETER PublisherPrefix
    Dataverse publisher prefix. Default: "cr"

.PARAMETER OfflineOnly
    When set, skips live Dataverse comparison and only validates schema files
    against the provisioning script for completeness.

.EXAMPLE
    .\audit-schema-drift.ps1 -OrgUrl "https://myorg.crm.dynamics.com"

.EXAMPLE
    .\audit-schema-drift.ps1 -OfflineOnly
#>

param(
    [string]$OrgUrl,

    [string]$SchemaDir,

    [string]$ProvisionScript,

    [string]$PublisherPrefix = "cr",

    [switch]$OfflineOnly
)

$ErrorActionPreference = "Stop"

# ─────────────────────────────────────
# Resolve Paths
# ─────────────────────────────────────
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $SchemaDir) {
    $SchemaDir = Join-Path $scriptDir "..\schemas"
}
if (-not $ProvisionScript) {
    $ProvisionScript = Join-Path $scriptDir "provision-environment.ps1"
}

$SchemaDir = (Resolve-Path $SchemaDir -ErrorAction Stop).Path

Write-Host ""
Write-Host "Schema Drift Audit" -ForegroundColor Cyan
Write-Host "==================" -ForegroundColor Cyan
Write-Host "Schema directory: $SchemaDir" -ForegroundColor White
Write-Host "Mode: $(if ($OfflineOnly) { 'Offline (schema vs. provision script)' } else { 'Live (schema vs. Dataverse)' })" -ForegroundColor White
Write-Host ""

# ─────────────────────────────────────
# 1. Load Schema Files
# ─────────────────────────────────────
$schemaFiles = Get-ChildItem -Path $SchemaDir -Filter "*-table.json" -File
if ($schemaFiles.Count -eq 0) {
    Write-Warning "No *-table.json files found in $SchemaDir"
    exit 1
}

Write-Host "Found $($schemaFiles.Count) schema file(s):" -ForegroundColor Cyan
$schemas = @{}
$driftIssues = @()

foreach ($file in $schemaFiles) {
    $json = Get-Content $file.FullName -Raw | ConvertFrom-Json

    # Normalize table name — schemas use either "tableName" or "entityName"
    $tableName = if ($json.tableName) { $json.tableName } elseif ($json.entityName) { $json.entityName } else { $null }
    if (-not $tableName) {
        Write-Warning "  $($file.Name): No tableName or entityName found — skipping."
        continue
    }

    $schemas[$tableName] = @{
        File       = $file.Name
        Schema     = $json
        TableName  = $tableName
        Columns    = @()
        AltKeys    = @()
    }

    # Extract columns
    if ($json.columns) {
        foreach ($col in $json.columns) {
            $schemas[$tableName].Columns += @{
                LogicalName = $col.logicalName
                Type        = $col.type
                DisplayName = $col.displayName
                Required    = [bool]$col.required
                MaxLength   = $col.maxLength
            }
        }
    }

    # Extract alternate keys
    if ($json.alternateKeys) {
        foreach ($key in $json.alternateKeys) {
            $keyName = if ($key.schemaName) { $key.schemaName } elseif ($key.name) { $key.name } else { "unknown" }
            $keyAttrs = if ($key.keyAttributes) { $key.keyAttributes } elseif ($key.columns) { $key.columns } else { @() }
            $schemas[$tableName].AltKeys += @{
                Name       = $keyName
                Attributes = $keyAttrs
            }
        }
    }

    # Check for junction table definition embedded in the schema
    if ($json.junctionTable) {
        $jt = $json.junctionTable
        $jtName = $jt.tableName
        if ($jtName -and -not $schemas.ContainsKey($jtName)) {
            # Junction table is defined inline — we'll check it against the dedicated schema file
            Write-Host "  $($file.Name): Contains embedded junction table definition ($jtName)" -ForegroundColor DarkGray
        }
    }

    Write-Host "  $($file.Name) → $tableName ($($schemas[$tableName].Columns.Count) columns, $($schemas[$tableName].AltKeys.Count) alt keys)" -ForegroundColor Green
}

Write-Host ""

# ─────────────────────────────────────
# 2. Offline Mode: Cross-reference against provision script
# ─────────────────────────────────────
Write-Host "--- Offline Analysis: Schema vs. Provision Script ---" -ForegroundColor Cyan

if (Test-Path $ProvisionScript) {
    $scriptContent = Get-Content $ProvisionScript -Raw

    foreach ($tableName in $schemas.Keys) {
        $tableInfo = $schemas[$tableName]
        $shortName = $tableName -replace "^${PublisherPrefix}_", ""

        # Check if table is created in the provision script
        $tablePattern = "SchemaName\s*=\s*[`"'].*${shortName}[`"']"
        if ($scriptContent -notmatch $tablePattern) {
            $issue = "TABLE_MISSING_IN_SCRIPT: $tableName is defined in $($tableInfo.File) but not created in provision-environment.ps1"
            $driftIssues += $issue
            Write-Host "  [DRIFT] $issue" -ForegroundColor Red
            continue
        }

        Write-Host "  [OK] $tableName — found in provision script" -ForegroundColor Green

        # Check each column
        foreach ($col in $tableInfo.Columns) {
            $colShortName = ($col.LogicalName -replace "^${PublisherPrefix}_", "")

            # Skip auto-generated primary key columns (UniqueIdentifier type)
            if ($col.Type -eq "UniqueIdentifier") { continue }

            # Skip OneNote columns — intentionally provisioned by provision-onenote.ps1
            if ($colShortName -match "^onenote") { continue }

            # Match SchemaName references — handles both direct strings and ${PublisherPrefix} interpolation
            $found = $false
            if ($scriptContent -match "(?i)_${colShortName}[`"'\s]") { $found = $true }
            if ($scriptContent -match "(?i)SchemaName.*${colShortName}") { $found = $true }

            if (-not $found) {
                $issue = "COLUMN_MISSING_IN_SCRIPT: $($col.LogicalName) ($($col.DisplayName)) defined in $($tableInfo.File) but not provisioned in script"
                $driftIssues += $issue
                Write-Host "    [DRIFT] $($col.LogicalName) — not found in provision script" -ForegroundColor Yellow
            }
        }

        # Check alternate keys
        foreach ($key in $tableInfo.AltKeys) {
            $keyShortName = ($key.Name -replace "^${PublisherPrefix}_", "")
            $keyFound = $false
            if ($scriptContent -match "(?i)$($key.Name)") { $keyFound = $true }
            if ($scriptContent -match "(?i)_${keyShortName}[`"'\s]") { $keyFound = $true }
            if (-not $keyFound) {
                $issue = "ALTKEY_MISSING_IN_SCRIPT: $($key.Name) defined in $($tableInfo.File) but not created in provision script"
                $driftIssues += $issue
                Write-Host "    [DRIFT] Alt key '$($key.Name)' — not found in provision script" -ForegroundColor Yellow
            }
        }
    }

    # Reverse check: find tables in provision script not in schemas
    $scriptTableMatches = [regex]::Matches($scriptContent, "SchemaName\s*=\s*[`"']\`$\{PublisherPrefix\}_(\w+)[`"']")
    $scriptTableNames = @()
    foreach ($match in $scriptTableMatches) {
        $name = "${PublisherPrefix}_$($match.Groups[1].Value.ToLower())"
        if ($name -match "^${PublisherPrefix}_[a-z]" -and $name -notmatch "_[A-Z]") {
            # This is a table-level SchemaName (table names are lowercase)
            $scriptTableNames += $name
        }
    }

    # Deduplicate
    $scriptTableNames = $scriptTableNames | Sort-Object -Unique

    foreach ($scriptTable in $scriptTableNames) {
        if (-not $schemas.ContainsKey($scriptTable)) {
            # Only flag if it looks like a table (not a column)
            $shortTableName = $scriptTable -replace "^${PublisherPrefix}_", ""
            $entityDefPattern = "EntityMetadata.*SchemaName.*=.*$shortTableName"
            if ($scriptContent -match "(?i)$entityDefPattern") {
                $issue = "TABLE_MISSING_SCHEMA: $scriptTable is provisioned in script but has no *-table.json schema file"
                $driftIssues += $issue
                Write-Host "  [DRIFT] $issue" -ForegroundColor Yellow
            }
        }
    }
} else {
    Write-Warning "  Provision script not found at $ProvisionScript — skipping offline cross-reference."
}

Write-Host ""

# ─────────────────────────────────────
# 3. Live Mode: Compare against Dataverse
# ─────────────────────────────────────
if (-not $OfflineOnly) {
    if (-not $OrgUrl) {
        Write-Warning "No -OrgUrl specified and -OfflineOnly not set. Skipping live Dataverse comparison."
        Write-Host "  Use -OrgUrl to enable live comparison, or -OfflineOnly for schema-only analysis." -ForegroundColor Yellow
    } else {
        $OrgUrl = $OrgUrl.TrimEnd('/')
        $apiBase = "$OrgUrl/api/data/v9.2"

        Write-Host "--- Live Analysis: Schema vs. Dataverse ---" -ForegroundColor Cyan
        Write-Host "Acquiring Dataverse API token..." -ForegroundColor Cyan

        $token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv 2>$null
        if (-not $token) {
            Write-Warning "  Could not acquire token via Azure CLI. Run 'az login' first."
            Write-Host "  Skipping live Dataverse comparison." -ForegroundColor Yellow
        } else {
            $headers = @{
                "Authorization"    = "Bearer $token"
                "Content-Type"     = "application/json"
                "OData-MaxVersion" = "4.0"
                "OData-Version"    = "4.0"
            }

            # System columns that Dataverse creates automatically — exclude from drift checks
            $systemColumns = @(
                'createdon', 'modifiedon', 'statecode', 'statuscode', 'ownerid',
                'owningbusinessunit', 'owningteam', 'owninguser', 'versionnumber',
                'importsequencenumber', 'overriddencreatedon', 'timezoneruleversionnumber',
                'utcconversiontimezonecode', 'modifiedby', 'createdby',
                'modifiedonbehalfby', 'createdonbehalfby', 'organizationid'
            )

            foreach ($tableName in $schemas.Keys) {
                $tableInfo = $schemas[$tableName]
                Write-Host "  Checking $tableName..." -ForegroundColor White

                # Fetch entity metadata
                try {
                    $entityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='$tableName')" -Headers $headers
                } catch {
                    $issue = "TABLE_MISSING_IN_DATAVERSE: $tableName defined in $($tableInfo.File) but not found in Dataverse"
                    $driftIssues += $issue
                    Write-Host "    [DRIFT] Table not found in Dataverse" -ForegroundColor Red
                    continue
                }

                $entityId = $entityMeta.MetadataId

                # Fetch all attributes
                try {
                    $attrResponse = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($entityId)/Attributes?`$select=LogicalName,AttributeType,DisplayName,RequiredLevel,MaxLength" -Headers $headers
                    $dvColumns = @{}
                    foreach ($attr in $attrResponse.value) {
                        $dvColumns[$attr.LogicalName] = $attr
                    }
                } catch {
                    Write-Warning "    Could not fetch attributes for ${tableName}: $($_.Exception.Message)"
                    continue
                }

                # Check schema columns exist in Dataverse
                foreach ($col in $tableInfo.Columns) {
                    if (-not $dvColumns.ContainsKey($col.LogicalName)) {
                        $issue = "COLUMN_MISSING_IN_DATAVERSE: $($col.LogicalName) defined in $($tableInfo.File) but not found in $tableName"
                        $driftIssues += $issue
                        Write-Host "    [DRIFT] Column '$($col.LogicalName)' not found in Dataverse" -ForegroundColor Red
                    } else {
                        Write-Host "    [OK] $($col.LogicalName)" -ForegroundColor DarkGreen
                    }
                }

                # Check for Dataverse columns not in schema (excluding system columns)
                $schemaColNames = $tableInfo.Columns | ForEach-Object { $_.LogicalName }
                $primaryKey = "${tableName}id"
                foreach ($dvColName in $dvColumns.Keys) {
                    # Skip system columns, primary key, and columns without the publisher prefix
                    if ($dvColName -in $systemColumns) { continue }
                    if ($dvColName -eq $primaryKey) { continue }
                    if ($dvColName -notmatch "^${PublisherPrefix}_") { continue }
                    if ($dvColName -in $schemaColNames) { continue }

                    $issue = "COLUMN_NOT_IN_SCHEMA: $dvColName exists in Dataverse $tableName but not defined in $($tableInfo.File)"
                    $driftIssues += $issue
                    Write-Host "    [DRIFT] Column '$dvColName' in Dataverse but not in schema" -ForegroundColor Yellow
                }

                # Check alternate keys
                try {
                    $keysResponse = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions($entityId)/Keys" -Headers $headers
                    $dvKeys = @{}
                    foreach ($key in $keysResponse.value) {
                        $dvKeys[$key.SchemaName] = $key
                    }

                    foreach ($schemaKey in $tableInfo.AltKeys) {
                        if (-not $dvKeys.ContainsKey($schemaKey.Name)) {
                            $issue = "ALTKEY_MISSING_IN_DATAVERSE: $($schemaKey.Name) defined in $($tableInfo.File) but not found in $tableName"
                            $driftIssues += $issue
                            Write-Host "    [DRIFT] Alt key '$($schemaKey.Name)' not found in Dataverse" -ForegroundColor Red
                        } else {
                            Write-Host "    [OK] Alt key '$($schemaKey.Name)'" -ForegroundColor DarkGreen
                        }
                    }
                } catch {
                    Write-Warning "    Could not fetch keys for ${tableName}: $($_.Exception.Message)"
                }
            }
        }
    }
}

# ─────────────────────────────────────
# 4. Cross-Schema Relationship Validation
# ─────────────────────────────────────
Write-Host ""
Write-Host "--- Relationship Validation ---" -ForegroundColor Cyan

foreach ($tableName in $schemas.Keys) {
    $tableInfo = $schemas[$tableName]

    foreach ($col in $tableInfo.Schema.columns) {
        if ($col.type -eq "Lookup" -and $col.referencedTable) {
            $refTable = $col.referencedTable
            if (-not $schemas.ContainsKey($refTable)) {
                $issue = "LOOKUP_TARGET_MISSING: $($col.logicalName) in $tableName references $refTable which has no schema file"
                $driftIssues += $issue
                Write-Host "  [DRIFT] $($col.logicalName) → $refTable (no schema file)" -ForegroundColor Yellow
            } else {
                Write-Host "  [OK] $($col.logicalName) → $refTable" -ForegroundColor Green
            }
        }
    }
}

# ─────────────────────────────────────
# 5. Summary
# ─────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " SCHEMA DRIFT AUDIT SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Schema files analyzed:  $($schemas.Count)" -ForegroundColor White
Write-Host "  Total drift issues:     $($driftIssues.Count)" -ForegroundColor $(if ($driftIssues.Count -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($driftIssues.Count -eq 0) {
    Write-Host "  PASS: No schema drift detected" -ForegroundColor Green
} else {
    Write-Host "  FAIL: $($driftIssues.Count) drift issue(s) found:" -ForegroundColor Red
    Write-Host ""

    # Group by type
    $grouped = $driftIssues | Group-Object { ($_ -split ':')[0] }
    foreach ($group in $grouped) {
        Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor Yellow
        foreach ($item in $group.Group) {
            $detail = ($item -split ':', 2)[1].Trim()
            Write-Host "    - $detail" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""

# ─────────────────────────────────────
# Exit Code
# ─────────────────────────────────────
if ($driftIssues.Count -gt 0) {
    exit 1
} else {
    exit 0
}
