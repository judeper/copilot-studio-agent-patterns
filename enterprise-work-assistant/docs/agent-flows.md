# Agent Flows — Step-by-Step Build Guide

This guide walks through building the nine Power Automate flows that drive the Enterprise Work Assistant. The first three flows intercept signal types (email, Teams, calendar), invoke the Copilot Studio agent, and write results to the Dataverse `Assistant Cards` table. Flows 4-9 handle email sending, outcome tracking, daily briefings, staleness monitoring, command execution, and sender analytics.

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
| Trigger Type | EMAIL → 100000000, TEAMS_MESSAGE → 100000001, CALENDAR_SCAN → 100000002, DAILY_BRIEFING → 100000003, SELF_REMINDER → 100000004, COMMAND_RESULT → 100000005 |
| Priority | High → 100000000, Medium → 100000001, Low → 100000002, N/A → 100000003 |
| Card Status | READY → 100000000, LOW_CONFIDENCE → 100000001, SUMMARY_ONLY → 100000002, NO_OUTPUT → 100000003, NUDGE → 100000004 |
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
| Select columns | `cr_cardoutcome,cr_outcometimestamp,cr_originalsenderemail,cr_originalsenderdisplay,cr_humanizeddraft,createdon,_ownerid_value` |

**2. Switch — Route by outcome type**

Route to the appropriate branch based on the outcome value. Three branches handle different sender profile update logic:

**Branch A: SENT_AS_IS or SENT_EDITED** (response tracking)

```
@or(
    equals(outputs('Get_the_modified_card_row')?['body/cr_cardoutcome'], 100000001),
    equals(outputs('Get_the_modified_card_row')?['body/cr_cardoutcome'], 100000002)
)
```

**Branch B: DISMISSED** (dismiss tracking — Sprint 4)

```
@equals(outputs('Get_the_modified_card_row')?['body/cr_cardoutcome'], 100000003)
```

**Branch C: EXPIRED** — Terminate. No sender profile update needed for expired cards.

---

#### Branch B: DISMISSED — Increment dismiss count

When a user dismisses a card, the sender's dismiss count must be incremented. This data feeds the Sender Profile Analyzer (Flow 9), which computes `dismiss_rate` to auto-categorize senders. Without this branch, `cr_dismisscount` never increments and `dismiss_rate` is always 0, meaning AUTO_LOW categorization never triggers.

**2b-1. List rows — Find sender profile by email + owner**

| Setting | Value |
|---------|-------|
| Table name | Sender Profiles |
| Filter rows | `cr_senderemail eq '@{outputs('Get_the_modified_card_row')?['body/cr_originalsenderemail']}' and _ownerid_value eq '@{outputs('Get_the_modified_card_row')?['body/_ownerid_value']}'` |
| Row count | `1` |
| Select columns | `cr_senderprofileid,cr_dismisscount` |

**2b-2. Condition — Sender profile exists**

```
@greater(length(outputs('List_rows_dismissed')?['body/value']), 0)
```

**If No:** Log a warning and terminate. The sender profile should exist from the trigger flow's upsert (Flow 1/2/3 step 11).

**If Yes:**

**2b-3. Update a row — Increment dismiss count** — Dataverse → Sender Profiles

| Column | Value |
|--------|-------|
| Row ID | `@{first(outputs('List_rows_dismissed')?['body/value'])?['cr_senderprofileid']}` |
| Dismiss Count | `@{add(first(outputs('List_rows_dismissed')?['body/value'])?['cr_dismisscount'], 1)}` |

> Do NOT update response hours or response count for dismissals. Only `cr_dismisscount` is incremented.

---

#### Branch A: SENT_AS_IS or SENT_EDITED — Response tracking + edit distance

**2a-1. Condition — Is this SENT_EDITED?**

```
@equals(outputs('Get_the_modified_card_row')?['body/cr_cardoutcome'], 100000002)
```

**If Yes (SENT_EDITED):**

**2a-1a. Compose — EDIT_DISTANCE**

Compute whether the user edited the draft before sending. A full Levenshtein distance is complex in Power Automate expressions, so for MVP we use a simplified boolean comparison: if the final sent text differs from the humanized draft, mark as edited with a normalized distance of 1.0; if identical, distance is 0.0:

```
@{if(
    equals(
        outputs('Get_the_modified_card_row')?['body/cr_humanizeddraft'],
        triggerOutputs()?['body/cr_humanizeddraft']
    ),
    0,
    1
)}
```

> **Note**: For a more granular edit distance, a custom connector or Azure Function could compute the actual Levenshtein distance. The simplified 0/1 approach is acceptable for MVP — it still provides signal for "how often does this user edit drafts" analysis.

**2a-1b. Compose — NEW_AVG_EDIT_DISTANCE**

Uses the running average formula: `new_avg = ((old_avg * old_count) + new_distance) / (old_count + 1)`

```
@{if(
    empty(first(outputs('List_rows_Find_sender_profile')?['body/value'])?['cr_avgeditdistance']),
    outputs('Compose_EDIT_DISTANCE'),
    div(
        add(
            mul(
                float(first(outputs('List_rows_Find_sender_profile')?['body/value'])?['cr_avgeditdistance']),
                float(first(outputs('List_rows_Find_sender_profile')?['body/value'])?['cr_responsecount'])
            ),
            float(outputs('Compose_EDIT_DISTANCE'))
        ),
        add(
            float(first(outputs('List_rows_Find_sender_profile')?['body/value'])?['cr_responsecount']),
            1
        )
    )
)}
```

> The edit distance average is stored in `cr_avgeditdistance` on the SenderProfile table. For the simplified 0/1 approach, this effectively tracks the percentage of responses that were edited.

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
| Select columns | `cr_senderprofileid,cr_responsecount,cr_avgresponsehours,cr_dismisscount,cr_avgeditdistance` |

> **Note**: The filter includes the owner ID to ensure we update the correct user's sender profile (since Sender Profiles are UserOwned, the same sender email can appear once per user). The select includes `cr_dismisscount` and `cr_avgeditdistance` for the DISMISSED and SENT_EDITED branches respectively.

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
| Average Edit Distance | `@{outputs('Compose_NEW_AVG_EDIT_DISTANCE')}` *(only for SENT_EDITED outcomes; omit for SENT_AS_IS)* |

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
  ├── 1. Get modified card row (incl. cr_humanizeddraft)
  ├── 2. Switch on outcome type:
  │   │
  │   ├── Branch A: SENT_AS_IS or SENT_EDITED
  │   │   ├── 2a-1. Is SENT_EDITED?
  │   │   │   └── Yes → Compute edit distance + running avg
  │   │   ├── 3. Calculate response hours
  │   │   ├── 4. Find sender profile by email + owner
  │   │   ├── 5. Sender profile exists?
  │   │   │   └── No → Log warning → Terminate
  │   │   └── 6. Update sender profile
  │   │       ├── Increment response count
  │   │       ├── Recalculate avg response hours
  │   │       └── Update avg edit distance (SENT_EDITED only)
  │   │
  │   ├── Branch B: DISMISSED
  │   │   ├── 2b-1. Find sender profile by email + owner
  │   │   ├── 2b-2. Sender profile exists?
  │   │   │   └── No → Log warning → Terminate
  │   │   └── 2b-3. Increment cr_dismisscount
  │   │
  │   └── Branch C: EXPIRED → Terminate (no profile update)
```

### Deployment Checklist

- [ ] Flow trigger uses `filteringattributes = cr_cardoutcome` (verified in flow definition JSON)
- [ ] Test: Send a card as-is → Verify `cr_responsecount` incremented by 1
- [ ] Test: Send a card with edits → Verify `cr_responsecount` incremented AND `cr_avgeditdistance` updated
- [ ] Test: Dismiss a card → Verify `cr_dismisscount` incremented by 1 (not response count)
- [ ] Test: Expire a card → Verify NO sender profile update occurs
- [ ] Test: Send two cards from same sender → Verify running average calculation
- [ ] Test: Sender profile missing → Flow logs warning, does not error
- [ ] Verify flow does not re-trigger itself (no infinite loop)

---

## Flow 6 — Daily Briefing *(Sprint 2)*

### Overview

Runs every weekday morning. Gathers open cards, stale items, today's calendar, and sender profiles, then invokes the Daily Briefing Agent to produce a prioritized action plan. Writes the briefing as a special DAILY_BRIEFING card to Dataverse.

### Trigger

**Recurrence** — Schedule connector

| Setting | Value |
|---------|-------|
| Frequency | Week |
| Interval | 1 |
| Days | Monday, Tuesday, Wednesday, Thursday, Friday |
| At These Hours | 7 |
| At These Minutes | 0 |
| Time Zone | Select appropriate timezone for the user |

### Actions

**1. Get my profile (V2)** — Office 365 Users connector

Get the current user's AAD profile for ownership and identity.

**2. List open cards** — Dataverse connector

| Setting | Value |
|---------|-------|
| Table name | Assistant Cards |
| Filter rows | `cr_cardoutcome eq 100000000 and _ownerid_value eq '@{outputs('Get_my_profile_(V2)')?['body/id']}'` |
| Sort by | `createdon desc` |
| Row count | `50` |
| Select columns | `cr_assistantcardid,cr_fulljson,cr_humanizeddraft,cr_cardoutcome,cr_originalsenderemail,cr_originalsenderdisplay,cr_originalsubject,cr_conversationclusterid,cr_sourcesignalid,createdon,cr_triggertype,cr_priority,cr_cardstatus,cr_triagetier,cr_confidencescore` |

**3. Condition — Token budget guard** *(Council Issue 12)*

Serialize the open cards array and check length. If the serialized string exceeds ~40,000 characters (~10K tokens), truncate to the first N cards that fit:

```
@if(
    greater(length(string(outputs('List_open_cards')?['body/value'])), 40000),
    take(outputs('List_open_cards')?['body/value'], 30),
    outputs('List_open_cards')?['body/value']
)
```

> **Design note**: The 40,000 character threshold is conservative — it leaves room for the calendar events, sender profiles, and the agent's own reasoning within the context window. Monitor actual token usage in Copilot Studio analytics and adjust.

**4. List stale cards** — Dataverse connector

| Setting | Value |
|---------|-------|
| Table name | Assistant Cards |
| Filter rows | `cr_cardoutcome eq 100000000 and _ownerid_value eq '@{outputs('Get_my_profile_(V2)')?['body/id']}' and createdon lt @{addHours(utcNow(), -24)} and cr_priority ne 100000003` |
| Sort by | `createdon asc` |
| Row count | `20` |
| Select columns | `cr_assistantcardid,cr_itemsummary,cr_originalsenderdisplay,cr_priority,createdon` |

> The `cr_priority ne 100000003` filter excludes N/A priority items (Choice value 100000003), which are typically informational and don't become "stale."

**5. Get today's calendar** — Office 365 Outlook connector → Get events (V4)

| Setting | Value |
|---------|-------|
| Calendar ID | Default calendar |
| Start DateTime | `@{startOfDay(utcNow())}` |
| End DateTime | `@{addDays(startOfDay(utcNow()), 1)}` |
| Order By | start/dateTime asc |
| Top | 20 |

**6. List sender profiles** — Dataverse connector

| Setting | Value |
|---------|-------|
| Table name | Sender Profiles |
| Filter rows | `_ownerid_value eq '@{outputs('Get_my_profile_(V2)')?['body/id']}'` |
| Row count | `100` |
| Select columns | `cr_senderemail,cr_senderdisplayname,cr_signalcount,cr_responsecount,cr_avgresponsehours,cr_sendercategory` |

> This loads all sender profiles for the user. The briefing agent uses these to assess sender importance when ranking items. For users with >100 senders, consider filtering to senders appearing in the open_cards list.

**7. Compose — BRIEFING_INPUT**

Assemble the input JSON for the Daily Briefing Agent:

```json
{
    "open_cards": @{outputs('Condition_Token_budget_guard')},
    "stale_cards": @{outputs('List_stale_cards')?['body/value']},
    "today_calendar": @{outputs('Get_todays_calendar')?['body/value']},
    "sender_profiles": @{outputs('List_sender_profiles')?['body/value']},
    "user_context": "@{outputs('Get_my_profile_(V2)')?['body/displayName']}, @{outputs('Get_my_profile_(V2)')?['body/jobTitle']}, @{outputs('Get_my_profile_(V2)')?['body/department']}",
    "current_datetime": "@{utcNow()}"
}
```

**8. Invoke Daily Briefing Agent** — Microsoft Copilot Studio → "Execute Agent and wait"

Select the **Daily Briefing Agent**. Pass the serialized input:

```
@{string(outputs('Compose_BRIEFING_INPUT'))}
```

**9. Parse JSON** — Simplified briefing output schema

Use a flattened schema (no `oneOf`) matching the briefing output contract in `schemas/briefing-output-schema.json`. For the Parse JSON action, use:

```json
{
    "type": "object",
    "properties": {
        "briefing_type": { "type": "string" },
        "briefing_date": { "type": "string" },
        "total_open_items": { "type": "integer" },
        "day_shape": { "type": "string" },
        "action_items": { "type": "array" },
        "fyi_items": { "type": "array" },
        "stale_alerts": { "type": "array" }
    }
}
```

**10. Condition — Briefing generated successfully**

```
@not(empty(body('Parse_JSON')?['day_shape']))
```

**If Yes:**

**10a. Compose — OUTPUT_ENVELOPE** *(I-15 fix: wrap briefing in standard output-schema.json envelope)*

The Daily Briefing Agent returns a briefing-specific JSON structure (`briefing_type`, `day_shape`, `action_items`, etc.) that does NOT conform to the standard `output-schema.json` envelope. The PCF component's `BriefingCard.tsx` calls `parseBriefing()`, which reads from `card.draft_payload` to extract the briefing data. Without envelope wrapping, `draft_payload` would be `null` and `parseBriefing()` would fail.

Wrap the raw briefing response in the standard output envelope:

```json
{
    "trigger_type": "DAILY_BRIEFING",
    "triage_tier": "FULL",
    "item_summary": "@{body('Parse_JSON')?['day_shape']}",
    "card_status": "READY",
    "priority": "N/A",
    "temporal_horizon": "N/A",
    "confidence_score": 100,
    "draft_payload": "@{string(body('Parse_JSON'))}",
    "triage_reasoning": "Daily briefing generated automatically",
    "research_log": null,
    "key_findings": null,
    "verified_sources": [],
    "low_confidence_note": null
}
```

> **CRITICAL**: The `draft_payload` field contains the stringified briefing JSON. This is what `BriefingCard.tsx` parses via `JSON.parse(card.draft_payload)` to access `briefing_type`, `day_shape`, `action_items`, `fyi_items`, and `stale_alerts`. Without this envelope wrapping, the briefing card will fail to render because it cannot find `draft_payload` on the card record.

**11. Add a new row** — Dataverse → Assistant Cards

| Column | Value |
|--------|-------|
| Trigger Type | `100000003` *(DAILY_BRIEFING)* |
| Triage Tier | `100000002` *(FULL)* |
| Item Summary | `@{body('Parse_JSON')?['day_shape']}` |
| Priority | `100000003` *(N/A)* |
| Temporal Horizon | `100000004` *(N/A)* |
| Card Status | `100000000` *(READY)* |
| Confidence Score | `100` |
| Full JSON | `@{string(outputs('Compose_OUTPUT_ENVELOPE'))}` |
| Card Outcome | `100000000` *(PENDING)* |
| **Owner** | `@{outputs('Get_my_profile_(V2)')?['body/id']}` |

> **Key change from earlier version**: `cr_fulljson` now stores the **envelope-wrapped** output, not the raw briefing JSON. This ensures `cr_fulljson` conforms to `output-schema.json` like all other card types. The `draft_payload` field inside the envelope contains the raw briefing JSON that `BriefingCard.tsx` parses. Priority and Temporal Horizon are set to N/A (matching the envelope values) instead of being left null.

**If No:** Terminate — agent failed to produce valid output. Check Copilot Studio error logs.

### Deduplication

The briefing flow runs daily. To prevent duplicate briefings:

Add a pre-check at the start of the flow (between steps 1 and 2):

**1a. List existing briefings today** — Dataverse

| Setting | Value |
|---------|-------|
| Table name | Assistant Cards |
| Filter rows | `cr_triggertype eq 100000003 and _ownerid_value eq '@{outputs('Get_my_profile_(V2)')?['body/id']}' and createdon ge @{startOfDay(utcNow())}` |
| Row count | `1` |

**1b. Condition — Briefing already exists today**

```
@greater(length(outputs('List_existing_briefings_today')?['body/value']), 0)
```

**If Yes:** Terminate — a briefing was already generated today (idempotent).

### Flow Diagram

```
Trigger (Recurrence — weekday 7 AM)
  │
  ├── 1. Get user profile
  ├── 1a. Check for existing briefing today
  │   └── Already exists? → Terminate
  │
  ├── 2. List open cards (top 50 PENDING)
  ├── 3. Token budget guard (truncate if >40K chars)
  ├── 4. List stale cards (>24h, non-N/A priority)
  ├── 5. Get today's calendar events
  ├── 6. List sender profiles
  ├── 7. Compose BRIEFING_INPUT
  ├── 8. Invoke Daily Briefing Agent
  ├── 9. Parse JSON response
  ├── 10. Valid briefing?
  │   └── No → Terminate
  ├── 10a. Wrap in output envelope (draft_payload = briefing JSON)
  └── 11. Write envelope-wrapped card to Dataverse
```

### Deployment Checklist

- [ ] Daily Briefing Agent created and published in Copilot Studio
- [ ] Flow trigger set to correct timezone for the user
- [ ] Token budget threshold set (default 40,000 characters)
- [ ] Test: Run manually → briefing card appears in dashboard with BriefingCard renderer
- [ ] Test: Run twice on same day → second run terminates (deduplication)
- [ ] Test: Empty inbox → briefing card shows "Your inbox is clear" message
- [ ] Test: Cards with stale_alerts → amber/red indicators render correctly
- [ ] Test: Verify `cr_fulljson` contains output envelope with `draft_payload` field (I-15)
- [ ] Test: BriefingCard.tsx `parseBriefing()` successfully parses `card.draft_payload`

---

## Flow 7 — Staleness Monitor *(Sprint 2)*

### Overview

Runs every 4 hours on weekdays. Performs two tasks:
1. Creates "nudge" cards for high-priority items that have gone >24 hours without action
2. Expires cards that have been PENDING for >7 days

### Trigger

**Recurrence** — Schedule connector

| Setting | Value |
|---------|-------|
| Frequency | Week |
| Interval | 1 |
| Days | Monday, Tuesday, Wednesday, Thursday, Friday |
| At These Hours | 8, 12, 16, 20 |
| At These Minutes | 0 |
| Time Zone | Select appropriate timezone for the user |

### Actions

**1. Get my profile (V2)** — Office 365 Users connector

**Scope: Create Nudge Cards**

**2. List overdue high-priority cards** — Dataverse

| Setting | Value |
|---------|-------|
| Table name | Assistant Cards |
| Filter rows | `cr_cardoutcome eq 100000000 and cr_priority eq 100000000 and _ownerid_value eq '@{outputs('Get_my_profile_(V2)')?['body/id']}' and createdon lt @{addHours(utcNow(), -24)} and cr_triggertype ne 100000003` |
| Row count | `10` |
| Select columns | `cr_assistantcardid,cr_itemsummary,cr_sourcesignalid,cr_originalsenderdisplay,createdon` |

> Filters: PENDING + High priority + older than 24 hours + not a briefing card itself.

**3. Apply to each** — Loop over overdue cards

**3a. List existing nudges for this card** — Dataverse

| Setting | Value |
|---------|-------|
| Table name | Assistant Cards |
| Filter rows | `cr_sourcesignalid eq 'NUDGE:@{items('Apply_to_each')?['cr_assistantcardid']}' and _ownerid_value eq '@{outputs('Get_my_profile_(V2)')?['body/id']}'` |
| Row count | `1` |

> Uses a synthetic `cr_sourcesignalid` prefixed with `NUDGE:` + the original card's ID. This prevents duplicate nudge cards for the same overdue item.

**3b. Condition — Nudge already exists**

```
@equals(length(outputs('List_existing_nudges')?['body/value']), 0)
```

**If Yes (no existing nudge):**

**3c. Calculate hours pending**

```
@{div(div(sub(ticks(utcNow()), ticks(items('Apply_to_each')?['createdon'])), 10000000), 3600)}
```

**3d. Add a new row** — Dataverse → Assistant Cards (create nudge card)

| Column | Value |
|--------|-------|
| Trigger Type | `@{items('Apply_to_each')?['cr_triggertype']}` *(same as original)* |
| Triage Tier | `100000001` *(LIGHT)* |
| Item Summary | `Reminder: @{items('Apply_to_each')?['cr_itemsummary']} — @{int(outputs('Compose_HOURS_PENDING'))} hours without action` |
| Priority | `100000000` *(High)* |
| Card Status | `100000004` *(NUDGE)* |
| Confidence Score | `100` |
| Card Outcome | `100000000` *(PENDING)* |
| Source Signal ID | `NUDGE:@{items('Apply_to_each')?['cr_assistantcardid']}` |
| Original Sender Display | `@{items('Apply_to_each')?['cr_originalsenderdisplay']}` |
| **Owner** | `@{outputs('Get_my_profile_(V2)')?['body/id']}` |

> **IMPORTANT — NUDGE via discrete column (I-02 fix)**: The `cr_cardstatus` column is set to `100000004` (NUDGE) directly on the **new nudge card row** as a discrete Dataverse Choice column. This is NOT stored inside `cr_fulljson` — the agent never produces NUDGE status because nudges are system-managed, not agent-generated. The PCF component's `useCardData.ts` must read `card_status` from the discrete `cr_cardstatus` column (not from parsed JSON) to correctly detect NUDGE cards. This is the key integration contract between this flow and the frontend (F-01 fix in Wave 3).

**3e. Update original card status** — Dataverse → Assistant Cards

Additionally, update the **original card's** discrete `cr_cardstatus` column to NUDGE so the frontend can show a visual indicator on the original card:

| Column | Value |
|--------|-------|
| Row ID | `@{items('Apply_to_each')?['cr_assistantcardid']}` |
| Card Status | `100000004` *(NUDGE)* |

> This discrete column update on the original card is what makes NUDGE status reachable in the UI for the original card. The `useCardData.ts` hook reads `cr_cardstatus` directly from the Dataverse record, not from the JSON blob. Without this step, only the nudge card itself would have NUDGE status, but the original overdue card would still show READY.

**Scope: Expire Abandoned Cards**

**4. List abandoned cards** — Dataverse

| Setting | Value |
|---------|-------|
| Table name | Assistant Cards |
| Filter rows | `cr_cardoutcome eq 100000000 and _ownerid_value eq '@{outputs('Get_my_profile_(V2)')?['body/id']}' and createdon lt @{addDays(utcNow(), -7)} and cr_triggertype ne 100000003` |
| Row count | `50` |
| Select columns | `cr_assistantcardid` |

> Cards that have been PENDING for >7 days with no user action.

**5. Apply to each** — Loop over abandoned cards

**5a. Update a row** — Dataverse → Assistant Cards

| Column | Value |
|--------|-------|
| Row ID | `@{items('Apply_to_each_expired')?['cr_assistantcardid']}` |
| Card Outcome | `100000004` *(EXPIRED)* |
| Card Status | `100000004` *(EXPIRED)* |
| Outcome Timestamp | `@{utcNow()}` |

> **Note**: Both `cr_cardoutcome` and `cr_cardstatus` are set to EXPIRED (100000004). Setting `cr_cardstatus` via the discrete column ensures the frontend reads the correct status without parsing `cr_fulljson`. The `cr_cardoutcome` update triggers the Card Outcome Tracker flow (Flow 5), which will see EXPIRED and terminate without updating sender profiles (Branch C) — by design. This resolves I-03 (EXPIRED writer) by documenting who sets the EXPIRED status and through which columns.

### Error Handling

Both scopes (nudge and expire) should be configured with "Run after: has failed" parallel branches that log errors but do NOT halt the flow. A failure to create one nudge should not prevent other nudges or the expiration process.

### Flow Diagram

```
Trigger (Recurrence — weekday every 4h)
  │
  ├── 1. Get user profile
  │
  ├── Scope: Create Nudge Cards
  │   ├── 2. List overdue High-priority cards (>24h PENDING)
  │   └── 3. For each overdue card:
  │       ├── 3a. Check for existing nudge
  │       ├── 3b. Nudge exists? → Skip
  │       ├── 3c. Calculate hours pending
  │       ├── 3d. Create nudge card (cr_cardstatus = NUDGE via discrete column)
  │       └── 3e. Update original card cr_cardstatus = NUDGE
  │
  └── Scope: Expire Abandoned Cards
      ├── 4. List abandoned cards (>7 days PENDING)
      └── 5. For each: set cr_cardoutcome + cr_cardstatus = EXPIRED
```

### Deployment Checklist

- [ ] Flow trigger set to correct timezone
- [ ] Test: Create a High-priority card, wait 24+ hours → nudge card appears with cr_cardstatus = NUDGE
- [ ] Test: Original overdue card also has cr_cardstatus = NUDGE (discrete column, not JSON)
- [ ] Test: Run again → no duplicate nudge created (dedup by source_signal_id)
- [ ] Test: Create a card, wait 7+ days → card expires with BOTH cr_cardoutcome AND cr_cardstatus = EXPIRED
- [ ] Test: Expired card disappears from dashboard (Canvas app filter excludes EXPIRED)
- [ ] Test: Nudge card for dismissed original → nudge still appears (dismissing the original does not auto-dismiss the nudge; user must dismiss separately)
- [ ] Test: useCardData.ts reads cr_cardstatus directly (not from cr_fulljson) for NUDGE detection



---

## Flow 8 — Command Execution *(Sprint 3)*

### Overview

Instant flow triggered from the Canvas app when the user submits a command in the command bar. Passes the command to the Orchestrator Agent and returns the response synchronously.

### Trigger

**Instant — manually triggered** (PowerAutomate.Run() from Canvas app)

**Input parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| commandText | Text | The user's natural language command |
| userId | Text | AAD user ID (from Canvas app User().EntraObjectId) |
| currentCardId | Text | ID of the currently expanded card, or empty string |

### Actions

**1. Get user profile** — Office 365 Users → Get user profile (V2)

Use the `userId` input to look up the user's display name, job title, department.

**2. Condition — Has current card context**

```
@not(empty(triggerBody()?['currentCardId']))
```

**If Yes:**

**2a. Get current card** — Dataverse → Get a row by ID

| Setting | Value |
|---------|-------|
| Table name | Assistant Cards |
| Row ID | `@{triggerBody()?['currentCardId']}` |
| Select columns | `cr_fulljson,cr_humanizeddraft,cr_itemsummary,cr_originalsenderemail,cr_originalsenderdisplay,cr_conversationclusterid` |

**3. Get recent briefing** — Dataverse → List rows

| Setting | Value |
|---------|-------|
| Table name | Assistant Cards |
| Filter rows | `cr_triggertype eq 100000003 and _ownerid_value eq '@{triggerBody()?['userId']}' and createdon ge @{startOfDay(utcNow())}` |
| Sort by | `createdon desc` |
| Row count | `1` |
| Select columns | `cr_itemsummary` |

**4. Compose — ORCHESTRATOR_INPUT**

```json
{
    "COMMAND_TEXT": "@{triggerBody()?['commandText']}",
    "USER_CONTEXT": "@{outputs('Get_user_profile')?['body/displayName']}, @{outputs('Get_user_profile')?['body/jobTitle']}, @{outputs('Get_user_profile')?['body/department']}",
    "CURRENT_CARD_JSON": @{if(empty(triggerBody()?['currentCardId']), 'null', outputs('Get_current_card')?['body/cr_fulljson'])},
    "RECENT_BRIEFING": @{if(empty(outputs('Get_recent_briefing')?['body/value']), 'null', concat('"', first(outputs('Get_recent_briefing')?['body/value'])?['cr_itemsummary'], '"'))},
    "CURRENT_DATETIME": "@{utcNow()}"
}
```

**5. Invoke Orchestrator Agent** — Microsoft Copilot Studio → "Execute Agent and wait"

Select the **Orchestrator Agent**. Pass the serialized input:

```
@{string(outputs('Compose_ORCHESTRATOR_INPUT'))}
```

> **Timeout:** Set the action timeout to 120 seconds. Multi-tool agent reasoning may take 30-60 seconds for complex queries.

**6. Parse JSON** — Parse the Orchestrator response

Schema:

```json
{
    "type": "object",
    "properties": {
        "response_text": { "type": "string" },
        "card_links": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "card_id": { "type": "string" },
                    "label": { "type": "string" }
                }
            }
        },
        "side_effects": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "action": { "type": "string" },
                    "description": { "type": "string" }
                }
            }
        }
    }
}
```

**7. Respond to a PowerApp or flow** — Return the parsed response as JSON

| Output | Value |
|--------|-------|
| responseJson | `@{string(body('Parse_JSON'))}` |

### Error Handling

Wrap steps 4-6 in a **Scope** with "Run after: has failed" parallel branch:

```json
{
    "response_text": "I wasn't able to process that command. Please try again or rephrase your request.",
    "card_links": [],
    "side_effects": []
}
```

### Flow Diagram

```
Trigger (Instant — from Canvas app)
  │
  ├── 1. Get user profile
  ├── 2. Has current card context?
  │   └── Yes → 2a. Get current card from Dataverse
  ├── 3. Get today's briefing (if exists)
  ├── 4. Compose orchestrator input
  ├── 5. Invoke Orchestrator Agent (120s timeout)
  ├── 6. Parse JSON response
  └── 7. Return response to Canvas app
```

### Deployment Checklist

- [ ] Orchestrator Agent created and published in Copilot Studio
- [ ] All 6 tool actions registered (QueryCards, QuerySenderProfile, UpdateCard, CreateCard, RefineDraft, QueryCalendar)
- [ ] Humanizer Agent connected as sub-agent for RefineDraft
- [ ] Flow timeout set to 120 seconds
- [ ] Error handling scope configured with fallback response
- [ ] Test: "What needs my attention?" → Returns ranked cards with links
- [ ] Test: "Remind me to follow up Friday" → Creates SELF_REMINDER card
- [ ] Test: With card expanded, "Make this shorter" → Draft refinement works
- [ ] Test: "How often do I respond to [sender]?" → Returns sender stats
- [ ] Test: Invalid command → Graceful error response

---

## Flow 9 — Sender Profile Analyzer *(Sprint 4)*

### Overview

Runs weekly (Sunday evening). Analyzes card outcome data from the past 30 days to compute sender-level statistics and auto-categorize senders by engagement level. Respects user overrides — senders with `cr_sendercategory = USER_OVERRIDE` are never recategorized.

### Trigger

**Recurrence** — Schedule connector

| Setting | Value |
|---------|-------|
| Frequency | Week |
| Interval | 1 |
| Days | Sunday |
| At These Hours | 20 |
| At These Minutes | 0 |

### Actions

**1. Get my profile (V2)** — Office 365 Users connector

**2. List all sender profiles** — Dataverse

| Setting | Value |
|---------|-------|
| Table name | Sender Profiles |
| Filter rows | `_ownerid_value eq '@{outputs('Get_my_profile_(V2)')?['body/id']}'` |
| Row count | `500` |
| Select columns | `cr_senderprofileid,cr_senderemail,cr_signalcount,cr_responsecount,cr_avgresponsehours,cr_sendercategory,cr_dismisscount` |

**3. Apply to each** — Loop over sender profiles

**3a. Condition — Skip user overrides**

```
@not(equals(items('Apply_to_each')?['cr_sendercategory'], 100000003))
```

> Senders with `USER_OVERRIDE` (100000003) are never recategorized.

**If Yes (not an override):**

**3b. Condition — Minimum signal threshold**

```
@greaterOrEquals(items('Apply_to_each')?['cr_signalcount'], 3)
```

> Senders with fewer than 3 signals don't have enough data for meaningful statistics.

**If Yes (≥ 3 signals):**

**3c. Query card outcomes for this sender (past 30 days)** — Dataverse

| Setting | Value |
|---------|-------|
| Table name | Assistant Cards |
| Filter rows | `cr_originalsenderemail eq '@{items('Apply_to_each')?['cr_senderemail']}' and _ownerid_value eq '@{outputs('Get_my_profile_(V2)')?['body/id']}' and createdon ge @{addDays(utcNow(), -30)} and cr_cardoutcome ne 100000000` |
| Row count | `100` |
| Select columns | `cr_cardoutcome,cr_outcometimestamp,cr_drafteditdistance,createdon` |

**3d. Compose — Calculate stats**

```json
{
    "total_resolved": @{length(outputs('Query_card_outcomes')?['body/value'])},
    "sent_count": @{length(
        filter(
            outputs('Query_card_outcomes')?['body/value'],
            or(
                equals(item()?['cr_cardoutcome'], 100000001),
                equals(item()?['cr_cardoutcome'], 100000002)
            )
        )
    )},
    "dismiss_count": @{length(
        filter(
            outputs('Query_card_outcomes')?['body/value'],
            equals(item()?['cr_cardoutcome'], 100000003)
        )
    )}
}
```

> Choice values: SENT_AS_IS = 100000001, SENT_EDITED = 100000002, DISMISSED = 100000003

**3e. Compose — Response rate and dismiss rate**

```
response_rate = @{if(greater(outputs('Compose_stats')?['total_resolved'], 0), div(float(outputs('Compose_stats')?['sent_count']), float(outputs('Compose_stats')?['total_resolved'])), 0)}

dismiss_rate = @{if(greater(outputs('Compose_stats')?['total_resolved'], 0), div(float(outputs('Compose_stats')?['dismiss_count']), float(outputs('Compose_stats')?['total_resolved'])), 0)}
```

**3f. Compose — Determine category**

Apply the categorization rules:

```
@{if(
    and(
        greaterOrEquals(outputs('Compose_rates')?['response_rate'], 0.8),
        less(items('Apply_to_each')?['cr_avgresponsehours'], 8)
    ),
    100000000,
    if(
        or(
            less(outputs('Compose_rates')?['response_rate'], 0.4),
            greaterOrEquals(outputs('Compose_rates')?['dismiss_rate'], 0.6)
        ),
        100000002,
        100000001
    )
)}
```

> AUTO_HIGH = 100000000, AUTO_MEDIUM = 100000001, AUTO_LOW = 100000002

**3g. Update a row** — Dataverse → Sender Profiles

| Column | Value |
|--------|-------|
| Row ID | `@{items('Apply_to_each')?['cr_senderprofileid']}` |
| Sender Category | `@{outputs('Compose_category')}` |
| Response Rate | `@{outputs('Compose_rates')?['response_rate']}` |
| Dismiss Rate | `@{outputs('Compose_rates')?['dismiss_rate']}` |
| Dismiss Count | `@{outputs('Compose_stats')?['dismiss_count']}` |

### Dependency: Card Outcome Tracker Dismiss Tracking

This flow depends on Flow 5 (Card Outcome Tracker) Branch B (DISMISSED) incrementing `cr_dismisscount` on each sender's profile whenever a card is dismissed. Without this, `dismiss_rate` computed in step 3e is always 0 and AUTO_LOW categorization never triggers. See Flow 5 Branch B for the implementation.

### Updating Existing Trigger Flows for Sender Profile Passthrough

All 3 trigger flows (EMAIL, TEAMS, CALENDAR) need an additional step to look up the sender profile and pass it to the agent:

**Insert between the pre-filter and the agent invocation:**

1. **List sender profile** — Dataverse → Sender Profiles
   - Filter: `cr_senderemail eq '@{...sender_email...}'`
   - Top: 1

2. **Compose SENDER_PROFILE** — Conditional:
   ```
   @{if(
       greater(length(outputs('List_sender_profile')?['body/value']), 0),
       string(first(outputs('List_sender_profile')?['body/value'])),
       'null'
   )}
   ```

3. Pass the serialized JSON (or the string `null`) as the `{{SENDER_PROFILE}}` input variable to the agent.

### Flow Diagram

```
Trigger (Recurrence — Sunday 8 PM)
  │
  ├── 1. Get user profile
  ├── 2. List all sender profiles
  └── 3. For each sender profile:
      ├── Skip if USER_OVERRIDE
      ├── Skip if signal_count < 3
      ├── 3c. Query card outcomes (past 30 days)
      ├── 3d. Calculate sent_count, dismiss_count
      ├── 3e. Compute response_rate, dismiss_rate
      ├── 3f. Determine category (AUTO_HIGH/MEDIUM/LOW)
      └── 3g. Update sender profile row
```

### Deployment Checklist

- [ ] Flow trigger set to Sunday 8 PM (or appropriate off-hours time)
- [ ] Card Outcome Tracker (Flow 5) Branch B verified: DISMISSED increments cr_dismisscount
- [ ] All 3 trigger flows updated with sender profile lookup + passthrough
- [ ] Main agent prompt updated with SENDER_PROFILE input and adaptive rules
- [ ] Test: Sender with >80% response rate and <8h avg → AUTO_HIGH
- [ ] Test: Sender with <40% response rate → AUTO_LOW
- [ ] Test: Sender with USER_OVERRIDE → Not recategorized
- [ ] Test: Sender with <3 signals → Skipped
- [ ] Test: Trigger flow passes sender profile JSON to agent
- [ ] Test: Agent adjusts triage tier based on sender category
