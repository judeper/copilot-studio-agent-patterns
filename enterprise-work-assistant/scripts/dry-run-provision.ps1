$ErrorActionPreference = "Stop"
$OrgUrl = "https://orgfeaa0fa5.crm.dynamics.com"
$PublisherPrefix = "cr"
$TenantId = (az account show --query tenantId -o tsv)

# Get token
$token = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
if (-not $token) { throw "Failed to get token" }

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version" = "4.0"
}
$apiBase = "$OrgUrl/api/data/v9.2"

# Token refresh helper
$script:apiCallCounter = 0
function Refresh-TokenIfNeeded {
    $script:apiCallCounter++
    if ($script:apiCallCounter % 20 -eq 0) {
        Write-Host "  Refreshing token..." -ForegroundColor Yellow
        $freshToken = az account get-access-token --resource $OrgUrl --query accessToken -o tsv
        if ($freshToken) { $script:token = $freshToken; $headers["Authorization"] = "Bearer $freshToken" }
    }
}

Write-Host "Connected to $OrgUrl" -ForegroundColor Green
Write-Host "Starting table provisioning..." -ForegroundColor Cyan

# Read the provisioning script from line 103 onwards (skip env creation, start at table creation)
$provScript = Get-Content "C:\Dev\copilot-studio-agent-patterns\enterprise-work-assistant\scripts\provision-environment.ps1" -Raw
# Extract everything from "# 3. Create AssistantCards" to end
$startMarker = "# 3. Create AssistantCards Table via Dataverse Web API"
$startIdx = $provScript.IndexOf($startMarker)
if ($startIdx -lt 0) { throw "Could not find table provisioning section" }

# Remove the Azure CLI login section (we're already authenticated)
$tableProvision = $provScript.Substring($startIdx)
$tableProvision = $tableProvision -replace 'Write-Host "Authenticating Azure CLI.*?\n', ''
$tableProvision = $tableProvision -replace 'az login --tenant \$TenantId\n', ''
$tableProvision = $tableProvision -replace 'if \(\$LASTEXITCODE -ne 0\) \{ throw "Azure CLI login.*?\n', ''
$tableProvision = $tableProvision -replace '\$token = az account get-access-token.*?\n', ''
$tableProvision = $tableProvision -replace 'if \(-not \$token\).*?\n', ''
$tableProvision = $tableProvision -replace '\$headers = @\{[\s\S]*?\}', ''
$tableProvision = $tableProvision -replace '\$apiBase = .*?\n', ''

Write-Host "Extracted provisioning block ($($tableProvision.Length) chars)" -ForegroundColor Yellow
# Execute
Invoke-Expression $tableProvision
