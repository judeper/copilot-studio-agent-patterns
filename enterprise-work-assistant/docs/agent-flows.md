# Agent Flows — Step-by-Step Build Guide

This guide walks through building the three Power Automate agent flows that feed the Enterprise Work Assistant. Each flow intercepts a specific signal type, invokes the Copilot Studio agent, and writes results to the Dataverse `Assistant Cards` table.

## Prerequisites

- Enterprise Work Assistant agent **published** in Copilot Studio with JSON output mode enabled (see [deployment-guide.md](deployment-guide.md), Phase 2)
- `Assistant Cards` Dataverse table provisioned (run `scripts/provision-environment.ps1`)
- Research tool actions registered in Copilot Studio (see [deployment-guide.md](deployment-guide.md), Section 2.4)
- Connections created for: Office 365 Outlook, Microsoft Teams, Office 365 Users, Microsoft Graph, SharePoint

> **Note on connections vs. connection references**: For initial development, you only need standard *connections* (authenticated links to connectors). If you later package these flows into a solution for deployment across environments, you will need *connection references* (solution-aware pointers to connections). See [Microsoft Learn: Connection references](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/create-connection-reference) for details.

> **Connector Note**: These flows use the **Microsoft Copilot Studio** connector's **"Execute Agent and wait"** action to invoke agents. Do not confuse this with the AI Builder **"Run a prompt"** action, which runs standalone prompts (not full agents). *Last verified: Feb 2026*

---

## Important: Row Ownership

Power Automate flows run under the connection owner's identity. By default, Dataverse rows created by the flow are owned by whichever account authenticated the Dataverse connector — **not** the end user whose email/message triggered the flow.

To ensure each user sees only their own cards (Row-Level Security), you **must** explicitly set the Owner field in every "Add a new row" action:

1. In the "Add a new row" action, expand **Show advanced options**
2. Set **Owner** to the user's Azure AD Object ID (from the "Get my profile V2" step):
   `@{outputs('Get_my_profile_(V2)')?['body/id']}`

This is **critical** for the ownership-based security model to work correctly.

---

## Important: Parse JSON Schema

The canonical schema in `schemas/output-schema.json` uses `oneOf` for the `draft_payload` field. Power Automate's **Parse JSON** action does **not** support `oneOf` or `anyOf`. You must use the simplified schema below for all Parse JSON actions in these flows:

```json
{
  "type": "object",
  "properties": {
    "trigger_type": { "type": "string" },
    "triage_tier": { "type": "string" },
    "item_summary": { "type": "string" },
    "priority": { "type": "string" },
    "temporal_horizon": { "type": "string" },
    "research_log": { "type": ["string", "null"] },
    "key_findings": { "type": ["string", "null"] },
    "verified_sources": {},
    "confidence_score": { "type": ["integer", "null"] },
    "card_status": { "type": "string" },
    "draft_payload": {},
    "low_confidence_note": { "type": ["string", "null"] }
  }
}
```

> The `{}` (empty schema) for `draft_payload` and `verified_sources` accepts any value (null, string, object, or array) without validation failure. The canonical `output-schema.json` remains the authoritative contract for development and testing.

> The `item_summary` field is always a non-nullable string. Even SKIP-tier items include a brief summary (e.g., "Marketing newsletter from Contoso Weekly -- no action needed."). See [`schemas/output-schema.json`](../schemas/output-schema.json) for the canonical contract.

*Last verified: Feb 2026*

---

## Error Handling Pattern

Wrap the agent invocation and downstream processing in a **Scope** action for error handling. Add a parallel **Scope** (configure "Run after" → "has failed") for error logging:

```
Scope: Process Signal
  ├── Invoke agent
  ├── Parse JSON
  ├── Condition: not SKIP
  │   └── Add row to Dataverse
  │       └── Condition: Humanizer handoff
  │           ├── Invoke Humanizer
  │           └── Update row
  └── (on failure) → Scope: Handle Error
                        └── Send notification / log to error table
```

For each flow, place steps 4–10 inside a **Scope** action named "Process Signal" and add a parallel error-handling scope.

---

## Flow 1 — EMAIL Trigger

### Trigger

**When a new email arrives (V3)** — Office 365 Outlook connector

| Setting | Value |
|---------|-------|
| Folder | Inbox |
| Include Attachments | No |
| Split On | Enabled (each email gets its own flow run) |
| Subject Filter | *(leave blank — filtering is done in step 1a below)* |

### Actions

**1a. Condition — Pre-filter low-value emails**

Skip emails from known no-reply senders and system-generated messages to avoid unnecessary agent calls:

```
@and(
  not(contains(toLower(triggerOutputs()?['body/from']), 'noreply')),
  not(contains(toLower(triggerOutputs()?['body/from']), 'no-reply')),
  not(contains(toLower(triggerOutputs()?['body/from']), 'mailer-daemon')),
  not(equals(triggerOutputs()?['body/importance'], 'low'))
)
```

> **Tip**: Customize this filter for your organization. Common additions: `notifications@`, `donotreply@`, automated report senders. If using the Office 365 Outlook V3 trigger, you can also use the built-in **From** filter setting.

**If No (filtered out):** Terminate the flow (no further action needed).

**If Yes:**

**1. Compose — PAYLOAD**

```json
{
  "from": "@{triggerOutputs()?['body/from']}",
  "to": "@{triggerOutputs()?['body/toRecipients']}",
  "cc": "@{triggerOutputs()?['body/ccRecipients']}",
  "subject": "@{triggerOutputs()?['body/subject']}",
  "bodyPreview": "@{triggerOutputs()?['body/bodyPreview']}",
  "receivedDateTime": "@{triggerOutputs()?['body/receivedDateTime']}",
  "importance": "@{triggerOutputs()?['body/importance']}",
  "hasAttachments": "@{triggerOutputs()?['body/hasAttachments']}",
  "conversationId": "@{triggerOutputs()?['body/conversationId']}",
  "internetMessageId": "@{triggerOutputs()?['body/internetMessageId']}"
}
```

> **Note**: We use `bodyPreview` (plain text, max ~255 chars) instead of `body` (which returns HTML). The agent prompt expects plain text. If you need the full body, use `body/bodyPreview` for plain text or strip HTML using the built-in `stripHtml()` expression: `@{if(not(empty(triggerOutputs()?['body/body'])), stripHtml(triggerOutputs()?['body/body']), '')}`.

**1b. Compose — SENDER_EMAIL** *(Sprint 1A)*

Parse the sender's email address from the trigger output. The V3 trigger may return `from` as a structured string like `"Sarah Chen" <sarah@contoso.com>` or just `sarah@contoso.com`:

```
@{if(
    contains(triggerOutputs()?['body/from'], '<'),
    last(split(first(split(triggerOutputs()?['body/from'], '>')), '<')),
    triggerOutputs()?['body/from']
)}
```

> **Tip**: If your Office 365 Outlook trigger version provides `sender/emailAddress/address` as a structured field, use that instead — it's more reliable. Check the dynamic content picker for a structured `from` object.

**1c. Compose — SENDER_DISPLAY** *(Sprint 1A)*

Parse the sender's display name:

```
@{if(
    contains(triggerOutputs()?['body/from'], '<'),
    trim(first(split(triggerOutputs()?['body/from'], '<'))),
    ''
)}
```

> Returns the display name portion before the `<email>` bracket, or empty string if the `from` field is just an email address.
**2. Get my profile (V2)** — Office 365 Users connector

**3. Compose — USER_CONTEXT**

Format as a comma-separated string to match the agent prompt's few-shot examples:

```
@{outputs('Get_my_profile_(V2)')?['body/displayName']}, @{outputs('Get_my_profile_(V2)')?['body/jobTitle']}, @{outputs('Get_my_profile_(V2)')?['body/department']}
```

> This produces a string like `"Jordan Martinez, Senior Account Manager, Enterprise Sales"` which matches the format used in the main agent prompt's few-shot examples.

**4. Invoke the agent**

Add the **Microsoft Copilot Studio** connector (search for "Microsoft Copilot Studio" in the connector list — do NOT use the AI Builder connector). Select the **"Execute Agent and wait"** action. Choose the **Enterprise Work Assistant** agent.

> **Important**: "Run a prompt" is a different action (AI Builder) that runs a standalone prompt, not a full agent. You must use **"Execute Agent and wait"** from the **Microsoft Copilot Studio** connector to invoke an agent with its system prompt, tools, and orchestration.

> After adding the action, check the *dynamic content picker* for the agent's response. The Execute Agent and wait action returns a `lastResponse` field (the agent's final text response). Use this field name consistently in steps 5 and 7. If the field name differs in your environment, verify via the dynamic content picker.

| Input Variable | Value |
|---------------|-------|
| TRIGGER_TYPE | `EMAIL` |
| PAYLOAD | `@{outputs('Compose_PAYLOAD')}` |
| USER_CONTEXT | `@{outputs('Compose_USER_CONTEXT')}` |
| CURRENT_DATETIME | `@{utcNow()}` |

**5. Parse JSON** — Parse the agent's response

Use the **simplified schema** from the "Parse JSON Schema" section above (not the canonical `output-schema.json` which contains unsupported `oneOf`).

**6. Condition — Check triage tier**

```
@not(equals(body('Parse_JSON')?['triage_tier'], 'SKIP'))
```

**If Yes (not SKIP):**

**7. Add a new row** — Dataverse connector → Assistant Cards table

For Choice columns, you must map the agent's string output to the integer option value. Add a **Compose** action with an `if()` expression chain for each Choice column. All five expressions are shown below — copy-paste each into its own Compose action:

**Compose -- Triage Tier Value:**

```
if(equals(body('Parse_JSON')?['triage_tier'],'LIGHT'),100000001,100000002)
```

> **Note**: The SKIP branch is omitted because this Compose action is inside the "If Yes (not SKIP)" condition — SKIP items never reach this point.

**Compose -- Trigger Type Value:**

```
if(equals(body('Parse_JSON')?['trigger_type'],'EMAIL'),100000000,if(equals(body('Parse_JSON')?['trigger_type'],'TEAMS_MESSAGE'),100000001,100000002))
```

**Compose -- Priority Value:**

```
if(equals(body('Parse_JSON')?['priority'],'High'),100000000,if(equals(body('Parse_JSON')?['priority'],'Medium'),100000001,if(equals(body('Parse_JSON')?['priority'],'Low'),100000002,100000003)))
```

**Compose -- Card Status Value:**

```
if(equals(body('Parse_JSON')?['card_status'],'READY'),100000000,if(equals(body('Parse_JSON')?['card_status'],'LOW_CONFIDENCE'),100000001,if(equals(body('Parse_JSON')?['card_status'],'SUMMARY_ONLY'),100000002,100000003)))
```

**Compose -- Temporal Horizon Value:**

```
if(equals(body('Parse_JSON')?['temporal_horizon'],'TODAY'),100000000,if(equals(body('Parse_JSON')?['temporal_horizon'],'THIS_WEEK'),100000001,if(equals(body('Parse_JSON')?['temporal_horizon'],'NEXT_WEEK'),100000002,if(equals(body('Parse_JSON')?['temporal_horizon'],'BEYOND'),100000003,100000004))))
```

**JSON serialization for draft_payload:**

```
@{string(body('Parse_JSON')?['draft_payload'])}
```

Serializes the `draft_payload` object back to a JSON string. Used when passing to the Humanizer Agent (step 9) and when storing the Full JSON Output.

| Column | Value |
|--------|-------|
| Item Summary | `@{body('Parse_JSON')?['item_summary']}` |
| Triage Tier | Choice value from Compose (see mapping table) |
| Trigger Type | Choice value from Compose (see mapping table) |
| Priority | Choice value from Compose (see mapping table) |
| Card Status | Choice value from Compose (see mapping table) |
| Temporal Horizon | Choice value from Compose (see mapping table) |
| Confidence Score | `@{body('Parse_JSON')?['confidence_score']}` (null for SKIP/LIGHT tier — the Dataverse WholeNumber column accepts null) |
| Full JSON Output | `@{body('Execute_Agent_and_wait')?['lastResponse']}` (the agent's text response — the field name in dynamic content may vary by connector version; look for the agent's text response output in the dynamic content picker) |
| **Owner** | `@{outputs('Get_my_profile_(V2)')?['body/id']}` **(required for RLS — see Row Ownership section)** |
| Card Outcome | `100000000` **(Sprint 1A: PENDING — all new cards start as PENDING)** |
| Original Sender Email | `@{outputs('Compose_SENDER_EMAIL')}` **(Sprint 1A)** |
| Original Sender Display | `@{outputs('Compose_SENDER_DISPLAY')}` **(Sprint 1A)** |
| Original Subject | `@{triggerOutputs()?['body/subject']}` **(Sprint 1A)** |
| Conversation Cluster ID | `@{triggerOutputs()?['body/conversationId']}` **(Sprint 1B)** |
| Source Signal ID | `@{triggerOutputs()?['body/internetMessageId']}` **(Sprint 1B)** |

**8. Condition — Humanizer handoff**

```
@and(
  equals(body('Parse_JSON')?['triage_tier'], 'FULL'),
  and(
    greaterOrEquals(body('Parse_JSON')?['confidence_score'], 40),
    not(equals(body('Parse_JSON')?['trigger_type'], 'CALENDAR_SCAN'))
  )
)
```

> **Note**: The nested `and()` ensures compatibility with older Power Automate environments that only accept two arguments per `and()` call.

**If Yes:**

**9. Invoke the Humanizer Agent**

Add another **Microsoft Copilot Studio** **"Execute Agent and wait"** action. Select the **Humanizer Agent**. The Humanizer expects a JSON string as input — serialize the `draft_payload` object:

```
@{string(body('Parse_JSON')?['draft_payload'])}
```

> **Important**: Copilot Studio input variables are typed as text. You must convert the parsed object back to a JSON string using `string()`. Passing the object directly will produce an error or unexpected format.

**10. Update a row** — Dataverse connector → Assistant Cards table

| Column | Value |
|--------|-------|
| Row ID | ID from step 7 |
| Humanized Draft | Response from step 9 |

**11. Upsert Sender Profile** *(Sprint 1B)*

Add a parallel branch after step 7 (the Dataverse card write) that runs independently of the humanizer handoff. This uses the List → Condition → Add/Update pattern since the Dataverse connector has no native upsert action.

**11a. List rows** — Dataverse connector → Sender Profiles table

| Setting | Value |
|---------|-------|
| Table name | Sender Profiles |
| Filter rows | `cr_senderemail eq '@{outputs('Compose_SENDER_EMAIL')}'` |
| Row count | `1` |
| Select columns | `cr_senderprofileid,cr_signalcount,cr_senderdisplayname` |

**11b. Condition — Sender exists**

```
@greater(length(outputs('List_rows')?['body/value']), 0)
```

**If Yes (update existing):**

**11c. Update a row** — Dataverse → Sender Profiles

| Column | Value |
|--------|-------|
| Row ID | `@{first(outputs('List_rows')?['body/value'])?['cr_senderprofileid']}` |
| Signal Count | `@{add(first(outputs('List_rows')?['body/value'])?['cr_signalcount'], 1)}` |
| Sender Display Name | `@{outputs('Compose_SENDER_DISPLAY')}` |
| Last Signal Date | `@{utcNow()}` |

**If No (create new):**

**11d. Add a new row** — Dataverse → Sender Profiles

| Column | Value |
|--------|-------|
| Sender Email | `@{outputs('Compose_SENDER_EMAIL')}` |
| Sender Display Name | `@{outputs('Compose_SENDER_DISPLAY')}` |
| Signal Count | `1` |
| Response Count | `0` |
| Last Signal Date | `@{utcNow()}` |
| Sender Category | `100000001` *(AUTO_MEDIUM — default for new senders)* |
| Is Internal | See expression below |
| **Owner** | `@{outputs('Get_my_profile_(V2)')?['body/id']}` |

**Compose — IS_INTERNAL:**

Compare the sender's email domain to the user's email domain:

```
@equals(
    last(split(outputs('Compose_SENDER_EMAIL'), '@')),
    last(split(outputs('Get_my_profile_(V2)')?['body/mail'], '@'))
)
```

> **Note**: This parallel branch should be wrapped in a **Scope** with error handling configured to continue on failure. A sender upsert failure should not block the main card creation flow.

---

## Flow 2 — TEAMS_MESSAGE Trigger

### Trigger

**When someone is mentioned** — Microsoft Teams connector (preferred for targeted processing)

| Setting | Value |
|---------|-------|
| Team | Select the relevant team |
| Channel | Select the specific channel to monitor |

> **Important**: Avoid using `Channel = "Any"` as this captures every message in every channel across the entire team, generating excessive agent calls. Either select specific channels or use the **"When someone is mentioned"** trigger to process only messages where the user is @mentioned.

> **Trigger scope note**: The "When someone is mentioned" trigger fires for ANY @mention in the configured channels, not just mentions of the flow owner. If multiple users share a team, consider adding a pre-filter condition to check that the mentioned user matches the authenticated user: `@equals(triggerOutputs()?['body/mentions']?[0]?['mentioned']?['user']?['id'], outputs('Get_my_profile_(V2)')?['body/id'])`.

### Actions

**1a. Condition — Pre-filter** (optional but recommended)

Skip messages from bots and the current user (avoid self-processing):

```
@and(
  not(equals(triggerOutputs()?['body/from/user/id'], outputs('Get_my_profile_(V2)')?['body/id'])),
  not(contains(toLower(triggerOutputs()?['body/from/user/displayName']), 'bot'))
)
```

**1. Compose — PAYLOAD**

```json
{
  "messageBody": "@{triggerOutputs()?['body/body/content']}",
  "from": "@{triggerOutputs()?['body/from/user/displayName']}",
  "channelName": "@{triggerOutputs()?['body/channelIdentity/channelName']}",
  "teamName": "@{triggerOutputs()?['body/channelIdentity/teamName']}",
  "mentions": "@{triggerOutputs()?['body/mentions']}",
  "timestamp": "@{triggerOutputs()?['body/createdDateTime']}",
  "threadId": "@{triggerOutputs()?['body/replyToId']}"
}
```

**2-10.** Same pattern as Flow 1 — Get user profile, compose USER_CONTEXT (comma-separated string), invoke agent, parse JSON (simplified schema), conditional Dataverse write **(with Owner field set)**, conditional humanizer handoff **(with `string()` serialization)**.

Change `TRIGGER_TYPE` to `TEAMS_MESSAGE`.

**Sprint 1A additions for TEAMS_MESSAGE flow:**

Add these Compose actions before the "Add a new row" step:

**Compose — SENDER_EMAIL:**
```
@{triggerOutputs()?['body/from/user/id']}
```

> For Teams messages, use the sender's AAD user ID as the "sender email" identifier. If you need the actual email, add a "Get user profile (V2)" action using the sender's user ID to retrieve their email address.

**Compose — SENDER_DISPLAY:**
```
@{triggerOutputs()?['body/from/user/displayName']}
```

Add these columns to the "Add a new row" action:

| Column | Value |
|--------|-------|
| Card Outcome | `100000000` (PENDING) |
| Original Sender Email | `@{outputs('Compose_SENDER_EMAIL')}` |
| Original Sender Display | `@{outputs('Compose_SENDER_DISPLAY')}` |
| Original Subject | *(leave null — Teams messages don't have subject lines)* |
| Conversation Cluster ID | `@{if(not(empty(triggerOutputs()?['body/replyToId'])), triggerOutputs()?['body/replyToId'], triggerOutputs()?['body/id'])}` **(Sprint 1B: threadId for replies, messageId for root messages)** |
| Source Signal ID | `@{triggerOutputs()?['body/id']}` **(Sprint 1B)** |

**Sprint 1B: Sender upsert for TEAMS_MESSAGE flow**

Same List → Condition → Add/Update pattern as Flow 1 step 11. For Teams, to get the sender's actual email (instead of AAD user ID), add a "Get user profile (V2)" action using the sender's user ID:

```
@{triggerOutputs()?['body/from/user/id']}
```

Use the returned `mail` property as the sender email for the upsert. If the "Get user profile" action fails (external user), fall back to the AAD user ID as the sender email.

---

## Flow 3 — CALENDAR_SCAN Trigger

### Trigger

**Recurrence** — Schedule connector

| Setting | Value |
|---------|-------|
| Frequency | Day |
| Interval | 1 |
| Start Time | 07:00 AM (user's timezone) |
| Time Zone | Select appropriate timezone |

### Actions

**1. Get events (V4)** — Office 365 Outlook connector

| Setting | Value |
|---------|-------|
| Calendar ID | Default calendar |
| Start DateTime | `@{utcNow()}` |
| End DateTime | `@{addDays(utcNow(), 14)}` |
| Order By | start/dateTime asc |

**2. Get my profile (V2)** — Office 365 Users connector

**3. Compose — USER_CONTEXT** (same comma-separated string format as Flow 1)

**4. Apply to each** — Loop over events from step 1

**4a. Condition — Pre-filter**

Skip events matching low-value patterns (case-insensitive):

```
@not(
  or(
    contains(toLower(items('Apply_to_each')?['subject']), 'focus time'),
    contains(toLower(items('Apply_to_each')?['subject']), 'lunch'),
    contains(toLower(items('Apply_to_each')?['subject']), 'ooh'),
    contains(toLower(items('Apply_to_each')?['subject']), 'oof'),
    contains(toLower(items('Apply_to_each')?['subject']), 'out of office'),
    contains(toLower(items('Apply_to_each')?['subject']), 'hold'),
    contains(toLower(items('Apply_to_each')?['subject']), 'holiday'),
    contains(toLower(items('Apply_to_each')?['subject']), 'personal'),
    contains(toLower(items('Apply_to_each')?['subject']), 'private'),
    equals(items('Apply_to_each')?['showAs'], 'free')
  )
)
```

> **Note**: Uses `toLower()` for case-insensitive matching. Also filters events marked as "free" (not blocking the user's calendar). Customize patterns as needed for your organization.

**If Yes (not filtered out):**

**4b. Compose — PAYLOAD**

```json
{
  "subject": "@{items('Apply_to_each')?['subject']}",
  "body": "@{items('Apply_to_each')?['bodyPreview']}",
  "start": "@{items('Apply_to_each')?['start/dateTime']}",
  "end": "@{items('Apply_to_each')?['end/dateTime']}",
  "location": "@{items('Apply_to_each')?['location/displayName']}",
  "organizer": "@{items('Apply_to_each')?['organizer/emailAddress/name']}",
  "attendees": "@{items('Apply_to_each')?['attendees']}",
  "isRecurring": "@{items('Apply_to_each')?['recurrence']}",
  "onlineMeetingUrl": "@{items('Apply_to_each')?['onlineMeetingUrl']}",
  "importance": "@{items('Apply_to_each')?['importance']}"
}
```

**4c. Invoke agent** with `TRIGGER_TYPE = "CALENDAR_SCAN"`

**4d. Parse JSON + Conditional Dataverse write** (same pattern as Flow 1 steps 5-7, **including Owner field**)

Note: Calendar items do NOT go through the Humanizer Agent. The `draft_payload` for CALENDAR_SCAN is a plain-text meeting briefing used as-is.

**Sprint 1A additions for CALENDAR_SCAN flow:**

Add these columns to the "Add a new row" action inside the Apply to each loop:

| Column | Value |
|--------|-------|
| Card Outcome | `100000000` (PENDING) |
| Original Sender Email | `@{items('Apply_to_each')?['organizer/emailAddress/address']}` |
| Original Sender Display | `@{items('Apply_to_each')?['organizer/emailAddress/name']}` |
| Original Subject | `@{items('Apply_to_each')?['subject']}` |
| Conversation Cluster ID | See expression below **(Sprint 1B)** |
| Source Signal ID | `@{items('Apply_to_each')?['id']}` **(Sprint 1B: Graph event ID)** |

**Compose — CALENDAR_CLUSTER_ID** *(Sprint 1B)*:

Use `seriesMasterId` for recurring events (correctly groups all instances of the same recurring meeting). For non-recurring events, use a normalized concatenation of subject and organizer:

```
@{if(
    not(empty(items('Apply_to_each')?['seriesMasterId'])),
    items('Apply_to_each')?['seriesMasterId'],
    toLower(concat(
        replace(replace(items('Apply_to_each')?['subject'], ' ', ''), '-', ''),
        '|',
        items('Apply_to_each')?['organizer/emailAddress/address']
    ))
)}
```

> The `seriesMasterId` approach groups all instances of recurring meetings (e.g., weekly 1:1s, quarterly QBRs) regardless of subject line changes between occurrences.

**Sprint 1B: Sender upsert for CALENDAR_SCAN flow**

Same List → Condition → Add/Update pattern as Flow 1 step 11, using the organizer's email address (`items('Apply_to_each')?['organizer/emailAddress/address']`) and display name (`items('Apply_to_each')?['organizer/emailAddress/name']`).

> **Performance note:** The Apply to each loop already has a 5-second delay between iterations. The sender upsert adds 2-3 actions per iteration. For a 14-day calendar scan that might process 30-50 events, the flow will take 3-5 minutes total. This is acceptable for a daily batch flow.

**4e. Delay** — 5 seconds

Rate limiting between iterations to avoid Copilot Studio and connector throttling. Increase to 10 seconds if you encounter 429 (throttling) errors.

---

## Choice Value Mapping

When writing Choice columns to Dataverse, map string values to integer option values using `if()` expression chains as shown in step 7 above.

| Column | String → Value |
|--------|---------------|
| Triage Tier | SKIP → 100000000, LIGHT → 100000001, FULL → 100000002 |
| Trigger Type | EMAIL → 100000000, TEAMS_MESSAGE → 100000001, CALENDAR_SCAN → 100000002 |
| Priority | High → 100000000, Medium → 100000001, Low → 100000002, N/A → 100000003 |
| Card Status | READY → 100000000, LOW_CONFIDENCE → 100000001, SUMMARY_ONLY → 100000002, NO_OUTPUT → 100000003 |
| Temporal Horizon | TODAY → 100000000, THIS_WEEK → 100000001, NEXT_WEEK → 100000002, BEYOND → 100000003, N/A → 100000004 |
| Card Outcome *(Sprint 1A)* | PENDING → 100000000, SENT_AS_IS → 100000001, SENT_EDITED → 100000002, DISMISSED → 100000003, EXPIRED → 100000004 |
| Sender Category *(Sprint 1B)* | AUTO_HIGH → 100000000, AUTO_MEDIUM → 100000001, AUTO_LOW → 100000002, USER_OVERRIDE → 100000003 |

These values match the definitions in `schemas/dataverse-table.json` and the provisioning script. See step 7 above for copy-pasteable expressions.

*Last verified: Feb 2026*

---

## Flow 4 — Send Email (Sprint 1A)

### Overview

User-initiated flow called from the Canvas app when the user confirms sending a draft email. This flow:
1. Validates the request (ownership, recipient match)
2. Sends the email from the user's own mailbox
3. Writes audit data to Dataverse (outcome, timestamps)
4. Returns success/failure to the Canvas app

### Key Architecture Decisions

- **Delegated identity**: Uses "Run only users" so each user provides their own Office 365 Outlook connection. The email is sent FROM the user's mailbox, not a service account.
- **Flow-guaranteed audit**: The flow writes `cr_cardoutcome`, `cr_senttimestamp`, and `cr_sentrecipient` to Dataverse server-side. The Canvas app does NOT Patch these columns for send actions.
- **Validation-first**: The flow validates all inputs before sending. No email is sent if validation fails.

### Trigger

**Instant — When a flow is called from a Canvas app** (also known as "Power Apps (V2)" trigger)

Inputs (passed from Canvas app via `PowerAutomate.Run()`):

| Input | Type | Description |
|-------|------|-------------|
| CardId | Text | Dataverse row GUID of the card |
| FinalDraftText | Text | The draft text to send as email body |

### Connection Configuration

**CRITICAL**: This flow must be configured with "Run only users" for the **Office 365 Outlook** connection:

1. In the flow's Properties → Run only users
2. For the Office 365 Outlook connection, select **"Provided by run-only user"**
3. For the Dataverse connection, select **"Use this connection"** (flow owner's connection is fine — RLS protects data)
4. For the Office 365 Users connection, select **"Use this connection"**

When a user first triggers this flow from the Canvas app, they will be prompted to provide their own Outlook connection. This is a one-time setup per user.

### Actions

**1. Get my profile (V2)** — Office 365 Users connector

Retrieves the current user's Azure AD profile. Used for ownership validation.

**2. Get a row by ID** — Dataverse connector → Assistant Cards table

| Setting | Value |
|---------|-------|
| Table name | Assistant Cards |
| Row ID | CardId input from trigger |
| Select columns | `cr_originalsenderemail,cr_originalsenderdisplay,cr_originalsubject,_ownerid_value` |

**3. Condition — Validate ownership**

```
@equals(
    outputs('Get_a_row_by_ID')?['body/_ownerid_value'],
    outputs('Get_my_profile_(V2)')?['body/id']
)
```

**If No (not the owner):** Respond to app with error:

| Output | Value |
|--------|-------|
| success | `false` |
| errorMessage | `Unauthorized: this card does not belong to your account.` |
| recipientDisplay | *(empty)* |

Then **Terminate** the flow.

**If Yes (owner verified):**

**4. Condition — Validate recipient exists**

```
@not(empty(outputs('Get_a_row_by_ID')?['body/cr_originalsenderemail']))
```

**If No:** Respond with error: `No recipient email address found for this card.`

**If Yes:**

**5. Condition — Validate draft text is not empty**

```
@not(empty(triggerBody()['text_1']))
```

> Note: `text_1` is the default name for the second input parameter (FinalDraftText) in the Power Apps V2 trigger. The actual name depends on the input parameter name you configured — check the dynamic content picker.

**If No:** Respond with error: `Draft text is empty. Cannot send an empty email.`

**If Yes:**

**6. Compose — REPLY_SUBJECT**

Strip existing "Re: " / "RE: " prefix to avoid "Re: Re: Re: " chains, then prepend "Re: ":

```
Re: @{if(
    startsWith(toLower(outputs('Get_a_row_by_ID')?['body/cr_originalsubject']), 're: '),
    substring(outputs('Get_a_row_by_ID')?['body/cr_originalsubject'], 4),
    if(
        empty(outputs('Get_a_row_by_ID')?['body/cr_originalsubject']),
        '(no subject)',
        outputs('Get_a_row_by_ID')?['body/cr_originalsubject']
    )
)}
```

**7. Send an email (V2)** — Office 365 Outlook connector **(uses the user's own connection)**

| Setting | Value |
|---------|-------|
| To | `@{outputs('Get_a_row_by_ID')?['body/cr_originalsenderemail']}` |
| Subject | `@{outputs('Compose_REPLY_SUBJECT')}` |
| Body | `@{triggerBody()['text_1']}` *(FinalDraftText input)* |
| Importance | Normal |
| Is HTML | No *(humanized drafts are plain text)* |

> **Scope wrapping**: Wrap steps 7-8 in a **Scope** named "Send and Audit" with a parallel error-handling Scope (configure "Run after" → "has failed"). If step 7 (send) succeeds but step 8 (audit write) fails, the email was still sent — log the audit failure but return success to the user.

**8. Update a row** — Dataverse connector → Assistant Cards table

| Column | Value |
|--------|-------|
| Row ID | CardId input from trigger |
| Card Outcome | `100000001` *(SENT_AS_IS)* |
| Outcome Timestamp | `@{utcNow()}` |
| Sent Timestamp | `@{utcNow()}` |
| Sent Recipient | `@{outputs('Get_a_row_by_ID')?['body/cr_originalsenderemail']}` |

> **Note**: Sprint 1A only supports Send As-Is (no inline editing). The outcome is always `SENT_AS_IS` (100000001). When Sprint 2 adds inline editing, the Canvas app will pass an `outcome` parameter to distinguish `SENT_AS_IS` vs `SENT_EDITED`.

**9. Respond to a PowerApp or flow** — Success response

| Output | Value |
|--------|-------|
| success | `true` |
| errorMessage | *(empty)* |
| recipientDisplay | `@{outputs('Get_a_row_by_ID')?['body/cr_originalsenderdisplay']}` |

### Error Handling

If step 7 (Send email) fails:

**10. Respond to a PowerApp or flow** — Error response (in the error-handling Scope)

| Output | Value |
|--------|-------|
| success | `false` |
| errorMessage | `Failed to send email. Please check your Outlook connection or try copying the draft to send manually.` |
| recipientDisplay | *(empty)* |

### Flow Diagram

```
Trigger (Canvas app)
  │
  ├── 1. Get my profile (V2)
  ├── 2. Get card row by ID
  ├── 3. Validate: owner matches
  │   └── No → Respond: unauthorized → Terminate
  ├── 4. Validate: recipient exists
  │   └── No → Respond: no recipient → Terminate
  ├── 5. Validate: draft not empty
  │   └── No → Respond: empty draft → Terminate
  ├── 6. Compose reply subject (strip Re: prefix)
  │
  └── Scope: Send and Audit
      ├── 7. Send email (V2) — user's connection
      ├── 8. Update card row (outcome, timestamps)
      └── 9. Respond: success
      │
      └── (on failure) → 10. Respond: error
```

### Deployment Checklist

- [ ] Flow created with "Run only users" configured for Outlook connector
- [ ] DLP policy reviewed: Outlook connector now used for WRITE operations
- [ ] Test: Send email to a test recipient, verify delivery and Dataverse update
- [ ] Test: Attempt send with a CardId belonging to another user — should fail
- [ ] Test: First-time user experience — Outlook connection prompt appears
- [ ] Update deployment guide with connection setup instructions

---

## Flow 5 — Card Outcome Tracker (Sprint 1B)

### Overview

Automated flow that fires when a card's outcome changes in Dataverse and performs downstream bookkeeping on the Sender Profile table. This creates a feedback loop: user actions on cards improve sender intelligence, which influences future card prioritization.

### Key Architecture Decisions

- **Trigger filtering**: Uses `filteringattributes` parameter set to exactly `cr_cardoutcome` to prevent infinite trigger loops. Only fires when the outcome column changes, not on any other row modification.
- **Non-blocking**: Failures in this flow do not affect the user experience. The outcome has already been written to the card row by the Send Email flow (for sends) or Canvas app Patch (for dismissals).
- **Running average**: Uses the standard running average formula to update `cr_avgresponsehours` without loading all historical data.

### Trigger

**When a row is added, modified or deleted** — Dataverse connector

| Setting | Value |
|---------|-------|
| Change type | Modified |
| Table name | Assistant Cards |
| Scope | Organization *(RLS handles user-level filtering)* |
| Filter columns (filteringattributes) | `cr_cardoutcome` |
| Filter rows (filterexpression) | `cr_cardoutcome ne 100000000` *(ignore PENDING → PENDING, only process actual outcome changes)* |

> **CRITICAL**: Use the **"When a row is added, modified or deleted"** trigger (not the older "When a record is changed" trigger). Only the newer trigger supports the `filteringattributes` parameter that prevents this flow from re-triggering when other columns on the same row are updated.

### Actions

**1. Get the modified card row** — Dataverse connector

| Setting | Value |
|---------|-------|
| Table name | Assistant Cards |
| Row ID | `@{triggerOutputs()?['body/cr_assistantcardid']}` |
| Select columns | `cr_cardoutcome,cr_outcometimestamp,cr_originalsenderemail,cr_originalsenderdisplay,createdon,_ownerid_value` |

**2. Condition — Is this a response action?**

Only update sender profile for SENT_AS_IS or SENT_EDITED outcomes (not DISMISSED or EXPIRED):

```
@or(
    equals(outputs('Get_the_modified_card_row')?['body/cr_cardoutcome'], 100000001),
    equals(outputs('Get_the_modified_card_row')?['body/cr_cardoutcome'], 100000002)
)
```

**If No (DISMISSED or EXPIRED):** Terminate — no sender profile update needed.

> **Design note**: Dismissals are intentionally excluded from sender profile updates. A dismissal could mean "low-value sender" OR "low-value topic from a high-value sender." The signal is ambiguous. Sprint 4 analytics can analyze dismissal patterns across senders to infer sender quality.

**If Yes (SENT_AS_IS or SENT_EDITED):**

**3. Calculate response time**

**Compose — RESPONSE_HOURS:**

```
@{div(
    div(
        sub(
            ticks(outputs('Get_the_modified_card_row')?['body/cr_outcometimestamp']),
            ticks(outputs('Get_the_modified_card_row')?['body/createdon'])
        ),
        10000000
    ),
    3600
)}
```

> Calculates the difference in ticks between outcome timestamp and card creation time, converts from 100-nanosecond ticks to seconds (÷10,000,000), then to hours (÷3,600). Result is a decimal number of hours.

**4. List rows — Find sender profile**

| Setting | Value |
|---------|-------|
| Table name | Sender Profiles |
| Filter rows | `cr_senderemail eq '@{outputs('Get_the_modified_card_row')?['body/cr_originalsenderemail']}' and _ownerid_value eq '@{outputs('Get_the_modified_card_row')?['body/_ownerid_value']}'` |
| Row count | `1` |
| Select columns | `cr_senderprofileid,cr_responsecount,cr_avgresponsehours` |

> **Note**: The filter includes the owner ID to ensure we update the correct user's sender profile (since Sender Profiles are UserOwned, the same sender email can appear once per user).

**5. Condition — Sender profile exists**

```
@greater(length(outputs('List_rows_Find_sender_profile')?['body/value']), 0)
```

**If No:** Log a warning and terminate. The sender profile should have been created by the trigger flow (step 11). If it's missing, the trigger flow may not have been updated for Sprint 1B yet. Do NOT create a new sender profile here — that's the trigger flow's responsibility.

**If Yes:**

**6. Update a row — Update sender profile** — Dataverse → Sender Profiles

| Column | Value |
|--------|-------|
| Row ID | `@{first(outputs('List_rows_Find_sender_profile')?['body/value'])?['cr_senderprofileid']}` |
| Response Count | `@{add(first(outputs('List_rows_Find_sender_profile')?['body/value'])?['cr_responsecount'], 1)}` |
| Average Response Hours | See running average expression below |

**Compose — NEW_AVG_RESPONSE_HOURS:**

Uses the running average formula: `new_avg = ((old_avg × old_count) + new_value) / (old_count + 1)`

```
@{div(
    add(
        mul(
            float(first(outputs('List_rows_Find_sender_profile')?['body/value'])?['cr_avgresponsehours']),
            float(first(outputs('List_rows_Find_sender_profile')?['body/value'])?['cr_responsecount'])
        ),
        float(outputs('Compose_RESPONSE_HOURS'))
    ),
    add(
        float(first(outputs('List_rows_Find_sender_profile')?['body/value'])?['cr_responsecount']),
        1
    )
)}
```

> **Edge case**: If `cr_avgresponsehours` is null (first response ever), the running average simplifies to just the current response hours. Handle with: `if(empty(first(outputs('List_rows_Find_sender_profile')?['body/value'])?['cr_avgresponsehours']), outputs('Compose_RESPONSE_HOURS'), <running average expression>)`

### Flow Diagram

```
Trigger (cr_cardoutcome changed, non-PENDING)
  │
  ├── 1. Get modified card row
  ├── 2. Is outcome SENT_AS_IS or SENT_EDITED?
  │   └── No → Terminate (no profile update)
  │
  ├── 3. Calculate response hours
  ├── 4. Find sender profile by email + owner
  ├── 5. Sender profile exists?
  │   └── No → Log warning → Terminate
  │
  └── 6. Update sender profile
      ├── Increment response count
      └── Recalculate average response hours
```

### Deployment Checklist

- [ ] Flow trigger uses `filteringattributes = cr_cardoutcome` (verified in flow definition JSON)
- [ ] Test: Send a card → Verify sender profile `cr_responsecount` incremented by 1
- [ ] Test: Dismiss a card → Verify sender profile NOT updated
- [ ] Test: Send two cards from same sender → Verify running average calculation
- [ ] Test: Sender profile missing → Flow logs warning, does not error
- [ ] Verify flow does not re-trigger itself (no infinite loop)

