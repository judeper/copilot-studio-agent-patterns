# Snooze Auto-Removal Flows — Step-by-Step Building Guide

This document provides detailed specifications for building the Power Automate flows that power the Snooze Auto-Removal system. Each flow is described with its trigger, actions, expressions, and error handling patterns.

---

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
Purpose: Retrieves the current user's systemuserid, which is needed for the
owner filter in Step 1 and the cr_owneruserid alternate key in the Dataverse upsert (Step 3).
Output: outputs('Get_my_profile_(V2)')?['body/id']
```

#### Step 1: Get or Create Managed Snoozed Folder

```
Action: Dataverse — Get a row by ID (or List rows filtered by owner)
Table: Nudge Configurations
Filter: _ownerid_value eq '@{outputs('Get_my_profile_(V2)')?['body/id']}'

Condition: cr_snoozefolderid is null or empty?
```

**If folder ID is null** (first run):

```
Action: HTTP with Microsoft Entra ID
Method: POST
URI: https://graph.microsoft.com/v1.0/me/mailFolders
Body:
{
  "displayName": "EPA-Snoozed",
  "isHidden": false
}
Authentication: Azure AD (delegated, Mail.ReadWrite)

Store response: body('Create_Folder')?['id'] → snooze folder ID

Action: Dataverse — Update a row
Table: Nudge Configurations
Row: <user's config row>
cr_snoozefolderid: <new folder ID>
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
Concurrency: 1 (sequential to avoid alternate key conflicts)
```

Inside the loop:

```
Action: HTTP with Microsoft Entra ID (Dataverse Upsert)
Method: PATCH
URI: {OrgUrl}/api/data/v9.2/cr_snoozedconversations(
  cr_conversationid='@{encodeURIComponent(items('Apply_to_each')?['conversationId'])}',
  cr_owneruserid='@{outputs('Get_my_profile_(V2)')?['body/id']}'
)
Headers:
  Content-Type: application/json
  (No If-Match header — this enables true upsert behavior: create if not exists, update if exists.
  If-Match: * would restrict to update-only; If-None-Match: * would restrict to create-only.)
Body:
{
  "cr_conversationid": "@{items('Apply_to_each')?['conversationId']}",
  "cr_owneruserid": "@{outputs('Get_my_profile_(V2)')?['body/id']}",
  "cr_originalmessageid": "@{items('Apply_to_each')?['id']}",
  "cr_currentfolder": "@{variables('snoozeFolderId')}",
  "cr_originalsubject": "@{take(items('Apply_to_each')?['subject'], 400)}"
}
```

> **Note:** The alternate key uses `cr_owneruserid` (a custom text column) instead of `ownerid` because Dataverse does not support the system `ownerid` lookup column in alternate keys.

> **Note:** `cr_unsnoozedbyagent` is intentionally omitted from the upsert body. It defaults to `false` on row creation (via Dataverse column default). Including it here would risk resetting the field to `false` on a row that Flow 4 has already marked as `true` (due to Graph API folder-listing cache propagation delays).

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

#### Step 4: If Match Found → Invoke Snooze Agent (Optional)

For MVP, you can skip the agent call and always unsnooze. For enhanced behavior:

```
Action: Run a flow from Copilot (or HTTP to agent)
Input:
  CONVERSATION_ID: outputs('newConversationId')
  NEW_MESSAGE_SENDER: triggerOutputs()?['body/from']?['emailAddress']?['address']
  NEW_MESSAGE_SENDER_NAME: triggerOutputs()?['body/from']?['emailAddress']?['name']
  NEW_MESSAGE_SUBJECT: triggerOutputs()?['body/subject']
  NEW_MESSAGE_EXCERPT: take(triggerOutputs()?['body/bodyPreview'], 500)
  SNOOZED_SUBJECT: <from Dataverse row>
  SNOOZE_UNTIL: <from Dataverse row>
  USER_TIMEZONE: <from user profile or NudgeConfig>
  CURRENT_DATETIME: utcNow()

Condition: Agent response unsnoozeAction equals "SUPPRESS"
  If yes → Exit (don't unsnooze)
```

#### Step 5: Move Snoozed Message Back to Inbox

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
Action: Microsoft Teams — Post adaptive card as the Flow bot to a user
Recipient: Current user (flow connection owner)
Adaptive Card:
{
  "type": "AdaptiveCard",
  "version": "1.4",
  "body": [
    {
      "type": "TextBlock",
      "text": "@{outputs('Agent_Response')?['notificationMessage']}",
      "wrap": true
    }
  ]
}

OR for simpler implementation without agent:

Action: Microsoft Teams — Post message as the Flow bot to a user
Message: "📬 Unsnoozed: **@{snoozedSubject}** — new reply from @{triggerOutputs()?['body/from']?['emailAddress']?['name']}"
```

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
The Snooze Agent can suppress unsnoozing outside working hours (before 7 AM, after 7 PM in user's timezone). This prevents weekend replies from surfacing snoozed emails when the user isn't working. The message will be unsnoozed on the next workday.

### Outlook Native Snooze Conflict
This system uses a **managed folder** (`EPA-Snoozed`), NOT Outlook's native snooze. If a user uses Outlook's built-in "Remind Me" feature, those snoozed emails are in a different folder and will NOT be auto-unsnoozed by this agent. Users should be educated to use the EPA-Snoozed folder (via Canvas App "Snooze" action) for auto-unsnooze behavior.

### Message ID Invalidation After Move
When `POST /me/messages/{id}/move` is called, Graph deletes the original message and returns a new message with a new ID. The flow MUST capture the new ID from the response body and update the Dataverse record. Failure to do so will cause subsequent operations to return 404.

### Folder Deletion
If the user manually deletes the EPA-Snoozed folder, Flow 3 will detect the 404 error, clear `cr_snoozefolderid`, and recreate the folder on the next run. Snoozed messages in the deleted folder are lost.
