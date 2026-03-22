# Deployment Guide

End-to-end deployment checklist for the Intelligent Work Layer solution.

## Prerequisites

### Development Tools

- [ ] **Bun** >= 1.x (Tested with Bun 1.3.8) — *recommended for faster installs/builds*
  - macOS: `brew install oven-sh/bun/bun`
  - Windows: `powershell -c "irm bun.sh/install.ps1|iex"`
- [ ] **Node.js** >= 20 (Tested with Node.js 20.x) — *alternative to Bun; `npm` works in place of `bun` for all commands*
  - macOS: `brew install node@20`
  - Windows: `winget install OpenJS.NodeJS.LTS`
- [ ] **.NET SDK** (required for PAC CLI)
  - macOS: `brew install --cask dotnet-sdk`
  - Windows: `winget install Microsoft.DotNet.SDK.8`

> **Bun vs npm**: All build/test commands work with either Bun (`bun install`, `bun run build`) or npm (`npm install`, `npm run build`). This guide uses Bun in examples; substitute `npm` if preferred.

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

> **Important**: Save the **Environment ID** and **Organization URL** (e.g., `https://orgname.crm.dynamics.com`) from the script output. You will need these values in later steps.

### 1.3 Enable PCF for Canvas Apps

This is now automated by `provision-environment.ps1` (step 2b) via the Power Platform Admin API. If the API call failed during provisioning, enable it manually:

1. Go to **Power Platform Admin Center** → **Environments** → select your environment
2. Click **Settings** → expand **Product** → click **Features**
3. Scroll to **Power Apps component framework for canvas apps** section
4. Toggle **"Allow publishing of canvas apps with code components"** → **On**
5. Click **Save**

### 1.4 Create Security Roles

```powershell
.\create-security-roles.ps1 -OrgUrl "https://<your-org>.crm.dynamics.com"
```

### 1.5 Assign Security Role to Demo User

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

### 1.7 Create Connections

Manually create connections in Power Automate for:

1. **Office 365 Outlook** — email triggers and send actions
2. **Microsoft Teams** — message triggers
3. **Office 365 Users** — user profile lookup (`Get my profile V2`)
4. **Microsoft Graph** — calendar events, people search
5. **SharePoint** — internal knowledge search

Navigate to: Power Automate → Connections → New connection

> **Why manual?** Connection creation requires interactive OAuth consent — each connection opens a browser popup for the user to sign in. This cannot be automated via API.

After creating connections, validate they are active:

```powershell
.\validate-connections.ps1 -EnvironmentId "<your-environment-id>"
```

> **Note on connections vs. connection references**: For initial development, you only need standard connections. For multi-environment deployment, convert to connection references inside a solution.

---

## Phase 2 — Copilot Studio Agent Setup

### 2.1 Create the Main Agent

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

Create five input variables in the agent. For each variable:

1. In Copilot Studio, open the agent → navigate to **Topics** → open the topic that handles the flow invocation
2. In the topic's **Trigger** node, click **+ Add an input** (or **Edit inputs**)
3. Set the **Name**, **Type**, and **Description** as shown below
4. For required variables, set **Is required** → Yes

| Variable | Type | Description | Required | Default |
|----------|------|-------------|----------|---------|
| TRIGGER_TYPE | Choice (EMAIL, TEAMS_MESSAGE, CALENDAR_SCAN) | Signal type | Yes | N/A |
| PAYLOAD | Multi-line text | Raw content JSON | Yes | N/A |
| USER_CONTEXT | Text | Comma-separated string: "DisplayName, JobTitle, Department" | Yes | N/A |
| CURRENT_DATETIME | Text | ISO 8601 timestamp | Yes | N/A |
| SENDER_PROFILE | Multi-line text | Serialized sender profile JSON from SenderProfile table, or the string 'null' for first-time senders. Contains signal_count, response_rate, avg_response_hours, dismiss_rate, avg_edit_distance, sender_category, is_internal. Populated by trigger flows (Flows 1-3) before agent invocation. Enables sender-adaptive triage threshold adjustments. | Optional | null if no profile exists |

> **Why manual?** Copilot Studio does not expose an API for creating agent input variables. This must be done through the Copilot Studio designer UI.

### 2.4 Register Research Tools (Actions)

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

## Phase 3 — Agent Flow Creation

Build the three agent flows following `docs/agent-flows.md`:

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

**Manual steps after provisioning:**
1. In Copilot Studio → Tools → Add **Microsoft Learn Docs MCP Server** from the built-in catalog
2. (Optional) Add additional MCP servers from the built-in catalog as needed (e.g., Dataverse, Microsoft Search)

> **Note:** Bing WebSearch MCP was retired (December 2024). Microsoft Learn Docs MCP replaces the learn.microsoft.com search capability. The Humanizer is provisioned as a **topic within the main agent**, not a standalone agent — no separate agent-sharing configuration is needed.

### 5.3 Deploy Agent Flows

#### Tool Flows (10 agent tool flows)

> **⚠️ IMPORTANT:** Agent tool flows use the `PowerVirtualAgents` trigger kind (`"When an agent calls the flow"`), which **cannot** be created via the Flow Management API. The API rejects this trigger kind with a deserialization error. Tool flows must be created via one of:
>
> 1. **Copilot Studio (recommended for POC):** Add Actions to the agent in the Copilot Studio designer — this auto-creates the tool flows
> 2. **Solution export/import (recommended for CI/CD):** `pac solution export` from a source environment → `pac solution import` to target. Post-import, re-associate the `botcomponent_workflow` N:N relationship via Dataverse API
>
> The `src/tool-*.json` files serve as **reference definitions** documenting the expected trigger schema, inputs, outputs, and action steps for each tool flow.

#### Main Flows (13 operational flows)

```bash
pwsh deploy-agent-flows.ps1 -EnvironmentId "<env-id>" -OrgUrl "https://<org>.crm.dynamics.com" -FlowsToCreate MainFlows
```

This deploys the 13 main flows (signal triggers, operations, scheduled tasks, and maintenance) via the Flow Management API. The JSON definitions in `src/flow-*.json` are POC scaffolding — some flows may require manual building or correction in the Power Automate designer following the step-by-step specs in `docs/agent-flows.md`.

Required connectors: Office 365 Outlook, Office 365 Users, Microsoft Teams, Microsoft Dataverse, HTTP with Entra ID, Microsoft Copilot Studio.

> **Note — Learning System Flows (Phase 5):** The learning subsystem flows (Flow 11: Heartbeat/Background Assessment, Flow 14: Memory Retention, Flow 15: Reflection/Knowledge Extraction, Flow 16: Memory Decay) are **not deployed by the current scripts**. These are documented in [`learning-enhancements.md`](learning-enhancements.md) as a future enhancement. The Dataverse tables they require (EpisodicMemory, SemanticKnowledge, UserPersona, SkillRegistry) are provisioned by `provision-environment.ps1`, but the flows themselves must be built manually when the learning system is implemented.

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

Create the four documented environment variables with the provisioning script:

```powershell
pwsh provision-env-variables.ps1 `
    -OrgUrl "https://<org>.crm.dynamics.com" `
    -AdminNotificationEmail "admin@contoso.com"
```

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

---

## Phase 8 — Sprint Extensions

This section covers new Dataverse columns, scheduled maintenance flows, Copilot Studio topics, and agent tool flows added in recent sprints.

### 8.1 New Dataverse Columns

Provision the following columns on existing tables. If using `provision-environment.ps1`, these are included in the latest version. For manual provisioning, add them via the Power Platform Admin Center or Dataverse Web API.

**AssistantCard table (`cr_assistantcard`):**

| Column | Logical Name | Type | Description |
|--------|-------------|------|-------------|
| Snoozed Until | `cr_snoozeduntil` | DateTime | ISO 8601 timestamp indicating when a snoozed/deferred card should resurface |
| Triage Reasoning | `cr_triagereasoning` | Multi-line text | Agent-generated explanation of why the card was triaged at its current tier |
| Focus Shield Active | `cr_focusshieldactive` | Boolean | Whether this card is currently suppressed by the user's Focus Shield |

**UserPersona table (`cr_userpersona`):**

| Column | Logical Name | Type | Description |
|--------|-------------|------|-------------|
| Autonomy Tier | `cr_autonomytier` | Choice (LOW, MEDIUM, HIGH) | Graduated autonomy level controlling how much the agent acts without confirmation |
| Total Interactions | `cr_totalinteractions` | Whole Number | Cumulative count of user interactions for autonomy graduation |
| Acceptance Rate | `cr_acceptancerate` | Decimal | Rolling acceptance rate of agent suggestions (0.0-1.0) |
| Tone Baseline | `cr_tonebaseline` | Multi-line text | JSON baseline of the user's communication tone preferences per recipient category |

### 8.2 Scheduled Maintenance Flows (Flows 11-13)

Three new scheduled flows handle background maintenance. These are recurrence-triggered with no user interaction. See [`agent-flows.md`](agent-flows.md) for full step-by-step build instructions.

| Flow | Name | Trigger | Interval | Connector |
|------|------|---------|----------|-----------|
| 11 | External Action Scanner | Recurrence | Every 15 minutes | Dataverse + Office 365 Outlook |
| 12 | LIGHT Auto-Archive | Recurrence | Every 6 hours | Dataverse |
| 13 | Data Retention | Recurrence | Weekly (Sunday 02:00 UTC) | Dataverse |

Deploy these flows manually in Power Automate or add them to the `deploy-agent-flows.ps1` script. They require only standard connectors (Dataverse and Office 365 Outlook) and no agent invocations.

### 8.3 New Copilot Studio Topics

Import the following topic YAML files into the Copilot Studio agent:

| Topic | File | Purpose |
|-------|------|---------|
| Draft Refiner | `src/draft-refiner-topic.yaml` | Handles iterative draft refinement requests (e.g., "make it shorter", "more formal") |
| Delegation | `src/delegation-topic.yaml` | Routes task delegation commands to the delegation agent for assignment and tracking |

To import: In Copilot Studio, open the agent → **Topics** → **Import** → select the YAML file. Alternatively, include them in the solution export/import workflow.

### 8.4 New Agent Tool Flows

Seven new tool flows extend the agent's action capabilities. Like existing tool flows, these use the `PowerVirtualAgents` trigger kind and must be created via Copilot Studio Actions or solution import (not the Flow Management API).

| Tool Flow | File | Purpose |
|-----------|------|---------|
| Query OneNote | `src/tool-query-onenote.json` | Search the assistant OneNote notebook by keyword or section |
| Update OneNote | `src/tool-update-onenote.json` | Create or append to a OneNote page |
| Query Skills | `src/tool-query-skills.json` | Look up available skills from the Skill Registry |
| Execute Skill | `src/tool-execute-skill.json` | Run a registered skill with parameters |
| Assign Task | `src/tool-assign-task.json` | Delegate a task to another user via Planner/To Do |
| Track Completion | `src/tool-track-completion.json` | Monitor delegated task completion status |
| Promote Knowledge | `src/tool-promote-knowledge.json` | Promote an episodic memory to semantic knowledge |
| Analyze Sent Patterns | `src/tool-analyze-sent-patterns.json` | Analyze the user's sent email patterns for tone and frequency insights |

Register each tool in Copilot Studio: **Actions** → **Add an action** → select the corresponding flow.

---

## Pre-Flight Validation

Before starting the demo, run the master validation script to catch any issues:

```powershell
cd intelligent-work-layer/scripts
.\validate-demo-readiness.ps1 `
    -EnvironmentId "<your-environment-id>" `
    -OrgUrl "https://<your-org>.crm.dynamics.com"
```

This checks all 9 Dataverse tables, critical columns, security roles, connections, DLP policies, environment variables, the Copilot Studio agent, and the PCF solution. Fix any ❌ failures before proceeding.

> **Tip**: Use `-SkipDlp` in sandbox environments without DLP policies. Use `-SkipConnections` if connection API access is restricted.

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

> If the CALENDAR_SCAN flow is configured, you can also test it by clicking "Run" manually in Power Automate (no need to wait for the daily schedule).

---

## Knowledge Source Configuration

The Copilot Studio agent requires knowledge sources to research incoming signals. Configure these after publishing the agent.

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

### Advanced: YAML-Based Knowledge Source Configuration

> **⚠️ Internal reference — not publicly documented by Microsoft yet.** This technique was validated via testing but may change. Use at your own discretion.

Knowledge sources can be configured programmatically via YAML using the `KnowledgeSourceConfiguration` kind. This enables **conditional filtering** — activating specific knowledge sources only when runtime conditions are met (e.g., user location, department, role).

#### YAML Syntax

```yaml
# Name: <descriptive name>
# <optional comment>
kind: KnowledgeSourceConfiguration
source:
  kind: SharePointSearchSource
  triggerCondition: =<Power Fx boolean expression>
  site: https://<tenant>.sharepoint.com/sites/<site>/<path>
```

#### Key Fields

| Field | Description |
|-------|-------------|
| `kind` | Always `KnowledgeSourceConfiguration` |
| `source.kind` | Source type: `SharePointSearchSource`, `DataverseSearchSource`, `WebsiteSearchSource`, etc. |
| `source.triggerCondition` | Power Fx expression (prefixed with `=`) that evaluates to `true`/`false`. The knowledge source is only searched when the condition is `true`. References global variables set in earlier topic nodes. |
| `source.site` | URL of the SharePoint site/library (for SharePoint sources) |

#### IWL-Relevant Examples

**Location-based filtering** (e.g., multi-region knowledge bases):

```yaml
kind: KnowledgeSourceConfiguration
source:
  kind: SharePointSearchSource
  triggerCondition: =Global.UserDepartment = "Engineering"
  site: https://contoso.sharepoint.com/sites/EngineeringKB
```

**Trigger-type filtering** (e.g., only search project docs for calendar items):

```yaml
kind: KnowledgeSourceConfiguration
source:
  kind: SharePointSearchSource
  triggerCondition: =Global.TriggerType = "CALENDAR_SCAN"
  site: https://contoso.sharepoint.com/sites/ProjectDocs
```

**Role-based filtering** (e.g., executive-only competitive intel):

```yaml
kind: KnowledgeSourceConfiguration
source:
  kind: SharePointSearchSource
  triggerCondition: =Global.UserRole = "Executive"
  site: https://contoso.sharepoint.com/sites/CompetitiveIntel
```

#### How to Deploy

1. Export the agent solution: `pac solution export --path ./solution.zip --name EnterpriseWorkAssistant`
2. Extract the ZIP and locate the bot component YAML files
3. Add `KnowledgeSourceConfiguration` entries to the agent's component definitions
4. Re-import: `pac solution import --path ./solution.zip`

Alternatively, configure knowledge sources in the Copilot Studio UI first, then export the solution to inspect and modify the generated YAML.

#### Prerequisites for triggerCondition

The global variables referenced in `triggerCondition` (e.g., `Global.UserDepartment`) must be set **before** the knowledge source is evaluated. Typically this means:

1. Create a global variable in the agent (e.g., `Global.UserDepartment`)
2. In a "On conversation start" or trigger topic, populate it (e.g., from `USER_CONTEXT` input or Office 365 Users connector)
3. The `triggerCondition` then references this variable

> **See also**: `src/knowledge-sources-example.yaml` for a complete reference file with IWL-specific patterns.

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

---

## Rollback Procedure

If deployment fails midway, use these steps to recover:

### Rolling Back Dataverse Tables

Tables created by `provision-environment.ps1` are idempotent — re-running the script skips existing tables. To fully remove and recreate:

1. **Delete tables** in Power Platform Admin Center → Environments → Settings → Customizations → Entities (or via Dataverse Web API: `DELETE /api/data/v9.2/EntityDefinitions(LogicalName='cr_assistantcard')`)
2. Re-run `provision-environment.ps1`

> **⚠️ Warning**: Deleting tables destroys all data. Only do this in development environments.

### Rolling Back Flows

1. **Delete flows** in Power Automate → My flows → select flow → Delete
2. Re-run `deploy-agent-flows.ps1`

### Rolling Back the Copilot Studio Agent

1. **Delete the agent** in Copilot Studio → select agent → Settings → Delete
2. Re-run `provision-copilot.ps1`

### Rolling Back the PCF Solution

```powershell
# Remove the solution (preserves the environment)
pac solution delete --solution-name "AssistantDashboard"
```

### Full Environment Reset

For a complete restart, delete the environment and re-provision:

```powershell
pac admin delete --environment "<environment-id>"
.\provision-environment.ps1 -TenantId "<tenant-id>"
```
