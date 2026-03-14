# Deployment Guide

End-to-end deployment checklist for the Intelligent Work Layer solution.

---

## Quick-Start Checklist

Condensed deployment sequence for experienced deployers. Each step references the detailed section below.

| # | Step | Command / Action | Section |
|---|------|-----------------|---------|
| 1 | **Pre-flight validation** | `.\preflight-check.ps1 -EnvironmentId "..." -OrgUrl "..."` | [Phase 0](#phase-0--pre-flight-validation) |
| 2 | **Provision environment & tables** | `.\provision-environment.ps1 -TenantId "..."` | [Phase 1.2](#12-create-environment-and-dataverse-table) |
| 3 | **⚠️ Manual setup** — Enable PCF, create security roles, assign roles, create connections | Portal steps (no CLI) | [Phase 1.3–1.7](#13-enable-pcf-for-canvas-apps) |
| 4 | **⚠️ Create agents in Copilot Studio** — Main agent, JSON output mode, input variables, research tools, publish | Copilot Studio portal | [Phase 2](#phase-2--copilot-studio-agent-setup) |
| 5 | **Populate placeholders** — Fill GUIDs in `copilot-studio/deployment-placeholders.json` | Manual edit | [Phase 2.5a](#25a-fill-in-the-placeholder-file) |
| 6 | **Substitute placeholders** | `.\substitute-placeholders.ps1` (preview with `-WhatIf` first) | [Phase 2.5c](#25c-perform-substitution) |
| 7 | **Deploy topics** | `.\provision-copilot.ps1 -EnvironmentId "..."` | [Phase 5.2](#52-deploy-copilot-studio-agent) |
| 8 | **Deploy flows** | `.\deploy-agent-flows.ps1 -EnvironmentId "..." -OrgUrl "..."` | [Phase 5.3](#53-deploy-agent-flows) |
| 9 | **Deploy PCF + Canvas app** | `.\deploy-solution.ps1 -EnvironmentId "..."` | [Phase 5.1](#51-build-and-deploy) |
| 10 | **Verify** — Schema drift audit + smoke test | `.\audit-schema-drift.ps1 -OrgUrl "..."` then [Smoke Test](#smoke-test-procedure) | [Phase 6.6](#phase-66--schema-drift-audit) |

> **Tip:** Steps 1–3 are sequential. Steps 4–6 must run in order. Steps 7–9 can run in any order once placeholders are substituted. Always finish with step 10.

---

## Prerequisites

### Development Tools

- [ ] **Bun** >= 1.x (Tested with Bun 1.3.8)
  - macOS: `brew install oven-sh/bun/bun`
  - Windows: `powershell -c "irm bun.sh/install.ps1|iex"`
- [ ] **Node.js** >= 20 (Tested with Node.js 20.x)
  - macOS: `brew install node@20`
  - Windows: `winget install OpenJS.NodeJS.LTS`
- [ ] **.NET SDK** (required for PAC CLI)
  - macOS: `brew install --cask dotnet-sdk`
  - Windows: `winget install Microsoft.DotNet.SDK.8`

### Power Platform Tools

- [ ] **PAC CLI** installed (`dotnet tool install --global Microsoft.PowerApps.CLI.Tool`)
- [ ] **Azure CLI** installed (`az` — required for Dataverse API authentication in provisioning scripts)
  - macOS: `brew install azure-cli`
  - Windows: `winget install Microsoft.AzureCLI`
- [ ] **PowerShell 7+** installed

### Environment Requirements

- [ ] Power Platform environment with Copilot Studio capacity allocated
- [ ] Admin access to the target tenant

> **Terminology**: **PCF** = Power Apps Component Framework (the SDK for building custom code components). **RLS** = Row-Level Security (controls which rows each user can see). **DLP** = Data Loss Prevention (policies that control which connectors can be used together).

---

## Phase 0 — Pre-Flight Validation

Before starting any deployment, run the pre-flight check to validate your local environment and (optionally) the target Power Platform environment:

```powershell
cd intelligent-work-layer/scripts

# Local-only checks (tools, placeholder file, schemas)
.\preflight-check.ps1

# Full validation including remote environment checks
.\preflight-check.ps1 `
    -EnvironmentId "<your-environment-id>" `
    -OrgUrl "https://<your-org>.crm.dynamics.com"
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-EnvironmentId` | No | Target Power Platform environment ID. Omit to run local-only checks |
| `-OrgUrl` | No | Dataverse organization URL. Required for table existence and connection checks |
| `-PublisherPrefix` | No | Dataverse publisher prefix (default: `cr`) |
| `-SkipRemote` | No | Explicitly skip all remote checks |

The script validates 7 categories:
1. Required tools (PowerShell 7+, PAC CLI, Azure CLI, Node.js, npm)
2. PAC CLI authentication (active profile exists)
3. Azure CLI authentication
4. Target environment exists and is accessible
5. Dataverse tables match schema definitions
6. Power Platform connections are created and authenticated
7. Deployment placeholder file is complete (all GUIDs filled in)

> **Exit codes:** `0` = all checks passed, `1` = one or more checks failed, `2` = critical error. Resolve all `FAIL` items before proceeding.

---

## Phase 1 — Environment Provisioning

### 1.1 Authenticate

```powershell
# Authenticate PAC CLI
pac auth create --tenant "<your-tenant-id>"

# Authenticate Azure CLI (required for Dataverse API token)
az login --tenant "<your-tenant-id>"
```

### 1.2 Create Environment and Dataverse Table

```powershell
cd intelligent-work-layer/scripts

.\provision-environment.ps1 `
    -TenantId "<your-tenant-id>" `
    -EnvironmentName "EnterpriseWorkAssistant-Dev" `
    -EnvironmentType "Sandbox"
```

This creates:
- A Power Platform environment with Dataverse
- The `cr_assistantcard` table (entity set name `cr_assistantcards`) with all required columns including `cr_triagetier`
- All 9 Dataverse tables (AssistantCards, SenderProfile, BriefingSchedule, ErrorLog, EpisodicMemory, SemanticKnowledge, UserPersona, SkillRegistry, SemanticEpisodic)

> **Important**: Save the **Environment ID** and **Organization URL** (e.g., `https://orgname.crm.dynamics.com`) from the script output. You will need these values in later steps.

> **HEARTBEAT trigger type**: The `cr_triggertype` choice column includes `HEARTBEAT` (value `100000006`). This was added to support the background assessment flow (Flow 11). If you are upgrading an existing environment provisioned before this fix, re-run `provision-environment.ps1` to add the missing choice value — the script is additive and will not duplicate existing values.

### 1.3 ⚠️ Enable PCF for Canvas Apps

> **Manual step** — there is no CLI command for this setting.

1. Go to **Power Platform Admin Center** → **Environments** → select your environment
2. Click **Settings** → expand **Product** → click **Features**
3. Scroll to **Power Apps component framework for canvas apps** section
4. Toggle **"Allow publishing of canvas apps with code components"** → **On**
5. Click **Save**

### 1.4 Create Security Roles

```powershell
.\create-security-roles.ps1 -OrgUrl "https://<your-org>.crm.dynamics.com"
```

### 1.5 ⚠️ Assign Security Role to Demo User

The IWL is a single-user experience — the agent processes signals on behalf of the dashboard owner. Only the **person presenting the demo** needs the role. Senders whose emails/Teams messages trigger the agent do **not** need it.

1. **Power Platform Admin Center** → **Environments** → select your environment
2. Click **Settings** → expand **Users + permissions** → click **Users**
3. Click on the demo presenter's user (e.g., the admin account)
4. Click **Manage security roles** (top toolbar)
5. Check ✅ **"Intelligent Work Layer User"**
6. Click **Save**

### 1.6 Verify Table Naming Consistency

```powershell
.\audit-table-naming.ps1
```

This script verifies that column names, choice values, and references are consistent across all artifacts (schemas, scripts, documentation). Run it after provisioning to catch any drift.

### 1.7 ⚠️ Create Connections

⚠️ Manually create connections in Power Automate for:

1. **Office 365 Outlook** — email triggers and send actions
2. **Microsoft Teams** — message triggers
3. **Office 365 Users** — user profile lookup (`Get my profile V2`)
4. **Microsoft Graph** — calendar events, people search
5. **SharePoint** — internal knowledge search

Navigate to: Power Automate → Connections → New connection

> **Note on connections vs. connection references**: For initial development, you only need standard connections. For multi-environment deployment, convert to connection references inside a solution.

---

## Phase 2 — Copilot Studio Agent Setup

### 2.1 ⚠️ Create the Main Agent

⚠️ These steps must be performed in the Copilot Studio portal:

1. Open **Copilot Studio** → select the provisioned environment
2. Create a new agent: **"Intelligent Work Layer"**
3. Enable **Generative Orchestration**
4. Paste the system prompt from `prompts/main-agent-system-prompt.md` into the system message

### 2.2 Configure JSON Output Mode

Configure the agent's prompt to output JSON format. In Copilot Studio's **Prompt builder**, set the output format to JSON and provide a schema example so the agent returns structured data.

1. Open the prompt in the **Prompt builder**
2. In the top-right corner of the prompt response area, select **JSON** from the output format dropdown (next to "Output:")
3. To customize the format, select the **settings icon** to the left of "Output: JSON"
4. Switch from **Auto detected** to **Custom** by editing the JSON example
5. Paste the following JSON schema example:

```json
{
  "trigger_type": "EMAIL",
  "triage_tier": "FULL",
  "item_summary": "Example summary",
  "priority": "High",
  "temporal_horizon": "N/A",
  "research_log": "Tier 1: searched...",
  "key_findings": "- Finding 1\n- Finding 2",
  "verified_sources": [{"title": "Source", "url": "https://example.com", "tier": 1}],
  "confidence_score": 85,
  "card_status": "READY",
  "draft_payload": {"draft_type": "EMAIL", "raw_draft": "Draft text", "research_summary": "Summary", "recipient_relationship": "Internal colleague", "inferred_tone": "direct", "confidence_score": 85, "user_context": "User Name, Title, Department"},
  "low_confidence_note": null
}
```

6. Select **Apply**, then **Test** to verify the agent returns valid JSON matching the schema, then **Save custom**

> **Note:** The exact UI location may change with Copilot Studio updates. Look for output format or JSON settings in the prompt configuration area.

> **Related**: For Power Automate flow configuration that consumes this JSON output, see [agent-flows.md](agent-flows.md).

*Last verified: Feb 2026*

### 2.3 Set Up Input Variables

Create four input variables in the agent:

| Variable | Type | Description | Required | Default |
|----------|------|-------------|----------|---------|
| TRIGGER_TYPE | Choice (EMAIL, TEAMS_MESSAGE, CALENDAR_SCAN) | Signal type | Yes | N/A |
| PAYLOAD | Multi-line text | Raw content JSON | Yes | N/A |
| USER_CONTEXT | Text | Comma-separated string: "DisplayName, JobTitle, Department" | Yes | N/A |
| CURRENT_DATETIME | Text | ISO 8601 timestamp | Yes | N/A |
| SENDER_PROFILE | Multi-line text | Serialized sender profile JSON from SenderProfile table, or the string 'null' for first-time senders. Contains signal_count, response_rate, avg_response_hours, dismiss_rate, avg_edit_distance, sender_category, is_internal. Populated by trigger flows (Flows 1-3) before agent invocation. Enables sender-adaptive triage threshold adjustments. | Optional | null if no profile exists |

### 2.4 ⚠️ Register Research Tools (Actions)

The main agent's 5-tier research system requires tool actions to access external data. In Copilot Studio, go to **Actions** → **Add an action** for each tool below.

For connector-based actions, select the relevant connector and the specific operation. For custom actions (MCP-based), you will need to configure a custom connector or plugin.

| Action | Connector | Operation | Research Tier |
|--------|-----------|-----------|---------------|
| SearchUserEmail | Office 365 Outlook | Search email (V2) | Tier 1 — Personal Context |
| SearchSentItems | Office 365 Outlook | Search email (V2) on Sent Items folder | Tier 1 — Personal Context |
| SearchTeamsMessages | Microsoft Teams (or Microsoft Search) | Search messages | Tier 1 — Personal Context |
| SearchSharePoint | SharePoint | Search (V2) | Tier 2 — Organizational Knowledge |
| SearchPlannerTasks | Microsoft Graph | `GET /me/planner/tasks` | Tier 3 — Project Tools |
| WebSearch | Bing Search (or MCP plugin) | Web search | Tier 4 — Public Sources |
| SearchMSLearn | Bing Search (or MCP plugin) | Web search with `site:learn.microsoft.com` | Tier 5 — Official Docs |

> **Note on Teams search**: The Microsoft Graph endpoint for searching Teams messages requires the Microsoft Search API (`/search/query` with `entityTypes: ["chatMessage"]`), not a direct chat messages endpoint. Alternatively, use the Microsoft Teams connector's built-in search action or configure a Microsoft Search connector action.

> **Tip**: The agent prompt references these actions by name. If you use different action names, update the corresponding tool references in `prompts/main-agent-system-prompt.md`.

*Last verified: Feb 2026*

### 2.5 Publish the Agent

1. Click **Publish** in the top-right corner of Copilot Studio
2. Wait for publishing to complete (this may take 1-2 minutes)
3. Verify the agent is listed as "Published" in the agent overview

> **Critical**: The agent must be published before Power Automate flows can invoke it. An unpublished agent will cause the "Invoke agent" action to fail.

### 2.6 Verify Agent Publication

After publishing each agent (Main, Humanizer, Daily Briefing, Orchestrator), verify the publication by testing in the Copilot Studio Test pane:

1. Open the agent in Copilot Studio
2. Click **Test** in the top-right corner to open the Test pane
3. Send a sample input matching the agent's expected format:
   - **Main Agent:** Send a sample email signal payload JSON with trigger_type, payload, user_context, and current_datetime fields
   - **Humanizer Agent:** Send a sample draft text for humanization
   - **Daily Briefing Agent:** Send a sample set of open cards JSON
   - **Orchestrator Agent:** Send a natural language command (e.g., "What's urgent?")
4. Confirm the agent returns a valid JSON response matching `output-schema.json` (for the Main Agent) or the expected output format (for other agents)
5. If the agent fails to respond or returns an error, check the system prompt, input variables, and action configurations before proceeding to flow creation

---

## Phase 2.5 — Placeholder Substitution (Copilot Studio Topics)

Before deploying topic YAML files to Copilot Studio, you must substitute environment-specific GUIDs into the topic files. The topic YAML files in `copilot-studio/topics/` contain `{{PLACEHOLDER_NAME}}` tokens that reference AI Builder model GUIDs and Power Automate flow GUIDs specific to your environment.

### 2.5a Fill in the Placeholder File

Edit `copilot-studio/deployment-placeholders.json` and populate every empty value with the actual GUID from your environment:

| Category | Placeholder | Where to Find the GUID |
|----------|-------------|------------------------|
| `AI_BUILDER_MODELS` | `ORCHESTRATOR_MODEL_GUID`, `ROUTER_MODEL_GUID`, `TRIAGE_MODEL_GUID`, etc. | Power Apps → AI models → click the model → copy the Model ID from the URL |
| `POWER_AUTOMATE_FLOWS` | `FLOW_GUID_QUERY_CARDS`, `FLOW_GUID_CREATE_CARD`, etc. | Printed by `deploy-agent-flows.ps1` after deployment, or found in Power Automate → flow details URL |

### 2.5b Preview Substitutions (Dry Run)

```powershell
cd intelligent-work-layer/scripts
.\substitute-placeholders.ps1 -WhatIf
```

This shows all substitutions that would be made without modifying any files. Verify every placeholder maps to a valid GUID.

### 2.5c Perform Substitution

```powershell
.\substitute-placeholders.ps1
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-PlaceholderFile` | No | Path to JSON file (default: `../copilot-studio/deployment-placeholders.json`) |
| `-TopicDir` | No | Directory with `*.topic.mcs.yml` files (default: `../copilot-studio/topics`) |
| `-Revert` | No | Restores `{{PLACEHOLDER_NAME}}` tokens from current GUID values |
| `-WhatIf` | No | Dry-run — shows changes without modifying files |

> **Exit codes:** `0` = success, `1` = placeholder file not found/invalid, `2` = empty placeholder values detected, `3` = substitution write errors.

> **Important:** After substitution, the topic YAML files contain your environment-specific GUIDs. Do **not** commit substituted files to source control. Run `.\substitute-placeholders.ps1 -Revert` before committing to restore the generic `{{PLACEHOLDER}}` tokens.

### 2.5d Push Topics to Copilot Studio

After placeholder substitution, deploy the topic YAML files to Copilot Studio using the provisioning script:

```powershell
.\provision-copilot.ps1 -EnvironmentId "<env-id>"
```

This provisions all 24 topic YAML files from `copilot-studio/topics/` as topics within the agent (including system topics like Greeting, Fallback, Escalate, etc.) and publishes the agent.

> **Manual alternative:** If the script fails or you need fine-grained control, you can import topics manually in Copilot Studio → Topics → Import → upload individual `.topic.mcs.yml` files.

### 2.5e Re-publish After Topic Changes

After any topic YAML change (including placeholder substitution), you **must** re-publish the agent:

1. Open **Copilot Studio** → select the agent
2. Click **Publish** in the top-right corner
3. Wait for "Published" status before testing

---

## Phase 3 — Agent Flow Creation

Build the three signal-trigger flows following `docs/agent-flows.md`:

> **Flow hardening (v2 improvements):** All 10 main flows now include the following production-readiness features. Ensure these are present when building or importing flows:
>
> | Improvement | Description |
> |------------|-------------|
> | **ErrorLog writes** | Each flow has a `Scope_Handle_Errors` block that writes to the `cr_errorlogs` Dataverse table on failure |
> | **Retry policies** | All API calls use `exponential` retry (3 attempts, PT10S–PT1M interval) for transient HTTP 429/5xx errors |
> | **Ownership checks** | Row-creating actions bind `item@odata.bind` to `systemusers({_ownerid_value})` to enforce row-level security |
> | **OData sanitization** | Filter expressions use parameterized choice integer values (e.g., `100000000`) instead of string labels |
> | **Null guards** | `coalesce()` wraps nullable fields (e.g., email subject, sender display name) to prevent null-reference failures |
> | **Admin notification** | Error Scopes send an email to the `AdminNotificationEmail` environment variable on unrecoverable failures |

### 3.1 EMAIL Flow
- Trigger: When a new email arrives (V3)
- Test with a real email to your inbox

### 3.2 TEAMS_MESSAGE Flow
- Trigger: When someone is mentioned (preferred) or When a new channel message is added
- Test by posting in the configured channel

### 3.3 CALENDAR_SCAN Flow
- Trigger: Daily recurrence at 7 AM
- Test by running manually

> **Important**: Review the [agent-flows.md](agent-flows.md) sections on **Row Ownership** (required for RLS), **Parse JSON Schema** (simplified schema without `oneOf`), and **Error Handling** before building flows.

> **Phased rollout tip**: You can start with just the EMAIL flow for initial validation. Once it works end-to-end (email → agent → Dataverse → Canvas app), add the TEAMS_MESSAGE and CALENDAR_SCAN flows incrementally. Steps 3.2 and 3.3 are independent and can be deployed in any order after 3.1.

---

## Phase 4 — Humanizer Agent

### 4.1 Create the Humanizer Agent

1. In Copilot Studio, create a second agent: **"Humanizer Agent"**
2. Paste the prompt from `prompts/humanizer-agent-prompt.md`
3. Publish the agent

### 4.2 Choose Integration Method

Pick **one** of the following approaches (they are mutually exclusive):

**Option A — Flow-based invocation (recommended):**
The Power Automate flows invoke the Humanizer Agent directly in steps 8-10 (see [agent-flows.md](agent-flows.md)). This is the approach documented in the agent flows guide and is recommended for most deployments because it gives you explicit control over when humanization happens.

**Option B — Connected Agent:**
Configure the Humanizer as a Connected Agent available to the main agent within Copilot Studio. In this approach, the main agent orchestrates the humanization call internally. This simplifies the flows but makes the humanization step less visible and harder to debug.

To configure the Humanizer as a Connected Agent: In Copilot Studio, open the main Intelligent Work Layer agent. Navigate to **Actions** -> **Add an action** -> select **Invoke a Copilot agent** -> select the **Humanizer Agent**. Map the input variable `draft_text` to the agent's draft payload (the `raw_draft` field from the main agent's `draft_payload` output). The Connected Agent will return the humanized text, which the main agent can then include in its output.

> Do not use both approaches simultaneously — this would result in double humanization.

---

## Phase 5 — PCF Component Deployment

### 5.1 Build and Deploy

```powershell
.\deploy-solution.ps1 -EnvironmentId "<environment-id>"
```

Or manually:

```bash
cd intelligent-work-layer/src
bun install
bun run build
```

Then pack and import the solution via PAC CLI.

> **Note**: The solution is packaged as **Unmanaged**, which is appropriate for development and testing. For production deployment, change `SolutionPackageType` to `Managed` in `src/Solutions/Solution.cdsproj` before building.

### 5.2 Deploy Copilot Studio Agent

```bash
cd scripts
pwsh provision-copilot.ps1 -EnvironmentId "<env-id>"
```

This creates the Intelligent Work Layer copilot with 4 topics (Main Triage, Humanizer, Daily Briefing, Orchestrator) and publishes it.

⚠️ **Manual steps after provisioning:**
1. ⚠️ In Copilot Studio → Tools → Add **Microsoft Learn Docs MCP Server** from the built-in catalog
2. ⚠️ (Optional) Add additional MCP servers from the built-in catalog as needed (e.g., Dataverse, Microsoft Search)

> **Note:** Bing WebSearch MCP was retired (December 2024). Microsoft Learn Docs MCP replaces the learn.microsoft.com search capability. The Humanizer is provisioned as a **topic within the main agent**, not a standalone agent — no separate agent-sharing configuration is needed.

### 5.3 Deploy Agent Flows

#### Tool Flows (10 agent tool flows)

> **⚠️ IMPORTANT:** Agent tool flows use the `PowerVirtualAgents` trigger kind (`"When an agent calls the flow"`), which **cannot** be created via the Flow Management API. The API rejects this trigger kind with a deserialization error. Tool flows must be created via one of:
>
> 1. **Copilot Studio (recommended for POC):** Add Actions to the agent in the Copilot Studio designer — this auto-creates the tool flows
> 2. **Solution export/import (recommended for CI/CD):** `pac solution export` from a source environment → `pac solution import` to target. Post-import, re-associate the `botcomponent_workflow` N:N relationship via Dataverse API
>
> The `src/tool-*.json` files serve as **reference definitions** documenting the expected trigger schema, inputs, outputs, and action steps for each tool flow.

#### Main Flows (10 operational flows)

```bash
pwsh deploy-agent-flows.ps1 -EnvironmentId "<env-id>" -OrgUrl "https://<org>.crm.dynamics.com" -FlowsToCreate MainFlows
```

This deploys the 10 main flows (signal triggers, operations, scheduled tasks) via the Flow Management API. The JSON definitions in `src/flow-*.json` are POC scaffolding — some flows may require manual building or correction in the Power Automate designer following the step-by-step specs in `docs/agent-flows.md`.

> **v2 flow improvements:** The deployed flow definitions include ErrorLog writes, exponential retry policies, ownership-bound Dataverse rows, OData filter sanitization, and null guards on all nullable trigger fields. If you are building flows manually from `docs/agent-flows.md`, apply these patterns from the JSON reference files. See the [flow hardening table in Phase 3](#phase-3--agent-flow-creation) for the full list.

Required connectors: Office 365 Outlook, Office 365 Users, Microsoft Teams, Microsoft Dataverse, HTTP with Entra ID, Microsoft Copilot Studio.

---

## Phase 6 — Canvas App

Follow `docs/canvas-app-setup.md` to create and configure the Canvas app.

---

## Phase 6.5 — Environment Configuration

### Connection References for Solution Packaging

When packaging the solution for multi-environment deployment, convert direct connections to connection references. Create connection references for each connector used:

| Connection Reference | Connector | Used By |
|---------------------|-----------|---------|
| `cr_Office365Outlook` | Office 365 Outlook | Email trigger flow, Send Email flow |
| `cr_MicrosoftTeams` | Microsoft Teams | Teams Message trigger flow |
| `cr_Office365Users` | Office 365 Users | User profile lookup in all trigger flows |
| `cr_MicrosoftGraph` | Microsoft Graph | Calendar Scan flow, research tool actions |
| `cr_SharePoint` | SharePoint | Research tool action (Tier 2) |
| `cr_Dataverse` | Microsoft Dataverse | All flows (card creation, outcome tracking, sender profiles) |
| `cr_CopilotStudio` | Microsoft Copilot Studio | Agent invocation in all trigger flows |

### Environment Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `AdminNotificationEmail` | Text | Email address for error and monitoring notifications sent by flow error Scopes | (set during deployment) |
| `StalenessThresholdHours` | Number | Hours before a High-priority PENDING card triggers a NUDGE | 24 |
| `ExpirationDays` | Number | Days before a PENDING card expires to EXPIRED | 7 |
| ~~`BriefingScheduleTime`~~ | ~~Text~~ | Replaced by the BriefingSchedule Dataverse table. Each user configures their schedule via the Canvas App UI. The Daily Briefing flow (Flow 6) checks the table every 15 minutes. Default for users without a schedule row: weekdays at 7 AM. | See `schemas/briefingschedule-table.json` |
| `SenderProfileMinSignals` | Number | Minimum signal count before sender categorization activates | 5 |

### Canvas App Formula Reference (PCF-to-Flow Wiring)

The Canvas App connects the PCF component to Power Automate flows through output properties. Key formulas:

- **Send Email:** `If(AssistantDashboard.sendAction <> "", Flow_SendEmail.Run(AssistantDashboard.sendAction))`
- **Dismiss:** Update Dataverse row directly via `Patch(cr_assistantcards, ...)`
- **Command Execution:** `If(AssistantDashboard.commandText <> "", Set(varResponse, Flow_CommandExecution.Run(AssistantDashboard.commandText).response))`
- **Refresh Timer:** `Timer.OnTimerEnd = Refresh(cr_assistantcards)` (30-second interval for staleness refresh)

---

## Phase 6.6 — Schema Drift Audit

After provisioning tables and deploying flows, run the schema drift audit to verify consistency between your local schema files, provisioning scripts, and the live Dataverse environment:

```powershell
cd intelligent-work-layer/scripts

# Offline-only: validate schema files against provision-environment.ps1
.\audit-schema-drift.ps1 -OfflineOnly

# Live: compare schemas against the deployed Dataverse environment
.\audit-schema-drift.ps1 -OrgUrl "https://<your-org>.crm.dynamics.com"
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-OrgUrl` | Yes (unless `-OfflineOnly`) | Dataverse organization URL |
| `-SchemaDir` | No | Path to `*-table.json` schema files (default: `../schemas`) |
| `-ProvisionScript` | No | Path to `provision-environment.ps1` (default: `./provision-environment.ps1`) |
| `-PublisherPrefix` | No | Publisher prefix (default: `cr`) |
| `-OfflineOnly` | No | Skip live Dataverse comparison; validate schema vs. provision script only |

The audit detects:
- Tables defined in schema but missing from Dataverse (or vice versa)
- Columns defined in schema but not provisioned (or vice versa)
- Column type mismatches
- Missing alternate keys
- Broken lookup relationships (referenced tables without schema files)

> **When to run:** After `provision-environment.ps1`, after schema changes, and as part of CI/CD validation. Exit code `1` indicates drift.

---

## Phase 6.7 — OneNote Integration (Optional)

If OneNote integration is desired (Phase 1 — write-only sync for meeting prep, daily briefings, and active to-dos):

### Prerequisites

- Microsoft Graph PowerShell SDK (`Microsoft.Graph.Groups`, `Microsoft.Graph.Notes` modules)
- Authenticated session with `Group.ReadWrite.All` and `Notes.ReadWrite.All` permissions
- Dataverse environment with Assistant Cards table already provisioned

### Provision OneNote

```powershell
.\provision-onenote.ps1 `
    -EnvironmentId "<env-id>" `
    -OrgUrl "https://<your-org>.crm.dynamics.com"
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-EnvironmentId` | Yes | Power Platform environment ID |
| `-OrgUrl` | Yes | Dataverse organization URL |
| `-PublisherPrefix` | No | Publisher prefix (default: `cr`) |
| `-GroupDisplayName` | No | M365 Group name (default: `Intelligent Work Layer - OneNote`) |
| `-NotebookDisplayName` | No | Notebook name (default: `Work Layer`) |
| `-SkipGroupCreation` | No | Skip M365 Group creation; use existing group |
| `-GroupId` | Conditional | Existing M365 Group ID (required when `-SkipGroupCreation` is set) |

### Validate OneNote Integration

After provisioning, run the consistency validator:

```powershell
.\validate-onenote-integration.ps1
```

This checks that OneNote column references, template placeholders, tool action names, and JSON schemas are internally consistent. Run after any changes to OneNote integration files.

> **Feature flags:** OneNote sync is gated by `cr_onenoteenabled` (environment-level) and `cr_onenoteoptout` (per-user). See `docs/onenote-integration.md` for full design.

---

## Phase 7 — Governance

### 7.1 Data Loss Prevention (DLP) Policies

Ensure the environment's DLP policies allow the required connector combinations. All of these connectors must be in the **same DLP group** (typically "Business"):

- Office 365 Outlook + Dataverse
- Microsoft Teams + Dataverse
- Microsoft Graph + Dataverse
- SharePoint + Dataverse
- Copilot Studio + Dataverse

> **Note**: The Copilot Studio connector is required for the "Invoke agent" actions in the Power Automate flows. If it is blocked by DLP, the flows will fail silently.

### 7.2 Audit and Retention

- Enable **Purview/Sentinel auditing** for Copilot Studio agent activities
- Configure **Dataverse retention policy** for AssistantCards (recommended: 30-day auto-delete for dismissed cards)
- Power Automate flow run history provides execution logs

### 7.3 Responsible AI

- Copilot Studio's built-in Responsible AI content filtering is active by default
- Review agent outputs periodically for accuracy and appropriateness

### 7.4 User Data Erasure (GDPR / CCPA)

For GDPR Article 17 (Right to Erasure) or CCPA deletion requests, use the data erasure script:

```powershell
# Dry-run — see what would be deleted
.\user-data-erasure.ps1 `
    -OrgUrl "https://<your-org>.crm.dynamics.com" `
    -UserEmail "user@example.com" `
    -WhatIf

# Actual erasure (interactive confirmation)
.\user-data-erasure.ps1 `
    -OrgUrl "https://<your-org>.crm.dynamics.com" `
    -UserEmail "user@example.com"
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-OrgUrl` | Yes | Dataverse organization URL |
| `-UserEmail` | Yes | Email of the user whose data should be erased |
| `-PublisherPrefix` | No | Publisher prefix (default: `cr`) |
| `-WhatIf` | No | Reports what would be deleted without deleting |
| `-Force` | No | Skips interactive confirmation prompt (for pipelines) |

Purges all 9 Dataverse tables in dependency-safe order. See `docs/data-governance.md` for compliance context.

---

## Verification Checklist

- [ ] Environment provisioned and accessible
- [ ] AssistantCards table has all columns (including `cr_triagetier`)
- [ ] PCF for Canvas apps enabled in environment settings
- [ ] Security role assigned to test users
- [ ] Connections created and authenticated
- [ ] Main agent published and responds with valid JSON
- [ ] Humanizer agent published
- [ ] EMAIL flow fires on new email and writes to Dataverse (verify Owner field is set to triggering user)
- [ ] TEAMS_MESSAGE flow fires on channel message
- [ ] CALENDAR_SCAN flow runs on schedule
- [ ] Humanizer agent produces polished drafts
- [ ] PCF component renders cards in test harness
- [ ] Canvas app shows cards from Dataverse (only current user's cards visible)
- [ ] Filters work correctly
- [ ] Card detail view shows all sections
- [ ] Send, Copy to Clipboard, and Dismiss actions work
- [ ] DLP policies allow all required connector combinations
- [ ] Error logging: trigger flows write to `cr_errorlogs` table on agent invocation failure
- [ ] Retry policies: trigger flows retry transient failures (HTTP 429/5xx) up to 3 times with exponential backoff
- [ ] Error notification: `AdminNotificationEmail` receives alerts when error Scope fires

### Sprint 1A Verification
- [ ] AssistantCards table has `cr_cardoutcome`, `cr_outcometimestamp`, `cr_senttimestamp`, `cr_sentrecipient`, `cr_originalsenderemail`, `cr_originalsenderdisplay`, `cr_originalsubject`
- [ ] New cards created with `cr_cardoutcome = PENDING` and sender fields populated
- [ ] Send Email flow: configured with "Run only users" for Outlook connection
- [ ] Send Email flow: ownership validation prevents cross-user sends
- [ ] Send button visible only on EMAIL FULL READY cards with humanized draft
- [ ] PCF Send → Confirm → Flow → Email delivered → Card shows "Sent ✓"
- [ ] Dismiss updates `cr_cardoutcome = DISMISSED` with timestamp

### Sprint 1B Verification
- [ ] AssistantCards table has `cr_conversationclusterid`, `cr_sourcesignalid`
- [ ] SenderProfile table created with all 8 columns
- [ ] Alternate key on `cr_senderemail` is Active
- [ ] Security role includes SenderProfile table Basic privileges
- [ ] EMAIL flow: sender profile upserted (signal count increments on repeat senders)
- [ ] TEAMS flow: cluster ID uses threadId; sender profile upserted
- [ ] CALENDAR flow: cluster ID uses `seriesMasterId` for recurring events
- [ ] Card Outcome Tracker flow: response count increments on SENT outcomes
- [ ] Card Outcome Tracker flow: does NOT fire on DISMISSED outcomes
- [ ] Running average for `cr_avgresponsehours` calculates correctly

### Sprint 2 Verification
- [ ] Daily Briefing Agent published in Copilot Studio
- [ ] Daily Briefing Flow runs on schedule (weekday 7 AM) and produces briefing card
- [ ] Briefing card renders at top of dashboard with BriefingCard component
- [ ] Action items show rank, summary, recommended action, and calendar correlation
- [ ] "Open card →" links navigate to the referenced card
- [ ] FYI section is collapsible
- [ ] Stale alerts render with amber/red severity indicators
- [ ] Staleness Monitor creates nudge cards for High-priority items >24h PENDING
- [ ] No duplicate nudge cards created for the same source
- [ ] Cards expire to EXPIRED after 7 days PENDING
- [ ] Inline editing: "Edit draft" button appears on sendable cards
- [ ] Inline editing: Modified draft shows "(edited)" in confirmation panel
- [ ] Inline editing: "Revert to original" restores the humanized draft
- [ ] Send Email flow sets SENT_EDITED when final text differs from humanized draft

### Sprint 3 Verification
- [ ] Orchestrator Agent published in Copilot Studio with 6 tool actions registered
- [ ] Humanizer Agent connected as sub-agent for draft refinement
- [ ] Command Execution Flow created (instant trigger, 120s timeout)
- [ ] Command bar renders at bottom of dashboard (persistent in gallery + detail views)
- [ ] Quick action chips visible when command bar not expanded
- [ ] "What's urgent?" returns ranked open items with card links
- [ ] "Remind me to [action] on [date]" creates SELF_REMINDER card
- [ ] Context-aware commands work (e.g., "Make this shorter" with card expanded)
- [ ] "How often do I respond to [sender]?" returns sender profile stats
- [ ] Card links in responses navigate to the referenced card
- [ ] Conversation history maintained within session (cleared on clear button)
- [ ] Error handling: invalid commands return graceful fallback response
- [ ] SELF_REMINDER and COMMAND_RESULT trigger types provisioned in Dataverse

### Sprint 4 Verification
- [ ] Sprint 4 SenderProfile columns provisioned (dismiss_count, avg_edit_distance, response_rate, dismiss_rate)
- [ ] Sender Profile Analyzer flow runs weekly and categorizes senders correctly
- [ ] AUTO_HIGH: response_rate ≥ 0.8 AND avg_response_hours < 8
- [ ] AUTO_LOW: response_rate < 0.4 OR dismiss_rate ≥ 0.6
- [ ] USER_OVERRIDE senders are never recategorized by the analyzer
- [ ] Senders with < 5 total interactions are skipped
- [ ] Card Outcome Tracker increments cr_dismisscount on DISMISSED outcomes
- [x] Trigger flows pass SENDER_PROFILE JSON to the main agent
- [ ] Agent upgrades LIGHT → FULL for AUTO_HIGH senders with actionable content
- [ ] Agent does NOT downgrade FULL → LIGHT for executives/clients regardless of category
- [ ] Confidence scoring applies sender-adaptive modifiers (staleness urgency, edit distance penalty)
- [ ] Confidence Calibration dashboard accessible and shows 4 tabs
- [ ] Confidence accuracy buckets display correct action rates
- [ ] Top Senders tab shows ranked engagement data

---

## Smoke Test Procedure

After completing all phases, run through this end-to-end test to verify the solution works:

1. **Send yourself a test email** with a distinctive subject line (e.g., "Test: Project Alpha budget review needed by Friday")
2. **Wait 1-2 minutes** for the EMAIL flow to trigger
3. **Check Power Automate flow run history** — verify the flow run succeeded (green checkmark). If it failed, click into the run to see which step errored
4. **Open Dataverse** → Tables → Assistant Cards → verify a new row exists with your test email's summary
5. **Open the Canvas app** → verify the card appears in the gallery
6. **Click the card** → verify the detail view renders correctly (summary, priority badge, key findings, sources)
7. **Click Dismiss** → verify the card outcome updates to `DISMISSED` in the `cr_cardoutcome` column in Dataverse
8. **Test filters** → use the dropdown controls to filter by trigger type, priority, and status
9. **Verify error logging** — intentionally trigger an error (e.g., temporarily disable a connection) and confirm:
   - A row is written to the `cr_errorlogs` Dataverse table with the error details
   - The `AdminNotificationEmail` receives an error alert
   - The flow retries transient failures (check the flow run history for retry attempts before final failure)
10. **Run pre-flight check** — after all tests pass, run `.\preflight-check.ps1` with full parameters to confirm all checks still pass
11. **Run schema drift audit** — confirm no drift: `.\audit-schema-drift.ps1 -OrgUrl "https://<org>.crm.dynamics.com"`

> If the CALENDAR_SCAN flow is configured, you can also test it by clicking "Run" manually in Power Automate (no need to wait for the daily schedule).

---

## ⚠️ Knowledge Source Configuration

The Copilot Studio agent requires knowledge sources to research incoming signals. ⚠️ Configure these manually in the Copilot Studio portal after publishing the agent.

### Required Knowledge Sources

| # | Source Type | Content | Purpose |
|---|-----------|---------|---------|
| 1 | **SharePoint Site** | Internal company wiki or knowledge base | Tier 2 research — internal documentation lookup |
| 2 | **Uploaded Documents** | Product/project documentation (PDF, DOCX) | Tier 3 research — domain-specific context |
| 3 | **Public Website** | Company external site or help center URL | Tier 4 research — public information fallback |

### Configuration Steps

1. **Open Copilot Studio** → Select the Intelligent Work Layer agent
2. Navigate to **Knowledge** in the left sidebar
3. Click **+ Add knowledge**
4. For each source type:
   - **SharePoint**: Enter the SharePoint site URL → Select specific document libraries or lists → Click **Add**
   - **Documents**: Upload PDF/DOCX files directly (max 3 MB per file, 10 files) → Click **Add**
   - **Website**: Enter the root URL → Set crawl depth (recommended: 2 levels) → Click **Add**
5. Wait for indexing to complete (status shows "Ready")
6. **Test**: Use the Test pane to ask a question that requires knowledge lookup

> **Note**: Knowledge sources are environment-specific. When moving between dev/test/prod, reconfigure knowledge sources in each environment.

---

## License and Role Requirements

### Power Platform Licenses

| License | Required For | Notes |
|---------|-------------|-------|
| **Power Apps per-user** or **per-app** | Canvas App access | Each user viewing the dashboard needs this |
| **Copilot Studio capacity** | Agent message processing | Billed per message; PAYGO or prepaid capacity |
| **Power Automate per-user** or **included** | Flow execution | Included with most Power Apps licenses for standard connectors |
| **Microsoft 365 E3/E5** or **Exchange Online** | Email/Teams/Calendar triggers | Required for Office 365 Outlook and Teams connectors |

### Dataverse Security Roles

| Role | Assigned To | Permissions |
|------|------------|-------------|
| **AssistantCard User** | All dashboard users | Read/Write own `cr_assistantcard` rows (row-level security) |
| **AssistantCard Admin** | Solution administrators | Full CRUD on all `cr_assistantcard` rows + `cr_briefingschedule` |
| **System Customizer** | Deployment admin (one-time) | Required for solution import and table creation |

### Connector Permissions

| Connector | Auth Type | Permissions Needed |
|-----------|----------|-------------------|
| Office 365 Outlook | Delegated (user) | Mail.Read, Mail.Send |
| Microsoft Teams | Delegated (user) | Chat.Read |
| Office 365 Users | Delegated (user) | User.Read |
| Microsoft Dataverse | Delegated (user) | Entity CRUD (scoped by security role) |
| Microsoft Copilot Studio | Service | Agent invocation |

> **Minimum viable setup for POC**: Power Apps per-user trial + Copilot Studio trial + M365 E3/E5 license. All trials are available from the Microsoft 365 admin center.

---

## Troubleshooting

Common errors and their fixes:

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| "Parse JSON failed" in flow run | Using the canonical `output-schema.json` (which contains `oneOf`) instead of the simplified schema | Use the simplified Parse JSON schema from [agent-flows.md](agent-flows.md) — it uses `{}` for polymorphic fields |
| No cards appearing in Canvas app | Flow isn't running, Owner field not set, or DLP blocking connectors | Check flow run history. Verify the Owner field is set in the "Add a new row" action. Check DLP policies |
| PCF control not showing in Canvas app | PCF for Canvas apps not enabled in environment | Enable in Admin Center → Environments → Settings → Features → "Allow publishing of canvas apps with code components" |
| "Access token failed" in provisioning script | Azure CLI not authenticated | Run `az login --tenant <tenant-id>` before running `provision-environment.ps1` |
| Choice column mismatch (wrong values in Dataverse) | Integer mapping doesn't match schema | Verify the `if()` expression chains in your Compose actions match the values in `schemas/dataverse-table.json` |
| "Invoke agent" action fails | Agent not published, or using wrong connector | Ensure the agent is published in Copilot Studio. Use the **Microsoft Copilot Studio** connector (not AI Builder) |
| Flow runs but no Dataverse row created | Item was triaged as SKIP | SKIP-tier items are filtered out before the Dataverse write. Check the agent's JSON output in the flow run to see the `triage_tier` value |
| Humanized draft not appearing | Confidence score below 40, or trigger type is CALENDAR_SCAN | The humanizer handoff condition requires `triage_tier = FULL`, `confidence_score >= 40`, and `trigger_type != CALENDAR_SCAN` |
| Placeholder substitution used wrong GUIDs | Incorrect values in `deployment-placeholders.json` | Run `.\substitute-placeholders.ps1 -Revert`, fix the JSON, then re-run `.\substitute-placeholders.ps1` |
| Schema drift after manual Dataverse changes | Columns added/removed outside of provisioning script | Run `.\audit-schema-drift.ps1 -OrgUrl "..."` to identify drift, then update schemas or Dataverse to match |

---

## Rollback Procedures

### Reverting Placeholder Substitution

If topic YAML files were substituted with incorrect GUIDs, or you need to restore them to the generic `{{PLACEHOLDER}}` token state:

```powershell
cd intelligent-work-layer/scripts
.\substitute-placeholders.ps1 -Revert
```

This replaces all GUID values in `*.topic.mcs.yml` files back to their `{{PLACEHOLDER_NAME}}` tokens using the current values in `deployment-placeholders.json`. After reverting:

1. Fix the GUID values in `copilot-studio/deployment-placeholders.json`
2. Re-run `.\substitute-placeholders.ps1` with corrected values
3. Re-deploy topics via `.\provision-copilot.ps1 -EnvironmentId "<env-id>"`
4. Re-publish the agent in Copilot Studio

> **Caution:** Revert only works if the GUID values in `deployment-placeholders.json` match what was previously substituted. If the JSON was changed after substitution, you may need to restore topic files from source control: `git checkout -- copilot-studio/topics/`

### Reverting Flow Deployment

If flows deployed but are misconfigured or causing errors:

1. **Disable flows immediately** — In Power Automate, navigate to each IWL flow and click **Turn off** to stop signal processing
2. **Delete and re-deploy** — Delete the problematic flows in Power Automate, fix the underlying issue, then re-run:
   ```powershell
   .\deploy-agent-flows.ps1 -EnvironmentId "<env-id>" -OrgUrl "https://<org>.crm.dynamics.com" -FlowsToCreate MainFlows
   ```
3. **Solution rollback** — If flows were imported via solution:
   ```powershell
   pac solution delete --solution-name EnterpriseWorkAssistant --environment "<env-id>"
   ```
   Then re-import the previous solution version.

### Reverting Agent Publication

If the agent was published with bad topics or system prompt:

1. **Unpublish is not supported** — Copilot Studio does not have a one-click unpublish. Instead:
   - Open the agent in Copilot Studio
   - Fix the problematic topics or system prompt
   - Re-publish with the corrected configuration
2. **Disable agent invocation** — To immediately stop the agent from processing signals while you fix it:
   - Turn off all trigger flows (Flows 1-3) in Power Automate
   - This prevents new signals from reaching the agent without unpublishing
3. **Restore topics from source control** — If topic YAML files are corrupted:
   ```powershell
   git checkout -- copilot-studio/topics/
   .\substitute-placeholders.ps1       # re-apply correct GUIDs
   .\provision-copilot.ps1 -EnvironmentId "<env-id>"
   ```

### Re-provisioning Corrupted Tables

If Dataverse tables are corrupted (wrong column types, missing columns, broken alternate keys):

1. **Run schema drift audit** to identify the exact discrepancies:
   ```powershell
   .\audit-schema-drift.ps1 -OrgUrl "https://<org>.crm.dynamics.com"
   ```
2. **For missing columns/keys** — Re-run the provisioning script. It is designed to be additive (creates missing items without deleting existing data):
   ```powershell
   .\provision-environment.ps1 -TenantId "<tenant-id>"
   ```
3. **For type mismatches** — Column types cannot be changed after creation in Dataverse. You must:
   - Export any data you want to preserve (Dataverse → Export to Excel)
   - Delete the affected table in Dataverse admin
   - Re-run `.\provision-environment.ps1` to recreate it
   - Re-import the data
4. **Nuclear option — full environment reset:**
   ```powershell
   # Delete the environment entirely
   pac admin delete --environment "<env-id>"
   # Re-provision from scratch
   .\provision-environment.ps1 -TenantId "<tenant-id>" -EnvironmentName "EnterpriseWorkAssistant-Dev"
   ```

### Partial Deployment Recovery

If a deployment fails midway through the phases:

| Failed At | What Happened | Recovery Steps |
|-----------|---------------|----------------|
| Phase 1 (provisioning) | Environment created but tables incomplete | Re-run `.\provision-environment.ps1` — it is idempotent |
| Phase 2 (agent setup) | Agent created but topics wrong | Fix topics, re-run `.\provision-copilot.ps1`, re-publish |
| Phase 2.5 (placeholders) | Substitution applied with wrong GUIDs | Run `.\substitute-placeholders.ps1 -Revert`, fix JSON, re-substitute |
| Phase 3 (flows) | Some flows deployed, others failed | Re-run `.\deploy-agent-flows.ps1` — it reuses existing flows by name |
| Phase 5 (PCF) | Solution import failed | Check `deploy-*.log` for errors, fix, re-run `.\deploy-solution.ps1` |
| Phase 6 (Canvas app) | App created but PCF control not bound | Follow `docs/canvas-app-setup.md` to re-bind the control |

> **General principle:** Most IWL provisioning scripts are idempotent — they check for existing resources before creating new ones. When in doubt, re-run the script for the failed phase.
