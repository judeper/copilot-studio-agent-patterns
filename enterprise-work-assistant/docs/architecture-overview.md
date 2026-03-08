<!-- Status: IMPLEMENTED (v3.0) · Last validated: 2026-03-08 -->

# Architecture Overview — Intelligent Work Layer

Current-state architecture document describing what is deployed today. For future-state Phase 5 designs, see [`architecture-enhancements.md`](architecture-enhancements.md).

---

## 1. System Identity

The **Intelligent Work Layer (IWL)** is an **Intelligent Work Layer** for Microsoft 365.

- **Augments** Outlook, Teams, and Calendar — does **not** replace them. Users continue working in their familiar apps; IWL intercepts signals and surfaces prepared intelligence.
- **Built entirely on the customer's existing Microsoft investment**: Power Platform, Copilot Studio, Dataverse. No external SaaS dependencies.
- **Core value**: Converts raw signals (emails, messages, calendar events) into triaged, researched, confidence-scored cards with AI-drafted responses — before the user ever has to ask.

---

## 2. Layered Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  SIGNAL SOURCES  (External — not owned by IWL)                      │
│    Outlook (email)  ·  Teams (messages)  ·  Calendar (events)       │
└───────────────────────────────┬─────────────────────────────────────┘
                                │  Signal capture via Power Automate triggers
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  ORCHESTRATION & INFERENCE LAYER                                    │
│    ├─ Power Automate (10 flows)                                     │
│    │    Signal ingestion (Flows 1-3) · Send (Flow 4)                │
│    │    Outcome tracking (Flow 5) · Briefing (Flow 6)               │
│    │    Staleness (Flow 7) · Commands (Flow 8)                      │
│    │    Sender analytics (Flow 9) · Reminders (Flow 10)             │
│    └─ Copilot Studio (17 agents)                                    │
│         MARL pipeline: Triage · Research · Confidence · Draft       │
│         Domain agents: Calendar · Task · Email · Search · Delegation│
│         Utility agents: Router · Validation · Humanizer · Heartbeat │
│         + Orchestrator · Edit Analyzer · Draft Refiner              │
└───────────────────────────────┬─────────────────────────────────────┘
                                │  Store decisions, research, drafts
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  SYSTEM OF RECORD  (Dataverse)                                      │
│    ├─ cr_assistantcard        Card state + research + draft          │
│    ├─ cr_senderprofile        Sender intelligence & behavior         │
│    ├─ cr_episodicmemory       Decision log (what the agent did)      │
│    ├─ cr_semanticknowledge    Knowledge graph (learned facts)        │
│    ├─ cr_userpersona          Communication style preferences        │
│    ├─ cr_briefingschedule     User briefing preferences              │
│    ├─ cr_skillregistry        Custom skill definitions               │
│    ├─ cr_errorlog             Operational error records              │
│    └─ cr_semanticepisodic     Junction (episodic ↔ semantic)         │
└───────────────────────────────┬─────────────────────────────────────┘
                                │  Query + render + interact
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  INTERACTION SURFACE                                                │
│    ├─ Canvas Power App        Data source, filters, event handlers   │
│    └─ PCF React Dashboard     Virtual control (CardGallery,          │
│                                CardDetail, CommandBar, BriefingCard) │
└───────────────────────────────┬─────────────────────────────────────┘
                                │  Optional downstream (feature-flagged)
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  OPTIONAL OUTPUT                                                    │
│    OneNote — write-only, Phase 1                                    │
│    Meeting prep · Daily briefings · Active to-dos                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. System of Record vs. Execution Surface

### Dataverse = System of Record

Durable state. Cards, sender profiles, episodic memory, semantic knowledge. Source of truth for all decisions. Ownership-based row-level security ensures each user sees only their own data.

### Power Automate + Copilot Studio = Orchestration & Inference

Stateless workers. Each flow run is idempotent — it reads from Dataverse, invokes agents, and writes outcomes back. No local storage; no state carried between runs.

### Canvas App + PCF = Interaction Surface

Progressive-disclosure dashboard. Users review, edit, and act on agent-prepared cards. The PCF emits output actions (`onSendDraft`, `onDismissCard`, `onSaveDraft`, `onExecuteCommand`, etc.) that the Canvas app handles via `OnChange` formulas.

### What IWL is NOT

IWL is **not** the system of record for email or calendar — Outlook and Teams remain canonical. IWL creates *derived intelligence* (cards, research, drafts) stored in Dataverse. If a user replies directly from Outlook, the External Action Detection flow (Flow 5) auto-updates the corresponding IWL card outcome.

---

## 4. Agent Pipeline (MARL Architecture)

The Multi-Agent Reinforcement Loop (MARL) processes signals through Flows 1–3:

```
Signal arrives (Email / Teams / Calendar trigger)
  │
  ▼
┌──────────────────┐
│  Triage Agent     │──▶  SKIP → minimal JSON, not persisted
│                   │──▶  LIGHT → summary only, no research
│                   │──▶  FULL → proceed to research
└────────┬─────────┘
         │ FULL
         ▼
┌──────────────────┐
│  Research Agent   │  Multi-tier source scan:
│                   │    Tier 1: Email/Teams history
│                   │    Tier 2: SharePoint/internal wikis
│                   │    Tier 3: Planner/To Do tasks
│                   │    Tier 4: Public web
│                   │    Tier 5: Official documentation
└────────┬─────────┘
         ▼
┌──────────────────┐
│ Confidence Scorer │  Score 0–100 based on evidence strength
└────────┬─────────┘
         │
         ├─ confidence < 40 → LOW_CONFIDENCE card (no draft)
         │
         ▼ confidence ≥ 40
┌──────────────────┐
│  Draft Generator  │  Raw draft grounded in research
└────────┬─────────┘
         ▼
┌──────────────────┐
│  Humanizer Agent  │  Polished draft with tone/relationship context
│ (Connected Agent) │  Calibrated to recipient + user persona
└────────┬─────────┘
         ▼
   AssistantCard stored in Dataverse
```

### Interactive Commands (Flow 8)

```
User command (CommandBar)
  → Router Agent (intent classification + domain routing)
    → Flow Switch dispatches to domain agent:
        EMAIL       → Email Compose Agent
        CALENDAR    → Calendar Agent
        TASK        → Task Agent
        SEARCH      → Search Agent
        DELEGATION  → Delegation Agent
        default     → Orchestrator Agent
    → Result stored as COMMAND_RESULT card
```

---

## 5. Contract Summary

### Trigger Types

| Type | Source | Typical Triage | Draft Generated? |
|------|--------|---------------|-----------------|
| `EMAIL` | Outlook inbox | SKIP / LIGHT / FULL | Yes if FULL + confidence ≥ 40 |
| `TEAMS_MESSAGE` | Teams channel/chat | SKIP / LIGHT / FULL | Yes if FULL + confidence ≥ 40 |
| `CALENDAR_SCAN` | Daily calendar scan | LIGHT / FULL | `PREP_NOTES` (briefing format) |
| `DAILY_BRIEFING` | Scheduled flow (Flow 6) | N/A | Briefing card |
| `SELF_REMINDER` | User-created (Flow 10) | N/A | Reminder card |
| `COMMAND_RESULT` | CommandBar (Flow 8) | N/A | Response card |

> **v3.0 Note:** The `DAILY_BRIEFING` trigger now supports four briefing sub-types via the `BriefingType` enum:
> `MORNING` (start-of-day summary), `DAILY` (standard briefing), `END_OF_DAY` (review + carry-forward),
> and `MEETING_PREP` (enhanced with what-changed, decisions needed, talking points).
> See `types.ts` for `MorningBriefingData`, `EndOfDayData`, and `MorningMetric` interfaces.

### Card State Machine

```
                ┌─── READY             (agent completed, draft available)
                ├─── LOW_CONFIDENCE    (research insufficient, no draft)
[CREATED] ──────┼─── SUMMARY_ONLY     (LIGHT tier, summary only)
                ├─── NO_OUTPUT         (agent error)
                └─── NUDGE             (follow-up reminder)

READY ──────────┬─── SENT_AS_IS       (user sent without editing)
                ├─── SENT_EDITED      (user edited then sent)
                ├─── DISMISSED         (user dismissed)
                └─── EXPIRED           (retention policy / staleness)
```

> **v3.0 Note:** Card state transitions now include visual transition feedback in the
> PCF dashboard. Confidence is displayed as a three-state label — **Ready to send** (≥ 70),
> **Review suggested** (40–69), **Draft only** (< 40) — rather than a raw numeric score.
> The `getConfidenceState()` helper in `constants.ts` maps scores to these states.

### Signal Type → Output Field Matrix

Shows which `output-schema.json` fields are populated for each trigger/tier combination:

| Field | SKIP | LIGHT | FULL (conf < 40) | FULL (conf ≥ 40) | CALENDAR | BRIEFING |
|-------|------|-------|-------------------|-------------------|----------|----------|
| `trigger_type` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `triage_tier` | `SKIP` | `LIGHT` | `FULL` | `FULL` | `FULL` | N/A |
| `item_summary` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `priority` | null | ✓ | ✓ | ✓ | ✓ | N/A |
| `temporal_horizon` | null | null | null | null | ✓ | N/A |
| `research_log` | null | null | ✓ | ✓ | ✓ | N/A |
| `key_findings` | null | null | ✓ | ✓ | ✓ | N/A |
| `verified_sources` | null | null | ✓ | ✓ | ✓ | N/A |
| `confidence_score` | null | null | ✓ | ✓ | ✓ | N/A |
| `card_status` | `NO_OUTPUT` | `SUMMARY_ONLY` | `LOW_CONFIDENCE` | `READY` | `READY` | `READY` |
| `draft_payload` | null | null | null | Humanizer handoff object | Plain-text prep notes | N/A |
| `low_confidence_note` | null | null | ✓ | null | null | null |
| `skip_reason` | ✓ | null | null | null | null | null |

> **Note**: SKIP items are **not** persisted to Dataverse (by design). The DAILY_BRIEFING trigger type uses a separate schema (`briefing-output-schema.json`) with `action_items`, `fyi_items`, and `stale_alerts` arrays.

---

## 6. Source App Integration

| App | Role | Details |
|-----|------|---------|
| **Outlook** | Signal source + action target | New email trigger (Flow 1). Send Email action (Flow 4). |
| **Teams** | Signal source + future reply target | New message trigger (Flow 2). Reply target planned (Flow 12). |
| **Calendar** | Signal source + research source | Daily scan trigger (Flow 3). Meeting context for prep notes. |
| **SharePoint** | Research source | Tier 2 file search via agent tool action. |
| **Planner / To Do** | Research source | Tier 3 task context via agent tool action. |
| **OneNote** | Optional output | Write-only, feature-flagged (Phase 1). Gated by `cr_onenoteenabled` + per-user `cr_onenoteoptout`. |
| **Microsoft Graph** | Organizational context | People API, org chart, contacts for relationship inference. |

### User Experience Model

Users continue to use Outlook and Teams as their **primary tools**. IWL intercepts signals **from** those apps and surfaces prepared cards on the dashboard. If a user acts directly in the source app (e.g., replies from Outlook inbox), the Outcome Tracker flow (Flow 5) detects the external action and auto-updates the corresponding IWL card status to reflect the action taken.

---

## 7. Data Consistency Model

| Aspect | Behavior |
|--------|----------|
| **Consistency** | Eventual. Signal → agent processing → Dataverse write → PCF read. Typical lag < 1–2 seconds. |
| **Concurrency** | No optimistic locking (deferred to Phase 5). Concurrent card edits could race — acceptable for POC. |
| **Delegation** | Canvas app uses Dataverse delegation for filter and sort operations. PCF loads up to 500 records client-side. |
| **Idempotency** | Flow runs are stateless and idempotent. Re-running a flow for the same signal produces the same result. |
| **Retention** | No automated cleanup (known limitation). Implement a scheduled flow to archive/delete cards older than N days based on `cr_createdon`. |

---

## Contract Evolution — Work OS Proposal

The current `AssistantCard` / `output-schema.json` contract remains the shipped baseline. A proposal `WorkOsViewModel` contract (`schemas/workos/work-os-view-model.schema.json`) introduces richer governance, scenario moments, and agent activity models.

### Proposal Artifacts

| Artifact | Location | Purpose |
|----------|----------|---------|
| TypeScript models | `src/models/` | Typed interfaces for all Work OS objects |
| JSON Schemas | `schemas/workos/` | Payload validation for agent-to-UI contract |
| Adapter layer | `src/models/adapters.ts` | Backward-compatible bridge: `AssistantCard` → `WorkQueueItem` |
| Mock data | `src/mock-data/`, `mock-api/` | Typed fixtures for development and testing |
| Contract spec | [`agent-contract.md`](agent-contract.md) | Full specification with governance rules and UI evolution roadmap |

### Compatibility

The adapter layer (`adapters.ts`) maps current Dataverse-sourced `AssistantCard` records to the proposed `WorkQueueItem` shape. This enables gradual adoption — the existing `CardGallery` / `CardDetail` rendering path continues to work unchanged while new surfaces can consume the richer contract.

Key mappings:
- `Priority "N/A"` → `PriorityLevel "Low"`
- `CardStatus` / `CardOutcome` → `WorkItemState` (e.g., READY + confidence ≥ 90 → "Ready")
- `DraftPayload` → `DraftArtifact` (prefers humanized draft)
- Confidence score → `GovernanceState` (< 90 requires approval)

---

## 8. Cross-References

| Topic | Document |
|-------|----------|
| Future-state architecture (Phase 5) | [`architecture-enhancements.md`](architecture-enhancements.md) `<!-- Status: DESIGN (Phase 5) -->` |
| Agent flow build guide (Flows 1–10) | [`agent-flows.md`](agent-flows.md) |
| Deployment checklist | [`deployment-guide.md`](deployment-guide.md) |
| Data governance & PII handling | [`data-governance.md`](data-governance.md) |
| UX patterns & WCAG compliance | [`ux-enhancements.md`](ux-enhancements.md) |
| Learning system (episodic + semantic) | [`learning-enhancements.md`](learning-enhancements.md) |
| OneNote integration (Phase 1–3) | [`onenote-integration.md`](onenote-integration.md) |
| Canvas app + PCF setup | [`canvas-app-setup.md`](canvas-app-setup.md) |
| Agent output contract | [`../schemas/output-schema.json`](../schemas/output-schema.json) |
| Agent-to-UI contract | [`agent-contract.md`](agent-contract.md) |
