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
pwsh provision-environment.ps1 -TenantId "<tenant-id>" -AdminEmail "<admin@domain.com>"
```

This creates:
- Power Platform environment (`EmailProductivityAgent-Dev`)
- `cr_followuptracking` table with 12 columns + composite alternate key
- `cr_nudgeconfiguration` table with 7 columns + owner alternate key

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
4. In the **Overview** tab, under **Instructions**, paste the entire contents of `prompts/nudge-agent-system-prompt.md`
   - Include everything from the role description through the constraints and examples
   - Do NOT include the markdown title (`# Follow-Up Nudge Agent — System Prompt`) — start from the role/context section
5. **Enable Generative Orchestration:**
   - Go to **Settings** (gear icon, top-right) → **Generative AI**
   - Under **How should your agent interact with people?**, select **Generative (preview)**
   - This allows the agent to use its instructions to handle any input, rather than requiring pre-defined topics
6. **Define Input Variables:**
   - Go to **Topics** → click the **System** topic that handles the agent's main logic
   - In the topic editor, click **Variables** (right panel) → **Add input variable** for each:

   | Variable Name | Type | Description |
   |---|---|---|
   | `CONVERSATION_ID` | String | Graph API conversationId for the email thread |
   | `ORIGINAL_SUBJECT` | String | Subject line of the original sent email |
   | `RECIPIENT_EMAIL` | String | Email address of the tracked recipient |
   | `RECIPIENT_TYPE` | String | One of: Internal, External, Priority, General |
   | `DAYS_SINCE_SENT` | Number | Business days since the email was sent |
   | `THREAD_EXCERPT` | String | Plain text excerpt of the email thread (up to 2000 chars) |
   | `USER_DISPLAY_NAME` | String | Display name of the user who sent the email |

7. **Configure JSON Output:**
   - In the topic editor, at the end of the conversation flow, add a **Message** node
   - Set the message to return the agent's structured JSON response
   - Alternatively, configure the agent's **Output variable** as a Text variable containing the JSON response
   - The downstream Power Automate flow will parse this JSON using the simplified schema in `docs/follow-up-nudge-flows.md`
8. Click **Publish** (top-right) to make the agent available to Power Automate flows

> **Tip:** After publishing, test the agent using the **Test agent** panel (bottom-left). Provide sample input values and verify the response is valid JSON matching the output schema in the prompt.

### Step 4: Build Power Automate Flows

Follow the step-by-step guide in `docs/follow-up-nudge-flows.md`:

1. **Flow 1: Sent Items Tracker** — Trigger: "When a new email arrives" on Sent Items
2. **Flow 2: Response Detection & Nudge Delivery** — Trigger: Daily recurrence at 9 AM
3. **Flow 5: Data Retention Cleanup** — Trigger: Weekly recurrence

### Step 5: Configure Connection References

Set up these Power Automate connections:
- **Office 365 Outlook** — for email triggers and message queries
- **Microsoft Teams** — for Adaptive Card nudge delivery
- **Dataverse** — for FollowUpTracking and NudgeConfiguration operations
- **HTTP with Azure AD** — for direct Graph API calls (premium connector)

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

### Step 8: Provision Snoozed Conversations Table

If you ran the provisioning script before the SnoozedConversation table was added, re-run it:

```powershell
pwsh provision-environment.ps1 -TenantId "<tenant-id>"
```

The script is idempotent — it will skip existing tables and columns, and create only the missing `cr_snoozedconversation` table.

Or manually create the table following `schemas/snoozed-conversations-table.json`.

### Step 9: Configure Snooze Agent

1. In Copilot Studio, open the **Email Productivity Agent** created in Step 3
2. Go to **Topics** → **Add a topic** → **From blank**
3. Name the topic **"Snooze Auto-Removal"**
4. Set up **trigger phrases** such as: "snooze check", "evaluate snooze", "check snoozed email"
5. In the topic editor, add a **Generative answers** node or a **Message** node with the prompt logic
6. Paste the contents of `prompts/snooze-agent-system-prompt.md` as the topic's instructions
7. Define input variables for this topic:

   | Variable Name | Type | Description |
   |---|---|---|
   | `CONVERSATION_ID` | String | Graph API conversationId of the snoozed thread |
   | `ORIGINAL_SUBJECT` | String | Subject of the snoozed email |
   | `NEW_MESSAGE_SENDER_NAME` | String | Display name of the person who replied |
   | `NEW_MESSAGE_SUBJECT` | String | Subject of the new reply |
   | `NEW_MESSAGE_EXCERPT` | String | Plain text excerpt of the reply (up to 500 chars) |
   | `SNOOZE_UNTIL` | String | ISO 8601 datetime when snooze expires (or null if indefinite) |
   | `CURRENT_DATETIME` | String | Current UTC datetime in ISO 8601 format |
   | `USER_TIMEZONE` | String | IANA timezone identifier (e.g., "America/New_York") |

8. Click **Save** and **Publish** the agent

> **Note:** The snooze agent is invoked by Flow 4 (Auto-Unsnooze) when a new reply is detected for a snoozed conversation. For MVP, you can skip the agent and always unsnooze — see `docs/snooze-auto-removal-flows.md` Step 4 for details.

### Step 10: Build Snooze Flows

Follow `docs/snooze-auto-removal-flows.md`:

1. **Flow 3: Snooze Detection** — Trigger: Every 15 minutes
2. **Flow 4: Auto-Unsnooze** — Trigger: "When a new email arrives" on Inbox
3. **Flow 6: Snooze Cleanup** — Trigger: Weekly recurrence

### Step 11: Ensure Mail.ReadWrite Permission

If not already granted, update the Entra ID app registration to include `Mail.ReadWrite` (delegated). Re-consent if needed.

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
