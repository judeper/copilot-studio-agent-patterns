# Snooze Auto-Removal Flows — Step-by-Step Building Guide

This document provides detailed specifications for building the Power Automate flows that power the Snooze Auto-Removal system. Each flow is described with its trigger, actions, expressions, and error handling patterns.

---

> **Current validated POC state:** The dry-run build keeps Flow 4 deterministic. Flow 11 and Flow 12 are the HTTP harness equivalents of Flow 3 and Flow 4, and Flow 13 seeds a real message into `EPA-Snoozed` so the Phase 2 path can be tested end to end without waiting on manual mailbox actions. The production Snooze Agent pattern is still documented below as an optional future enhancement.

## Prerequisites

Before building these flows, ensure:
1. Phase 1 (Follow-Up Nudges) is deployed — NudgeConfiguration table exists with `cr_snoozefolderid` column
2. The `cr_snoozedconversation` Dataverse table is provisioned
3. Security roles include Basic-depth privileges on `cr_SnoozedConversation`

> **Automated deployment:** These flows can be deployed automatically using the deploy script:
> ```powershell
> pwsh deploy-agent-flows.ps1 -OrgUrl "https://<org>.crm.dynamics.com" -EnvironmentId "<env-id>" -FlowsToCreate "Phase2"
> ```
> The specifications below are provided as reference for customization and troubleshooting.

---

## Flow 3: Snooze Detection (Folder Scanner)

**Purpose**: Periodically scan the managed EPA-Snoozed folder to detect newly snoozed emails and track them in Dataverse.

### Trigger

| Setting | Value |
|---------|-------|
| Trigger Type | Recurrence (Scheduled) |
| Frequency | Minute |
| Interval | 15 |

### Actions

#### Step 0: Get User Profile

```
Action: Office 365 Users — Get my profile (V2)
Purpose: Retrieves the current user's Entra object ID, which is used as the
owner-scoped key in `cr_nudgeconfiguration.cr_owneruserid` and `cr_snoozedconversation.cr_owneruserid`.
Output: outputs('Get_my_profile_(V2)')?['body/id']
```

#### Step 1: Get or Create Managed Snoozed Folder

```
Action: Dataverse — List rows
Table: Nudge Configurations
Filter: cr_owneruserid eq '@{outputs('Get_my_profile_(V2)')?['body/id']}'
Top Count: 1

Condition: cr_snoozefolderid is null or empty?
```

**If folder ID is null or empty**:

```
Action: HTTP with Microsoft Entra ID
Method: GET
URI: https://graph.microsoft.com/v1.0/me/mailFolders?$filter=displayName eq 'EPA-Snoozed'&$select=id,displayName

Condition: length(body('Find_Existing_Snoozed_Folder')?['value']) greater than 0

If yes:
  Compose: snoozeFolderId = first(body('Find_Existing_Snoozed_Folder')?['value'])?['id']

If no:
Action: HTTP with Microsoft Entra ID
Method: POST
URI: https://graph.microsoft.com/v1.0/me/mailFolders
Body:
{
  "displayName": "EPA-Snoozed",
  "isHidden": false
}
Authentication: Azure AD (delegated, Mail.ReadWrite)

Compose: snoozeFolderId = body('Create_Folder')?['id']

Then persist the resolved folder ID back to Dataverse:

Action: Dataverse — Update a row (if config exists)
  Table: Nudge Configurations
  Row: <existing config row>
  cr_snoozefolderid: @{outputs('Compose_snoozeFolderId')}

OR

Action: Dataverse — Create a new row (if config does not yet exist)
  Table: Nudge Configurations
  cr_owneruserid: @{outputs('Get_my_profile_(V2)')?['body/id']}
  cr_snoozefolderid: @{outputs('Compose_snoozeFolderId')}
```

**If folder ID exists**: Use the stored value.

```
Variable: snoozeFolderId = outputs('Get_Config')?['body/cr_snoozefolderid']
```

#### Step 2: List Messages in Snoozed Folder

```
Action: HTTP with Microsoft Entra ID
Method: GET
URI: https://graph.microsoft.com/v1.0/me/mailFolders/{snoozeFolderId}/messages
  ?$select=id,conversationId,subject,receivedDateTime
  &$top=50
Authentication: Azure AD (delegated, Mail.Read)
```

**Error handling**: If the folder no longer exists (404), clear `cr_snoozefolderid` and recreate on next run.

#### Step 3: Upsert Each Message to Dataverse

```
Action: Apply to each
Input: body('List_Snoozed_Messages')?['value']
Concurrency: 1 (sequential to avoid overlapping writes)
```

Inside the loop:

```
Action: Dataverse — List rows
Table: Snoozed Conversations
Filter:
  cr_conversationid eq '@{items('Apply_to_each')?['conversationId']}'
  and cr_owneruserid eq '@{outputs('Get_my_profile_(V2)')?['body/id']}'
Top Count: 1

Condition: length(body('List_Existing_SnoozedConversation')?['value']) greater than 0

If yes:
  Action: Dataverse — Update a row
  Row ID: first(body('List_Existing_SnoozedConversation')?['value'])?['cr_snoozedconversationid']
  Fields:
    cr_originalmessageid = @{items('Apply_to_each')?['id']}
    cr_currentfolder = @{variables('snoozeFolderId')}
    cr_originalsubject = @{take(items('Apply_to_each')?['subject'], 400)}

If no:
  Action: Dataverse — Create a new row
  Fields:
    cr_conversationid = @{items('Apply_to_each')?['conversationId']}
    cr_owneruserid = @{outputs('Get_my_profile_(V2)')?['body/id']}
    cr_originalmessageid = @{items('Apply_to_each')?['id']}
    cr_currentfolder = @{variables('snoozeFolderId')}
    cr_originalsubject = @{take(items('Apply_to_each')?['subject'], 400)}
    cr_unsnoozedbyagent = false
```

> **Important:** The Dataverse connector save-time validation requires `cr_unsnoozedbyagent` to be set explicitly on the create path, even though the column also has a Dataverse default.

### Error Handling

```
Scope: Scope_Scan_Folder
  [Steps 0-3 above]

Scope: Scope_Handle_Errors (Run After: has failed)
  Actions:
    - Log error (folder ID may be stale, Graph throttling, etc.)
    - If error is 404 (folder not found): clear cr_snoozefolderid
    - Terminate: Succeeded (don't fail the scheduled run)
```

> **Dry-run hardening note:** The validated flow first checks whether `EPA-Snoozed` already exists before creating it. This avoids the Graph `Conflict` response that occurs when the folder exists in Outlook but `cr_snoozefolderid` is blank in Dataverse.

---

## Flow 4: Auto-Unsnooze on New Reply

**Purpose**: When a new email arrives in the Inbox, check if it belongs to a snoozed conversation and automatically move the snoozed message back to Inbox.

### Trigger

| Setting | Value |
|---------|-------|
| Connector | Office 365 Outlook |
| Trigger | When a new email arrives (V3) |
| Folder | Inbox |
| Include Attachments | No |
| Split On | Enabled |

### Actions

#### Step 1: Get ConversationId of New Email

```
Compose: newConversationId
Expression: triggerOutputs()?['body/conversationId']
```

#### Step 2: Check Dataverse for Matching Snoozed Conversation

```
Action: Dataverse — List rows
Table: Snoozed Conversations (cr_snoozedconversations)
Filter:
  cr_conversationid eq '@{outputs('newConversationId')}'
  and cr_unsnoozedbyagent eq false
Top Count: 1
```

#### Step 3: If No Match → Exit

```
Condition: length(outputs('Check_Snoozed')?['body/value']) equals 0
If yes → Terminate (no action needed — this is the most common path)
```

#### Step 4: If Match Found → Determine Unsnooze Action

**Current validated POC implementation**:

```
Initialize variable: unsnoozeAction = "UNSNOOZE"

Scope: Scope_Agent_Decision
  Action: Compose
  Message: "POC mode: skipping Snooze Agent invocation and using the default UNSNOOZE path."
```

> **Timezone handling:** Flow 4 resolves the user's timezone from Graph mailbox settings (`/v1.0/me/mailboxSettings`). If that lookup fails, it falls back to **UTC** (not the Eastern Standard Time used by scheduled flows). This is intentional — event-driven flows should use the actual user timezone rather than a hardcoded zone.

**Production enhancement (optional)**:

Reintroduce a Snooze Agent call only when you want suppression logic such as working-hours awareness. The agent should set `unsnoozeAction` to either `UNSNOOZE` or `SUPPRESS`, after which the flow can branch on that value.

#### Step 5: If Not Suppressed → Move Snoozed Message Back to Inbox

```
Action: HTTP with Microsoft Entra ID
Method: POST
URI: https://graph.microsoft.com/v1.0/me/messages/{cr_originalmessageid}/move
Body:
{
  "destinationId": "inbox"
}
Authentication: Azure AD (delegated, Mail.ReadWrite)

CRITICAL: Capture the NEW message ID from the response body.
The original message ID is now invalid (Graph deletes it during move).

Compose: newMessageId
Expression: body('Move_Message')?['id']
```

#### Step 6: Update Dataverse Record

```
Action: Dataverse — Update a row
Table: Snoozed Conversations
Row ID: <matched row's cr_snoozedconversationid>
cr_unsnoozedbyagent: true
cr_unsnoozeddatetime: @{utcNow()}
cr_originalmessageid: @{outputs('newMessageId')}
cr_currentfolder: "inbox"
```

#### Step 7: Notify User (Optional)

```
Action: Microsoft Teams — Post message as the Flow bot to a user
Location: Chat with Flow bot
Recipient: Current user (flow connection owner)
Parameter shape:
  body/recipient = @{coalesce(outputs('Get_my_profile_(V2)')?['body/mail'], outputs('Get_my_profile_(V2)')?['body/userPrincipalName'])}
  body/messageBody = <text payload>

Message: "📬 Unsnoozed: **@{snoozedSubject}** — new reply from @{triggerOutputs()?['body/from']?['emailAddress']?['name']}"
```

> **Connector quirk:** For `location = "Chat with Flow bot"`, use `body/recipient` as a flat email/UPN string. Do **not** send a nested `body/recipient/to` object.

### Error Handling

```
Scope: Scope_Auto_Unsnooze
  [Steps 1-7 above]

Scope: Scope_Handle_Errors (Run After: has failed)
  Actions:
    - If move failed with 404:
        The snoozed message may have been manually moved or deleted.
        Update Dataverse: cr_unsnoozedbyagent = true (mark as handled)
    - If move failed with 429 (throttling):
        Wait and retry (use Retry policy on the HTTP action)
    - Log error details
    - Terminate: Succeeded
```

---

## Flow 6: Snooze Cleanup (Weekly)

**Purpose**: Purge completed snooze tracking records older than 30 days.

### Trigger

| Setting | Value |
|---------|-------|
| Trigger Type | Recurrence (Scheduled) |
| Frequency | Week |
| Interval | 1 |
| Day | Sunday |
| Time | 02:30 AM |

### Actions

```
Action: Dataverse — List rows
Table: Snoozed Conversations
Filter:
  cr_unsnoozedbyagent eq true
  and createdon lt @{addDays(utcNow(), -30)}
Top Count: 100

Action: Apply to each
  Action: Dataverse — Delete a row
  Row ID: items('Apply_to_each')?['cr_snoozedconversationid']
```

---

## Edge Cases & Known Limitations

### ConversationId Mismatch
If the recipient changes the email subject when replying, Graph assigns a new `conversationId`. The reply will not match the snoozed conversation and auto-unsnooze will not trigger. **Mitigation**: Document as a known limitation. Future enhancement: secondary matching on subject similarity.

### Multiple Snoozed Messages in Same Thread
If a user snoozed multiple messages from the same conversation, the Dataverse alternate key (conversationId + owner) means only one row exists per thread. The most recently detected message's ID is stored. All messages in the thread effectively share one snooze record.

### Working Hours
The current validated dry-run build does **not** suppress unsnoozing outside working hours; it always takes the deterministic UNSNOOZE path. Working-hours suppression remains a production enhancement that can be reintroduced when the Snooze Agent is wired back in.

### Outlook Native Snooze Conflict
This system uses a **managed folder** (`EPA-Snoozed`), NOT Outlook's native snooze. If a user uses Outlook's built-in "Remind Me" feature, those snoozed emails are in a different folder and will NOT be auto-unsnoozed by this agent. Users should be educated to use the EPA-Snoozed folder (via Canvas App "Snooze" action) for auto-unsnooze behavior.

### Message ID Invalidation After Move
When `POST /me/messages/{id}/move` is called, Graph deletes the original message and returns a new message with a new ID. The flow MUST capture the new ID from the response body and update the Dataverse record. Failure to do so will cause subsequent operations to return 404.

### Folder Deletion
If the user manually deletes the EPA-Snoozed folder, Flow 3 will detect the 404 error, clear `cr_snoozefolderid`, and recreate the folder on the next run. Snoozed messages in the deleted folder are lost.
