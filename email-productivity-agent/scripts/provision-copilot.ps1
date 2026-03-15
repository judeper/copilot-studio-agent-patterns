<#
.SYNOPSIS
    Creates and publishes the Email Productivity Agent copilot from repo assets.

.DESCRIPTION
    Builds a Copilot Studio template from the repo's base bot template plus the
    Email Productivity Agent follow-up and snooze prompts, then creates or reuses
    the `Email Productivity Agent` copilot in the target environment and publishes it.

    This script automates the Copilot Studio portion of the EPA setup that was
    previously manual. It provisions two flow-invoked topics:
      - Follow-Up Nudge
      - Snooze Auto-Removal

    The generated topics use generative actions and return raw JSON through the
    `AgentResponseJSON` output expected by the EPA flows.

.PARAMETER EnvironmentId
    Power Platform environment ID (GUID).

.PARAMETER DisplayName
    Display name of the copilot. Default: "Email Productivity Agent"

.PARAMETER SchemaName
    Schema name (unique name) of the copilot. Default: "cr_emailproductivityagent"

.PARAMETER SolutionName
    Solution name that should contain the copilot. Default: "EmailProductivityAgent"

.EXAMPLE
    .\provision-copilot.ps1 `
        -EnvironmentId "af3070e1-da9a-e06b-85e5-dec492b54d1d"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [string]$DisplayName = "Email Productivity Agent",

    [string]$SchemaName = "cr_emailproductivityagent",

    [string]$SolutionName = "EmailProductivityAgent"
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
    $match = [regex]::Match($result.Output, "(?m)^\s*$escapedName\s+(?<id>[0-9a-fA-F-]{36})\s*")
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
    $template.metadata.description = "$DisplayName for follow-up nudges and snooze auto-removal."
    $template.content.displayName = $DisplayName
    $template.content.description = "Evaluates unreplied emails and snoozed replies and returns raw JSON decisions to Power Automate flows."
    $template.content.instructions = "When invoked by automated flows, use the active topic instructions and return raw JSON only."
    $template.spec.connectors = @()

    $template | ConvertTo-Json -Depth 20 | Set-Content -Path $DestinationPath -Encoding UTF8
}

function Get-FollowUpNudgeComponent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PromptBody
    )

    $instructions = Format-YamlLiteralBlock -Value $PromptBody -Indent 14

    return @"
  - kind: DialogComponent
    managedProperties:
      isCustomizable: false

    displayName: Follow-Up Nudge
    description: Evaluate unreplied emails for follow-up nudges and return raw JSON for Flow 2.
    shareContext: {}
    state: Active
    status: Active
    schemaName: template-content.topic.FollowUpNudge
    dialog:
      kind: AdaptiveDialog
      modelDisplayName: Follow-Up Nudge
      modelDescription: Evaluate unreplied emails for follow-up nudges and return JSON.
      inputs:
        - kind: AutomaticTaskInput
          propertyName: CONVERSATION_ID
          description: The Microsoft Graph conversationId that uniquely identifies the email thread being tracked for follow-up
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: ORIGINAL_SUBJECT
          description: Subject line of the original sent email that has not received a reply
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: RECIPIENT_EMAIL
          description: Email address of the specific recipient who has not replied to the sent email
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: RECIPIENT_TYPE
          description: Recipient classification: Internal, External, Priority, or General
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: DAYS_SINCE_SENT
          description: Number of calendar days that have elapsed since the original email was sent
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: THREAD_EXCERPT
          description: Plain text excerpt of the most recent messages in the email thread, up to 2000 characters, for context
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: USER_DISPLAY_NAME
          description: Display name of the user who sent the original email
          shouldPromptUser: false

      beginDialog:
        kind: OnRecognizedIntent
        id: main
        intent: {}
        actions:
          - kind: SearchAndSummarizeContent
            id: generateNudge
            autoSend: false
            variable: Topic.AgentResponseJSON
            responseCaptureType: TextOnly
            userInput: =Concatenate("FLOW_MESSAGE: ", System.Activity.Text, Char(10), "CONVERSATION_ID: ", Topic.CONVERSATION_ID, Char(10), "ORIGINAL_SUBJECT: ", Topic.ORIGINAL_SUBJECT, Char(10), "RECIPIENT_EMAIL: ", Topic.RECIPIENT_EMAIL, Char(10), "RECIPIENT_TYPE: ", Topic.RECIPIENT_TYPE, Char(10), "DAYS_SINCE_SENT: ", Text(Topic.DAYS_SINCE_SENT), Char(10), "THREAD_EXCERPT: ", Topic.THREAD_EXCERPT, Char(10), "USER_DISPLAY_NAME: ", Topic.USER_DISPLAY_NAME)
            additionalInstructions: |-
$instructions
            webBrowsing: false
            searchEmails: false
            fileSearchDataSource:
              searchFilesMode:
                kind: DoNotSearchFiles

          - kind: EndDialog
            id: endNudge

      inputType:
        properties:
          CONVERSATION_ID:
            displayName: CONVERSATION_ID
            description: The Microsoft Graph conversationId that uniquely identifies the email thread being tracked for follow-up
            type: String

          DAYS_SINCE_SENT:
            displayName: DAYS_SINCE_SENT
            description: Number of calendar days that have elapsed since the original email was sent
            type: Number

          ORIGINAL_SUBJECT:
            displayName: ORIGINAL_SUBJECT
            description: Subject line of the original sent email that has not received a reply
            type: String

          RECIPIENT_EMAIL:
            displayName: RECIPIENT_EMAIL
            description: Email address of the specific recipient who has not replied to the sent email
            type: String

          RECIPIENT_TYPE:
            displayName: RECIPIENT_TYPE
            description: Recipient classification: Internal, External, Priority, or General
            type: String

          THREAD_EXCERPT:
            displayName: THREAD_EXCERPT
            description: Plain text excerpt of the most recent messages in the email thread, up to 2000 characters, for context
            type: String

          USER_DISPLAY_NAME:
            displayName: USER_DISPLAY_NAME
            description: Display name of the user who sent the original email
            type: String

      outputType:
        properties:
          AgentResponseJSON:
            displayName: AgentResponseJSON
            description: Structured JSON with nudgeAction, skipReason, threadSummary, suggestedDraft, nudgePriority, and confidence
            type: String
"@
}

function Get-SnoozeAutoRemovalComponent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PromptBody
    )

    $instructions = Format-YamlLiteralBlock -Value $PromptBody -Indent 14

    return @"
  - kind: DialogComponent
    managedProperties:
      isCustomizable: false

    displayName: Snooze Auto-Removal
    description: Decide whether a snoozed conversation should be unsnoozed and return raw JSON for Flow 4.
    shareContext: {}
    state: Active
    status: Active
    schemaName: template-content.topic.SnoozeAutoRemoval
    dialog:
      kind: AdaptiveDialog
      modelDisplayName: Snooze Auto-Removal
      modelDescription: Decide whether a snoozed conversation should be unsnoozed and return JSON.
      inputs:
        - kind: AutomaticTaskInput
          propertyName: CONVERSATION_ID
          description: The Microsoft Graph conversationId of the snoozed email thread that received a new reply
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: NEW_MESSAGE_SENDER
          description: Email address of the sender who authored the new reply that triggered auto-unsnooze evaluation
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: NEW_MESSAGE_SENDER_NAME
          description: Display name of the sender who authored the new reply that triggered auto-unsnooze evaluation
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: NEW_MESSAGE_SUBJECT
          description: Subject line of the newly received reply message
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: NEW_MESSAGE_EXCERPT
          description: Plain text excerpt of the new reply, up to 500 characters, used to detect out-of-office responses and urgency
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: SNOOZED_SUBJECT
          description: Subject line of the original snoozed conversation
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: SNOOZE_UNTIL
          description: Snooze expiration timestamp for the tracked conversation, if one exists
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: USER_TIMEZONE
          description: User timezone identifier from Microsoft 365 or a fallback default, used for working-hours suppression
          shouldPromptUser: false

        - kind: AutomaticTaskInput
          propertyName: CURRENT_DATETIME
          description: Current UTC timestamp when the flow invokes the Snooze Agent
          shouldPromptUser: false

      beginDialog:
        kind: OnRecognizedIntent
        id: main
        intent: {}
        actions:
          - kind: SearchAndSummarizeContent
            id: generateSnoozeDecision
            autoSend: false
            variable: Topic.AgentResponseJSON
            responseCaptureType: TextOnly
            userInput: =Concatenate("FLOW_MESSAGE: ", System.Activity.Text, Char(10), "CONVERSATION_ID: ", Topic.CONVERSATION_ID, Char(10), "NEW_MESSAGE_SENDER: ", Topic.NEW_MESSAGE_SENDER, Char(10), "NEW_MESSAGE_SENDER_NAME: ", Topic.NEW_MESSAGE_SENDER_NAME, Char(10), "NEW_MESSAGE_SUBJECT: ", Topic.NEW_MESSAGE_SUBJECT, Char(10), "NEW_MESSAGE_EXCERPT: ", Topic.NEW_MESSAGE_EXCERPT, Char(10), "SNOOZED_SUBJECT: ", Topic.SNOOZED_SUBJECT, Char(10), "SNOOZE_UNTIL: ", Topic.SNOOZE_UNTIL, Char(10), "USER_TIMEZONE: ", Topic.USER_TIMEZONE, Char(10), "CURRENT_DATETIME: ", Topic.CURRENT_DATETIME)
            additionalInstructions: |-
$instructions
            webBrowsing: false
            searchEmails: false
            fileSearchDataSource:
              searchFilesMode:
                kind: DoNotSearchFiles

          - kind: EndDialog
            id: endSnooze

      inputType:
        properties:
          CONVERSATION_ID:
            displayName: CONVERSATION_ID
            description: The Microsoft Graph conversationId of the snoozed email thread that received a new reply
            type: String

          NEW_MESSAGE_EXCERPT:
            displayName: NEW_MESSAGE_EXCERPT
            description: Plain text excerpt of the new reply, up to 500 characters, used to detect out-of-office responses and urgency
            type: String

          NEW_MESSAGE_SENDER:
            displayName: NEW_MESSAGE_SENDER
            description: Email address of the sender who authored the new reply that triggered auto-unsnooze evaluation
            type: String

          NEW_MESSAGE_SENDER_NAME:
            displayName: NEW_MESSAGE_SENDER_NAME
            description: Display name of the sender who authored the new reply that triggered auto-unsnooze evaluation
            type: String

          NEW_MESSAGE_SUBJECT:
            displayName: NEW_MESSAGE_SUBJECT
            description: Subject line of the newly received reply message
            type: String

          SNOOZED_SUBJECT:
            displayName: SNOOZED_SUBJECT
            description: Subject line of the original snoozed conversation
            type: String

          SNOOZE_UNTIL:
            displayName: SNOOZE_UNTIL
            description: Snooze expiration timestamp for the tracked conversation, if one exists
            type: String

          USER_TIMEZONE:
            displayName: USER_TIMEZONE
            description: User timezone identifier from Microsoft 365 or a fallback default, used for working-hours suppression
            type: String

          CURRENT_DATETIME:
            displayName: CURRENT_DATETIME
            description: Current UTC timestamp when the flow invokes the Snooze Agent
            type: String

      outputType:
        properties:
          AgentResponseJSON:
            displayName: AgentResponseJSON
            description: Structured JSON with unsnoozeAction, suppressReason, notificationMessage, urgency, and confidence
            type: String
"@
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

    $validationTemplatePath = Join-Path $WorkingDirectory "epa-validation.yaml"
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
        "displayName: Follow-Up Nudge",
        "displayName: Snooze Auto-Removal",
        "displayName: AgentResponseJSON"
    )

    foreach ($marker in $requiredMarkers) {
        if ($templateText -notmatch [regex]::Escape($marker)) {
            throw "Created copilot is missing expected content marker: $marker"
        }
    }
}

$baseTemplatePath = Join-Path $PSScriptRoot "..\src\copilot-base-template.yaml"
$kickStartTemplatePath = Join-Path $PSScriptRoot "..\src\kickStartTemplate-1.0.0.json"
$nudgePromptPath = Join-Path $PSScriptRoot "..\prompts\nudge-agent-system-prompt.md"
$snoozePromptPath = Join-Path $PSScriptRoot "..\prompts\snooze-agent-system-prompt.md"

Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Email Productivity Agent — Copilot Provisioning    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

if (-not (Get-Command "pac" -ErrorAction SilentlyContinue)) {
    throw "PAC CLI not found. Install: dotnet tool install --global Microsoft.PowerApps.CLI.Tool"
}

foreach ($path in @($baseTemplatePath, $kickStartTemplatePath, $nudgePromptPath, $snoozePromptPath)) {
    if (-not (Test-Path $path)) {
        throw "Required asset not found: $path"
    }
}

if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    throw "Azure CLI not found. Install: winget install Microsoft.AzureCLI"
}

# Ensure the Dataverse solution exists (pac copilot create --solution requires it)
Write-Host "[0/4] Ensuring '$SolutionName' solution exists..." -ForegroundColor Cyan

$pacSelectResult = Invoke-PacCommand -Arguments @("org", "select", "--environment", $EnvironmentId)
if ($pacSelectResult.ExitCode -ne 0) {
    throw "Failed to select environment ${EnvironmentId}: $($pacSelectResult.Output)"
}

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

$workDir = Join-Path $env:TEMP ("epa-copilot-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

try {
    Write-Host "[1/4] Checking for an existing copilot..." -ForegroundColor Cyan
    $botId = Get-ExistingCopilotId -EnvironmentId $EnvironmentId -DisplayName $DisplayName
    if ($botId) {
        Write-Host "  ✓ Copilot already exists: $botId" -ForegroundColor Green
    }
    else {
        Write-Host "  No existing copilot found. Building template..." -ForegroundColor Gray

        $nudgePromptBody = Get-PromptBody -Path $nudgePromptPath
        $snoozePromptBody = Get-PromptBody -Path $snoozePromptPath
        $baseTemplate = Get-Content -Path $baseTemplatePath -Raw
        $fullTemplate = $baseTemplate.TrimEnd() + "`n" +
            (Get-FollowUpNudgeComponent -PromptBody $nudgePromptBody) + "`n" +
            (Get-SnoozeAutoRemovalComponent -PromptBody $snoozePromptBody) + "`n"

        $templatePath = Join-Path $workDir "epa-template.yaml"
        Set-Content -Path $templatePath -Value $fullTemplate -Encoding UTF8
        New-CleanKickStartTemplate -SourcePath $kickStartTemplatePath -DestinationPath (Join-Path $workDir "kickStartTemplate-1.0.0.json") -DisplayName $DisplayName

        Write-Host "[2/4] Creating the copilot..." -ForegroundColor Cyan
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

    Write-Host "[3/4] Publishing the copilot..." -ForegroundColor Cyan
    $publishResult = Invoke-PacCommand -Arguments @(
        "copilot", "publish",
        "--environment", $EnvironmentId,
        "--bot", $botId
    )

    if ($publishResult.ExitCode -ne 0) {
        throw "Copilot publish failed: $($publishResult.Output)"
    }

    Write-Host "  ✓ Copilot published" -ForegroundColor Green

    Write-Host "[4/4] Validating the created topics..." -ForegroundColor Cyan
    Push-Location $workDir
    try {
        Test-CopilotTemplate -EnvironmentId $EnvironmentId -BotId $botId -WorkingDirectory $workDir
    }
    finally {
        Pop-Location
    }

    Write-Host "  ✓ Follow-Up Nudge and Snooze Auto-Removal topics verified" -ForegroundColor Green

    Write-Host "`nProvisioning complete." -ForegroundColor Green
    Write-Host "Copilot ID: $botId" -ForegroundColor Gray
}
finally {
    if (Test-Path $workDir) {
        Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
