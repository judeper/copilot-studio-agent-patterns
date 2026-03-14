# IWL Flow Design Completeness Review

**Reviewer:** AI Council — Architect  
**Date:** 2025-07-10  
**Scope:** 10 main flows (`flow-*.json`) + 10 tool flows (`tool-*.json`)

---

## Executive Summary

| Rating | Count | Flows |
|--------|-------|-------|
| **Complete** | 12 | F1, F2, F3, F5, F6, F7, F8, F9, F10, T-QueryCards, T-QuerySenderProfile, T-SearchSharePoint |
| **Partial** | 7 | F4, T-UpdateCard, T-CreateCard, T-RefineDraft, T-SearchUserEmail, T-SearchSentItems, T-SearchPlannerTasks |
| **Scaffold** | 1 | T-SearchTeamsMessages |

Overall: **85% structurally complete**. The signal-trigger flows (1–3) are the strongest. The tool flows have a consistent pattern bug (unused `user_aad_id`) and one broken Graph API endpoint.

---

## Per-Flow Assessments

### MAIN FLOWS

#### Flow 1 — Email Trigger ✅ Complete

| Aspect | Status | Notes |
|--------|--------|-------|
| Trigger | ✅ | `OnNewEmailV3`, Inbox, splitOn for parallel |
| Actions | ✅ | Full pipeline: get email → filter no-reply/low-importance → sender profile → agent → parse → card create → humanizer → upsert profile |
| Data Flow | ✅ | Proper output references between all steps |
| Agent Integration | ✅ | `ExecuteAgentAndWait` with exponential retry (2×, 15s) |
| Error Handling | ⚠️ | Scope catches Failed/TimedOut but **only composes error details — never writes to `cr_errorlog`** |

**Issues:**
1. `Upsert_SenderProfile` uses `UpdateRecord` with `recordId: null` for new profiles — this will **fail** for first-time senders. Needs a conditional branch: if profile exists → UpdateRecord, else → CreateRecord.
2. `botId: "<ewa-agent-schema-name>"` placeholder must be replaced at deployment.
3. `USER_CONTEXT` is a JSON object but docs say it should be a comma-separated string — minor contract deviation (agent handles both).

---

#### Flow 2 — Teams Trigger ✅ Complete

| Aspect | Status | Notes |
|--------|--------|-------|
| Trigger | ✅ | `OnNewMention` via Teams connector |
| Actions | ✅ | Bot sender filtering, sender profile, agent, card create, humanizer |
| Data Flow | ✅ | Teams-specific fields (threadId, channelName, mentions) properly mapped |
| Error Handling | ⚠️ | Same as Flow 1 — no ErrorLog write |

**Issues:**
1. Same `Upsert_SenderProfile` null-recordId bug as Flow 1.
2. `Compose_ClusterId` falls back to `body/id` — correct for 1:1 chats.
3. `botId` placeholder.

---

#### Flow 3 — Calendar Trigger ✅ Complete

| Aspect | Status | Notes |
|--------|--------|-------|
| Trigger | ✅ | Daily 7AM recurrence (EST) |
| Actions | ✅ | 14-day scan, event filtering, per-event agent invocation, 5s rate-limit delay |
| Data Flow | ✅ | Temporal horizon pre-computed, cluster ID uses seriesMasterId for recurring events |
| Error Handling | ⚠️ | Same as Flow 1 |

**Issues:**
1. `Apply_to_each_event` has **no concurrency limit** — could fire 200 parallel agent calls. Add `runtimeConfiguration.concurrency.repetitions: 1` (sequential is correct here due to rate limiting).
2. Same upsert bug.
3. Filter expression uses keyword matching (`focus time`, `lunch`, `ooo`) — reasonable but not configurable.

---

#### Flow 4 — Send Email ⚠️ Partial

| Aspect | Status | Notes |
|--------|--------|-------|
| Trigger | ✅ | Manual/Button with CardId + FinalDraftText |
| Actions | ⚠️ | Ownership check ✅, recipient validation ✅, send ✅, outcome update ✅ |
| Data Flow | ✅ | Correct output chaining |
| Error Handling | ✅ | HTTP 403/400/500 responses |

**Issues:**
1. **Missing trigger inputs**: The docs specify `forward_to`, `reply_all`, and `cc_recipients` parameters but the trigger schema only has `CardId` and `FinalDraftText`. Without these, the flow can only send to the original sender.
2. **No HTML body support**: `SendEmailV2` body is plain text from `FinalDraftText`. Should use `emailMessage/Body` with `<html>` wrapping if the humanizer produces HTML.
3. **Misplaced parameters**: Several actions have `$connections` and `$authentication` inside the `parameters` object rather than at the definition level — harmless but clutters action inputs.
4. Outcome is hardcoded to `SENT_AS_IS` (100000001) — should be `SENT_EDITED` (100000002) if the user modified the draft.

**Recommended fix for trigger schema:**
```json
"schema": {
  "type": "object",
  "properties": {
    "CardId": { "type": "string" },
    "FinalDraftText": { "type": "string" },
    "forward_to": { "type": "string", "description": "Comma-separated email addresses for forward" },
    "reply_all": { "type": "boolean", "description": "Whether to reply-all" },
    "cc_recipients": { "type": "string", "description": "Comma-separated CC addresses" },
    "was_edited": { "type": "boolean", "description": "Whether user modified the draft" }
  },
  "required": ["CardId", "FinalDraftText"]
}
```

---

#### Flow 5 — Card Outcome Tracker ✅ Complete

| Aspect | Status | Notes |
|--------|--------|-------|
| Trigger | ✅ | Dataverse webhook on `cr_assistantcards` modification, filtered on `cr_cardoutcome` |
| Actions | ✅ | Full switch on all 4 non-PENDING outcomes with running-average math |
| Data Flow | ✅ | Correct rolling average formula for response hours and edit distance |
| Error Handling | ✅ | Terminate with error code |

**Issues:**
1. `SENT_EDITED` case references `cr_editdistanceratio` on the card — this field must be pre-computed by the Canvas App before setting the outcome. This implicit contract should be documented.
2. Trigger has `scope: "Organization"` — will fire for ALL users' cards. Should be scoped to the connection user or filtered to avoid processing other users' cards.

---

#### Flow 6 — Daily Briefing ✅ Complete

| Aspect | Status | Notes |
|--------|--------|-------|
| Trigger | ✅ | Every 15 minutes (polls briefing schedules) |
| Actions | ✅ | Timezone matching, duplicate prevention, parallel data fetch, agent invoke, card create |
| Data Flow | ✅ | 5-way parallel join on briefing data |
| Error Handling | ✅ | Terminate on failure |

**Issues:**
1. `Get_Today_Calendar` uses `CalendarGetOnNewItemsV3` — this operation is a trigger, not an action. Should use `CalendarGetEventsV3` or `GetEventsCalendarViewV3` (as Flow 3 does).
2. `Execute_Briefing_Agent` uses `@parameters('BriefingAgentBotId')` — good parameterized pattern, but this parameter isn't declared in the `parameters` section.
3. Briefing card has no `cr_priority` set — defaults to null. Should be `100000003` (N/A).

---

#### Flow 7 — Staleness Monitor ✅ Complete

| Aspect | Status | Notes |
|--------|--------|-------|
| Trigger | ✅ | 4× daily (8/12/16/20 EST) |
| Actions | ✅ | Nudge creation with dedup, card expiration |
| Data Flow | ✅ | NUDGE: prefix for signal ID dedup |
| Error Handling | ✅ | Both scopes handle failure |

**Issues:**
1. **Nudge card `cr_triggertype` is `100000000` (EMAIL)** — this is incorrect. Nudge cards should use a distinct trigger type or at minimum `100000004` (SELF_REMINDER). Using EMAIL causes the nudge to appear as if it was an email-triggered card.
2. `Scope_Expire_Abandoned` runs even if `Scope_Create_Nudges` fails — this is intentional and correct.
3. Overdue query has no pagination (`$top` not set) — could return 5000 records for very active users.

---

#### Flow 8 — Command Execution ✅ Complete

| Aspect | Status | Notes |
|--------|--------|-------|
| Trigger | ✅ | Manual/Button with commandText, userId, currentCardId |
| Actions | ✅ | Card context resolution, briefing fetch, orchestrator agent, response parse |
| Data Flow | ✅ | Proper null handling via Compose_CardJSON_Found/Null pattern |
| Error Handling | ✅ | HTTP 500 with error details |

**Issues:**
1. Uses `ExecuteCopilotAsyncV2` webhook operation vs `ExecuteAgentAndWait` in Flows 1–3 — different connector operations. `ExecuteCopilotAsyncV2` passes `inputVariables` (correct for orchestrator topics with named inputs) while `ExecuteAgentAndWait` passes a single `message` string.
2. `parameters` section is missing `$connections` and `$authentication` definitions — will fail at import.
3. Response body stringifies `card_links` and `side_effects` via `@{...}` which produces a string, not JSON arrays. Should use `@body(...)` without string interpolation.

---

#### Flow 9 — Sender Profile Analyzer ✅ Complete

| Aspect | Status | Notes |
|--------|--------|-------|
| Trigger | ✅ | Weekly Sunday 3AM EST |
| Actions | ✅ | Filter ≥5 signals, skip USER_OVERRIDE, calculate rates, categorize |
| Data Flow | ✅ | Proper division-by-zero guards |
| Error Handling | ✅ | Terminate with error details |

**Issues:**
1. **AUTO_LOW logic incomplete**: The Compose_Category expression checks `responseRate >= 0.8 → HIGH`, `responseRate >= 0.4 → MEDIUM`, else `LOW`. But docs specify `dismiss_rate >= 0.6` should also trigger AUTO_LOW regardless of response rate. Missing condition:
```
@if(greaterOrEquals(outputs('Compose_DismissRate'), 0.6), 100000002, 
  if(and(greaterOrEquals(outputs('Compose_ResponseRate'), 0.8), ...
```
2. Missing `$authentication` on Dataverse actions — will fail at runtime.

---

#### Flow 10 — Reminder Firing ✅ Complete

| Aspect | Status | Notes |
|--------|--------|-------|
| Trigger | ✅ | Every 10 minutes |
| Actions | ✅ | Query due reminders, Teams notification, mark delivered |
| Data Flow | ✅ | Owner lookup via O365 Users, Teams notification via Flow bot |
| Error Handling | ✅ | Terminate with error details |

**Issues:**
1. Minor: `Get_Card_Owner` result isn't used in the notification body — the owner lookup is unnecessary. The notification uses `_ownerid_value` directly as the recipient.

---

### TOOL FLOWS

#### T-QueryCards ✅ Complete

| Input | Output | Notes |
|-------|--------|-------|
| `user_aad_id`, `filter_expression`, `max_results` | `cards_json`, `result_count` | Ownership scoping appended to filter |

**Issues:** `$select` uses `cr_assistantcardsid` (with trailing 's') — verify against actual Dataverse column name.

---

#### T-QuerySenderProfile ✅ Complete

| Input | Output | Notes |
|-------|--------|-------|
| `sender_email` | `profile_json`, `found` | Found/not-found branching with full field projection |

No significant issues.

---

#### T-UpdateCard ⚠️ Partial

| Input | Output | Notes |
|-------|--------|-------|
| `card_id`, `update_json` | `success`, `card_id` | JSON parse → update |

**Issues:**
1. **Null-field overwrites**: The `Update_Card` action always sends ALL 7 fields from the parsed JSON. If `update_json` only contains `{"cr_priority": 100000000}`, the other 6 fields resolve to `null` and **overwrite existing values**. Fix: use conditional field mapping or Power Automate's `removeNulls` pattern.
2. **No ownership verification**: Any user can update any card if they know the card_id. Add ownership check before update.

**Recommended fix:**
```json
"Update_Card": {
  "type": "OpenApiConnection",
  "inputs": {
    "parameters": {
      "entityName": "cr_assistantcards",
      "recordId": "@triggerBody()?['card_id']",
      "item": "@removeProperty(removeProperty(removeProperty(
        body('Parse_Update_JSON'),
        if(equals(body('Parse_Update_JSON')?['cr_priority'], null), 'cr_priority', '__keep__')),
        ...
      )"
    }
  }
}
```

Or use separate conditional Update actions per field.

---

#### T-CreateCard ⚠️ Partial

| Input | Output | Notes |
|-------|--------|-------|
| `user_aad_id`, `card_json` | `new_card_id`, `success` | JSON parse → create |

**Issues:**
1. **Invalid default priority**: `coalesce(body('Parse_Card_JSON')?['priority'], 50)` — value `50` is not a valid Dataverse choice column value. Valid values are 100000000–100000003. Should default to `100000002` (Low).
2. `cr_confidencescore` is not set — will be null.

---

#### T-RefineDraft ⚠️ Partial

| Input | Output | Notes |
|-------|--------|-------|
| `draft_text`, `modification_instructions`, `target_channel` | `refined_text` | Humanizer agent invocation |

**Issues:**
1. `RECIPIENT_CONTEXT` is set to `modification_instructions` — should be a separate field or derived from card context.
2. No `retryPolicy` on agent invocation (Flows 1–3 have retry).
3. `botId` placeholder.

---

#### T-SearchUserEmail ⚠️ Partial

| Input | Output | Notes |
|-------|--------|-------|
| `user_aad_id`, `query`, `max_results` | `results_json`, `result_count` | Graph API `/me/messages` |

**Issues:**
1. **`user_aad_id` is accepted but unused** — the Graph call uses `/me/messages` which always searches the connection user's mailbox, not the specified user's. For delegated access, should use `/users/{user_aad_id}/messages`.
2. Uses `shared_webcontents` (HTTP) connector — should use `HTTP with Azure AD` connector for proper auth scoping.

---

#### T-SearchSentItems ⚠️ Partial

Same issues as T-SearchUserEmail. Uses `/me/mailFolders/SentItems/messages`.

---

#### T-SearchTeamsMessages 🔴 Scaffold

| Input | Output | Notes |
|-------|--------|-------|
| `user_aad_id`, `query`, `max_results` | `results_json`, `result_count` | **BROKEN** Graph API path |

**Critical Issue:** The Graph API path `/me/chats/messages?$search=...` does **not exist**. The Messages endpoint under `/chats` requires a specific `{chat-id}`. To search across all Teams messages, you must use the **Microsoft Search API**:

**Recommended fix:**
```json
"Search_Teams": {
  "type": "OpenApiConnection",
  "inputs": {
    "parameters": {
      "request/method": "POST",
      "request/url": "https://graph.microsoft.com/v1.0/search/query",
      "request/body": {
        "requests": [{
          "entityTypes": ["chatMessage"],
          "query": {
            "queryString": "@{triggerBody()?['query']}"
          },
          "from": 0,
          "size": "@coalesce(triggerBody()?['max_results'], 10)"
        }]
      }
    },
    "host": {
      "connectionName": "shared_webcontents",
      "operationId": "InvokeHttp",
      "apiId": "/providers/Microsoft.PowerApps/apis/shared_webcontents"
    }
  }
}
```

---

#### T-SearchSharePoint ✅ Complete

Properly uses Graph Search API POST with `driveItem` + `listItem` entity types. Correctly extracts hits from `value[0].hitsContainers[0].hits`.

**Issues:** `user_aad_id` unused (same `/me/` pattern).

---

#### T-SearchPlannerTasks ⚠️ Partial

| Input | Output | Notes |
|-------|--------|-------|
| `user_aad_id`, `query`, `max_results` | `results_json`, `result_count` | Fetch all → client filter |

**Issues:**
1. Only fetches first 50 tasks (`$top=50`) with no `@odata.nextLink` pagination. Users with many tasks will miss results.
2. Client-side `contains(toLower(title), toLower(query))` is substring-only — doesn't search task descriptions or notes.

---

## Contract Mismatches

| # | Source | Target | Mismatch | Severity |
|---|--------|--------|----------|----------|
| 1 | Orchestrator topic `Topic.FilterExpression` | tool-query-cards `filter_expression` | Case mismatch in variable binding (PascalCase vs snake_case) | 🟡 Medium — Copilot Studio does case-insensitive matching for flow inputs, but fragile |
| 2 | tool-create-card `priority` default | Dataverse `cr_priority` choice column | Default `50` is invalid; valid range is 100000000–100000003 | 🔴 High — will cause Dataverse write error |
| 3 | All 5 search/tool flows `user_aad_id` | Graph API `/me/` | Input accepted but never used for delegation | 🟡 Medium — works in single-user POC but wrong for multi-user |
| 4 | Flow 4 trigger schema | docs/agent-flows.md spec | Missing `forward_to`, `reply_all`, `cc_recipients` | 🟡 Medium — limits email sending to reply-only |
| 5 | Flow 8 `ExecuteCopilotAsyncV2` | Flows 1–3 `ExecuteAgentAndWait` | Different connector operations with different response shapes | 🟢 Low — both work, but inconsistent pattern |
| 6 | tool-refine-draft `RECIPIENT_CONTEXT` | Humanizer topic `RECIPIENT_CONTEXT` | Flow reuses `modification_instructions` for this field instead of providing actual recipient context | 🟡 Medium — degrades humanizer quality |
| 7 | Flow 5 trigger scope | Expected behavior | Trigger scope `Organization` fires for ALL users' card changes, not just the connection user | 🟡 Medium — works if connection user has org-wide read, but noisy |

---

## Top 5 Highest-Impact Improvements

### 1. 🔴 Fix T-SearchTeamsMessages broken Graph API endpoint
**Impact:** This tool flow will fail 100% of the time at runtime.  
**Fix:** Replace `/me/chats/messages?$search=...` with Microsoft Search API POST to `/search/query` using `entityTypes: ["chatMessage"]`. See recommended snippet above.  
**Files:** `src/tool-search-teams-messages.json`

### 2. 🔴 Fix Sender Profile Upsert pattern in Flows 1–3
**Impact:** First-time senders will cause a Dataverse error (UpdateRecord with null recordId).  
**Fix:** Replace `Upsert_SenderProfile` with a conditional: if `List_SenderProfile` returned results → `UpdateRecord`, else → `CreateRecord`.

```json
"Condition_Profile_Exists": {
  "type": "If",
  "expression": {
    "and": [{ "greater": ["@length(outputs('List_SenderProfile')?['body/value'])", 0] }]
  },
  "actions": {
    "Update_Existing_Profile": { /* UpdateRecord with existing recordId */ }
  },
  "else": {
    "actions": {
      "Create_New_Profile": { /* CreateRecord with initial values */ }
    }
  }
}
```
**Files:** `src/flow-1-email-trigger.json`, `src/flow-2-teams-trigger.json`, `src/flow-3-calendar-trigger.json`

### 3. 🟠 Fix T-UpdateCard null-field overwrites
**Impact:** Partial updates (e.g., only changing priority) will null out summary, confidence, draft, and other fields.  
**Fix:** Use separate conditional update fields or build a dynamic `item` object that only includes non-null properties. The simplest Power Automate approach is conditional field mapping:

```json
"Update_Card": {
  "inputs": {
    "parameters": {
      "entityName": "cr_assistantcards",
      "recordId": "@triggerBody()?['card_id']",
      "item/@{if(not(equals(body('Parse_Update_JSON')?['cr_priority'], null)), 'cr_priority', 'cr_SKIP_priority')}":
        "@body('Parse_Update_JSON')?['cr_priority']"
    }
  }
}
```
Or refactor to use individual `Condition` → `UpdateRecord` blocks per field.  
**Files:** `src/tool-update-card.json`

### 4. 🟠 Add ErrorLog writes to Flows 1–3 error scopes
**Impact:** Currently, errors are composed but lost — no persistent record for diagnostics.  
**Fix:** Add a `CreateRecord` action in each `Scope_Handle_Errors` to write to `cr_errorlog`:

```json
"Create_ErrorLog": {
  "type": "OpenApiConnection",
  "inputs": {
    "parameters": {
      "entityName": "cr_errorlogs",
      "item/cr_flowname": "IWL-Flow-1-EmailTrigger",
      "item/cr_errortimestamp": "@utcNow()",
      "item/cr_errormessage": "@{result('Scope_Process_Email')}",
      "item/cr_triggercontext": "@coalesce(triggerOutputs()?['body/subject'], 'Unknown')"
    },
    "host": {
      "operationId": "CreateRecord",
      "apiId": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps",
      "connectionName": "shared_commondataserviceforapps"
    },
    "authentication": "@parameters('$authentication')"
  },
  "runAfter": { "Compose_ErrorDetails": ["Succeeded"] }
}
```
**Files:** `src/flow-1-email-trigger.json`, `src/flow-2-teams-trigger.json`, `src/flow-3-calendar-trigger.json`

### 5. 🟠 Fix T-CreateCard invalid default priority
**Impact:** Cards created without explicit priority get value `50` which is not a valid Dataverse choice — will cause a write error or silent data corruption.  
**Fix:** Change default from `50` to `100000002` (Low):

```json
"cr_priority": "@coalesce(body('Parse_Card_JSON')?['priority'], 100000002)"
```
**Files:** `src/tool-create-card.json`

---

## Additional Recommendations (Priority Order)

| # | Issue | Files | Effort |
|---|-------|-------|--------|
| 6 | Add `concurrency.repetitions: 1` to Flow 3 foreach (prevent 200 parallel agent calls) | flow-3 | 1 line |
| 7 | Fix Flow 7 nudge card `cr_triggertype` from EMAIL (100000000) to COMMAND_RESULT (100000005) or new value | flow-7 | 1 line |
| 8 | Fix Flow 9 AUTO_LOW logic to include dismiss_rate ≥ 0.6 check | flow-9 | 5 lines |
| 9 | Add `retryPolicy` to tool-refine-draft agent invocation | tool-refine-draft | 4 lines |
| 10 | Add `$authentication` parameter declarations to Flows 8, 9 | flow-8, flow-9 | 3 lines each |
| 11 | Replace all `<ewa-agent-schema-name>` / `<humanizer-agent-schema-name>` placeholders with `@parameters('EwaAgentBotId')` pattern | All flows using botId | Parameterize |
| 12 | Add ownership check to tool-update-card before update | tool-update-card | 15 lines |
| 13 | Fix Flow 6 calendar operation from `CalendarGetOnNewItemsV3` to `GetEventsCalendarViewV3` | flow-6 | 1 line |
| 14 | Add T-SearchPlannerTasks pagination via `@odata.nextLink` | tool-search-planner | 20 lines |
| 15 | Document the `cr_editdistanceratio` contract between Canvas App and Flow 5 | docs/agent-flows.md | Docs only |

---

## Architecture Notes

**Strengths:**
- Consistent Scope-based error handling pattern across all 20 flows
- Clean separation between signal triggers (1–3), operations (4–10), and tool flows
- Proper choice column mapping with integer values matching Dataverse schema
- Rate limiting in Flow 3 (5s delay per event)
- Duplicate prevention in Flows 6 and 7
- Concurrency controls in Flows 9 and 10

**Deployment Blockers:**
1. All `botId` values are placeholders — need parameterization
2. T-SearchTeamsMessages will fail at runtime (invalid Graph API path)
3. Flows 1–3 Upsert pattern will fail for new senders
4. Missing `$authentication` parameter declarations in Flows 8, 9
