<#
.SYNOPSIS
    Builds and deploys the PCF component solution to a Power Platform environment.

.DESCRIPTION
    Validates prerequisites (Bun, Node.js, .NET SDK, PAC CLI, PAC auth),
    runs the PCF build pipeline (bun install, bun run build),
    packs the solution, and imports it to the target environment.
    Supports -WhatIf to preview planned operations without executing.
    All output is logged to a timestamped deploy-*.log file.

    Exit codes:
      0 = Success
      1 = Prerequisite check failure
      2 = Build failure (bun install, bun run build, or dotnet build)
      3 = Solution import failure

.PARAMETER EnvironmentId
    Target Power Platform environment ID (required).

.PARAMETER SolutionPath
    Path to the PCF src/ directory. Default: "../src"

.PARAMETER SolutionName
    Name for the packed solution. Default: "EnterpriseWorkAssistant"

.PARAMETER WhatIf
    Shows what operations would be performed without executing them.

.EXAMPLE
    .\deploy-solution.ps1 -EnvironmentId "abc-123-def"

.EXAMPLE
    .\deploy-solution.ps1 -EnvironmentId "abc-123-def" -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [string]$SolutionPath = (Join-Path $PSScriptRoot ".." "src"),

    [string]$SolutionName = "EnterpriseWorkAssistant"
)

$ErrorActionPreference = "Stop"

$logFile = Join-Path $PSScriptRoot "deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $logFile -UseMinimalHeader

try {

# -----------------------------------------
# 1. Validate Prerequisites
# -----------------------------------------
Write-Host "Validating prerequisites..." -ForegroundColor Cyan
$prereqFailed = $false

# Check Bun
if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
    Write-Host "  MISSING: Bun" -ForegroundColor Red
    Write-Host "  Install: https://bun.sh" -ForegroundColor Yellow
    $prereqFailed = $true
} else {
    $bunVer = bun --version 2>&1
    Write-Host "  Bun: $bunVer" -ForegroundColor Green
}

# Check Node.js
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "  MISSING: Node.js" -ForegroundColor Red
    Write-Host "  Install: https://nodejs.org" -ForegroundColor Yellow
    $prereqFailed = $true
} else {
    $nodeVer = node --version 2>&1
    Write-Host "  Node.js: $nodeVer" -ForegroundColor Green
}

# Check .NET SDK
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host "  MISSING: .NET SDK" -ForegroundColor Red
    Write-Host "  Install: https://dotnet.microsoft.com/download" -ForegroundColor Yellow
    $prereqFailed = $true
} else {
    $dotnetVer = dotnet --version 2>&1
    Write-Host "  .NET SDK: $dotnetVer" -ForegroundColor Green
}

# Check PAC CLI
if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
    Write-Host "  MISSING: PAC CLI" -ForegroundColor Red
    Write-Host "  Install: dotnet tool install --global Microsoft.PowerApps.CLI.Tool" -ForegroundColor Yellow
    $prereqFailed = $true
} else {
    $pacVer = pac --version 2>&1
    Write-Host "  PAC CLI: $pacVer" -ForegroundColor Green
}

# Check PAC auth (only if pac exists)
if (Get-Command pac -ErrorAction SilentlyContinue) {
    $authList = pac auth list 2>&1
    if ($authList -match "No profiles" -or $LASTEXITCODE -ne 0) {
        Write-Host "  MISSING: PAC CLI authentication" -ForegroundColor Red
        Write-Host "  Run: pac auth create --tenant <tenant-id>" -ForegroundColor Yellow
        $prereqFailed = $true
    } else {
        Write-Host "  PAC auth: OK" -ForegroundColor Green
    }
}

if ($prereqFailed) {
    Write-Host ""
    Write-Host "Prerequisite check failed. Install missing tools and retry." -ForegroundColor Red
    exit 1
}

# Resolve solution path
$SolutionPath = Resolve-Path $SolutionPath
Write-Host "  Solution path: $SolutionPath" -ForegroundColor Green

# -----------------------------------------
# 2. Install Dependencies
# -----------------------------------------
if ($PSCmdlet.ShouldProcess($SolutionPath, "Install dependencies (bun install)")) {
    Write-Host "Installing dependencies..." -ForegroundColor Cyan
    Push-Location $SolutionPath
    try {
        bun install
        if ($LASTEXITCODE -ne 0) {
            Write-Host "bun install failed." -ForegroundColor Red
            exit 2
        }
        Write-Host "  Dependencies installed." -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

# -----------------------------------------
# 3. Build PCF Component
# -----------------------------------------
if ($PSCmdlet.ShouldProcess($SolutionPath, "Build PCF component (bun run build)")) {
    Write-Host "Building PCF component..." -ForegroundColor Cyan
    Push-Location $SolutionPath
    try {
        bun run build
        if ($LASTEXITCODE -ne 0) {
            Write-Host "PCF build failed. Check TypeScript errors above." -ForegroundColor Red
            exit 2
        }
        Write-Host "  Build successful." -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

# -----------------------------------------
# 4. Pack Solution
# -----------------------------------------
if ($PSCmdlet.ShouldProcess($SolutionPath, "Pack solution (dotnet build)")) {
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
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Solution build failed." -ForegroundColor Red
            exit 2
        }

        # The built solution zip will be in bin/Debug
        $builtZip = Get-ChildItem -Path (Join-Path $solutionDir "bin" "Debug") -Filter "*.zip" | Select-Object -First 1
        if (-not $builtZip) {
            Write-Host "No solution zip found in bin/Debug." -ForegroundColor Red
            exit 2
        }

        Copy-Item $builtZip.FullName $zipPath
        Write-Host "  Solution packed: $zipPath" -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

# -----------------------------------------
# 5. Import Solution
# -----------------------------------------
if ($PSCmdlet.ShouldProcess("Environment $EnvironmentId", "Import solution ($SolutionName)")) {
    Write-Host "Importing solution to environment $EnvironmentId..." -ForegroundColor Cyan
    Write-Host "  This may take several minutes..." -ForegroundColor Yellow
    pac solution import --path $zipPath --environment $EnvironmentId
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Solution import failed (exit code: $LASTEXITCODE)." -ForegroundColor Red
        Write-Host "Check the PAC CLI output above for details." -ForegroundColor Yellow
        Write-Host "Common causes: missing dependencies, version conflict, auth expired." -ForegroundColor Yellow
        exit 3
    }
    Write-Host "  Solution imported and verified (exit code 0)." -ForegroundColor Green
}

# -----------------------------------------
# 6. Summary
# -----------------------------------------
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Solution: $SolutionName" -ForegroundColor White
Write-Host "Environment: $EnvironmentId" -ForegroundColor White
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Open the Canvas app and import the PCF control" -ForegroundColor White
Write-Host "  2. Configure dataset binding to AssistantCards" -ForegroundColor White
Write-Host "  3. See canvas-app-setup.md for detailed instructions" -ForegroundColor White
Write-Host ""

} finally {
    Stop-Transcript
}
