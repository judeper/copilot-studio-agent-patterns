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

### 1.5 Verify Table Naming Consistency

```powershell
.\audit-table-naming.ps1
```

This script verifies that column names, choice values, and references are consistent across all artifacts (schemas, scripts, documentation). Run it after provisioning to catch any drift.

### 1.6 Create Connections

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
- [ ] Senders with < 3 signals are skipped
- [ ] Card Outcome Tracker increments cr_dismisscount on DISMISSED outcomes
- [ ] Trigger flows pass SENDER_PROFILE JSON to the main agent
- [ ] Agent upgrades LIGHT → FULL for AUTO_HIGH senders with actionable content
- [ ] Agent does NOT downgrade FULL → LIGHT for executives/clients regardless of category
- [ ] Confidence scoring applies sender-adaptive modifiers (staleness urgency, edit distance penalty)
- [ ] Confidence Calibration dashboard accessible and shows 4 tabs
- [ ] Confidence accuracy buckets display correct action rates
- [ ] Top Senders tab shows ranked engagement data

### Sprint 2 Verification
- [ ] Daily Briefing Agent published in Copilot Studio with correct input contract
- [ ] Daily Briefing Flow runs on weekday mornings (test with manual run)
- [ ] Briefing card appears at top of dashboard with day shape narrative
- [ ] Action items in briefing have working "Open card →" links
- [ ] FYI section is collapsible
- [ ] Staleness Monitor: cards >7 days PENDING are marked EXPIRED
- [ ] Staleness Monitor: High priority cards >24h get NUDGE cards
- [ ] No duplicate nudge cards on repeated monitor runs
- [ ] PCF inline editing: "Edit draft" button appears on EMAIL FULL cards
- [ ] Edited drafts can be sent; confirmation panel shows "(edited)" label
- [ ] NUDGE cards render correctly in gallery (distinct from regular cards)
- [ ] Trigger Type filter shows DAILY_BRIEFING option

---

## Smoke Test Procedure

After completing all phases, run through this end-to-end test to verify the solution works:

1. **Send yourself a test email** with a distinctive subject line (e.g., "Test: Project Alpha budget review needed by Friday")
2. **Wait 1-2 minutes** for the EMAIL flow to trigger
3. **Check Power Automate flow run history** — verify the flow run succeeded (green checkmark). If it failed, click into the run to see which step errored
4. **Open Dataverse** → Tables → Assistant Cards → verify a new row exists with your test email's summary
5. **Open the Canvas app** → verify the card appears in the gallery
6. **Click the card** → verify the detail view renders correctly (summary, priority badge, key findings, sources)
7. **Click Dismiss** → verify the card status updates to SUMMARY_ONLY in Dataverse
8. **Test filters** → use the dropdown controls to filter by trigger type, priority, and status

> If the CALENDAR_SCAN flow is configured, you can also test it by clicking "Run" manually in Power Automate (no need to wait for the daily schedule).

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
