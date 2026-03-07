<#
.SYNOPSIS
    Creates and publishes the Enterprise Work Assistant copilot from repo assets.

.DESCRIPTION
    Builds a Copilot Studio template from the repo's base bot template plus the
    Enterprise Work Assistant topic prompts, then creates or reuses the
    `Enterprise Work Assistant` copilot in the target environment and publishes it.

    This script automates the Copilot Studio portion of the EWA setup that was
    previously manual. It provisions four flow-invoked topics:
      - Main Triage
      - Humanizer
      - Daily Briefing
      - Orchestrator

    The generated topics use generative actions and return raw JSON through
    their respective output variables expected by the EWA flows and canvas app.

.PARAMETER EnvironmentId
    Power Platform environment ID (GUID).

.PARAMETER DisplayName
    Display name of the copilot. Default: "Enterprise Work Assistant"

.PARAMETER SchemaName
    Schema name (unique name) of the copilot. Default: "cr_enterpriseworkassistant"

.PARAMETER SolutionName
    Solution name that should contain the copilot. Default: "EnterpriseWorkAssistant"

.EXAMPLE
    .\provision-copilot.ps1 `
        -EnvironmentId "af3070e1-da9a-e06b-85e5-dec492b54d1d"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [string]$DisplayName = "Enterprise Work Assistant",

    [string]$SchemaName = "cr_enterpriseworkassistant",

    [string]$SolutionName = "EnterpriseWorkAssistant"
)

$ErrorActionPreference = "Stop"

function Invoke-PacCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & pac @Arguments 2>&1 | Out-String
    $exitCode = $LASTEXITCODE

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output = $output.Trim()
    }
}

function Get-PromptBody {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $lines = Get-Content -Path $Path
    while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[0])) {
        $lines = $lines[1..($lines.Count - 1)]
    }

    if ($lines.Count -gt 0 -and $lines[0] -match '^#\s+') {
        if ($lines.Count -eq 1) {
            $lines = @()
        }
        else {
            $lines = $lines[1..($lines.Count - 1)]
        }
    }

    while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[0])) {
        $lines = $lines[1..($lines.Count - 1)]
    }

    $body = ($lines -join "`n").Trim()
    if (-not $body) {
        throw "Prompt file is empty after trimming heading: $Path"
    }

    return "$body`n`nReturn only raw JSON. Never wrap the JSON in markdown fences."
}

function Format-YamlLiteralBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [int]$Indent
    )

    $prefix = " " * $Indent
    $lines = $Value -split "`r?`n"
    if ($lines.Count -eq 0) {
        return $prefix
    }

    return ($lines | ForEach-Object {
        if ($_ -eq "") {
            $prefix.TrimEnd()
        }
        else {
            "$prefix$_"
        }
    }) -join "`n"
}

function Get-ExistingCopilotId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentId,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    $result = Invoke-PacCommand -Arguments @("copilot", "list", "--environment", $EnvironmentId)
    if ($result.ExitCode -ne 0) {
        throw "Failed to list copilots: $($result.Output)"
    }

    $escapedName = [regex]::Escape($DisplayName)
    $match = [regex]::Match($result.Output, "(?m)^\s*$escapedName\s+(?<id>[0-9a-fA-F-]{36})\s+")
    if ($match.Success) {
        return $match.Groups["id"].Value
    }

    return $null
}

function New-CleanKickStartTemplate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    $template = Get-Content -Path $SourcePath -Raw | ConvertFrom-Json -AsHashtable
    $template.metadata.name = $DisplayName
    $template.metadata.description = "$DisplayName for triaging emails, Teams messages, and calendar events."
    $template.content.displayName = $DisplayName
    $template.content.description = "Triages incoming signals, conducts multi-tier research, and prepares briefings with draft responses."
    $template.content.instructions = "When invoked by automated flows or user commands, use the active topic instructions and return raw JSON only."
    $template.spec.connectors = @()

    $template | ConvertTo-Json -Depth 20 | Set-Content -Path $DestinationPath -Encoding UTF8
}

function Test-CopilotTemplate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentId,

        [Parameter(Mandatory = $true)]
        [string]$BotId,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    $validationTemplatePath = Join-Path $WorkingDirectory "ewa-validation.yaml"
    $extractResult = Invoke-PacCommand -Arguments @(
        "copilot", "extract-template",
        "--environment", $EnvironmentId,
        "--bot", $BotId,
        "--templateFileName", $validationTemplatePath,
        "--overwrite"
    )

    if ($extractResult.ExitCode -ne 0) {
        throw "Failed to extract created copilot for validation: $($extractResult.Output)"
    }

    if (-not (Test-Path $validationTemplatePath)) {
        throw "Copilot validation template was not created: $validationTemplatePath"
    }

    $templateText = Get-Content -Path $validationTemplatePath -Raw
    $requiredMarkers = @(
        "displayName: Main Triage",
        "displayName: Humanizer",
        "displayName: Daily Briefing",
        "displayName: Orchestrator"
    )

    foreach ($marker in $requiredMarkers) {
        if ($templateText -notmatch [regex]::Escape($marker)) {
            throw "Created copilot is missing expected content marker: $marker"
        }
    }
}

# ── Component generators ─────────────────────────────────────────────────────

function Get-MainTriageComponent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PromptBody
    )

    $instructions = Format-YamlLiteralBlock -Value $PromptBody -Indent 14

    return @"
  - kind: DialogComponent
    managedProperties:
      isCustomizable: false

    displayName: Main Triage
    description: Triage incoming signals (email, Teams, calendar) and return structured JSON with research findings and draft responses.
    shareContext: {}
    state: Active
    status: Active
    schemaName: template-content.topic.MainTriage
    dialog:
      kind: AdaptiveDialog
      modelDisplayName: Main Triage
      modelDescription: Triage incoming signals and return structured JSON with research and drafts.
      inputs:
        - kind: AutomaticTaskInput
          propertyName: TRIGGER_TYPE
          description: The type of incoming signal that triggered this triage (Email, Teams, or Calendar)
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: PAYLOAD
          description: The full payload of the incoming signal including subject, body, sender, and metadata
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: USER_CONTEXT
          description: Current user context including role, preferences, and organizational information
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: CURRENT_DATETIME
          description: Current UTC timestamp when the flow invokes the triage agent
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: SENDER_PROFILE
          description: Profile information about the sender including relationship, communication history, and priority level
          shouldPromptUser: false

      beginDialog:
        kind: OnRecognizedIntent
        id: main
        intent: {}
        actions:
          - kind: SearchAndSummarizeContent
            id: generateTriage
            autoSend: false
            variable: Topic.AgentResponseJSON
            responseCaptureType: TextOnly
            userInput: =Concatenate("FLOW_MESSAGE: ", System.Activity.Text, Char(10), "TRIGGER_TYPE: ", Topic.TRIGGER_TYPE, Char(10), "PAYLOAD: ", Topic.PAYLOAD, Char(10), "USER_CONTEXT: ", Topic.USER_CONTEXT, Char(10), "CURRENT_DATETIME: ", Topic.CURRENT_DATETIME, Char(10), "SENDER_PROFILE: ", Topic.SENDER_PROFILE)
            additionalInstructions: |-
$instructions
            webBrowsing: false
            searchEmails: false
            fileSearchDataSource:
              searchFilesMode:
                kind: DoNotSearchFiles

          - kind: EndDialog
            id: endTriage

      inputType:
        properties:
          CURRENT_DATETIME:
            displayName: CURRENT_DATETIME
            description: Current UTC timestamp when the flow invokes the triage agent
            type: String

          PAYLOAD:
            displayName: PAYLOAD
            description: The full payload of the incoming signal including subject, body, sender, and metadata
            type: String

          SENDER_PROFILE:
            displayName: SENDER_PROFILE
            description: Profile information about the sender including relationship, communication history, and priority level
            type: String

          TRIGGER_TYPE:
            displayName: TRIGGER_TYPE
            description: The type of incoming signal that triggered this triage (Email, Teams, or Calendar)
            type: String

          USER_CONTEXT:
            displayName: USER_CONTEXT
            description: Current user context including role, preferences, and organizational information
            type: String

      outputType:
        properties:
          AgentResponseJSON:
            displayName: AgentResponseJSON
            description: Structured JSON with triage decision, research findings, confidence score, and draft response
            type: String
"@
}

function Get-HumanizerComponent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PromptBody
    )

    $instructions = Format-YamlLiteralBlock -Value $PromptBody -Indent 14

    return @"
  - kind: DialogComponent
    managedProperties:
      isCustomizable: false

    displayName: Humanizer
    description: Rewrite raw drafts in natural human tone calibrated to recipient relationship and channel.
    shareContext: {}
    state: Active
    status: Active
    schemaName: template-content.topic.Humanizer
    dialog:
      kind: AdaptiveDialog
      modelDisplayName: Humanizer
      modelDescription: Rewrite raw drafts in natural human tone calibrated to recipient and channel.
      inputs:
        - kind: AutomaticTaskInput
          propertyName: DRAFT_PAYLOAD
          description: The raw draft text and metadata to be humanized including original content and formatting preferences
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: TARGET_CHANNEL
          description: The communication channel for the humanized output (Email, Teams, or Calendar)
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: RECIPIENT_CONTEXT
          description: Recipient relationship context including formality level, communication history, and organizational role
          shouldPromptUser: false

      beginDialog:
        kind: OnRecognizedIntent
        id: main
        intent: {}
        actions:
          - kind: SearchAndSummarizeContent
            id: generateHumanized
            autoSend: false
            variable: Topic.HumanizedText
            responseCaptureType: TextOnly
            userInput: =Concatenate("FLOW_MESSAGE: ", System.Activity.Text, Char(10), "DRAFT_PAYLOAD: ", Topic.DRAFT_PAYLOAD, Char(10), "TARGET_CHANNEL: ", Topic.TARGET_CHANNEL, Char(10), "RECIPIENT_CONTEXT: ", Topic.RECIPIENT_CONTEXT)
            additionalInstructions: |-
$instructions
            webBrowsing: false
            searchEmails: false
            fileSearchDataSource:
              searchFilesMode:
                kind: DoNotSearchFiles

          - kind: EndDialog
            id: endHumanized

      inputType:
        properties:
          DRAFT_PAYLOAD:
            displayName: DRAFT_PAYLOAD
            description: The raw draft text and metadata to be humanized including original content and formatting preferences
            type: String

          RECIPIENT_CONTEXT:
            displayName: RECIPIENT_CONTEXT
            description: Recipient relationship context including formality level, communication history, and organizational role
            type: String

          TARGET_CHANNEL:
            displayName: TARGET_CHANNEL
            description: The communication channel for the humanized output (Email, Teams, or Calendar)
            type: String

      outputType:
        properties:
          HumanizedText:
            displayName: HumanizedText
            description: Rewritten draft text in natural human tone calibrated to the recipient and channel
            type: String
"@
}

function Get-DailyBriefingComponent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PromptBody
    )

    $instructions = Format-YamlLiteralBlock -Value $PromptBody -Indent 14

    return @"
  - kind: DialogComponent
    managedProperties:
      isCustomizable: false

    displayName: Daily Briefing
    description: Generate a personalized daily work briefing with prioritized action items.
    shareContext: {}
    state: Active
    status: Active
    schemaName: template-content.topic.DailyBriefing
    dialog:
      kind: AdaptiveDialog
      modelDisplayName: Daily Briefing
      modelDescription: Generate a personalized daily work briefing with prioritized action items.
      inputs:
        - kind: AutomaticTaskInput
          propertyName: BRIEFING_INPUT
          description: Aggregated data for the daily briefing including pending cards, calendar events, and priority items
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: CURRENT_DATETIME
          description: Current UTC timestamp when the flow invokes the briefing agent
          shouldPromptUser: false

      beginDialog:
        kind: OnRecognizedIntent
        id: main
        intent: {}
        actions:
          - kind: SearchAndSummarizeContent
            id: generateBriefing
            autoSend: false
            variable: Topic.BriefingJSON
            responseCaptureType: TextOnly
            userInput: =Concatenate("FLOW_MESSAGE: ", System.Activity.Text, Char(10), "BRIEFING_INPUT: ", Topic.BRIEFING_INPUT, Char(10), "CURRENT_DATETIME: ", Topic.CURRENT_DATETIME)
            additionalInstructions: |-
$instructions
            webBrowsing: false
            searchEmails: false
            fileSearchDataSource:
              searchFilesMode:
                kind: DoNotSearchFiles

          - kind: EndDialog
            id: endBriefing

      inputType:
        properties:
          BRIEFING_INPUT:
            displayName: BRIEFING_INPUT
            description: Aggregated data for the daily briefing including pending cards, calendar events, and priority items
            type: String

          CURRENT_DATETIME:
            displayName: CURRENT_DATETIME
            description: Current UTC timestamp when the flow invokes the briefing agent
            type: String

      outputType:
        properties:
          BriefingJSON:
            displayName: BriefingJSON
            description: Structured JSON with prioritized action items, calendar summary, and briefing sections
            type: String
"@
}

function Get-OrchestratorComponent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PromptBody
    )

    $instructions = Format-YamlLiteralBlock -Value $PromptBody -Indent 14

    return @"
  - kind: DialogComponent
    managedProperties:
      isCustomizable: false

    displayName: Orchestrator
    description: Process natural language commands and use tool actions to query cards, update data, and refine drafts.
    shareContext: {}
    state: Active
    status: Active
    schemaName: template-content.topic.Orchestrator
    dialog:
      kind: AdaptiveDialog
      modelDisplayName: Orchestrator
      modelDescription: Process natural language commands to query cards, update data, and refine drafts.
      inputs:
        - kind: AutomaticTaskInput
          propertyName: COMMAND_TEXT
          description: The natural language command entered by the user in the canvas app command bar
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: USER_CONTEXT
          description: Current user context including role, preferences, and organizational information
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: CURRENT_CARD_JSON
          description: JSON representation of the currently selected assistant card, if any
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: RECENT_BRIEFING
          description: The most recent daily briefing JSON for context-aware command processing
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: CURRENT_DATETIME
          description: Current UTC timestamp when the orchestrator is invoked
          shouldPromptUser: false

      beginDialog:
        kind: OnRecognizedIntent
        id: main
        intent: {}
        actions:
          - kind: SearchAndSummarizeContent
            id: generateOrchestrator
            autoSend: false
            variable: Topic.OrchestratorResponseJSON
            responseCaptureType: TextOnly
            userInput: =Concatenate("FLOW_MESSAGE: ", System.Activity.Text, Char(10), "COMMAND_TEXT: ", Topic.COMMAND_TEXT, Char(10), "USER_CONTEXT: ", Topic.USER_CONTEXT, Char(10), "CURRENT_CARD_JSON: ", Topic.CURRENT_CARD_JSON, Char(10), "RECENT_BRIEFING: ", Topic.RECENT_BRIEFING, Char(10), "CURRENT_DATETIME: ", Topic.CURRENT_DATETIME)
            additionalInstructions: |-
$instructions
            webBrowsing: false
            searchEmails: false
            fileSearchDataSource:
              searchFilesMode:
                kind: DoNotSearchFiles

          - kind: EndDialog
            id: endOrchestrator

      inputType:
        properties:
          COMMAND_TEXT:
            displayName: COMMAND_TEXT
            description: The natural language command entered by the user in the canvas app command bar
            type: String

          CURRENT_CARD_JSON:
            displayName: CURRENT_CARD_JSON
            description: JSON representation of the currently selected assistant card, if any
            type: String

          CURRENT_DATETIME:
            displayName: CURRENT_DATETIME
            description: Current UTC timestamp when the orchestrator is invoked
            type: String

          RECENT_BRIEFING:
            displayName: RECENT_BRIEFING
            description: The most recent daily briefing JSON for context-aware command processing
            type: String

          USER_CONTEXT:
            displayName: USER_CONTEXT
            description: Current user context including role, preferences, and organizational information
            type: String

      outputType:
        properties:
          OrchestratorResponseJSON:
            displayName: OrchestratorResponseJSON
            description: Structured JSON with command result, updated card data, and any follow-up actions
            type: String
"@
}

# ── Main script ───────────────────────────────────────────────────────────────

$baseTemplatePath = Join-Path $PSScriptRoot "..\src\copilot-base-template.yaml"
$kickStartTemplatePath = Join-Path $PSScriptRoot "..\src\kickStartTemplate-1.0.0.json"
$mainPromptPath = Join-Path $PSScriptRoot "..\prompts\main-agent-system-prompt.md"
$humanizerPromptPath = Join-Path $PSScriptRoot "..\prompts\humanizer-agent-prompt.md"
$briefingPromptPath = Join-Path $PSScriptRoot "..\prompts\daily-briefing-agent-prompt.md"
$orchestratorPromptPath = Join-Path $PSScriptRoot "..\prompts\orchestrator-agent-prompt.md"

Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Enterprise Work Assistant — Copilot Provisioning   ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

if (-not (Get-Command "pac" -ErrorAction SilentlyContinue)) {
    throw "PAC CLI not found. Install: dotnet tool install --global Microsoft.PowerApps.CLI.Tool"
}

foreach ($path in @($baseTemplatePath, $kickStartTemplatePath, $mainPromptPath, $humanizerPromptPath, $briefingPromptPath, $orchestratorPromptPath)) {
    if (-not (Test-Path $path)) {
        throw "Required asset not found: $path"
    }
}

if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    throw "Azure CLI not found. Install: winget install Microsoft.AzureCLI"
}

# [0/5] Ensure the Dataverse solution exists (pac copilot create --solution requires it)
Write-Host "[0/5] Ensuring '$SolutionName' solution exists..." -ForegroundColor Cyan

$pacOrgResult = Invoke-PacCommand -Arguments @("org", "who")
$orgUrlMatch = [regex]::Match($pacOrgResult.Output, "(https://[^\s/]+\.crm[^\s/]*\.dynamics\.com)")
if (-not $orgUrlMatch.Success) {
    throw "Cannot determine Org URL from 'pac org who'. Ensure PAC CLI is connected to the target environment."
}
$orgUrl = $orgUrlMatch.Groups[1].Value

$dvToken = az account get-access-token --resource $orgUrl --query accessToken -o tsv 2>$null
if (-not $dvToken) {
    throw "Cannot acquire Dataverse token. Run: az login --tenant <tenantId>"
}
$dvHeaders = @{
    "Authorization"    = "Bearer $dvToken"
    "Content-Type"     = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
}

$solCheck = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/solutions?`$filter=uniquename eq '$SolutionName'&`$select=solutionid" -Headers $dvHeaders
if ($solCheck.value.Count -gt 0) {
    Write-Host "  ✓ Solution '$SolutionName' already exists" -ForegroundColor Green
}
else {
    $prefix = $SchemaName.Split('_')[0]
    $pubs = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/publishers?`$filter=customizationprefix eq '$prefix'&`$select=publisherid,friendlyname" -Headers $dvHeaders
    if ($pubs.value.Count -eq 0) {
        throw "No publisher found with prefix '$prefix'. Run provision-environment.ps1 first."
    }
    $publisherId = $pubs.value[0].publisherid

    $solBody = @{
        uniquename   = $SolutionName
        friendlyname = $DisplayName
        description  = "$DisplayName - copilot, flows, connection references, and components"
        version      = "1.0.0.0"
        "publisherid@odata.bind" = "/publishers($publisherId)"
    } | ConvertTo-Json

    Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/solutions" -Headers $dvHeaders -Method Post -Body $solBody | Out-Null
    Write-Host "  ✓ Solution '$SolutionName' created" -ForegroundColor Green
}

$workDir = Join-Path $env:TEMP ("ewa-copilot-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

try {
    # [1/5] Check for existing copilot
    Write-Host "[1/5] Checking for an existing copilot..." -ForegroundColor Cyan
    $botId = Get-ExistingCopilotId -EnvironmentId $EnvironmentId -DisplayName $DisplayName
    if ($botId) {
        Write-Host "  ✓ Copilot already exists: $botId" -ForegroundColor Green
    }
    else {
        Write-Host "  No existing copilot found. Building template..." -ForegroundColor Gray

        # [2/5] Build template
        Write-Host "[2/5] Building template..." -ForegroundColor Cyan
        $mainPromptBody = Get-PromptBody -Path $mainPromptPath
        $humanizerPromptBody = Get-PromptBody -Path $humanizerPromptPath
        $briefingPromptBody = Get-PromptBody -Path $briefingPromptPath
        $orchestratorPromptBody = Get-PromptBody -Path $orchestratorPromptPath
        $baseTemplate = Get-Content -Path $baseTemplatePath -Raw
        $fullTemplate = $baseTemplate.TrimEnd() + "`n" +
            (Get-MainTriageComponent -PromptBody $mainPromptBody) + "`n" +
            (Get-HumanizerComponent -PromptBody $humanizerPromptBody) + "`n" +
            (Get-DailyBriefingComponent -PromptBody $briefingPromptBody) + "`n" +
            (Get-OrchestratorComponent -PromptBody $orchestratorPromptBody) + "`n"

        $templatePath = Join-Path $workDir "ewa-template.yaml"
        Set-Content -Path $templatePath -Value $fullTemplate -Encoding UTF8
        New-CleanKickStartTemplate -SourcePath $kickStartTemplatePath -DestinationPath (Join-Path $workDir "kickStartTemplate-1.0.0.json") -DisplayName $DisplayName

        # [3/5] Create copilot
        Write-Host "[3/5] Creating the copilot..." -ForegroundColor Cyan
        Push-Location $workDir
        try {
            $createResult = Invoke-PacCommand -Arguments @(
                "copilot", "create",
                "--environment", $EnvironmentId,
                "--schemaName", $SchemaName,
                "--templateFileName", $templatePath,
                "--displayName", $DisplayName,
                "--solution", $SolutionName
            )
        }
        finally {
            Pop-Location
        }

        if ($createResult.ExitCode -ne 0) {
            throw "Copilot creation failed: $($createResult.Output)"
        }

        # PAC CLI can return exit code 0 but include errors in output (e.g., solution not found).
        # Detect this and fail early with a clear message.
        if ($createResult.Output -match "(?i)Error:.*ObjectDoesNotExist|Error:.*solution.*not valid") {
            throw "Copilot creation failed silently. PAC CLI output:`n$($createResult.Output)"
        }

        $idMatch = [regex]::Match($createResult.Output, "id\s+(?<id>[0-9a-fA-F-]{36})")
        if ($idMatch.Success) {
            $botId = $idMatch.Groups["id"].Value
        }
        else {
            $botId = Get-ExistingCopilotId -EnvironmentId $EnvironmentId -DisplayName $DisplayName
        }

        if (-not $botId) {
            throw "Copilot creation reported success, but the new copilot ID could not be resolved."
        }

        Write-Host "  ✓ Copilot created: $botId" -ForegroundColor Green
    }

    # [4/5] Publish
    Write-Host "[4/5] Publishing the copilot..." -ForegroundColor Cyan
    $publishResult = Invoke-PacCommand -Arguments @(
        "copilot", "publish",
        "--environment", $EnvironmentId,
        "--bot", $botId
    )

    if ($publishResult.ExitCode -ne 0) {
        throw "Copilot publish failed: $($publishResult.Output)"
    }

    Write-Host "  ✓ Copilot published" -ForegroundColor Green

    # [5/5] Validate + manual steps reminder
    Write-Host "[5/5] Validating the created topics..." -ForegroundColor Cyan
    Push-Location $workDir
    try {
        Test-CopilotTemplate -EnvironmentId $EnvironmentId -BotId $botId -WorkingDirectory $workDir
    }
    finally {
        Pop-Location
    }

    Write-Host "  ✓ Main Triage, Humanizer, Daily Briefing, and Orchestrator topics verified" -ForegroundColor Green

    Write-Host "`nProvisioning complete." -ForegroundColor Green
    Write-Host "Copilot ID: $botId" -ForegroundColor Gray

    Write-Host "`n⚠️  Manual steps required:" -ForegroundColor Yellow
    Write-Host "  1. Copilot Studio → Tools → Add MCP server for Bing WebSearch (Streamable transport)" -ForegroundColor Yellow
    Write-Host "  2. Copilot Studio → Tools → Add MCP server for Microsoft Learn (Streamable transport)" -ForegroundColor Yellow
    Write-Host "  3. Humanizer Agent → Settings → Enable 'Let other agents connect'" -ForegroundColor Yellow
}
finally {
    if (Test-Path $workDir) {
        Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
