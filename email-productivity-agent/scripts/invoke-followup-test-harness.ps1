[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [Parameter(Mandatory = $true)]
    [string]$TrackingId,

    [string]$FlowDisplayName = "EPA - Flow 8: Follow-Up Test Harness",

    [switch]$ForceNudge,

    [int]$TimeoutSeconds = 90,

    [int]$PollIntervalSeconds = 5
)

$ErrorActionPreference = "Stop"

function Get-AzCliToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Resource
    )

    $token = az account get-access-token --resource $Resource --query accessToken -o tsv 2>$null
    if (-not $token) {
        throw "Failed to acquire Azure CLI token for resource: $Resource. Run 'az login' first."
    }

    return $token
}

$flowToken = Get-AzCliToken -Resource "https://service.flow.microsoft.com/"
$flowHeaders = @{
    Authorization = "Bearer $flowToken"
    Accept        = "application/json"
    "x-ms-client-scope" = "/providers/Microsoft.ProcessSimple/environments/$EnvironmentId"
}

$flowApiBase = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentId"
$flowsUrl = "$flowApiBase/flows?api-version=2016-11-01"
$flowsResponse = Invoke-RestMethod -Method Get -Uri $flowsUrl -Headers $flowHeaders
$flow = $flowsResponse.value | Where-Object { $_.properties.displayName -eq $FlowDisplayName } | Select-Object -First 1

if (-not $flow) {
    throw "Flow '$FlowDisplayName' was not found in environment $EnvironmentId. Deploy Flow8 first."
}

$callbackUrlResponse = Invoke-RestMethod -Method Post -Uri "$flowApiBase/flows/$($flow.name)/triggers/manual/listCallbackUrl?api-version=2016-11-01" -Headers $flowHeaders
$callbackUrl = $callbackUrlResponse.value
if (-not $callbackUrl -and $callbackUrlResponse.response) {
    $callbackUrl = $callbackUrlResponse.response.value
}

if (-not $callbackUrl) {
    throw "Flow '$FlowDisplayName' did not return a callback URL. Confirm it uses an HTTP request trigger."
}

$requestBody = @{
    trackingId = $TrackingId
    forceNudge = $ForceNudge.IsPresent
} | ConvertTo-Json

$invokedAt = (Get-Date).ToUniversalTime()
$httpResponse = Invoke-WebRequest -Method Post -Uri $callbackUrl -ContentType "application/json" -Body $requestBody -UseBasicParsing
Write-Host "Triggered '$FlowDisplayName' (HTTP $($httpResponse.StatusCode)). Waiting for run history..." -ForegroundColor Green

$deadline = (Get-Date).ToUniversalTime().AddSeconds($TimeoutSeconds)
$terminalStates = @("Succeeded", "Failed", "TimedOut", "Cancelled")
$run = $null

do {
    Start-Sleep -Seconds $PollIntervalSeconds
    $runsResponse = Invoke-RestMethod -Method Get -Uri "$flowApiBase/flows/$($flow.name)/runs?api-version=2016-11-01&`$top=10" -Headers $flowHeaders
    $run = $runsResponse.value |
        Sort-Object { [datetime]$_.properties.startTime } -Descending |
        Where-Object { [datetime]$_.properties.startTime -ge $invokedAt.AddSeconds(-2) } |
        Select-Object -First 1
} while (-not $run -and (Get-Date).ToUniversalTime() -lt $deadline)

if (-not $run) {
    throw "The flow was invoked, but no matching run appeared within $TimeoutSeconds seconds."
}

do {
    if ($run.properties.status -in $terminalStates) {
        break
    }

    Start-Sleep -Seconds $PollIntervalSeconds
    $run = Invoke-RestMethod -Method Get -Uri "$flowApiBase/flows/$($flow.name)/runs/$($run.name)?api-version=2016-11-01" -Headers $flowHeaders
} while ((Get-Date).ToUniversalTime() -lt $deadline)

[pscustomobject]@{
    FlowDisplayName = $FlowDisplayName
    FlowId          = $flow.name
    RunId           = $run.name
    Status          = $run.properties.status
    StartTimeUtc    = $run.properties.startTime
    EndTimeUtc      = $run.properties.endTime
}
