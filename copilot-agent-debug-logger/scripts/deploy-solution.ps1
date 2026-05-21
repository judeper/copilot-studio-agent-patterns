<#
.SYNOPSIS
    Builds and imports the Copilot Agent Debug Logger unmanaged solution.
.DESCRIPTION
    Validates prerequisites (.NET SDK, PAC CLI 1.32+, PAC auth), verifies the
    Phase-0 Agent Debug Console model-driven app has been unpacked into source,
    builds src\Solutions\Solution.cdsproj into a solution zip, imports it to the
    target Power Platform environment, and runs inject-flow-guid.ps1 to prepare
    Copilot Studio topic YAMLs for import. Supports -WhatIf and logs all output
    to a timestamped deploy-*.log file.

    Exit codes:
      0 = Success
      1 = Prerequisite check failure (missing tool, bad PAC CLI version, no auth)
      2 = MDA precheck failed (Phase-0 not done)
      3 = Solution build failure (dotnet restore/build)
      4 = Solution import failure (pac solution import)
      5 = GUID substitution failure (inject-flow-guid.ps1 exit non-zero)
.PARAMETER EnvironmentId
    Target Power Platform environment ID. Required.
.PARAMETER SolutionPath
    Path to the folder containing Solution.cdsproj. Default: ..\src\Solutions.
.PARAMETER SolutionName
    Unique name of the solution. Default: CopilotAgentDebugLogger.
.PARAMETER SkipInjectFlowGuid
    Skips post-import GUID substitution for first-ever deploy or recovery runs.
.EXAMPLE
    pwsh .\deploy-solution.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000"
.EXAMPLE
    pwsh .\deploy-solution.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000" -SkipInjectFlowGuid
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "EnvironmentId is required.")]
    [string]$EnvironmentId,
    [string]$SolutionPath = (Join-Path $PSScriptRoot ".." "src" "Solutions"),
    [string]$SolutionName = "CopilotAgentDebugLogger",
    [switch]$SkipInjectFlowGuid
)

$ErrorActionPreference = "Stop"
$logFile = Join-Path $PSScriptRoot "deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$script:ExitCode = 0
$script:TranscriptStarted = $false

function Stop-Deploy { param([int]$Code, [string]$Message) $script:ExitCode = $Code; throw $Message }
function Get-ObjectValue {
    param($Object, [string[]]$Names)
    foreach ($name in $Names) {
        if ($Object -and $Object.PSObject.Properties.Name -contains $name -and $Object.$name) { return $Object.$name }
    }
    return $null
}

try {
    Start-Transcript -Path $logFile -UseMinimalHeader | Out-Null
    $script:TranscriptStarted = $true

# -----------------------------------------
# 1. Validate Prerequisites
# -----------------------------------------
    Write-Host "Validating prerequisites..." -ForegroundColor Cyan
    $prereqFailed = $false

    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        Write-Host "  MISSING: .NET SDK" -ForegroundColor Red
        Write-Host "  Install: https://dotnet.microsoft.com/download" -ForegroundColor Yellow
        $prereqFailed = $true
    } else {
        $dotnetVer = dotnet --version 2>&1
        if ($LASTEXITCODE -ne 0 -or -not $dotnetVer) { Write-Host "  ERROR: unable to read .NET SDK version." -ForegroundColor Red; $prereqFailed = $true }
        else { Write-Host "  .NET SDK: $dotnetVer" -ForegroundColor Green }
    }

    if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
        Write-Host "  MISSING: PAC CLI" -ForegroundColor Red
        Write-Host "  Install: dotnet tool install --global Microsoft.PowerApps.CLI.Tool" -ForegroundColor Yellow
        $prereqFailed = $true
    } else {
        $pacRaw = pac --version 2>&1
        $versionMatch = [regex]::Match(($pacRaw | Out-String), '(\d+\.\d+(\.\d+)?)')
        if ($LASTEXITCODE -ne 0 -or -not $versionMatch.Success) { Write-Host "  ERROR: unable to read PAC CLI version." -ForegroundColor Red; $prereqFailed = $true }
        elseif ([Version]$versionMatch.Groups[1].Value -lt [Version]"1.32") {
            Write-Host "  ERROR: PAC CLI >= 1.32 required (found $($versionMatch.Groups[1].Value))." -ForegroundColor Red
            Write-Host "  Update: dotnet tool update --global Microsoft.PowerApps.CLI.Tool" -ForegroundColor Yellow
            $prereqFailed = $true
        } else { Write-Host "  PAC CLI: $($versionMatch.Groups[1].Value)" -ForegroundColor Green }
    }

    if (Get-Command pac -ErrorAction SilentlyContinue) {
        $authText = (pac auth list 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0 -or $authText -match "No profiles|No auth|not authenticated|There are no") {
            Write-Host "  MISSING: PAC CLI authentication profile" -ForegroundColor Red
            Write-Host "  Run: pac auth create, then retry this deploy." -ForegroundColor Yellow
            $prereqFailed = $true
        } else { Write-Host "  PAC auth: profile(s) found" -ForegroundColor Green }
    }

    if ($prereqFailed) { Stop-Deploy 1 "Prerequisite check failed. Install missing tools or create PAC auth, then retry." }

# -----------------------------------------
# 2. MDA Presence Pre-check (D7)
# -----------------------------------------
    Write-Host "`nChecking Phase-0 model-driven app presence..." -ForegroundColor Cyan
    if (-not (Test-Path $SolutionPath)) { Stop-Deploy 3 "Solution path not found: $SolutionPath" }
    $resolvedSolutionPath = (Resolve-Path $SolutionPath).Path
    # Per pac solution clone/unpack convention the MDA lives under src\AppModules\
    # (Microsoft's official layout). Earlier scaffold expected CanvasApps\AgentDebugConsole_*
    # which is the legacy MDA folder pattern that the modern PAC CLI no longer produces.
    $mdaPattern = Join-Path $resolvedSolutionPath "src\AppModules\cr_AgentDebugConsole"
    # The MDA folder is a leaf containing AppModule.xml + AppModule_managed.xml — use
    # Test-Path -PathType Container to check the dir itself, NOT Get-ChildItem -Directory
    # which would return its CHILD directories (none, since it only holds files).
    if (-not (Test-Path -Path $mdaPattern -PathType Container)) {
        Stop-Deploy 2 "Phase-0 MDA authoring not done. See copilot-agent-debug-logger/docs/phase-0-mda-authoring.md before running deploy. The Agent Debug Console MDA must be authored in the Maker portal and pulled into src/Solutions/src/AppModules/cr_AgentDebugConsole/ via 'pac solution clone' before deploy-solution.ps1 can succeed."
    }
    Write-Host "  MDA folder present: $mdaPattern" -ForegroundColor Green

# -----------------------------------------
# 3. Select Target Environment
# -----------------------------------------
    Write-Host "`nSelecting Power Platform environment..." -ForegroundColor Cyan
    $environmentStatus = "Skipped by WhatIf"
    $environmentUrl = "Not resolved"
    if ($PSCmdlet.ShouldProcess("Environment $EnvironmentId", "Select PAC auth profile")) {
        pac auth select --environment $EnvironmentId | Out-Null
        if ($LASTEXITCODE -ne 0) { Stop-Deploy 1 "pac auth select failed for environment '$EnvironmentId'. Run 'pac auth create' first, then retry." }
        $orgInfoRaw = pac org who --json 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $orgInfoRaw) { Stop-Deploy 1 "Unable to verify selected environment with 'pac org who --json'." }
        $orgInfo = $orgInfoRaw | Out-String | ConvertFrom-Json
        $environmentUrl = Get-ObjectValue $orgInfo @("OrgUrl", "OrganizationUrl", "EnvironmentUrl", "DataverseUrl", "Url")
        $environmentStatus = "Selected"
        Write-Host "  Environment selected: $EnvironmentId" -ForegroundColor Green
        if ($environmentUrl) { Write-Host "  Environment URL: $environmentUrl" -ForegroundColor Green }
    }

# -----------------------------------------
# 4. Pack Solution
# -----------------------------------------
    Write-Host "`nPacking solution..." -ForegroundColor Cyan
    # Discover the cdsproj. PAC solution clone produces <SolutionName>.cdsproj
    # (e.g. CopilotAgentDebugLogger.cdsproj); earlier scaffolds used Solution.cdsproj.
    # Glob for any single .cdsproj in the SolutionPath to handle both shapes.
    $cdsProjs = @(Get-ChildItem -Path $resolvedSolutionPath -Filter "*.cdsproj" -File -ErrorAction SilentlyContinue)
    if ($cdsProjs.Count -eq 0) { Stop-Deploy 3 "No .cdsproj found in $resolvedSolutionPath." }
    if ($cdsProjs.Count -gt 1) { Stop-Deploy 3 "Multiple .cdsproj files found in ${resolvedSolutionPath}: $(($cdsProjs.Name) -join ', ')." }
    $cdsProjPath = $cdsProjs[0].FullName
    $cdsProjFile = $cdsProjs[0].Name
    $zipPath = $null
    $buildStatus = "Skipped by WhatIf"

    if ($PSCmdlet.ShouldProcess($cdsProjPath, "dotnet restore and dotnet build")) {
        $debugOutputPath = Join-Path $resolvedSolutionPath "bin\Debug"
        if (Test-Path $debugOutputPath) { Get-ChildItem $debugOutputPath -Filter "*.zip" -File -ErrorAction SilentlyContinue | Remove-Item -Force }
        Push-Location $resolvedSolutionPath
        try {
            Write-Host "  Restoring NuGet packages..." -ForegroundColor Gray
            dotnet restore ".\$cdsProjFile" --verbosity minimal
            if ($LASTEXITCODE -ne 0) { Stop-Deploy 3 "dotnet restore failed for $cdsProjPath." }
            Write-Host "  Building solution package..." -ForegroundColor Gray
            dotnet build ".\$cdsProjFile" --configuration Debug --nologo --verbosity minimal
            if ($LASTEXITCODE -ne 0) { Stop-Deploy 3 "dotnet build failed for $cdsProjPath." }
        } finally { Pop-Location }

        $zips = @(Get-ChildItem $debugOutputPath -Filter "*.zip" -File -ErrorAction SilentlyContinue)
        if ($zips.Count -eq 0) { Stop-Deploy 3 "No solution zip found in $debugOutputPath after build." }
        if ($zips.Count -gt 1) { Stop-Deploy 3 "Multiple solution zips found in ${debugOutputPath}: $(($zips.Name) -join ', ')." }
        $zipPath = $zips[0].FullName
        $buildStatus = "Built $zipPath"
        Write-Host "  Solution packed: $zipPath" -ForegroundColor Green
    }

# -----------------------------------------
# 5. Import Solution
# -----------------------------------------
    Write-Host "`nImporting solution..." -ForegroundColor Cyan
    $importStatus = "Skipped by WhatIf"
    if ($PSCmdlet.ShouldProcess("Environment $EnvironmentId", "pac solution import ($SolutionName)")) {
        if (-not $zipPath -or -not (Test-Path $zipPath)) { Stop-Deploy 4 "Solution zip is missing; build must succeed before import." }
        # Connection references for shared_commondataserviceforapps may need manual
        # binding in the Power Apps maker portal after import. See
        # docs/deployment-guide.md Connection References for the click-path. The
        # --settings-file strategy was evaluated and deferred for POC simplicity.
        pac solution import --path $zipPath --environment $EnvironmentId --activate-plugins true
        if ($LASTEXITCODE -ne 0) { Stop-Deploy 4 "pac solution import failed for $zipPath (exit code $LASTEXITCODE)." }
        $importStatus = "Imported $SolutionName to $EnvironmentId"
        Write-Host "  Solution import completed." -ForegroundColor Green
    }

# -----------------------------------------
# 6. Post-import GUID Substitution
# -----------------------------------------
    Write-Host "`nRunning post-import GUID substitution..." -ForegroundColor Cyan
    $guidStatus = "Skipped by -SkipInjectFlowGuid"
    if (-not $SkipInjectFlowGuid) {
        $injectScript = Join-Path $PSScriptRoot "inject-flow-guid.ps1"
        if (-not (Test-Path $injectScript)) { Stop-Deploy 5 "Required post-import script not found: $injectScript" }
        if ($PSCmdlet.ShouldProcess($injectScript, "Run inject-flow-guid.ps1")) {
            try {
                & $injectScript -EnvironmentId $EnvironmentId
                if ($LASTEXITCODE -ne 0) { Stop-Deploy 5 "inject-flow-guid.ps1 exited with code $LASTEXITCODE." }
                $guidStatus = "GUID substitution completed; see dist\topics output."
            } catch {
                $injectMessage = $_.Exception.Message
                if ($injectMessage -match "Tool flow 'tool-log-agent-trace' not found|PVA-trigger flows|first Action attach") {
                    $guidStatus = "Deferred: tool flow not materialized yet. Add tool-log-agent-trace as an Action on each consumer agent, then rerun without -SkipInjectFlowGuid."
                    Write-Host "  Expected on first deploy: $guidStatus" -ForegroundColor Yellow
                    if ($VerbosePreference -eq "Continue") { Stop-Deploy 5 $injectMessage }
                } else { Stop-Deploy 5 "GUID substitution failed: $injectMessage" }
            }
        } else { $guidStatus = "Skipped by WhatIf" }
    } else { Write-Host "  Skipped by -SkipInjectFlowGuid." -ForegroundColor Yellow }

# -----------------------------------------
# 7. Summary
# -----------------------------------------
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host " COPILOT AGENT DEBUG LOGGER DEPLOY COMPLETE" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "Solution: $SolutionName" -ForegroundColor White
    Write-Host "Environment: $EnvironmentId" -ForegroundColor White
    Write-Host "Environment status: $environmentStatus" -ForegroundColor White
    Write-Host "Environment URL: $environmentUrl" -ForegroundColor White
    Write-Host "Build status: $buildStatus" -ForegroundColor White
    Write-Host "Import status: $importStatus" -ForegroundColor White
    Write-Host "GUID substitution: $guidStatus" -ForegroundColor White
    Write-Host "Log file: $logFile" -ForegroundColor White
    Write-Host "`nNEXT STEPS:" -ForegroundColor Yellow
    Write-Host "  1. Enable cr_DebugLoggerEnabled in the Power Apps maker portal." -ForegroundColor White
    Write-Host "  2. Add tool-log-agent-trace as an Action on each consumer agent in Copilot Studio." -ForegroundColor White
    Write-Host "  3. Rerun this script without -SkipInjectFlowGuid to refresh dist\topics." -ForegroundColor White
    Write-Host "  4. If connection references are unresolved, bind them manually in the maker portal." -ForegroundColor White
} catch {
    if ($script:ExitCode -eq 0) { $script:ExitCode = 1 }
    Write-Host "Deploy failed: $($_.Exception.Message)" -ForegroundColor Red
    exit $script:ExitCode
} finally {
    if ($script:TranscriptStarted) { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null }
}
