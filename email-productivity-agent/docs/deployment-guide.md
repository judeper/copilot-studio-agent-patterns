# Deployment Guide — Email Productivity Agent

Step-by-step checklist for deploying the Email Productivity Agent to a Power Platform environment.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **PAC CLI** | `dotnet tool install --global Microsoft.PowerApps.CLI.Tool` |
| **Azure CLI** | `winget install Microsoft.AzureCLI` (Windows) or `brew install azure-cli` (macOS) |
| **PowerShell 7+** | Required for provisioning scripts |
| **Power Platform Environment** | With Copilot Studio capacity allocated |
| **Microsoft 365 License** | E3/E5 or Business Premium (for Graph API access) |
| **Power Automate Premium** | Required for Dataverse connector and HTTP with Azure AD connector |
| **Power Apps Premium** | Required for Canvas App accessing custom Dataverse tables |
| **Copilot Studio License** | Required for agent invocations (consumed per call) |

### DLP Policy Check

Verify that the following connectors are in the same DLP connector group (Business or Non-Business) in the **Power Platform Admin Center** → **Data policies**:

- Office 365 Outlook
- Microsoft Teams
- Microsoft Dataverse
- HTTP with Azure AD (premium)

If HTTP with Azure AD is blocked or in a different group, contact your tenant admin to update the DLP policy.

### Graph API Permissions (Delegated)

| Permission | Scope | Justification |
|------------|-------|---------------|
| `Mail.Read` | Read mailbox messages | Query sent items, detect replies, read thread content |
| `Mail.ReadWrite` | Read/write mailbox | **Required for snooze**: move messages between folders, create EPA-Snoozed folder. This is a permission escalation from read-only. |
| `Mail.Send` | Send email | Send follow-up emails when user approves a draft |
| `MailboxSettings.Read` | Read settings | Access user timezone for business-day calculations |

> **Note on Mail.ReadWrite**: The Enterprise Work Assistant requires only `Mail.Read`. This agent requires `Mail.ReadWrite` because the snooze feature moves messages between folders via `POST /me/messages/{id}/move`. If deploying Phase 1 only (nudges without snooze), `Mail.Read` is sufficient.

---

## Phase 1: Follow-Up Nudges

### Step 1: Provision Environment & Dataverse Tables

```powershell
cd email-productivity-agent/scripts
pwsh provision-environment.ps1 -TenantId "<tenant-id>" -AdminEmail "<admin@example.com>"
```

This creates:
- Power Platform environment (`EmailProductivityAgent-Dev`)
- `cr_followuptracking` table with 12 columns + composite alternate key
- `cr_nudgeconfiguration` table with 8 columns (including cr_owneruserid) + owner alternate key
- `cr_snoozedconversation` table with 8 columns (conversationId, ownerUserId, originalMessageId, snoozeUntil, currentFolder, unsnoozedByAgent, unsnoozedDateTime, originalSubject) + composite alternate key (cr_conversationid + cr_owneruserid)

### Step 2: Create Security Roles

```powershell
pwsh create-security-roles.ps1 -OrgUrl "https://<org>.crm.dynamics.com"
```

This creates the "Email Productivity Agent User" role with Basic-depth CRUD on:
- `cr_FollowUpTracking`
- `cr_NudgeConfiguration`
- `cr_SnoozedConversation` (will show a warning if Phase 2 table doesn't exist yet)

### Step 3: Configure Copilot Studio Agent

1. Open [Copilot Studio](https://copilotstudio.microsoft.com) and select the provisioned environment from the environment picker (top-right)
2. Click **Create** → **New agent** → **Skip to configure** (to bypass the wizard)
3. Set the agent name to **"Email Productivity Agent"**
4. **Select AI Model:**
   - The default model (GPT-5 Chat or equivalent) is recommended
   - The prompts are model-agnostic and work with any capable LLM available in Copilot Studio
   - No model change is required unless your organization has specific model governance requirements
5. In the **Overview** tab, under **Instructions**, paste the entire contents of `prompts/nudge-agent-system-prompt.md`
   - Include everything from the role description through the constraints and examples
   - Do NOT include the markdown title (`# Follow-Up Nudge Agent — System Prompt`) — start from the role/context section
6. **Enable Generative Orchestration:**
   - Go to **Settings** (gear icon, top-right) → **Generative AI**
   - Under **How should your agent interact with people?**, select **Generative (preview)**
   - This allows the agent to use its instructions to handle any input, rather than requiring pre-defined topics
7. **Define Input Variables (via Topic Details → Inputs tab):**
   - Go to **Topics** in the left sidebar
   - Open the main topic (e.g., the default conversational topic, or create a new topic named "Follow-Up Nudge")
   - In the topic authoring canvas, click **Details** in the top navigation bar
   - Navigate to the **Inputs** tab
   - Click **Create a new variable** for each input below:

   | Variable Name | Data Type | Description |
   |---|---|---|
   | `CONVERSATION_ID` | String | Graph API conversationId for the email thread |
   | `ORIGINAL_SUBJECT` | String | Subject line of the original sent email |
   | `RECIPIENT_EMAIL` | String | Email address of the tracked recipient |
   | `RECIPIENT_TYPE` | String | One of: Internal, External, Priority, General |
   | `DAYS_SINCE_SENT` | Number | Calendar days since the email was sent |
   | `THREAD_EXCERPT` | String | Plain text excerpt of the email thread (up to 2000 chars) |
   | `USER_DISPLAY_NAME` | String | Display name of the user who sent the email |

   > **Generative fill behavior:** With generative orchestration enabled, each input has a "How will the agent fill this input?" property. The default is "Dynamically fill with the best option" — the agent extracts the value from conversation context. When invoked from Power Automate, the values are passed explicitly, so the default behavior is fine.
   >
   > **Note:** Input variables are defined via the **Topic Details → Inputs tab**, NOT via Settings → Agent inputs (which does not exist). This is distinct from tool-level inputs which are configured on the Tools page.

8. **Configure Agent Output:**
   1. In the agent's main topic, add a **Text** output variable named `agentResponse`
   2. In the last **Message** node, set the output to the system's generated response
   3. In the Power Automate flow, parse this output with `json(outputs('Run_a_flow_action')?['body/agentResponse'])` to access individual fields

   **Verify:** Test the agent with sample inputs from the Examples section of the prompt file. The response should be valid JSON matching the output schema.
9. Click **Publish** (top-right) to make the agent available to Power Automate flows

> **Tip:** After publishing, test the agent using the **Test agent** panel (bottom-left). Provide sample input values and verify the response is valid JSON matching the output schema in the prompt.

### Step 4: Configure Connection References

Set up these Power Automate connections:
- **Office 365 Outlook** — for email triggers and message queries
- **Microsoft Teams** — for Adaptive Card nudge delivery
- **Dataverse** — for FollowUpTracking and NudgeConfiguration operations
- **HTTP with Azure AD** — for direct Graph API calls (premium connector)
  - **Base Resource URL:** `https://graph.microsoft.com`
  - **Azure AD Resource URI:** `https://graph.microsoft.com`

### Step 5: Build Power Automate Flows

Follow the step-by-step guide in `docs/follow-up-nudge-flows.md`:

1. **Flow 1: Sent Items Tracker** — Trigger: "When a new email arrives" on Sent Items
2. **Flow 2: Response Detection & Nudge Delivery** — Trigger: Daily recurrence at 9 AM
3. **Flow 5: Data Retention Cleanup** — Trigger: Weekly recurrence

### Step 6: Teams Admin Policy Check

Verify the Power Automate flow bot is allowed in your Teams environment:
1. Open **Teams Admin Center** → **Teams apps** → **Permission policies**
2. Confirm "Power Automate" app is not blocked
3. If using a custom bot, ensure it's approved in the app catalog

### Step 7: Pilot Testing

1. Assign the security role to 5-10 pilot users
2. Each user's NudgeConfiguration row is auto-created on first sent email
3. Default timeframes: Internal 3 days, External 5 days, Priority 1 day, General 7 days
4. Monitor flow run history for errors
5. Collect feedback on nudge timing and relevance

---

## Phase 2: Snooze Auto-Removal

### Step 8: Verify Snoozed Conversations Table

On a fresh install, Step 1 already creates all three tables (including `cr_snoozedconversation`). No additional provisioning is needed.

If you ran an earlier version of the script that didn't include SnoozedConversation, manually create the table using the Dataverse maker portal following `schemas/snoozed-conversations-table.json`, or use the PAC CLI to add just the table.

### Step 9: Configure Snooze Agent

1. In Copilot Studio, open the **Email Productivity Agent** created in Step 3
2. Go to **Topics** → **Add a topic** → **From blank**
3. Name the topic **"Snooze Auto-Removal"**
4. Set up **trigger phrases** such as: "snooze check", "evaluate snooze", "check snoozed email"
5. In the topic editor, add a **Generative answers** node or a **Message** node with the prompt logic
6. Paste the contents of `prompts/snooze-agent-system-prompt.md` as the topic's instructions
7. Define input variables for this topic via **Details** → **Inputs** tab (click **Details** in the topic authoring canvas top bar):

   | Variable Name | Data Type | Description |
   |---|---|---|
   | `CONVERSATION_ID` | String | Graph API conversationId of the snoozed thread |
   | `SNOOZED_SUBJECT` | String | Subject of the original snoozed email |
   | `NEW_MESSAGE_SENDER` | String | Email address of the person who sent the new reply |
   | `NEW_MESSAGE_SENDER_NAME` | String | Display name of the person who replied |
   | `NEW_MESSAGE_SUBJECT` | String | Subject of the new reply |
   | `NEW_MESSAGE_EXCERPT` | String | Plain text excerpt of the reply (up to 500 chars) |
   | `SNOOZE_UNTIL` | String | ISO 8601 datetime when snooze expires (or null if indefinite) |
   | `CURRENT_DATETIME` | String | Current UTC datetime in ISO 8601 format |
   | `USER_TIMEZONE` | String | IANA timezone identifier (e.g., "America/New_York") |

   > **Note:** Input variables are defined via **Topic Details → Inputs tab**, NOT via Settings. See Step 7 (Phase 1) for full details on the generative fill behavior.

8. Click **Save** and **Publish** the agent

> **Note:** The snooze agent is invoked by Flow 4 (Auto-Unsnooze) when a new reply is detected for a snoozed conversation. For MVP, you can skip the agent and always unsnooze — see `docs/snooze-auto-removal-flows.md` Step 4 for details.

### Step 10: Build Snooze Flows

Follow `docs/snooze-auto-removal-flows.md`:

1. **Flow 3: Snooze Detection** — Trigger: Every 15 minutes
2. **Flow 4: Auto-Unsnooze** — Trigger: "When a new email arrives" on Inbox
3. **Flow 6: Snooze Cleanup** — Trigger: Weekly recurrence

### Step 11: Ensure Mail.ReadWrite Permission

The **HTTP with Azure AD** connector uses a delegated auth model — the connection owner consents to permissions at connection-creation time. No separate app registration is needed.

- For `Mail.ReadWrite`, if your tenant requires admin consent for this scope, a **Global Admin** must pre-approve it in **Entra ID** → **Enterprise applications** → the "HTTP with Azure AD" service principal → **Permissions** → **Grant admin consent**.
- If you are using a **custom connector** with a registered app instead of the built-in HTTP with Azure AD connector, add `Mail.ReadWrite` to the app's **API permissions** in the Entra ID app registration and re-consent.

### Multi-User Deployment Model

Each user runs their own set of flows under their own connections:

**Event-driven flows** (Flow 1: Sent Items Tracker, Flow 4: Auto-Unsnooze):
- Each user must have their own copy with their own Office 365 connection
- Use "Send a copy" or export/import to distribute to pilot users

**Scheduled flows** (Flow 2: Response Detection, Flow 3: Snooze Detection):
- Each user needs their own instance running on their own schedule
- The flow uses `Get my profile (V2)` to scope all queries to the current user

**Per-user connections:** Every flow uses `/me/` Graph API endpoints and the current user's Office 365 connection. Flows cannot be shared via a single service account without significant modification.

> ⚠️ For organizations with 50+ users, consider a service account model with application permissions. This requires Graph API application permissions (`Mail.Read`, `Mail.ReadWrite`) and modifying flows to iterate over users. Contact your Power Platform admin for guidance.

---

## Rollback Procedure

To disable the Email Productivity Agent without affecting other systems:

1. **Turn off flows**: Disable Flows 1-6 in Power Automate
2. **Disable agent**: Deactivate the Copilot Studio agent
3. **(Optional) Clean up data**: Delete all rows in `cr_followuptracking` and `cr_snoozedconversation`
4. **(Optional) Remove folder**: Delete the EPA-Snoozed folder via Graph or Outlook
5. Existing Enterprise Work Assistant flows are unaffected

---

## Monitoring

### Flow Run Health

- Power Automate → Flow details → Run history
- Enable "Send me an email notification when my cloud flow fails" for each flow
- For enterprise monitoring: create a meta-flow that queries flow run history daily

### Key Metrics to Track

| Metric | Source | Target |
|--------|--------|--------|
| Nudges sent per user per day | Flow 2 run history | 1-5 (too many = fatigue) |
| Nudges dismissed vs acted on | Dataverse query on cr_dismissedbyuser | <30% dismiss rate |
| Unsnooze events per day | Dataverse query on cr_unsnoozedbyagent | Low volume expected |
| Flow failure rate | Power Automate run history | <1% |
| Graph API throttling events | HTTP action responses (429) | 0 ideally |

---

## GDPR & Data Subject Requests

### Right to Access
Users can view all their tracked data via the Canvas App (ownership-based RLS ensures they only see their own rows).

### Right to Erasure
To delete all data for a specific user:

```powershell
# PowerShell script using Dataverse Web API
$userId = "<user-systemuserid>"
$orgUrl = "https://<org>.crm.dynamics.com"

# Authenticate
$token = az account get-access-token --resource $orgUrl --query accessToken -o tsv
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version" = "4.0"
}

# Delete FollowUpTracking rows
$trackingRows = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/cr_followuptrackings?`$filter=_ownerid_value eq '$userId'" -Headers $headers
foreach ($row in $trackingRows.value) {
    Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/cr_followuptrackings($($row.cr_followuptrackingid))" -Method Delete -Headers $headers
}

# Delete NudgeConfiguration
$configRows = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/cr_nudgeconfigurations?`$filter=_ownerid_value eq '$userId'" -Headers $headers
foreach ($row in $configRows.value) {
    Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/cr_nudgeconfigurations($($row.cr_nudgeconfigurationid))" -Method Delete -Headers $headers
}

# Delete SnoozedConversations
$snoozeRows = Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/cr_snoozedconversations?`$filter=_ownerid_value eq '$userId'" -Headers $headers
foreach ($row in $snoozeRows.value) {
    Invoke-RestMethod -Uri "$orgUrl/api/data/v9.2/cr_snoozedconversations($($row.cr_snoozedconversationid))" -Method Delete -Headers $headers
}
```
