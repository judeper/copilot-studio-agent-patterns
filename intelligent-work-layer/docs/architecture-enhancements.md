# Phase 5 — Architecture Enhancements

Design document covering architectural improvements for scalability, resilience, and cross-solution integration in the Intelligent Work Layer.

> **Status**: Design — not yet implemented. These enhancements build on the v2.2 baseline and assume all Phase 1–4 artifacts (Dataverse tables, agent prompts, Power Automate flows, PCF dashboard) are deployed.

---

## Agent Registry Design

### Purpose

A centralized Dataverse table for dynamic agent discovery, health monitoring, and contract validation. Instead of hard-coding agent references in flows, the Router Agent queries the registry at runtime to discover available domain agents and their capabilities.

### Table: `cr_agentregistry`

| Column | Type | Description |
|--------|------|-------------|
| `cr_agentid` | GUID (PK) | Unique identifier for the agent |
| `cr_agentname` | String (100) | Human-readable agent name (e.g., "Calendar Agent") |
| `cr_agenttype` | Choice | `PIPELINE` · `DOMAIN` · `UTILITY` · `CONNECTED` |
| `cr_version` | String (20) | Semantic version (e.g., "2.2.0") |
| `cr_inputcontract` | Multiline Text (JSON) | JSON Schema defining the agent's expected input |
| `cr_outputcontract` | Multiline Text (JSON) | JSON Schema defining the agent's response shape |
| `cr_healthstatus` | Choice | `HEALTHY` · `DEGRADED` · `OFFLINE` |
| `cr_mcpserverurl` | String (500), nullable | Optional MCP server endpoint for tool-server agents |
| `cr_lasthealthcheck` | DateTime | Timestamp of the most recent health ping |
| `cr_isactive` | Boolean | `true` = eligible for routing; `false` = disabled |

### Usage

The Router Agent queries the registry before dispatching:

```
Filter: cr_isactive eq true and cr_healthstatus ne 'OFFLINE'
Select: cr_agentid, cr_agentname, cr_agenttype, cr_inputcontract, cr_version
```

This enables zero-downtime deployment of new agents — add a registry row, publish the agent, and the Router discovers it on the next invocation.

---

## Router Agent → Flow 8 Switch Pattern

Flow 8 (Command Execution) currently invokes the Orchestrator directly. This enhancement introduces a Router Agent layer that classifies user intent and dispatches to specialized domain agents.

### Flow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│ Flow 8 — Command Execution                                      │
│                                                                  │
│  ┌────────────┐     ┌──────────────┐     ┌───────────────────┐  │
│  │ User       │────▶│ Router Agent │────▶│ Flow Switch on    │  │
│  │ Command    │     │ (intent +    │     │ domain field      │  │
│  │            │     │  domain)     │     └───────┬───────────┘  │
│  └────────────┘     └──────────────┘             │              │
│                                                  │              │
│  ┌───────────────────────────────────────────────┼───────┐      │
│  │                                               ▼       │      │
│  │  EMAIL ──────────────▶ Email Compose Agent            │      │
│  │  CALENDAR ───────────▶ Calendar Agent                 │      │
│  │  TASK ───────────────▶ Task Agent                     │      │
│  │  SEARCH ─────────────▶ Search Agent                   │      │
│  │  DELEGATION ─────────▶ Delegation Agent               │      │
│  │  CARD_MANAGEMENT ────▶ Orchestrator Agent             │      │
│  │  (default) ──────────▶ Orchestrator Agent             │      │
│  │                                                       │      │
│  └───────────────────────────────────────────────────────┘      │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### Router Agent Output

```json
{
  "intent": "schedule_meeting",
  "domain": "CALENDAR",
  "confidence": 0.92,
  "extracted_params": {
    "subject": "Q3 planning sync",
    "attendees": ["sarah@contoso.com"],
    "preferred_time": "next Tuesday afternoon"
  }
}
```

### Domain Agent Tool Limits

Each domain agent has 2–5 tools max to keep prompts focused and reduce latency:

| Domain Agent | Tools |
|-------------|-------|
| Email Compose Agent | ComposeDraft, LookupRecipient |
| Calendar Agent | QueryCalendar, CreateEvent, UpdateEvent |
| Task Agent | CreateTask, QueryTasks, UpdateTask |
| Search Agent | SearchCards, SearchOneNote, SearchSenderProfile |
| Delegation Agent | AssignTask, NotifyDelegate |
| Orchestrator Agent | QueryCards, UpdateCard, CreateCard, RefineDraft, PromoteKnowledge |

---

## Orchestrator Decomposition

### Current State

The Orchestrator Agent has 11 tools, which increases prompt size, latency, and the risk of tool misselection.

### Target State

Decompose cross-domain tools into dedicated Connected Agent calls:

| Current Tool | Target Agent | Rationale |
|-------------|-------------|-----------|
| QuerySenderProfile | People Agent | Sender lookup is a people-domain concern |
| QueryCalendar | Calendar Agent | Calendar queries belong with calendar management |
| QueryOneNote | Search Agent | OneNote search is a search-domain concern |
| UpdateOneNote | Document Agent | Write operations need separate permission scoping |

### Retained on Orchestrator

The Orchestrator retains tools that are core to card management:

- **QueryCards** — Search the user's Assistant Cards
- **UpdateCard** — Modify card status, outcome, or notes
- **CreateCard** — Create a new card (e.g., manual reminders)
- **RefineDraft** — Invoke the Humanizer for draft rewriting
- **PromoteKnowledge** — Elevate a card finding to the knowledge base

### Integration Pattern

Each decomposed tool becomes a Connected Agent invocation:

```
Orchestrator receives "Who sent me the most emails this week?"
  → Orchestrator calls People Agent (Connected Agent)
    → People Agent uses QuerySenderProfile tool
    → Returns sender statistics
  → Orchestrator formats response for user
```

---

## Signal Deduplication Gate

### Problem

Rapid-fire signals (e.g., multiple updates to the same email thread within seconds) can produce duplicate cards for the same conversation.

### Solution

Before agent invocation in Flows 1–3, query Dataverse for a recent card matching the same conversation:

```
Filter: cr_conversationclusterid eq '{signal.conversationId}'
        and cr_createdon gt '@{addMinutes(utcNow(), -5)}'
Top: 1
```

### Flow Integration

Insert this check immediately after the PAYLOAD compose step and before the agent invocation:

```
1. Compose — PAYLOAD
2. List rows — Check for recent duplicate
3. Condition: length(body/value) > 0
   ├── Yes → Terminate (signal already handled)
   └── No  → Continue to agent invocation
```

> **Tuning**: The 5-minute window balances deduplication against legitimate follow-ups. Adjust based on observed signal patterns. For high-volume mailboxes, consider a shorter window (2–3 minutes).

> **Cross-reference**: This addresses [Gap 15: Card Deduplication](../.planning/design-review-productivity-noise.md) from the Productivity & Noise Reduction design review. Priority: P3.

---

## Degraded Mode Fallback

### Problem

If the Copilot Studio agent is unavailable (HTTP 429, 500, or 503), signal processing silently fails and the user loses visibility into incoming items.

### Solution

After 3 retry attempts, create a minimal card with raw signal data so the user can still see and manually handle the item.

### Retry Logic

```
Scope: Invoke Agent with Retry
  ├── Do Until: success OR retryCount >= 3
  │     ├── Execute Agent and wait
  │     ├── Condition: HTTP status in (429, 500, 503)
  │     │     ├── Yes → Increment retryCount, Delay (exponential backoff)
  │     │     └── No  → Set success = true
  └── Condition: success eq false
        └── Yes → Create fallback card
```

### Fallback Card

When all retries are exhausted:

1. **Create minimal card** with raw signal data:
   - `cr_triggerttype` = signal type (EMAIL, TEAMS, CALENDAR)
   - `cr_itemsummary` = subject line or message preview
   - `cr_originalsenderemail` = sender address
   - `cr_cardstatus` = `PENDING_MANUAL`
   - `cr_triagetier` = null (not triaged)
   - `cr_confidencescore` = null

2. **Add processing note**:
   `"AI processing unavailable — manual review required"`

3. **Log error** to `cr_errorlog`:
   - Retry count
   - Last HTTP status code
   - Last error message
   - Flow run ID for correlation

> **Cross-reference**: This addresses [Gap 16: Degraded Mode](../.planning/design-review-productivity-noise.md) from the Productivity & Noise Reduction design review. Priority: P3. Add `PENDING_MANUAL` (value: 100000006) to the `cr_cardstatus` choice column.

---

## Agent Versioning Strategy

### Prompt Versioning

Every agent prompt includes a version header as an HTML comment on the first line:

```markdown
<!-- Agent Version: 2.2.0 -->
# Agent Name — System Prompt
...
```

This version is informational — it does not affect agent behavior but enables auditing and troubleshooting.

### Topic-Level A/B Testing

To test a new prompt version against the current one:

1. Duplicate the Copilot Studio topic (e.g., `Triage Email` → `Triage Email v2`)
2. In the triggering flow, add a condition to split traffic:

```
Condition: mod(ticks(utcNow()), 2) eq 0
  ├── Yes → Invoke topic "Triage Email v2"
  └── No  → Invoke topic "Triage Email"
```

3. Tag output cards with the version used (`cr_agentversion` column) for comparison

### Rollback

Revert a topic to its previous version in Copilot Studio. No schema changes are needed — the output contract is stable across versions.

### Registry Integration

The `cr_agentregistry.cr_version` column tracks the currently deployed version of each agent. Update this value whenever a new prompt version is published.

---

## EPA Integration

### Cross-Solution Link

The Email Productivity Agent (EPA) and Intelligent Work Layer (IWL) share a common signal source — email. This integration connects them via a foreign key relationship.

### Schema

```
cr_followuptracking.cr_relatedcardid  →  cr_assistantcard.cr_cardid
```

The `cr_relatedcardid` column is a lookup (nullable) on the EPA's `cr_followuptracking` table that references the IWL's `cr_assistantcard` table.

### Behavior

When the EPA detects a missing reply on a tracked email:

1. **Query IWL**: Check if an `cr_assistantcard` row exists for the same `cr_conversationclusterid`
2. **If card exists**:
   - Update the existing card with a nudge indicator (`cr_hasnudge = true`)
   - Append nudge details to `cr_processingnotes`
   - Set `cr_relatedcardid` on the EPA tracking row
3. **If no card exists**:
   - Create a new `cr_assistantcard` with `cr_triggertype = FOLLOW_UP_NUDGE`
   - Link the EPA tracking row via `cr_relatedcardid`

### Dashboard Impact

The PCF dashboard can display a nudge badge on cards where `cr_hasnudge eq true`, alerting the user that a follow-up is overdue.

---

## Cost Governance Alerts

### Purpose

Surface Copilot Studio cost alerts directly in the Intelligent Work Layer dashboard, connecting the [Agent Cost Governance — PAYGO](../../agent-cost-governance-paygo/) solution to the card-based workflow.

### New Trigger Type

Add `COST_ALERT` to the `cr_triggertype` choice column (alongside EMAIL, TEAMS, CALENDAR, FOLLOW_UP_NUDGE).

### Signal Flow

```
ARM Budget Alert
  → Logic App (webhook receiver)
    → Power Automate (HTTP trigger)
      → Create AssistantCard
```

### Card Content

| Field | Value |
|-------|-------|
| `cr_triggertype` | `COST_ALERT` |
| `cr_itemsummary` | "Cost alert: {agent_name} has reached {percentage}% of budget" |
| `cr_priority` | HIGH |
| `cr_cardstatus` | `READY` |
| `cr_triagetier` | `FULL` |
| `cr_processingnotes` | JSON with: agent name, current spend, budget threshold, trend direction |

### Power BI Link

The card's `cr_actionurl` field links to the Power BI cost dashboard from the `agent-cost-governance-paygo` solution, giving the user one-click access to detailed cost analysis.

---

## Shared Pattern Library

### Purpose

Reusable prompt fragments that enforce consistent behavior across all agents. Each agent prompt can reference these patterns instead of duplicating rules.

### Directory Structure

```
prompts/
├── patterns/
│   ├── security-constraints.md
│   ├── output-format.md
│   └── error-handling.md
├── main-agent-system-prompt.md
├── orchestrator-agent-prompt.md
├── triage-agent-prompt.md
└── ...
```

### Pattern Files

| File | Purpose |
|------|---------|
| [`security-constraints.md`](../prompts/patterns/security-constraints.md) | Standard security rules all agents must follow |
| [`output-format.md`](../prompts/patterns/output-format.md) | JSON output formatting and validation rules |
| [`error-handling.md`](../prompts/patterns/error-handling.md) | Graceful degradation, retry guidance, error reporting |

### Usage in Agent Prompts

Reference patterns in agent prompt headers:

```markdown
<!-- Agent Version: 2.3.0 -->
<!-- Patterns: security-constraints, output-format, error-handling -->
# Agent Name — System Prompt
```

When composing the final prompt in Copilot Studio, concatenate the referenced pattern files before the agent-specific instructions. This ensures all agents inherit the same security, formatting, and error-handling baseline.

---

## Signal Batching

> **Cross-reference**: [Gap 6: No Signal Batching](../.planning/design-review-productivity-noise.md) · Priority: P1 · Complexity: Medium

### Problem

Every email/Teams message triggers an immediate agent invocation. During a busy morning, 20 emails arrive in 30 minutes → 20 agent runs → 20 cards appear. Even with quiet mode on, the user sees "20 items waiting" and feels overwhelmed.

### Solution

Add a 5-minute batching window to Flows 1–2. Collect signals, deduplicate by sender+subject, then invoke the agent once per batch.

### Flow Integration

Insert batching logic at the start of Flows 1 and 2:

```
1. Signal arrives → Write to a staging table (cr_signalstaging)
2. Delay (5 minutes)
3. Query staging table for all unprocessed signals from same user
4. Group by conversation cluster (sender + subject or conversationId)
5. For each group: pick the latest signal, invoke agent ONCE
6. Mark all signals in the group as processed
```

### Deduplication Within Batch

For email threads, only process the latest message per thread within the window:

```
Filter: cr_conversationclusterid eq '{conversationId}'
         and cr_processedat eq null
OrderBy: cr_receivedat desc
Top: 1
```

### Tuning

- **Window size**: 5 minutes is the default. Can be reduced to 2 minutes for latency-sensitive users or increased to 10 minutes for high-volume mailboxes.
- **Agent invocations saved**: In testing, a 5-minute window reduces agent invocations by 30–50% during peak hours.
- **Queue perception**: The staging delay means cards appear in small batches rather than a continuous stream, which feels calmer to users.

---

## Focus Shield Integration

> **Cross-reference**: [Gap 7: No Focus Session Integration](../.planning/design-review-productivity-noise.md) · Priority: P1 · Complexity: Medium

### Problem

IWL doesn't know when the user is in deep work. Calendar has "Focus Time" blocks and Teams has "Do Not Disturb" — but IWL keeps processing signals at full fidelity during these periods, growing the queue.

### Solution

Before agent invocation in Flows 1–2, check if the user's calendar has a "Focus Time" event in progress. If so, auto-triage all non-URGENT signals to LIGHT tier and defer queue delivery until the focus window ends.

### Detection Logic

```
GET /me/calendarView?startDateTime={now}&endDateTime={now}
    &$filter=categories/any(c: c eq 'Focus Time') or showAs eq 'tentative'
    &$select=subject,start,end,showAs,categories
```

Alternatively, check Teams presence:

```
GET /me/presence
→ Check if activity eq 'DoNotDisturb'
```

### Flow Integration

Insert Focus Shield check in Flows 1–2 after the "Get my profile" step and before agent invocation:

```
1. Get my profile (V2)
2. Query calendar for active Focus Time events
3. Condition: Focus Time active?
   ├── Yes → Set FOCUS_ACTIVE = true in agent payload
   │         Agent auto-downgrades non-urgent items to LIGHT
   │         Set cr_focusshieldactive = true on created card
   └── No  → Set FOCUS_ACTIVE = false (normal triage)
```

### Agent Behavior

When `FOCUS_ACTIVE = true`, the Triage Agent:
- Downgrades FULL → LIGHT for all items that do NOT contain urgency signals (explicit deadlines within 4 hours, escalation language, AUTO_HIGH sender with direct question)
- Sets `triage_reasoning` to include "Downgraded from FULL to LIGHT — Focus Shield active"
- Items meeting urgency criteria remain FULL

### Dataverse Column

`cr_focusshieldactive` (Boolean) on `cr_assistantcard` — enables post-focus-session review: "Show me what was downgraded during my focus time."

---

## LIGHT Tier Auto-Archive Flow

> **Cross-reference**: [Gap 5: LIGHT Tier Card Accumulation](../.planning/design-review-productivity-noise.md) · Priority: P1 · Complexity: Low

### Problem

LIGHT-tier cards (summary-only, no draft) accumulate indefinitely. After a week, the "New Signals" section has 50+ stale items — noise.

### Solution

Implement a 6-hour scheduled flow that marks LIGHT-tier cards with `cr_cardoutcome = EXPIRED` after 48 hours of no interaction.

### Flow Design

```
Trigger: Recurrence — every 6 hours

Steps:
1. List rows from cr_assistantcard where:
   - cr_triagetier eq 100000001 (LIGHT)
   - cr_cardoutcome eq 100000000 (PENDING)
   - createdon lt addHours(utcNow(), -48)
   Top: 100

2. Apply to each:
   - Update row: cr_cardoutcome = EXPIRED (100000004)
   - Update row: cr_outcometimestamp = utcNow()

3. Compose summary: "{count} LIGHT cards auto-archived"
```

### User Opt-Out

Add `cr_autoarchivedisabled` (Boolean) to `cr_userpersona`. When true, the flow skips this user's cards. Default: false (auto-archive enabled).

---

## External Action Detection Enhancement

> **Cross-reference**: [Gap 3: No External Action Detection](../.planning/design-review-productivity-noise.md) · Priority: P0 · Complexity: Medium

### Problem

If a user replies to an email directly in Outlook (bypassing IWL), the card stays in "Action Required" as a phantom task. The user sees work they've already done.

### Solution

Enhance Flow 5 (Card Outcome Tracker) with a 15-minute Sent Items scan that detects external replies and auto-resolves the corresponding cards.

### Detection Flow

```
Trigger: Recurrence — every 15 minutes

Steps:
1. List rows from cr_assistantcard where:
   - cr_cardoutcome eq 100000000 (PENDING)
   - cr_triggertype in (100000000, 100000001) (EMAIL or TEAMS)
   Top: 50

2. For each card:
   a. Extract cr_conversationclusterid (email conversationId)
   b. Query Outlook Sent Items:
      GET /me/mailFolders/sentitems/messages
        ?$filter=conversationId eq '{conversationClusterId}'
                 and sentDateTime gt '{card.createdon}'
        &$top=1&$select=sentDateTime,conversationId

   c. Condition: Sent item found?
      ├── Yes → Update card:
      │         cr_cardoutcome = RESOLVED_EXTERNALLY (100000005)
      │         cr_outcometimestamp = sentItem.sentDateTime
      └── No  → Skip (card remains PENDING)
```

### Edge Cases

- **Forwarded messages**: Match on `conversationId`, not `internetMessageId`, to catch forwards within the same thread
- **Rate limits**: Graph API rate limits at 10,000 requests per 10 minutes per user. The 50-card cap ensures the flow stays well under this limit.
- **Timing window**: Only check sent items after the card's creation time to avoid false matches from pre-existing replies.

---

## Data Retention Automation

> **Cross-reference**: [Gap 17: No Data Retention](../.planning/design-review-productivity-noise.md) · Priority: P3 · Complexity: Low

### Problem

AssistantCards grow indefinitely. After months, the Dataverse table has thousands of resolved cards consuming storage.

### Solution

Implement a weekly scheduled flow that archives cards with a terminal outcome older than 90 days.

### Flow Design

```
Trigger: Recurrence — weekly (Sunday 02:00 UTC)

Steps:
1. List rows from cr_assistantcard where:
   - cr_cardoutcome ne 100000000 (not PENDING)
   - cr_outcometimestamp lt addDays(utcNow(), -90)
   Top: 500

2. Apply to each:
   - Delete row (or set statecode = Inactive if soft-delete preferred)

3. Log to cr_errorlog:
   - Operation: "DATA_RETENTION"
   - Details: "{count} cards archived"
   - Severity: "INFO"
```

### Configuration

- **Retention period**: 90 days (configurable via environment variable or UserPersona setting)
- **Soft vs. hard delete**: Recommend soft delete (statecode = Inactive) for the first 6 months, then hard delete after 180 days total
- **Exclusions**: Cards with `cr_cardoutcome = PINNED` (if Card Pin feature is implemented) are never archived

---

*Last updated: Phase 5 design — not yet implemented.*
