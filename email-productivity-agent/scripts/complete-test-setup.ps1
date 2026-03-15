<#
.SYNOPSIS
    Completes the remaining scripted setup for an Email Productivity Agent test environment.

.DESCRIPTION
    Runs the EPA readiness check, proceeds only when the remaining blockers are limited
    to flow deployment and/or the Settings Canvas App, deploys both flow phases,
    optionally syncs the Settings Canvas App source back into the repo, and reruns the
    readiness check.

    This script is intended to be run after the environment, Dataverse schema, security
    role, and copilot have already been provisioned.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$OrgUrl,

    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [Parameter(Mandatory = $true)]
    [string]$PilotUserEmail,

    [string]$PublisherPrefix = "cr",

    [string]$AppName = "Email Productivity Agent Settings",

    [switch]$SkipCanvasSourceSync,

    [string]$CopilotBotId
)

$ErrorActionPreference = "Stop"
$OrgUrl = $OrgUrl.TrimEnd('/')

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$readinessScript = Join-Path $scriptRoot "check-test-readiness.ps1"
$deployScript = Join-Path $scriptRoot "deploy-agent-flows.ps1"
$syncCanvasScript = Join-Path $scriptRoot "sync-settings-canvas-app-source.ps1"

function Invoke-PowerShellScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string[]]$Arguments = @(),

        [switch]$AllowFailure
    )

    Write-Host ""
    Write-Host ">>> Running $(Split-Path -Leaf $Path)" -ForegroundColor Cyan

    $captured = @()
    & pwsh -NoLogo -NoProfile -File $Path @Arguments 2>&1 | Tee-Object -Variable captured
    $exitCode = $LASTEXITCODE
    $output = ($captured | Out-String).Trim()

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "$(Split-Path -Leaf $Path) failed with exit code $exitCode."
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Get-BlockingCategories {
    param([string]$Output)

    $match = [regex]::Match($Output, '(?im)^Blocking areas:\s*(.+)$')
    if (-not $match.Success) {
        return @()
    }

    return @(
        $match.Groups[1].Value.Split(',') |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Test-CanvasAppExists {
    param([string]$Name)

    $canvasList = & pac canvas list --environment $EnvironmentId 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "PAC CLI could not query canvas apps in $EnvironmentId."
    }

    return ($canvasList -match ("(?im)^\s*" + [regex]::Escape($Name) + "\b"))
}

Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║ Email Productivity Agent — Complete Test Setup      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "Environment:   $EnvironmentId" -ForegroundColor Gray
Write-Host "Org URL:       $OrgUrl" -ForegroundColor Gray
Write-Host "Pilot user:    $PilotUserEmail" -ForegroundColor Gray
Write-Host "Canvas app:    $AppName`n" -ForegroundColor Gray

$commonArgs = @(
    "-OrgUrl", $OrgUrl,
    "-EnvironmentId", $EnvironmentId,
    "-PilotUserEmail", $PilotUserEmail,
    "-PublisherPrefix", $PublisherPrefix
)
$deployCopilotArgs = if ($CopilotBotId) { @("-CopilotBotId", $CopilotBotId) } else { @() }

$precheck = Invoke-PowerShellScript -Path $readinessScript -Arguments $commonArgs -AllowFailure
if ($precheck.ExitCode -ne 0) {
    $blockingCategories = @(Get-BlockingCategories -Output $precheck.Output)
    if ($blockingCategories.Count -eq 0) {
        throw "The readiness precheck failed before it reported blocking categories."
    }

    $unsupportedBlockers = @($blockingCategories | Where-Object { $_ -notin @("Flow", "Canvas App") })
    if ($unsupportedBlockers.Count -gt 0) {
        throw "Resolve these blockers before continuing: $($unsupportedBlockers -join ', ')"
    }

    Write-Host ""
    Write-Host "Only flow/canvas blockers remain; proceeding with flow deployment." -ForegroundColor Yellow
}
else {
    Write-Host ""
    Write-Host "Precheck already passed; deployment scripts will run idempotently." -ForegroundColor Green
}

Invoke-PowerShellScript -Path $deployScript -Arguments (@(
    "-OrgUrl", $OrgUrl,
    "-EnvironmentId", $EnvironmentId,
    "-PublisherPrefix", $PublisherPrefix,
    "-FlowsToCreate", "Phase1"
) + $deployCopilotArgs) | Out-Null

Invoke-PowerShellScript -Path $deployScript -Arguments (@(
    "-OrgUrl", $OrgUrl,
    "-EnvironmentId", $EnvironmentId,
    "-PublisherPrefix", $PublisherPrefix,
    "-FlowsToCreate", "Phase2"
) + $deployCopilotArgs) | Out-Null

Invoke-PowerShellScript -Path $deployScript -Arguments (@(
    "-OrgUrl", $OrgUrl,
    "-EnvironmentId", $EnvironmentId,
    "-PublisherPrefix", $PublisherPrefix,
    "-FlowsToCreate", "Phase3"
) + $deployCopilotArgs) | Out-Null

if ($SkipCanvasSourceSync) {
    Write-Host ""
    Write-Host "Skipping canvas app source sync by request." -ForegroundColor Yellow
}
elseif (Test-CanvasAppExists -Name $AppName) {
    Invoke-PowerShellScript -Path $syncCanvasScript -Arguments @(
        "-AppName", $AppName,
        "-EnvironmentId", $EnvironmentId
    ) | Out-Null
}
else {
    Write-Host ""
    Write-Warning "Canvas app '$AppName' is still missing; skipping source sync."
}

Invoke-PowerShellScript -Path $readinessScript -Arguments $commonArgs | Out-Null

Write-Host ""
Write-Host "EPA environment is ready for manual testing." -ForegroundColor Green
