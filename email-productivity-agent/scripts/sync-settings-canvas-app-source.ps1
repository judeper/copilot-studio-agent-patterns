<#
.SYNOPSIS
    Downloads and extracts the Email Productivity Agent Settings Canvas App source files.

.DESCRIPTION
    Uses PAC CLI to download a published Canvas App and extract its generated source
    files into the repository for review/source control. Per Microsoft guidance,
    only the generated Src\*.pa.yaml files should be treated as source artifacts.

.PARAMETER AppName
    Display name or app ID of the Canvas App to download.

.PARAMETER EnvironmentId
    Optional environment ID or URL. If omitted, PAC CLI uses the active auth profile's environment.

.PARAMETER OutputDirectory
    Directory where the extracted app files should be written.
#>

param(
    [string]$AppName = "Email Productivity Agent Settings",
    [string]$EnvironmentId,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\power-apps\settings-canvas-app")
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command "pac" -ErrorAction SilentlyContinue)) {
    throw "PAC CLI not found. Install: dotnet tool install --global Microsoft.PowerApps.CLI.Tool"
}

$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

if (Test-Path $resolvedOutputDirectory) {
    Remove-Item -Path $resolvedOutputDirectory -Recurse -Force
}

New-Item -ItemType Directory -Path $resolvedOutputDirectory | Out-Null

$downloadDirectory = Join-Path $env:TEMP ("epa-canvas-" + [guid]::NewGuid().ToString("N"))
$msAppPath = Join-Path $downloadDirectory "settings-canvas-app.msapp"
New-Item -ItemType Directory -Path $downloadDirectory | Out-Null

$downloadArgs = @(
    "canvas", "download",
    "--name", $AppName,
    "--path", $msAppPath
)

if ($EnvironmentId) {
    $downloadArgs += @("--environment", $EnvironmentId)
}

$unpackArgs = @(
    "canvas", "unpack",
    "--msapp", $msAppPath,
    "--sources", $resolvedOutputDirectory
)

try {
    Write-Host "Downloading Canvas App for '$AppName'..." -ForegroundColor Cyan
    & pac @downloadArgs

    if ($LASTEXITCODE -ne 0) {
        throw "PAC CLI failed while downloading the Canvas App."
    }

    Write-Host "Extracting Canvas App source for '$AppName'..." -ForegroundColor Cyan
    & pac @unpackArgs

    if ($LASTEXITCODE -ne 0) {
        throw "PAC CLI failed while extracting the Canvas App source."
    }
}
finally {
    if (Test-Path $downloadDirectory) {
        Remove-Item -Path $downloadDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Canvas App source extracted to: $resolvedOutputDirectory" -ForegroundColor Green
Write-Host "Source-control guidance: review and diff only Src\*.pa.yaml files; other extracted files are runtime/editor metadata." -ForegroundColor Yellow
