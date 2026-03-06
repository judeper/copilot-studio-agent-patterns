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
| **Power Apps Premium** | Required for Canvas App accessing custom Dataverse tables |
| **Copilot Studio License** | Required for agent invocations; premium connectors (Dataverse, HTTP/Entra ID) are covered by Copilot Studio license |

### DLP Policy Check

Verify that the following connectors are in the same DLP connector group (Business or Non-Business) in the **Power Platform Admin Center** → **Data policies**:

- Office 365 Outlook
- Office 365 Users
- Microsoft Teams
- Microsoft Dataverse
- HTTP with Microsoft Entra ID (premium)

If HTTP with Microsoft Entra ID is blocked or in a different group, contact your tenant admin to update the DLP policy.

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

   | Variable Name | Data Type | Description (paste into Description field) |
   |---|---|---|
   | `CONVERSATION_ID` | String | The Microsoft Graph conversationId that uniquely identifies the email thread being tracked for follow-up |
   | `ORIGINAL_SUBJECT` | String | Subject line of the original sent email that has not received a reply |
   | `RECIPIENT_EMAIL` | String | Email address of the specific recipient who has not replied to the sent email |
   | `RECIPIENT_TYPE` | String | Recipient classification: Internal (same org), External (different org), Priority (VIP), or General (default) |
   | `DAYS_SINCE_SENT` | Number | Number of calendar days that have elapsed since the original email was sent |
   | `THREAD_EXCERPT` | String | Plain text excerpt of the most recent messages in the email thread, up to 2000 characters, for context |
   | `USER_DISPLAY_NAME` | String | Display name of the user who sent the original email, used for personalizing the follow-up draft |

   > **Descriptions matter:** These descriptions help generative orchestration reason about each variable during interactive testing. While Power Automate passes values explicitly, good descriptions improve the agent's ability to infer values in the test panel and any future interactive scenarios.
   >
   > **Fill behavior for PA-invoked agents:** For each input variable, set **"How will the agent fill this input?"** to **"Set as a value"** (not "Dynamically fill with best option"). Since Power Automate passes values programmatically, the agent should not attempt to infer or prompt for these values.
   >
   > **Note:** Input variables are defined via the **Topic Details → Inputs tab**, NOT via Settings → Agent inputs (which does not exist). This is distinct from tool-level inputs which are configured on the Tools page.

8. **Configure Agent Output (required — generative orchestration does NOT auto-return output to PA):**

   Generative orchestration's LLM response text is **not** automatically piped back to the calling Power Automate flow. You must explicitly define an output variable and wire it to the LLM response.

   **Step A — Define the output variable:**
   1. In the topic authoring canvas, click **Details** (top bar) → **Outputs** tab
   2. Click **Create a new variable**
   3. Name: `AgentResponseJSON`
   4. Data type: **String** (Copilot Studio only supports Number, String, Boolean for outputs — not Object/List)
   5. Description: "Structured JSON with action, confidence, priority, threadSummary, suggestedFollowUp, and reasoning"
   6. Click **Save**

   **Step B — Wire the LLM response to the output variable:**
   1. On the authoring canvas, click **+ Add node** → **Add an action** → **Create a prompt** (or **Generative answers**)
   2. In the prompt/instruction box, author the system prompt referencing the 7 input variables using the `/` variable picker (e.g., `{Topic.RECIPIENT_EMAIL}`). Instruct the model to return only valid JSON in the target schema.
   3. Under **Save response as**, select or create a local variable (e.g., `Topic.GeneratedJSON`)
   4. Below the Generative Answers node, add a **Variable management** → **Set a variable value** node:
      - **Set:** `Topic.AgentResponseJSON` (your declared output variable)
      - **To:** `Topic.GeneratedJSON` (the Generative Answers output)
   5. Add an **End topic** node at the bottom
      - ⚠️ Do **NOT** add a "Send a message" node — that sends a reply to an interactive user, not to the calling flow

   **Step C — Verify in Power Automate (after flow is built):**
   - The output variable `AgentResponseJSON` appears in the Copilot Studio connector action's dynamic content panel
   - Expression to access: `outputs('Your_CopilotStudio_Action_Name')?['body']?['AgentResponseJSON']`
   - To parse the JSON string: `json(outputs('Your_CopilotStudio_Action_Name')?['body']?['AgentResponseJSON'])`
   - Then access fields: `body('Parse_JSON')?['action']`, `body('Parse_JSON')?['confidence']`, etc.

   > **Defensive pattern:** Since LLMs can occasionally return malformed JSON, add a Condition node in PA after Parse JSON to check `empty(body('Parse_JSON')?['action'])`. If true, retry or route to a fallback branch.

9. Click **Publish** (top-right) to make the agent available to Power Automate flows

> **Tip:** After publishing, test the agent using the **Test agent** panel (bottom-left). Provide sample input values and verify the response is valid JSON matching the output schema in the prompt.

### Step 4: Configure Connection References

Set up these Power Automate connections:
- **Office 365 Outlook** — for email triggers and message queries
- **Office 365 Users** — for user profile lookups (Get my profile V2)
- **Microsoft Teams** — for Adaptive Card nudge delivery
- **Dataverse** — for FollowUpTracking and NudgeConfiguration operations
- **HTTP with Microsoft Entra ID** — for direct Graph API calls (premium connector)
  - Use the **"preauthorized"** variant if the standard version fails with `AADSTS65002` (consent error). The preauthorized connector has pre-consented Graph permissions.
  - **Base Resource URL:** `https://graph.microsoft.com`
  - **Azure AD Resource URI:** `https://graph.microsoft.com`

### Step 5: Deploy Power Automate Flows

The deploy script creates the 4 Phase 1 flows (Flow 1, 2, 2b, 5) via the **Flow Management API** with connection bindings, then adds them to the Dataverse solution.

> **Why the Flow Management API?** Flows must be created via `api.flow.microsoft.com` (not the Dataverse `workflows` entity) because only the Flow API properly binds connections at runtime. Dataverse-created flows always fail activation with "connection references need connections" regardless of PAC solution import settings.

**Prerequisites:**
- All connections from Step 4 must exist and be in "Connected" status
- `az login` must be active (the script acquires 3 tokens: Dataverse, Flow API, PowerApps API)

```powershell
cd email-productivity-agent/scripts
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<your-org>.crm.dynamics.com" `
    -EnvironmentId "<environment-guid>" `
    -FlowsToCreate "Phase1"
```

The script will:
1. Create/reuse the `EmailProductivityAgent` solution
2. Create 5 connection references in the solution
3. Auto-discover connections in the environment and map them to connectors
4. Create all 4 Phase 1 flows via the Flow Management API with `state=Started`
5. Add flows to the solution

**Expected output:** All 4 Phase 1 flows created and running (✓ ON).

> **Troubleshooting — Flow API validation errors:**
> - `WorkflowOperationParametersExtraParameter`: A dynamic parameter (e.g., `body/recipient/to`) is in flattened format. Convert to nested: `"body": { "recipient": { "to": "..." } }`
> - `WorkflowOperationInputsApiOperationNotFound`: The operationId doesn't exist in the connector. Check with the PowerApps connector API.
> - `DynamicParameterInputInvalid`: The trigger requires design-time parameters. For Teams `TeamsCardTrigger`, provide `inputsAdaptiveCard` and `CardTypeId`.

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

### Step 9: Deploy Snooze Flows

Deploy the 3 snooze flows using the same deploy script from Step 5:

```powershell
cd email-productivity-agent/scripts
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<your-org>.crm.dynamics.com" `
    -EnvironmentId "<environment-guid>" `
    -FlowsToCreate "Phase2"
```

This creates:
- **Flow 3: Snooze Detection** — Scans the EPA-Snoozed folder every 15 minutes and tracks conversations in Dataverse
- **Flow 4: Auto-Unsnooze** — Watches Inbox for new emails; if one matches a snoozed conversation, moves the snoozed message back to Inbox and notifies via Teams
- **Flow 6: Snooze Cleanup** — Weekly purge of unsnoozed records older than 30 days

**Expected output:** All 3 flows created and running (✓ ON).

> **POC simplifications vs. production:**
> - Flow 4 always unsnoozes on match (no Snooze Agent invocation for SUPPRESS/UNSNOOZE decisions)
> - No working-hours check (production would suppress unsnooze outside 7AM-7PM)
> - Simple Teams text notification (production would use adaptive card with deeplink)

### Step 10: Ensure Mail.ReadWrite Permission

Flow 3 (create mail folder, list messages) and Flow 4 (move messages) use the **HTTP with Microsoft Entra ID** connector to call Graph API endpoints that require `Mail.ReadWrite`.

- The connector uses delegated auth — the connection owner consents at connection-creation time
- If your tenant requires admin consent for `Mail.ReadWrite`, a **Global Admin** must pre-approve it in **Entra ID** → **Enterprise applications** → the "HTTP with Microsoft Entra ID" service principal → **Permissions** → **Grant admin consent**
- The same HTTP with Entra ID connection from Phase 1 (Step 4) is reused — no new connection setup needed

### Step 11: Test the Snooze Workflow

1. **Trigger Flow 3** — Wait 15 minutes or manually run Flow 3. On first run, it creates the "EPA-Snoozed" mail folder and stores the folder ID in NudgeConfiguration
2. **Move an email** — In Outlook, drag an email to the "EPA-Snoozed" folder
3. **Wait for next Flow 3 run** — Verify a row appears in `cr_snoozedconversation` with the email's conversationId
4. **Send a reply** — Have someone (or yourself from another account) reply to the snoozed email
5. **Verify Flow 4** — The reply triggers Flow 4, which:
   - Moves the original snoozed message back to Inbox
   - Marks `cr_unsnoozedbyagent = true` in Dataverse
   - Sends a Teams notification: "📬 Unsnoozed: {subject} — reply from {sender}"

### Step 12: Configure Snooze Agent (Optional — Production)

For production deployments, you can add intelligent snooze decisions:

1. In Copilot Studio, add a **"Snooze Auto-Removal"** topic
2. Paste `prompts/snooze-agent-system-prompt.md` as instructions
3. Define input variables (CONVERSATION_ID, SNOOZED_SUBJECT, NEW_MESSAGE_SENDER, etc.)
4. Update Flow 4 to invoke the agent before unsnoozing

See `docs/snooze-auto-removal-flows.md` Step 4 for the agent invocation pattern.

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

1. **Turn off flows**: Disable all 7 flows (1, 2, 2b, 3, 4, 5, 6) in Power Automate
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
