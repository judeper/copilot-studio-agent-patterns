# Deployment Guide

End-to-end deployment checklist for the Enterprise Work Assistant solution.

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
cd enterprise-work-assistant/scripts

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

This must be done manually — there is no CLI command:

1. Go to **Power Platform Admin Center** → **Environments** → select your environment
2. Click **Settings** → **Features**
3. Enable **Allow publishing of canvas apps with code components**
4. Click **Save**

### 1.4 Create Security Roles

```powershell
.\create-security-roles.ps1 -OrgUrl "https://<your-org>.crm.dynamics.com"
```

### 1.5 Create Connections

Manually create connections in Power Automate for:

1. **Office 365 Outlook** — email triggers and send actions
2. **Microsoft Teams** — message triggers
3. **Office 365 Users** — user profile lookup (`Get my profile V2`)
4. **Microsoft Graph** — calendar events, people search
5. **SharePoint** — internal knowledge search

Navigate to: Power Automate → Connections → New connection

> **Note on connections vs. connection references**: For initial development, you only need standard connections. For multi-environment deployment, convert to connection references inside a solution.

---

## Phase 2 — Copilot Studio Agent Setup

### 2.1 Create the Main Agent

1. Open **Copilot Studio** → select the provisioned environment
2. Create a new agent: **"Enterprise Work Assistant"**
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

| Variable | Type | Description |
|----------|------|-------------|
| TRIGGER_TYPE | Choice (EMAIL, TEAMS_MESSAGE, CALENDAR_SCAN) | Signal type |
| PAYLOAD | Multi-line text | Raw content JSON |
| USER_CONTEXT | Text | Comma-separated string: "DisplayName, JobTitle, Department" |
| CURRENT_DATETIME | Text | ISO 8601 timestamp |

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

> Do not use both approaches simultaneously — this would result in double humanization.

---

## Phase 5 — PCF Component Deployment

### 5.1 Build and Deploy

```powershell
.\deploy-solution.ps1 -EnvironmentId "<environment-id>"
```

Or manually:

```bash
cd enterprise-work-assistant/src
bun install
bun run build
```

Then pack and import the solution via PAC CLI.

> **Note**: The solution is packaged as **Unmanaged**, which is appropriate for development and testing. For production deployment, change `SolutionPackageType` to `Managed` in `src/Solutions/Solution.cdsproj` before building.

---

## Phase 6 — Canvas App

Follow `docs/canvas-app-setup.md` to create and configure the Canvas app.

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
- [ ] Edit Draft and Dismiss actions work
- [ ] DLP policies allow all required connector combinations
