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
    "attendees": ["sarah@example.com"],
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

*Last updated: Phase 5 design — not yet implemented.*
