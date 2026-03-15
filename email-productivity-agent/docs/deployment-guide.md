# Deployment Guide — Email Productivity Agent

Step-by-step checklist for deploying the Email Productivity Agent to a Power Platform environment.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **PAC CLI** | `dotnet tool install --global Microsoft.PowerApps.CLI.Tool` |
| **Azure CLI** | `winget install Microsoft.AzureCLI` (Windows) or `brew install azure-cli` (macOS) |
| **PowerShell 7+** | Required for provisioning scripts |
| **Power Platform Environment** | Any environment with Dataverse and Copilot Studio capacity |
| **Microsoft 365 License** | E3/E5 or Business Premium (for Graph API access) |
| **Power Apps Premium** | Required for Canvas App accessing custom Dataverse tables |
| **Copilot Studio License** | Required for live agent decisioning in Flow 2, 2b, 4, 8, 9, and 12 |

### DLP Policy Check

Verify that the following connectors are in the same DLP connector group (Business or Non-Business) in the **Power Platform Admin Center** → **Data policies**:

- Office 365 Outlook
- Office 365 Users
- Microsoft Teams
- Microsoft Dataverse
- HTTP with Microsoft Entra ID (premium)
- Microsoft Copilot Studio

If HTTP with Microsoft Entra ID or Microsoft Copilot Studio is blocked or in a different group, contact your tenant admin to update the DLP policy.

### Graph API Permissions (Delegated)

| Permission | Scope | Justification |
|------------|-------|---------------|
| `Mail.Read` | Read mailbox messages | Query sent items, detect replies, read thread content |
| `Mail.ReadWrite` | Read/write mailbox | **Required for snooze**: move messages between folders, create EPA-Snoozed folder. This is a permission escalation from read-only. |
| `Mail.Send` | Send email | Send follow-up emails when user approves a draft |
| `MailboxSettings.Read` | Read settings | Access user timezone for business-day calculations |

> **Note on Mail.ReadWrite**: The Intelligent Work Layer requires only `Mail.Read`. This agent requires `Mail.ReadWrite` because the snooze feature moves messages between folders via `POST /me/messages/{id}/move`. If deploying Phase 1 only (nudges without snooze), `Mail.Read` is sufficient.

---

## Inter-Flow Dependencies

Understanding which flows depend on which tables and other flows helps ensure correct deployment order and simplifies troubleshooting.

```
Dataverse Tables                          Flows
──────────────                            ─────
                                          Flow 1 (Sent Items Tracker)
cr_nudgeconfiguration  ◄──── created by ──── Flow 1 (auto-creates on first email)
cr_followuptracking    ◄──── created by ──── Flow 1 (one row per recipient)
                                              │
cr_followuptracking    ──── read by ─────► Flow 2 (Response Detection)
cr_nudgeconfiguration  ──── read by ─────► Flow 2
                                              │ posts Teams card
                                              ▼
cr_followuptracking    ◄──── updated by ── Flow 2b (Card Action Handler)
                                          
cr_nudgeconfiguration  ──── read by ─────► Flow 3 (Snooze Detection)
cr_snoozedconversation ◄──── created by ── Flow 3
                                          
cr_snoozedconversation ──── read by ─────► Flow 4 (Auto-Unsnooze)
cr_snoozedconversation ◄──── updated by ── Flow 4
                                          
cr_followuptracking    ◄──── deleted by ── Flow 5 (Data Retention, >90 days)
cr_snoozedconversation ◄──── deleted by ── Flow 6 (Snooze Cleanup, >30 days)
                                          
cr_nudgeconfiguration  ──── read/write ──► Flow 7/7b (Settings)
```

**Deployment order:** Phase 1 (Flow 5, 1, 2, 2b) → Phase 2 (Flow 6, 3, 4) → Phase 3 (Flow 7, 7b). Each phase's flows can run independently, but Phase 2 flows require Phase 1 tables to exist.

---

## Phase 1: Follow-Up Nudges

### Step 1: Provision Environment & Dataverse Tables

```powershell
cd email-productivity-agent/scripts
pwsh provision-environment.ps1 -TenantId "<tenant-id>"
```

This creates:
- Power Platform environment (`EmailProductivityAgent-Dev`)
- `cr_followuptracking` table with 12 columns + composite alternate key
- `cr_nudgeconfiguration` table with 8 columns (including cr_owneruserid) + owner alternate key
- `cr_snoozedconversation` table with 8 columns (conversationId, ownerUserId, originalMessageId, snoozeUntil, currentFolder, unsnoozedByAgent, unsnoozedDateTime, originalSubject) + composite alternate key (cr_conversationid + cr_owneruserid)

> **Naming convention:** Dataverse table logical names are singular (e.g., `cr_snoozedconversation`) while the OData entity set names used in API calls and Power Automate connectors are plural (e.g., `cr_snoozedconversations`). Both forms appear throughout this documentation — singular when referring to the table definition, plural when referencing connector operations.

### Step 2: Create Security Roles

```powershell
pwsh create-security-roles.ps1 -OrgUrl "https://<org>.crm.dynamics.com"
```

This creates the "Email Productivity Agent User" role with Basic-depth CRUD on:
- `cr_followuptracking`
- `cr_nudgeconfiguration`
- `cr_snoozedconversation` (will show a warning if Phase 2 table doesn't exist yet)

### Step 3: Configure Copilot Studio Agent

> **Required:** Flow 2 and Flow 4 invoke the Copilot Studio agent for real-time AI-powered nudge and snooze decisions. The agent must be provisioned before deploying flows.
>
> **Automated provisioning (recommended):** Run `provision-copilot.ps1` to create the agent with both topics automatically:
> ```powershell
> pwsh provision-copilot.ps1 -EnvironmentId "<env-id>"
> ```
> Note the **Bot ID** from the output — you'll pass it as `-CopilotBotId` when deploying flows.
>
> The script generates `SearchAndSummarizeContent`-based topic definitions instead of using the `InvokeAIBuilderModelAction` pattern in the committed YAML files. The committed `src/nudge-topic.yaml` and `src/snooze-topic.yaml` are reference templates — the script produces its own runnable topic definitions.
>
> **Manual provisioning:** Follow the steps below to create the agent manually in Copilot Studio.

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
   5. Description: "Structured JSON with nudgeAction, skipReason, threadSummary, suggestedDraft, nudgePriority, and confidence"
   6. Click **Save**

   **Step B — Wire the LLM response to the output variable:**
   1. On the authoring canvas, click **+ Add node** → **Add an action** → **Create a prompt** (or **Generative answers**)
   2. In the prompt/instruction box, author the system prompt referencing the 7 input variables using the `/` variable picker (e.g., `{Topic.RECIPIENT_EMAIL}`). Instruct the model to return only valid JSON in the target schema.
   3. Under **Save response as**, select or create a local variable (e.g., `Topic.GeneratedJSON`)
   4. Below the Generative Answers node, add a **Variable management** → **Set a variable value** node:
      - **Set:** `Topic.AgentResponseJSON` (your declared output variable)
      - **To:** `Topic.GeneratedJSON.text` (the text content from the Generative Answers output)
   5. Add an **End topic** node at the bottom
      - ⚠️ Do **NOT** add a "Send a message" node — that sends a reply to an interactive user, not to the calling flow

   **Step C — Verify in Power Automate (after flow is built):**
   - The output variable `AgentResponseJSON` appears in the Copilot Studio connector action's dynamic content panel
   - Expression to access: `outputs('Your_CopilotStudio_Action_Name')?['body']?['AgentResponseJSON']`
   - To parse the JSON string: `json(outputs('Your_CopilotStudio_Action_Name')?['body']?['AgentResponseJSON'])`
   - Then access fields: `body('Parse_JSON')?['nudgeAction']`, `body('Parse_JSON')?['confidence']`, etc.

   > **Defensive pattern:** Since LLMs can occasionally return malformed JSON, add a Condition node in PA after Parse JSON to check `empty(body('Parse_JSON')?['nudgeAction'])`. If true, retry or route to a fallback branch.

9. Click **Publish** (top-right) to make the agent available to Power Automate flows

> **Tip:** After publishing, test the agent using the **Test agent** panel (bottom-left). Provide sample input values and verify the response is valid JSON matching the output schema in the prompt.

#### Snooze Auto-Removal Topic (Required for Phase 2)

If deploying Phase 2 (Snooze Auto-Removal), create a second topic in the same agent:

1. Go to **Topics** → **+ New topic** → **From blank**
2. Name: **Snooze Auto-Removal**
3. Click **Details** → **Inputs** tab and create these 9 input variables (all set to **"Set as a value"**):

   | Variable Name | Data Type | Description |
   |---|---|---|
   | `CONVERSATION_ID` | String | The Microsoft Graph conversationId of the snoozed email thread that received a new reply |
   | `NEW_MESSAGE_SENDER` | String | Email address of the sender who authored the new reply |
   | `NEW_MESSAGE_SENDER_NAME` | String | Display name of the reply sender |
   | `NEW_MESSAGE_SUBJECT` | String | Subject line of the newly received reply message |
   | `NEW_MESSAGE_EXCERPT` | String | Plain text excerpt of the new reply, up to 500 characters |
   | `SNOOZED_SUBJECT` | String | Subject line of the original snoozed conversation |
   | `SNOOZE_UNTIL` | String | Snooze expiration timestamp (null if indefinite) |
   | `USER_TIMEZONE` | String | User timezone identifier for working-hours suppression |
   | `CURRENT_DATETIME` | String | Current UTC timestamp when the flow invokes the agent |

4. Go to **Details** → **Outputs** tab → create `AgentResponseJSON` (String type)
5. In the topic canvas, paste the contents of `prompts/snooze-agent-system-prompt.md` (excluding the markdown title)
6. Wire the output: Set `Topic.AgentResponseJSON = Topic.GeneratedJSON.text`
7. Add an **End topic** node
8. **Publish** the agent again

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

- **Microsoft Copilot Studio** — for agent invocation in Flow 2 and Flow 4
  - Create the connection after running `provision-copilot.ps1`
  - The connection must be in the same DLP group as the other 5 connectors

### Step 5: Deploy Power Automate Flows

The deploy script creates flows via the **Flow Management API** with connection bindings, then adds them to the Dataverse solution. Flow definitions are located in the `src/` directory as JSON files (e.g., `src/flow-1-sent-items-tracker.json`).

**Phase groups:**
- **Phase1**: Flow 5 (Data Retention), Flow 1 (Sent Items Tracker), Flow 2 (Response Detection), Flow 2b (Card Action Handler)
- **Phase2**: Flow 6 (Snooze Cleanup), Flow 3 (Snooze Detection), Flow 4 (Auto-Unsnooze)
- **Phase3**: Flow 7 (Settings Card), Flow 7b (Settings Card Handler)
- **Individual harnesses** (optional): Flow8 through Flow13 — deployed one at a time for regression testing

> **Why the Flow Management API?** Flows must be created via `api.flow.microsoft.com` (not the Dataverse `workflows` entity) because only the Flow API properly binds connections at runtime. Dataverse-created flows always fail activation with "connection references need connections" regardless of PAC solution import settings.

**Prerequisites:**
- All connections from Step 4 must exist and be in "Connected" status
- `az login` must be active (the script acquires 3 tokens: Dataverse, Flow API, PowerApps API)

```powershell
cd email-productivity-agent/scripts
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<your-org>.crm.dynamics.com" `
    -EnvironmentId "<environment-guid>" `
    -FlowsToCreate "Phase1" `
    -CopilotBotId "<bot-id-from-provision-copilot>"
```

The script will:
1. Create/reuse the `EmailProductivityAgent` solution
2. Create 6 connection references in the solution
3. Auto-discover connections in the environment and map them to connectors
4. Create all 4 Phase 1 flows via the Flow Management API with `state=Started`
5. Add flows to the solution

**Expected output:** All 4 Phase 1 flows created and running (✓ ON).

> **Troubleshooting — Flow API validation errors:**
> - `WorkflowOperationParametersExtraParameter`: The Teams payload shape does not match the selected posting location. For `PostCardToConversation` with `location = "Chat with Flow bot"`, use `body/recipient = "user@contoso.com"` and `body/messageBody = "{...}"`. Do **not** use `body/recipient/to` for chat posts.
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

### Optional: Deploy Phase 1 Regression Harnesses

Use the harness flows when you need to re-run Phase 1 logic without waiting for scheduled recurrences or Teams card clicks.

```powershell
cd email-productivity-agent/scripts
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<your-org>.crm.dynamics.com" `
    -EnvironmentId "<environment-guid>" `
    -FlowsToCreate "Flow8" `
    -CopilotBotId "<bot-id-from-provision-copilot>"

pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<your-org>.crm.dynamics.com" `
    -EnvironmentId "<environment-guid>" `
    -FlowsToCreate "Flow9" `
    -CopilotBotId "<bot-id-from-provision-copilot>"

pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<your-org>.crm.dynamics.com" `
    -EnvironmentId "<environment-guid>" `
    -FlowsToCreate "Flow10"

pwsh invoke-followup-test-harness.ps1 `
    -EnvironmentId "<environment-guid>" `
    -TrackingId "<cr_followuptrackingid-guid>" `
    -ForceNudge

pwsh invoke-http-flow-harness.ps1 `
    -EnvironmentId "<environment-guid>" `
    -FlowDisplayName "EPA - Flow 10: Settings Handler Test Harness" `
    -BodyJson '{"action":"restore_defaults","responderEmail":"<user@domain.com>","responderUserPrincipalName":"<user@domain.com>"}'
```

Flow 8 validates Flow 2, Flow 9 validates Flow 2b, and Flow 10 validates Flow 7b. `invoke-followup-test-harness.ps1` is purpose-built for Flow 8, while `invoke-http-flow-harness.ps1` is the generic helper for Flow 9-13. The generic helper automatically resolves the callback URL, handles the required `x-ms-client-scope` header, understands callback URLs returned under either `value` or `response.value`, and waits for the run to finish. Use `-ForceNudge` with Flow 8 when you need to replay the Teams-card branch even if the row is already marked replied, dismissed, or nudged.

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
    -FlowsToCreate "Phase2" `
    -CopilotBotId "<bot-id-from-provision-copilot>"
```

This creates:
- **Flow 3: Snooze Detection** — Scans the EPA-Snoozed folder every 15 minutes and tracks conversations in Dataverse
- **Flow 4: Auto-Unsnooze** — Watches Inbox for new emails; if one matches a snoozed conversation, invokes the Snooze Agent to decide UNSNOOZE or SUPPRESS, then moves the message back to Inbox and notifies via Teams
- **Flow 6: Snooze Cleanup** — Weekly purge of unsnoozed records older than 30 days

**Expected output:** All 3 flows created and running (✓ ON).

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

### Optional: Deploy Phase 2 Regression Harnesses

Use these harness flows when you want CLI-driven coverage for the snooze path (pass `-CopilotBotId` for Flows 12):

```powershell
cd email-productivity-agent/scripts
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<your-org>.crm.dynamics.com" `
    -EnvironmentId "<environment-guid>" `
    -FlowsToCreate "Flow11"

pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<your-org>.crm.dynamics.com" `
    -EnvironmentId "<environment-guid>" `
    -FlowsToCreate "Flow12" `
    -CopilotBotId "<bot-id-from-provision-copilot>"

pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<your-org>.crm.dynamics.com" `
    -EnvironmentId "<environment-guid>" `
    -FlowsToCreate "Flow13"

# 1. Seed a real message into EPA-Snoozed
pwsh invoke-http-flow-harness.ps1 `
    -EnvironmentId "<environment-guid>" `
    -FlowDisplayName "EPA - Flow 13: Snooze Seed Test Harness" `
    -BodyJson '{"subjectPrefix":"EPA Snooze Harness","bodyText":"Automated snooze seed"}'

# 2. Scan the folder and create/update cr_snoozedconversation rows
pwsh invoke-http-flow-harness.ps1 `
    -EnvironmentId "<environment-guid>" `
    -FlowDisplayName "EPA - Flow 11: Snooze Detection Test Harness"
```

Then query the newest active `cr_snoozedconversation` row and pass its `conversationId` into Flow 12:

```powershell
pwsh invoke-http-flow-harness.ps1 `
    -EnvironmentId "<environment-guid>" `
    -FlowDisplayName "EPA - Flow 12: Auto-Unsnooze Test Harness" `
    -BodyJson '{"conversationId":"<graph-conversation-id>","subject":"Re: <original-subject>","bodyPreview":"Automated reply payload","from":{"emailAddress":{"address":"<user@domain.com>","name":"<display-name>"}}}'
```

This harness sequence validates the real mailbox move, Dataverse update, Snooze Agent invocation, and Teams notification path without waiting on a live reply.

> **Observed hardening:** Flow 3 now first checks whether `EPA-Snoozed` already exists before trying to create it, persists the recovered folder ID back into `cr_nudgeconfiguration`, and uses `ListRecords` + `UpdateRecord`/`CreateRecord` for `cr_snoozedconversation` writes. The create path must explicitly set `item/cr_unsnoozedbyagent = false` for the Dataverse connector to save successfully.

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

1. **Turn off flows**: Disable all 9 production flows (1, 2, 2b, 3, 4, 5, 6, 7, 7b) in Power Automate
2. **Disable agent**: Deactivate the Copilot Studio agent
3. **(Optional) Clean up data**: Delete all rows in `cr_followuptracking` and `cr_snoozedconversation`
4. **(Optional) Remove folder**: Delete the EPA-Snoozed folder via Graph or Outlook
5. **(Optional) Remove harness flows**: Delete Flow 8-13 if you deployed the regression harnesses
6. Existing Intelligent Work Layer flows are unaffected

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
Users can view their nudge configuration via the Canvas App. For full data access, use the Dataverse maker portal (Power Apps → Tables) with ownership-based RLS ensuring users only see their own rows.

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
