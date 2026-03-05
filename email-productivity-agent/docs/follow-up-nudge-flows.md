# Follow-Up Nudge Flows — Step-by-Step Building Guide

This document provides detailed specifications for building the Power Automate flows that power the Follow-Up Nudge system. Each flow is described with its trigger, actions, expressions, and error handling patterns.

---

## Flow 1: Sent Items Tracker

**Purpose**: Automatically log every sent email to the FollowUpTracking Dataverse table, creating one row per To-line recipient.

### Trigger

| Setting | Value |
|---------|-------|
| Connector | Office 365 Outlook |
| Trigger | When a new email arrives (V3) |
| Folder | Sent Items |
| Include Attachments | No |
| Split On | Enabled (each email = separate flow run) |

### Step 0: Get Full Email Details

```
Action: Office 365 Outlook — Get email (V2)
  Message Id: triggerOutputs()?['body/id']
```

This retrieves the full message with structured properties (`toRecipients` array, `internetMessageHeaders`, `itemClass`) that are not available in the V3 trigger output.

### Pre-Filter Conditions

Add these conditions immediately after the trigger to skip irrelevant emails:

```
Condition 1: Skip auto-replies
  Filter outputs('Get_email_(V2)')?['body/internetMessageHeaders'] where
    item()?['name'] equals 'Auto-Submitted'
  Check: filtered result is empty OR first item's value equals 'no'
  AND subject does not start with 'Automatic reply:'

  Note: internetMessageHeaders is an array of {name, value} pairs,
  NOT a flat object. Use a Filter array action to find headers by name.

Condition 2: Skip calendar responses
  startsWith(outputs('Get_email_(V2)')?['body/itemClass'], 'IPM.Schedule')
  If true → skip (this catches IPM.Schedule.Meeting.* and related classes)

Condition 3: Skip no-reply senders
  outputs('Get_email_(V2)')?['body/toRecipients'] does not contain 'noreply@'
  AND outputs('Get_email_(V2)')?['body/toRecipients'] does not contain 'no-reply@'

Condition 4: Skip self-sends
  For each recipient in outputs('Get_email_(V2)')?['body/toRecipients']:
    recipient?['emailAddress']?['address'] does not equal
    outputs('Get_email_(V2)')?['body/from']?['emailAddress']?['address']
```

### Actions

#### Step 0: Get User Profile

```
Action: Office 365 Users — Get my profile (V2)
Purpose: Retrieves the current user's ID and domain for owner filtering and recipient classification.
```

#### Step 1: Get User's Nudge Configuration

```
Action: Dataverse — List rows
Table: Nudge Configurations (cr_nudgeconfigurations)
Filter: _ownerid_value eq '@{outputs('Get_my_profile_(V2)')?['body/id']}'
Top Count: 1
```

If no configuration exists, create a default row:

```
Action: Dataverse — Add a new row (if config not found)
Table: Nudge Configurations
cr_configlabel: "<User Display Name> Nudge Config"
cr_internaldays: 3
cr_externaldays: 5
cr_prioritydays: 1
cr_generaldays: 7
cr_nudgesenabled: true
cr_owneruserid: "@{outputs('Get_my_profile_(V2)')?['body/id']}"
```

> **Note:** `cr_owneruserid` is required and serves as the alternate key. Without it, the Dataverse create will fail.

> **Note:** Flow 1 always tracks sent emails regardless of the `cr_nudgesenabled` setting. The nudge-enabled check is performed in Flow 2 (Response Detection), so disabling nudges only suppresses notifications — tracking continues and pending nudges will catch up when re-enabled.

#### Step 2: Get User's Tenant Domain

```
Expression: split(outputs('Get_my_profile_(V2)')?['body/mail'], '@')[1]
Store as: variable 'userDomain'

Note: Get_my_profile_(V2) is called in Step 0 above. This step only extracts the domain.
```

#### Step 3: Loop Through To-Line Recipients

```
Action: Apply to each
Input: outputs('Get_email_(V2)')?['body/toRecipients']
```

Inside the loop:

##### Step 3a: Determine Recipient Type

```
Compose: recipientDomain
Expression: split(items('Apply_to_each')?['emailAddress']?['address'], '@')[1]

Condition: Is Internal?
  If recipientDomain equals userDomain → recipientType = "Internal"
  Else → recipientType = "External"

Note: Priority contact detection is a future enhancement.
      For MVP, all non-internal recipients are "External" or "General".
      Use "External" for external domains, "General" as the default fallback.
```

##### Step 3b-pre: Normalize Weekend Start Date

```
Compose: normalizedStartDate
Expression:
  if(
    equals(dayOfWeek(triggerOutputs()?['body/sentDateTime']), 0),
    addDays(triggerOutputs()?['body/sentDateTime'], 1),
    if(
      equals(dayOfWeek(triggerOutputs()?['body/sentDateTime']), 6),
      addDays(triggerOutputs()?['body/sentDateTime'], 2),
      triggerOutputs()?['body/sentDateTime']
    )
  )

(If Sunday, advance 1 day to Monday. If Saturday, advance 2 days to Monday.)
```

##### Step 3b: Calculate Follow-Up Date (Business Days)

```
Compose: followUpDays
Expression (switch on recipientType):
  if(equals(variables('recipientType'), 'Internal'),
     outputs('Get_nudge_config')?['body/cr_internaldays'],
  if(equals(variables('recipientType'), 'External'),
     outputs('Get_nudge_config')?['body/cr_externaldays'],
  if(equals(variables('recipientType'), 'Priority'),
     outputs('Get_nudge_config')?['body/cr_prioritydays'],
     outputs('Get_nudge_config')?['body/cr_generaldays']
  )))

Compose: followUpDate — Business Day Calculation
Expression:
  @{addDays(
    outputs('normalizedStartDate'),
    add(
      outputs('followUpDays'),
      mul(2, div(add(outputs('followUpDays'), sub(dayOfWeek(outputs('normalizedStartDate')), 1)), 5))
    )
  )}

Note: The normalizedStartDate shifts weekend-origin emails to Monday before
applying the business-day formula, preventing off-by-one errors when
dayOfWeek() returns 0 (Sunday) or 6 (Saturday).
This expression adds calendar days equivalent to the requested business
days by accounting for weekends. It adds 2 extra days for every 5 business
days to skip Saturday and Sunday. Holiday exclusion is out of scope for MVP.
```

##### Step 3c: Extract Internet Message Headers

> **Note:** `internetMessageHeaders` is returned as an array of `{name, value}` pairs,
> NOT a flat object. Extracting specific headers requires a Filter array action for each header.

```
Filter array: filterInReplyTo
  From: outputs('Get_email_(V2)')?['body/internetMessageHeaders']
  Where: item()?['name'] equals 'In-Reply-To'

Filter array: filterReferences
  From: outputs('Get_email_(V2)')?['body/internetMessageHeaders']
  Where: item()?['name'] equals 'References'

Compose: messageHeaders
Expression:
  concat(
    'In-Reply-To: ', if(greater(length(body('filterInReplyTo')), 0), first(body('filterInReplyTo'))?['value'], ''),
    '\nReferences: ', if(greater(length(body('filterReferences')), 0), first(body('filterReferences'))?['value'], ''),
    '\nMessage-ID: ', coalesce(triggerOutputs()?['body/internetMessageId'], '')
  )
```

##### Step 3d: Upsert to FollowUpTracking

```
Action: Dataverse — Perform an unbound action (Upsert)
  OR use HTTP with Azure AD connector:

  PATCH {OrgUrl}/api/data/v9.2/cr_followuptrackings(
    cr_sourcesignalid='@{encodeURIComponent(triggerOutputs()?['body/internetMessageId'])}',
    cr_recipientemail='@{encodeURIComponent(items('Apply_to_each')?['emailAddress']?['address'])}'
  )

  Body:
  {
    "cr_sourcesignalid": "@{triggerOutputs()?['body/internetMessageId']}",
    "cr_conversationid": "@{triggerOutputs()?['body/conversationId']}",
    "cr_internetmessageheaders": "@{outputs('messageHeaders')}",
    "cr_sentdatetime": "@{triggerOutputs()?['body/sentDateTime']}",
    "cr_recipientemail": "@{items('Apply_to_each')?['emailAddress']?['address']}",
    "cr_recipienttype": "@{variables('recipientType')}",
    "cr_originalsubject": "@{take(triggerOutputs()?['body/subject'], 400)}",
    "cr_followupdate": "@{outputs('followUpDate')}",
    "cr_responsereceived": false,
    "cr_nudgesent": false,
    "cr_dismissedbyuser": false
  }

  Note: The Upsert uses the composite alternate key
  (cr_sourcesignalid + cr_recipientemail) to prevent duplicates.
  The take() function truncates subject to 400 chars (maxLength).
```

### Error Handling

Wrap the entire "Apply to each" loop in a **Scope** action named `Scope_Track_Recipients`. Add a parallel branch:

```
Scope: Scope_Handle_Errors
  Configure Run After: Scope_Track_Recipients has failed
  Actions:
    - Compose: Error details from outputs('Scope_Track_Recipients')
    - (Optional) Post to a Teams channel or log to an error table
    - Terminate: Status = Succeeded (don't fail the whole flow for one email)
```

---

## Flow 2: Response Detection & Nudge Delivery

**Purpose**: Daily scheduled flow that checks for unreplied emails and delivers follow-up nudge Adaptive Cards via Teams.

### Trigger

| Setting | Value |
|---------|-------|
| Trigger Type | Recurrence (Scheduled) |
| Frequency | Day |
| Interval | 1 |
| Time Zone | User's local time (from BriefingSchedule or NudgeConfiguration) |
| Start Time | 09:00 |

### Actions

#### Step 1: Get User Profile

```
Action: Office 365 Users — Get my profile (V2)
Purpose: Provides USER_DISPLAY_NAME for agent input
```

#### Step 2: Check Nudge Enabled

```
Action: Dataverse — Get a row by ID (or List rows with filter)
Table: Nudge Configurations
Filter: cr_owneruserid eq '@{outputs('Get_my_profile_(V2)')?['body/id']}'

Condition: cr_nudgesenabled equals false
  If yes → Terminate flow (Status: Succeeded, Message: "Nudges disabled for this user")
  If no → Continue to Step 3
```

#### Step 3: Query Overdue Follow-Ups

```
Action: Dataverse — List rows
Table: Follow-Up Tracking (cr_followuptrackings)
Filter:
  cr_responsereceived eq false
  and cr_nudgesent eq false
  and cr_dismissedbyuser eq false
  and cr_followupdate le @{utcNow()}
  and _ownerid_value eq '@{outputs('Get_my_profile_(V2)')?['body/id']}'
Sort: cr_followupdate asc
Top Count: 50 (process in batches to avoid timeout)
```

> ⚠️ Owner filter is required for data isolation. Do not remove this filter even if using RLS-based security roles.

#### Step 4: Loop Through Pending Follow-Ups

```
Action: Apply to each
Input: outputs('List_overdue_followups')?['body/value']
Concurrency: 5 (limit parallel Graph API calls)
```

Inside the loop:

##### Step 4a: Check for Reply via Graph API

```
Action: HTTP with Azure AD
Method: GET
URI: https://graph.microsoft.com/v1.0/me/messages
  ?$filter=conversationId eq '@{items('Apply_to_each')?['cr_conversationid']}'
    and receivedDateTime gt @{items('Apply_to_each')?['cr_sentdatetime']}
  &$select=from,receivedDateTime,internetMessageHeaders,subject
  &$top=20
Authentication: Azure AD (delegated, Mail.Read)
```

> **Important: Check HTTP Status Code**
> Before proceeding to reply matching, verify the Graph API returned HTTP 200:
> ```
> Condition: equals(outputs('HTTP_Check_Replies')?['statusCode'], 200)
>   If Yes → proceed to reply matching (Step 2b)
>   If No → log error, skip this item, continue to next
> ```
> Without this check, a Graph API outage (429, 500, 503) is indistinguishable from "no reply found," causing false nudges.

##### Step 4b: Check If Specific Recipient Replied

```
Condition: Reply from tracked recipient?
Expression:
  contains(
    body('HTTP_Check_Replies')?['value'],
    items('Apply_to_each')?['cr_recipientemail']
  )

More precisely — use a Filter array:
  From: body('HTTP_Check_Replies')?['value']
  Where: toLower(item()?['from']?['emailAddress']?['address'])
         equals
         toLower(items('Apply_to_each')?['cr_recipientemail'])

If filter result is NOT empty → Reply found
```

> **Important: OOF/Auto-Reply Exclusion**
> After filtering replies by sender email, exclude auto-replies to prevent false "reply received" marking:
> - Filter out messages where `internetMessageHeaders` contains a header with `name` = `Auto-Submitted` and `value` ≠ `no`
> - Also filter out messages where `subject` starts with `Automatic reply:` or `Out of Office:`
> - Add `internetMessageHeaders` to the `$select` clause of the Graph API query in Step 2a
>
> Without this filter, Out-of-Office auto-replies will be counted as real replies, suppressing valid nudges.

##### Step 4c: If Reply Found → Update Dataverse

```
Action: Dataverse — Update a row
Table: Follow-Up Tracking
Row ID: items('Apply_to_each')?['cr_followuptrackingid']
cr_responsereceived: true
cr_lastchecked: @{utcNow()}
```

Then **continue** to next iteration (skip nudge).

##### Step 4d: If No Reply → Race Condition Guard

Before sending a nudge, re-query the row to confirm it hasn't been updated by another flow:

```
Action: Dataverse — Get a row by ID
Table: Follow-Up Tracking
Row ID: items('Apply_to_each')?['cr_followuptrackingid']

Condition: Still pending?
  cr_responsereceived eq false
  AND cr_nudgesent eq false
  AND cr_dismissedbyuser eq false
```

If the row has changed, skip this item.

##### Step 4d-pre: Get Thread Preview

```
Action: HTTP with Azure AD — GET
URI: https://graph.microsoft.com/v1.0/me/messages
  ?$filter=conversationId eq '@{items('Apply_to_each')?['cr_conversationid']}'
  &$select=bodyPreview,from,receivedDateTime
  &$orderby=receivedDateTime desc
  &$top=3

Select: extractPreviews
  From: body('Get_thread_preview')?['value']
  Map: item()?['bodyPreview']

Compose: threadExcerpt
  Expression: take(join(body('extractPreviews'), ' --- '), 2000)
```

##### Step 4e: If Still Pending → Invoke Copilot Agent (Optional)

```
Action: Run a flow from Copilot (or HTTP to agent endpoint)
Input Variables:
  CONVERSATION_ID: items('Apply_to_each')?['cr_conversationid']
  ORIGINAL_SUBJECT: items('Apply_to_each')?['cr_originalsubject']
  RECIPIENT_EMAIL: items('Apply_to_each')?['cr_recipientemail']
  RECIPIENT_TYPE: items('Apply_to_each')?['cr_recipienttype']
  DAYS_SINCE_SENT: div(sub(ticks(utcNow()), ticks(items('Apply_to_each')?['cr_sentdatetime'])), 864000000000)
  THREAD_EXCERPT: outputs('threadExcerpt')
  USER_DISPLAY_NAME: outputs('Get_my_profile_(V2)')?['body/displayName']

Note: 864000000000 ticks = 1 day. Power Automate does not have a
dateDifference() function; use ticks arithmetic instead.

Output:
  - nudgeAction: "NUDGE" or "SKIP"
  - skipReason: (only if nudgeAction = "SKIP") why the nudge was suppressed
  - threadSummary: Brief summary of the thread context
  - suggestedDraft: Suggested follow-up message text
  - nudgePriority: High / Medium / Low
  - confidence: 0-100 confidence score

Condition: nudgeAction equals "SKIP"
  If yes → Update cr_dismissedbyuser = true (agent-skipped), continue to next
  If no → Proceed to Step 2f
```

##### Step 4f: Post Adaptive Card (Fire-and-Forget)

```
Action: Microsoft Teams — Post adaptive card as the Flow bot to a user
Recipient: Current user (flow connection owner)
Adaptive Card: See schemas/adaptive-card-nudge.json
```

This posts the card but does NOT wait for a response. Button clicks are handled by a separate flow.

Then update Dataverse:

```
Action: Dataverse — Update a row
Table: Follow-Up Tracking
Row ID: items('Apply_to_each')?['cr_followuptrackingid']
cr_nudgesent: true
cr_lastchecked: @{utcNow()}
```

### Handling Card Button Responses — Flow 2b (Separate Flow)

> **Important:** The Adaptive Card buttons (Draft, Snooze, Dismiss) use Action.Submit. To handle these responses, create a **separate flow** with:
>
> **Trigger:** "When someone responds to an adaptive card" (Microsoft Teams connector)
>
> **Logic:**
> 1. Parse the response body to get `action`, `trackingId`, and other fields
> 2. Switch on `action`:
>    - `draft_followup` → Invoke the Copilot agent to generate a full draft, post back as a new card
>    - `snooze_nudge` → Update Dataverse: `cr_followupdate = addDays(utcNow(), 2)`, `cr_nudgesent = false`
>    - `dismiss_nudge` → Update Dataverse: `cr_dismissedbyuser = true`
> 3. Error handling: On failure, post a text message to the user: "Action couldn't be completed. Please try again."
>
> This separation is required because Power Automate's "Post adaptive card" action does not support inline response waiting within a batch processing loop.

### Error Handling

Same Scope + parallel error branch pattern:

```
Scope: Scope_Process_FollowUps
  [All steps above]

Scope: Scope_Handle_Errors (Run After: has failed)
  Actions:
    - Log error details
    - Continue (don't fail the daily sweep for one item)
```

---

## Flow 5: Data Retention Cleanup (Weekly)

**Purpose**: Purge completed follow-up tracking records older than 90 days.

### Trigger

| Setting | Value |
|---------|-------|
| Trigger Type | Recurrence (Scheduled) |
| Frequency | Week |
| Interval | 1 |
| Day | Sunday |
| Time | 02:00 AM |

### Actions

```
Action: Dataverse — List rows
Table: Follow-Up Tracking
Filter:
  (cr_responsereceived eq true or cr_dismissedbyuser eq true)
  and createdon lt @{addDays(utcNow(), -90)}
Top Count: 100

Action: Apply to each
  Action: Dataverse — Delete a row
  Row ID: items('Apply_to_each')?['cr_followuptrackingid']
```

---

## Common Patterns

### Business Day Calculation Expression

This Power Automate expression converts business days to calendar days by adding weekends:

```
addDays(
  startDate,
  add(
    businessDays,
    mul(2, div(add(businessDays, sub(dayOfWeek(startDate), 1)), 5))
  )
)
```

**How it works**: For every 5 business days, add 2 weekend days. The `dayOfWeek()` offset ensures the calculation starts correctly regardless of which day the email was sent.

**Limitation**: This does NOT account for holidays. Holiday handling requires a separate Dataverse reference table (out of scope for MVP).

### Scope + Parallel Error Branch

All flows use this error handling pattern:

```
┌─────────────────────────┐
│  Scope: Main Logic      │
│  (all actions inside)   │
├─────────────────────────┤
│  ✅ Success path        │  ❌ Failure path (Run After: has failed)
│  [continue normally]    │  [log error, notify admin, terminate as Succeeded]
└─────────────────────────┘
```

This ensures individual item failures don't crash the entire flow run.

### Graph API Reply Detection Query

```
GET https://graph.microsoft.com/v1.0/me/messages
  ?$filter=conversationId eq '{conversationId}' 
    and receivedDateTime gt {sentDateTime}
  &$select=from,receivedDateTime,internetMessageHeaders
  &$top=20
```

**Notes**:
- This queries across ALL mail folders (no folder filter), so it catches replies that were read and archived.
- The `$top=20` limits results to avoid large payloads for active threads.
- Match `from.emailAddress.address` against the tracked `cr_recipientemail` to confirm the specific recipient replied (not just any thread participant).
