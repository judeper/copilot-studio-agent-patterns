# Deployment Guide

End-to-end deployment checklist for the Enterprise Work Assistant solution.

## Prerequisites

- [ ] **PAC CLI** installed (`dotnet tool install --global Microsoft.PowerApps.CLI.Tool`)
- [ ] **Node.js 18+** installed
- [ ] **PowerShell 7+** installed
- [ ] Power Platform environment with Copilot Studio capacity allocated
- [ ] Admin access to the target tenant

> **Terminology**: **PCF** = Power Apps Component Framework (the SDK for building custom code components). **RLS** = Row-Level Security (controls which rows each user can see). **DLP** = Data Loss Prevention (policies that control which connectors can be used together).

---

## Phase 1 — Environment Provisioning

### 1.1 Create Environment and Dataverse Table

```powershell
cd enterprise-work-assistant/scripts

.\provision-environment.ps1 `
    -TenantId "<your-tenant-id>" `
    -AdminEmail "<admin@yourdomain.com>" `
    -EnvironmentName "EnterpriseWorkAssistant-Dev" `
    -EnvironmentType "Sandbox"
```

This creates:
- A Power Platform environment with Dataverse
- The `cr_assistantcard` table (entity set name `cr_assistantcards`) with all required columns
- Enables PCF for Canvas apps

> **Important**: Save the **Environment ID** and **Organization URL** (e.g., `https://orgname.crm.dynamics.com`) from the script output. You will need these values in later steps.

### 1.2 Create Security Roles

```powershell
.\create-security-roles.ps1 -OrgUrl "https://<your-org>.crm.dynamics.com"
```

### 1.3 Create Connection References

Manually create connection references in Power Automate for:

1. **Office 365 Outlook** — email triggers and send actions
2. **Microsoft Teams** — message triggers
3. **Office 365 Users** — user profile lookup (`Get my profile V2`)
4. **Microsoft Graph** — calendar events, people search
5. **SharePoint** — internal knowledge search

Navigate to: Power Automate → Connections → New connection

---

## Phase 2 — Copilot Studio Agent Setup

### 2.1 Create the Main Agent

1. Open **Copilot Studio** → select the provisioned environment
2. Create a new agent: **"Enterprise Work Assistant"**
3. Enable **Generative Orchestration**
4. Paste the system prompt from `prompts/main-agent-system-prompt.md` into the system message

### 2.2 Configure JSON Output Mode

1. In the agent settings, navigate to **Settings** → **Generative AI** (the exact label may vary by Copilot Studio version — look for the AI/model configuration section, not the "Instructions" or "Topics" tab)
2. Enable **Structured outputs** (or **JSON output** in older versions)
3. Select **Custom format**
4. Paste the following as the JSON example (this locks the schema):

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

### 2.3 Set Up Input Variables

Create four input variables in the agent:

| Variable | Type | Description |
|----------|------|-------------|
| TRIGGER_TYPE | Choice (EMAIL, TEAMS_MESSAGE, CALENDAR_SCAN) | Signal type |
| PAYLOAD | Multi-line text | Raw content JSON |
| USER_CONTEXT | Text | User profile JSON |
| CURRENT_DATETIME | Text | ISO 8601 timestamp |

### 2.4 Register Research Tools (Actions)

The main agent's 5-tier research system requires tool actions to access external data. In Copilot Studio, go to **Actions** → **Add an action** for each tool below.

For connector-based actions, select the relevant connector and the specific operation. For custom actions (MCP-based), you will need to configure a custom connector or plugin.

| Action | Connector | Operation | Research Tier |
|--------|-----------|-----------|---------------|
| SearchUserEmail | Office 365 Outlook | Search email (V2) | Tier 1 — Personal Context |
| SearchSentItems | Office 365 Outlook | Search email (V2) on Sent Items folder | Tier 1 — Personal Context |
| SearchTeamsMessages | Microsoft Graph | `GET /me/chats/messages` or Teams Search | Tier 1 — Personal Context |
| SearchSharePoint | SharePoint | Search (V2) | Tier 2 — Organizational Knowledge |
| SearchPlannerTasks | Microsoft Graph | `GET /me/planner/tasks` | Tier 3 — Project Tools |
| WebSearch | Bing Search (or MCP plugin) | Web search | Tier 4 — Public Sources |
| SearchMSLearn | Bing Search (or MCP plugin) | Web search with `site:learn.microsoft.com` | Tier 5 — Official Docs |

> **Tip**: The agent prompt references these actions by name. If you use different action names, update the corresponding tool references in `prompts/main-agent-system-prompt.md`.

---

## Phase 3 — Agent Flow Creation

Build the three agent flows following `docs/agent-flows.md`:

### 3.1 EMAIL Flow
- Trigger: When a new email arrives (V3)
- Test with a real email to your inbox

### 3.2 TEAMS_MESSAGE Flow
- Trigger: When a new channel message is added
- Test by posting in the configured channel

### 3.3 CALENDAR_SCAN Flow
- Trigger: Daily recurrence at 7 AM
- Test by running manually

---

## Phase 4 — Humanizer Agent

### 4.1 Create the Humanizer Agent

1. In Copilot Studio, create a second agent: **"Humanizer Agent"**
2. Paste the prompt from `prompts/humanizer-agent-prompt.md`
3. Configure as a **Connected Agent** available to the main agent
4. Alternatively, invoke it from the agent flows — see the "Humanizer handoff" steps (steps 8–10) in [agent-flows.md](agent-flows.md) for how the EMAIL and TEAMS_MESSAGE flows call the Humanizer after writing the initial card to Dataverse

---

## Phase 5 — PCF Component Deployment

### 5.1 Build and Deploy

```powershell
.\deploy-solution.ps1 -EnvironmentId "<environment-id>"
```

Or manually:

```bash
cd enterprise-work-assistant/src
npm install
npm run build
```

Then pack and import the solution via PAC CLI.

---

## Phase 6 — Canvas App

Follow `docs/canvas-app-setup.md` to create and configure the Canvas app.

---

## Phase 7 — Governance

### 7.1 Data Loss Prevention (DLP) Policies

Ensure the environment's DLP policies allow the required connector combinations:

- Office 365 Outlook + Dataverse (same group)
- Microsoft Teams + Dataverse (same group)
- Microsoft Graph + Dataverse (same group)
- SharePoint + Dataverse (same group)

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
- [ ] AssistantCards table has all columns
- [ ] Security role assigned to test users
- [ ] Connection references created and authenticated
- [ ] Main agent responds with valid JSON
- [ ] EMAIL flow fires on new email and writes to Dataverse
- [ ] TEAMS_MESSAGE flow fires on channel message
- [ ] CALENDAR_SCAN flow runs on schedule
- [ ] Humanizer agent produces polished drafts
- [ ] PCF component renders cards in test harness
- [ ] Canvas app shows cards from Dataverse
- [ ] Filters work correctly
- [ ] Card detail view shows all sections
- [ ] Edit Draft and Dismiss actions work
