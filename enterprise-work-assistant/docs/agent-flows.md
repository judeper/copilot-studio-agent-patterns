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

These values match the definitions in `schemas/dataverse-table.json` and the provisioning script. See step 7 above for copy-pasteable expressions.

*Last verified: Feb 2026*
