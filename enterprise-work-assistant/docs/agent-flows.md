# Agent Flows — Step-by-Step Build Guide

This guide walks through building the three Power Automate agent flows that feed the Enterprise Work Assistant. Each flow intercepts a specific signal type, invokes the Copilot Studio agent, and writes results to the Dataverse `Assistant Cards` table.

## Prerequisites

- Enterprise Work Assistant agent configured in Copilot Studio with JSON output mode enabled (see [deployment-guide.md](deployment-guide.md), Phase 2)
- `Assistant Cards` Dataverse table provisioned (run `scripts/provision-environment.ps1`)
- Connections created for: Office 365 Outlook, Microsoft Teams, Office 365 Users, Microsoft Graph, SharePoint

> **Note on connections vs. connection references**: For initial development, you only need standard *connections* (authenticated links to connectors). If you later package these flows into a solution for deployment across environments, you will need *connection references* (solution-aware pointers to connections). See [Microsoft Learn: Connection references](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/create-connection-reference) for details.

---

## Flow 1 — EMAIL Trigger

### Trigger

**When a new email arrives (V3)** — Office 365 Outlook connector

| Setting | Value |
|---------|-------|
| Folder | Inbox |
| Include Attachments | No |
| Split On | Enabled (each email gets its own flow run) |
| Pre-filter (Subject Filter) | Exclude known no-reply patterns if needed |

### Actions

**1. Compose — PAYLOAD**

```json
{
  "from": "@{triggerOutputs()?['body/from']}",
  "to": "@{triggerOutputs()?['body/toRecipients']}",
  "cc": "@{triggerOutputs()?['body/ccRecipients']}",
  "subject": "@{triggerOutputs()?['body/subject']}",
  "body": "@{triggerOutputs()?['body/body']}",
  "bodyPreview": "@{triggerOutputs()?['body/bodyPreview']}",
  "receivedDateTime": "@{triggerOutputs()?['body/receivedDateTime']}",
  "importance": "@{triggerOutputs()?['body/importance']}",
  "hasAttachments": "@{triggerOutputs()?['body/hasAttachments']}",
  "conversationId": "@{triggerOutputs()?['body/conversationId']}",
  "internetMessageId": "@{triggerOutputs()?['body/internetMessageId']}"
}
```

**2. Get my profile (V2)** — Office 365 Users connector

**3. Compose — USER_CONTEXT**

```json
{
  "displayName": "@{outputs('Get_my_profile_(V2)')?['body/displayName']}",
  "jobTitle": "@{outputs('Get_my_profile_(V2)')?['body/jobTitle']}",
  "department": "@{outputs('Get_my_profile_(V2)')?['body/department']}"
}
```

**4. Invoke the agent**

Add the **Copilot Studio** connector (search for "Copilot" in the connector list). Select the **"Run a prompt"** action (in some environments this appears as **"Invoke a Copilot Agent"** — the exact label may vary by platform version). Choose the **Enterprise Work Assistant** agent.

> **Important**: After adding the action, check the *dynamic content picker* to confirm the correct output field name for the agent's response. It is typically `text` or `responsemessage` depending on the connector version.

| Input Variable | Value |
|---------------|-------|
| TRIGGER_TYPE | `EMAIL` |
| PAYLOAD | `@{outputs('Compose_PAYLOAD')}` |
| USER_CONTEXT | `@{outputs('Compose_USER_CONTEXT')}` |
| CURRENT_DATETIME | `@{utcNow()}` |

**5. Parse JSON** — Parse the agent's response

Use the schema from `schemas/output-schema.json`. Add a **Parse JSON** action and paste the schema into the schema field.

**6. Condition — Check triage tier**

```
@not(equals(body('Parse_JSON')?['triage_tier'], 'SKIP'))
```

**If Yes (not SKIP):**

**7. Add a new row** — Dataverse connector → Assistant Cards table

For Choice columns, you must map the agent's string output to the integer option value. Use a **Compose** action with an `if()` expression chain for each Choice column. Here is an example for Trigger Type:

```
if(
  equals(body('Parse_JSON')?['trigger_type'], 'EMAIL'),
  100000000,
  if(
    equals(body('Parse_JSON')?['trigger_type'], 'TEAMS_MESSAGE'),
    100000001,
    100000002
  )
)
```

Repeat this pattern for Priority, Card Status, Triage Tier, and Temporal Horizon using the values from the Choice Value Mapping table at the bottom of this document.

| Column | Value |
|--------|-------|
| Item Summary | `@{body('Parse_JSON')?['item_summary']}` |
| Triage Tier | Choice value from Compose (see mapping table) |
| Trigger Type | Choice value from Compose (see mapping table) |
| Priority | Choice value from Compose (see mapping table) |
| Card Status | Choice value from Compose (see mapping table) |
| Temporal Horizon | Choice value from Compose (see mapping table) |
| Confidence Score | `@{body('Parse_JSON')?['confidence_score']}` |
| Full JSON Output | `@{body('Invoke_agent')?['text']}` (raw agent response — verify field name in dynamic content) |

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

Add another Copilot Studio "Run a prompt" action. Select the **Humanizer Agent**. Pass `draft_payload` from the parsed response as the input.

**10. Update a row** — Dataverse connector → Assistant Cards table

| Column | Value |
|--------|-------|
| Row ID | ID from step 7 |
| Humanized Draft | Response from step 9 |

---

## Flow 2 — TEAMS_MESSAGE Trigger

### Trigger

**When a new channel message is added** or **When someone is mentioned** — Microsoft Teams connector

| Setting | Value |
|---------|-------|
| Team | Select the relevant team |
| Channel | Select the channel (or "Any") |

### Actions

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

**2-10.** Same pattern as Flow 1 — Get user profile, compose USER_CONTEXT, invoke agent, parse JSON, conditional Dataverse write, conditional humanizer handoff.

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

**3. Compose — USER_CONTEXT** (same as Flow 1)

**4. Apply to each** — Loop over events from step 1

**4a. Condition — Pre-filter**

Skip events matching low-value patterns:

```
@not(
  or(
    contains(items('Apply_to_each')?['subject'], 'Focus Time'),
    contains(items('Apply_to_each')?['subject'], 'Lunch'),
    contains(items('Apply_to_each')?['subject'], 'OOF'),
    contains(items('Apply_to_each')?['subject'], 'Hold'),
    contains(items('Apply_to_each')?['subject'], 'Holiday')
  )
)
```

**If Yes (not filtered out):**

**4b. Compose — PAYLOAD**

```json
{
  "subject": "@{items('Apply_to_each')?['subject']}",
  "body": "@{items('Apply_to_each')?['body/content']}",
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

**4d. Parse JSON + Conditional Dataverse write** (same pattern as Flow 1 steps 5-7)

Note: Calendar items do NOT go through the Humanizer Agent. The `draft_payload` for CALENDAR_SCAN is a plain-text meeting briefing used as-is.

**4e. Delay** — 2 seconds

Rate limiting between iterations to avoid connector throttling.

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

These values match the definitions in `schemas/dataverse-table.json` and the provisioning script.
