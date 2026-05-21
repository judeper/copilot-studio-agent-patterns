<#
.SYNOPSIS
    Injects the debug logger tool flow GUID into Copilot Studio topic YAML files.
.DESCRIPTION
    Selects a Power Platform environment, queries Dataverse workflows for the
    tool-log-agent-trace cloud flow, replaces {{TOOL_LOG_AGENT_TRACE_FLOW_ID}}
    in copilot-studio\topics\*.topic.mcs.yml, and writes runtime output to
    dist/topics/ for Skills CLI import. Safe to re-run; output files are overwritten.
.PARAMETER EnvironmentId
    Power Platform environment ID to query. Required.
.EXAMPLE
    pwsh .\inject-flow-guid.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "EnvironmentId is required.")]
    [string]$EnvironmentId,
    [string]$ToolFlowDisplayName = "tool-log-agent-trace",
    [string]$Placeholder = "{{TOOL_LOG_AGENT_TRACE_FLOW_ID}}",
    [string]$TopicsDir = "$PSScriptRoot\..\copilot-studio\topics",
    [string]$OutputDir = "$PSScriptRoot\..\dist\topics"
)
$ErrorActionPreference = "Stop"
function ConvertTo-ODataString { param([string]$Value) return $Value.Replace("'", "''") }

# ── 0. Prerequisite Validation ──
Write-Host "`n0. Prerequisite Validation" -ForegroundColor Cyan
if (-not (Get-Command "pac" -ErrorAction SilentlyContinue)) { throw "PAC CLI not found. Install with: dotnet tool install --global Microsoft.PowerApps.CLI.Tool" }
if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) { throw "Azure CLI not found. Install with: winget install Microsoft.AzureCLI" }
$pacVer = (pac --version | Select-String -Pattern '(\d+\.\d+)' | ForEach-Object { $_.Matches[0].Value } | Select-Object -First 1)
if (-not $pacVer -or [Version]$pacVer -lt [Version]"1.32") { throw "PAC CLI >= 1.32 required (found '$pacVer'). Update with: dotnet tool update --global Microsoft.PowerApps.CLI.Tool" }
Write-Host "  PAC CLI version $pacVer OK." -ForegroundColor Green

# ── 1. Resolve Environment + Token ──
Write-Host "`n1. Resolve Environment + Token" -ForegroundColor Cyan
pac auth select --environment $EnvironmentId | Out-Null
if ($LASTEXITCODE -ne 0) { throw "pac auth select failed for environment '$EnvironmentId'. Run 'pac auth create' first, then retry." }
$orgInfoRaw = pac org who --json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $orgInfoRaw) { throw "Unable to read selected org info with 'pac org who --json'." }
$orgInfo = $orgInfoRaw | Out-String | ConvertFrom-Json
$envUrl = @($orgInfo.OrgUrl, $orgInfo.OrganizationUrl, $orgInfo.EnvironmentUrl, $orgInfo.DataverseUrl, $orgInfo.Url) | Where-Object { $_ } | Select-Object -First 1
if (-not $envUrl) { throw "Unable to resolve Dataverse URL after selecting environment '$EnvironmentId'." }
$envUrl = ([string]$envUrl).TrimEnd("/")
$token = az account get-access-token --resource $envUrl --query accessToken -o tsv 2>$null
if (-not $token) { throw "Failed to acquire Dataverse token. Run 'az login' with an account that can customize the target environment, then retry." }
$headers = @{ Authorization = "Bearer $token"; "OData-MaxVersion" = "4.0"; "OData-Version" = "4.0"; Accept = "application/json" }

# ── 2. Query Tool Flow GUID ──
Write-Host "`n2. Query Tool Flow GUID" -ForegroundColor Cyan
$flowName = ConvertTo-ODataString $ToolFlowDisplayName
$filter = "name eq '$flowName' and (category eq 5 or category eq 6)"
$url = "$envUrl/api/data/v9.2/workflows?`$filter=$([uri]::EscapeDataString($filter))&`$select=workflowid,name,modifiedon&`$orderby=modifiedon desc"
$result = Invoke-RestMethod -Method Get -Uri $url -Headers $headers
$matches = @($result.value)
if ($matches.Count -eq 0) { throw "Tool flow '$ToolFlowDisplayName' not found in environment $EnvironmentId. Has scripts/deploy-solution.ps1 been run AND has the tool flow been added as an Action on a consumer agent in Copilot Studio? (PVA-trigger flows are only created on first Action attach.)" }
if ($matches.Count -gt 1) { Write-Warning "$($matches.Count) flows matched '$ToolFlowDisplayName'; using most recent modifiedon $($matches[0].modifiedon)." }
$flowGuid = [string]$matches[0].workflowid
Write-Host "  Tool flow GUID: $flowGuid" -ForegroundColor Green

# ── 3. Substitute Topic YAML Files ──
Write-Host "`n3. Substitute Topic YAML Files" -ForegroundColor Cyan
if (-not (Test-Path $TopicsDir)) { throw "Topics directory not found: $TopicsDir" }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$topicFiles = @(Get-ChildItem -Path $TopicsDir -Filter "*.topic.mcs.yml")
$errors = 0; $substitutedFiles = 0
foreach ($file in $topicFiles) {
    try {
        $content = Get-Content -Raw -Path $file.FullName -Encoding UTF8
        $count = ([regex]::Matches($content, [regex]::Escape($Placeholder))).Count
        $newContent = if ($count -gt 0) { $content.Replace($Placeholder, $flowGuid) } else { $content }
        Set-Content -Path (Join-Path $OutputDir $file.Name) -Value $newContent -Encoding UTF8 -NoNewline
        if ($count -gt 0) { $substitutedFiles++; Write-Host "  ✓ $($file.Name): substituted $count placeholder(s)" -ForegroundColor Green }
        else { Write-Host "  ~ $($file.Name): no placeholder found; copied unchanged" -ForegroundColor DarkGray }
    } catch { $errors++; Write-Host "  ✗ $($file.Name): failed - $($_.Exception.Message)" -ForegroundColor Red }
}
if ($errors -gt 0) { throw "$errors topic file(s) failed during GUID substitution." }
Write-Host "`nProcessed $($topicFiles.Count) topic file(s); $substitutedFiles had substitutions." -ForegroundColor Cyan
Write-Host "Substituted topics written to: $OutputDir" -ForegroundColor Cyan
Write-Host "Import via Skills CLI: skills import-topics --folder $OutputDir" -ForegroundColor Cyan
