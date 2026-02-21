<#
.SYNOPSIS
    Builds and deploys the PCF component solution to a Power Platform environment.

.DESCRIPTION
    Runs the PCF build pipeline (npm install, npm run build), packs the solution,
    and imports it to the target environment.

.PARAMETER EnvironmentId
    Target Power Platform environment ID (required).

.PARAMETER SolutionPath
    Path to the PCF src/ directory. Default: "../src"

.PARAMETER SolutionName
    Name for the packed solution. Default: "EnterpriseWorkAssistant"

.EXAMPLE
    .\deploy-solution.ps1 -EnvironmentId "abc-123-def"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [string]$SolutionPath = (Join-Path $PSScriptRoot ".." "src"),

    [string]$SolutionName = "EnterpriseWorkAssistant"
)

$ErrorActionPreference = "Stop"

# ─────────────────────────────────────
# 1. Validate Prerequisites
# ─────────────────────────────────────
Write-Host "Validating prerequisites..." -ForegroundColor Cyan

# Check Node.js
try {
    $nodeVersion = node --version
    Write-Host "  Node.js: $nodeVersion" -ForegroundColor Green
} catch {
    throw "Node.js is not installed. Install Node.js 18+ from https://nodejs.org"
}

# Check PAC CLI
try {
    $pacVersion = pac --version
    Write-Host "  PAC CLI: $pacVersion" -ForegroundColor Green
} catch {
    throw "PAC CLI is not installed. Install via: dotnet tool install --global Microsoft.PowerApps.CLI.Tool"
}

# Resolve solution path
$SolutionPath = Resolve-Path $SolutionPath
Write-Host "  Solution path: $SolutionPath" -ForegroundColor Green

# ─────────────────────────────────────
# 2. Install Dependencies
# ─────────────────────────────────────
Write-Host "Installing npm dependencies..." -ForegroundColor Cyan
Push-Location $SolutionPath
try {
    npm install
    if ($LASTEXITCODE -ne 0) { throw "npm install failed." }
    Write-Host "  Dependencies installed." -ForegroundColor Green
} finally {
    Pop-Location
}

# ─────────────────────────────────────
# 3. Build PCF Component
# ─────────────────────────────────────
Write-Host "Building PCF component..." -ForegroundColor Cyan
Push-Location $SolutionPath
try {
    npm run build
    if ($LASTEXITCODE -ne 0) { throw "PCF build failed. Check TypeScript errors above." }
    Write-Host "  Build successful." -ForegroundColor Green
} finally {
    Pop-Location
}

# ─────────────────────────────────────
# 4. Pack Solution
# ─────────────────────────────────────
Write-Host "Packing solution..." -ForegroundColor Cyan
$solutionDir = Join-Path $SolutionPath "Solutions"
$zipPath = Join-Path $SolutionPath "$SolutionName.zip"

# Remove old zip if exists
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Push-Location $solutionDir
try {
    dotnet build
    if ($LASTEXITCODE -ne 0) { throw "Solution build failed." }

    # The built solution zip will be in bin/Debug
    $builtZip = Get-ChildItem -Path (Join-Path $solutionDir "bin" "Debug") -Filter "*.zip" | Select-Object -First 1
    if (-not $builtZip) { throw "No solution zip found in bin/Debug." }

    Copy-Item $builtZip.FullName $zipPath
    Write-Host "  Solution packed: $zipPath" -ForegroundColor Green
} finally {
    Pop-Location
}

# ─────────────────────────────────────
# 5. Import Solution
# ─────────────────────────────────────
Write-Host "Importing solution to environment $EnvironmentId..." -ForegroundColor Cyan
Write-Host "  This may take several minutes..." -ForegroundColor Yellow
pac solution import `
    --path $zipPath `
    --environment $EnvironmentId
if ($LASTEXITCODE -ne 0) { throw "Solution import failed. Check the output above for details." }
Write-Host "  Solution imported successfully." -ForegroundColor Green

# ─────────────────────────────────────
# 6. Verify
# ─────────────────────────────────────
Write-Host ""
Write-Host "Verifying deployment..." -ForegroundColor Cyan
pac solution list --environment $EnvironmentId

Write-Host ""
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Solution: $SolutionName" -ForegroundColor White
Write-Host "Environment: $EnvironmentId" -ForegroundColor White
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Open the Canvas app and import the PCF control" -ForegroundColor White
Write-Host "  2. Configure dataset binding to AssistantCards" -ForegroundColor White
Write-Host "  3. See canvas-app-setup.md for detailed instructions" -ForegroundColor White
Write-Host ""
