<!-- Status: PROPOSAL · Last validated: 2026-03-08 -->

# Agent-to-UI Contract — Intelligent Work Layer

Proposal-status contract defining the data shapes that flow between IWL agents and the UI surface. This contract enables a shared priority queue, scenario-specific work surfaces, human approval workflows, and background agent activity visibility.

> **Status:** This is a proposal contract under validation. It does not replace the current `AssistantCard` / `AppProps` interface. The existing card-based UI remains the shipped baseline. See the adapter layer (`src/models/adapters.ts`) for the bridge between current and proposed models.

---

## 1. Top-Level View Model

The orchestration layer returns a single `WorkOsViewModel` for the current user/session:

| Field | Type | Description |
|-------|------|-------------|
| `schemaVersion` | `"1.0"` | Contract version |
| `session` | `SessionContext` | User identity, locale, timezone |
| `shell` | `ShellState` | Quiet mode, interruption policy, current moment |
| `scenario` | `ScenarioState` | Day-flow moments and progress |
| `queue` | `WorkQueueItem[]` | Priority-sorted work items |
| `surfaces` | `SurfaceRegistry` | Scenario-specific surface models |
| `activities` | `AgentActivityItem[]` | Agent activity timeline |
| `copilot` | `CopilotPanelModel` | Contextual prompts and actions |
| `launchPoints` | `LaunchPoint[]` | Source app deep links |

TypeScript definition: `src/models/workOsViewModel.ts`
JSON Schema: `schemas/workos/work-os-view-model.schema.json`

---

## 2. Producer Responsibilities

Each agent in the IWL MARL pipeline produces specific model types:

| Agent | Produces | Contributes to |
|-------|----------|----------------|
| **Triage Agent** | `MessageDecisionItem[]` | `WorkQueueItem[]` (draft replies, quick replies) |
| **Planning Agent** | Focus blocks, carry-forward items | `WorkQueueItem[]`, `FocusLaneModel` |
| **Briefing Agent** | `BriefingPackModel` | `WorkQueueItem[]` (briefing entries) |
| **Calendar Agent** | Schedule-aware signals | `WorkQueueItem[]`, scenario metadata |
| **Review Agent** | `CloseOfDayReviewModel` | End-of-day metrics and carry-forward |
| **Copilot Orchestrator** | `CopilotPanelModel` | Contextual prompts, starter actions |

---

## 3. Governance and Approval Rules

Every `WorkQueueItem` carries a `GovernanceState` object:

```typescript
type GovernanceState = {
  approvalRequired: boolean;
  approvalState: "not_required" | "pending" | "approved" | "rejected";
  reviewability: "full_preview" | "summary_preview" | "no_preview";
  interventionAllowed: boolean;
  auditVisible: boolean;
  rationaleVisible: boolean;
};
```

**Enforcement rules:**
- Items with `approvalRequired: true` or `state: "NeedsApproval"` must NOT be auto-executed by the UI
- Items with `reviewability: "full_preview"` render the complete draft for review
- Items with `interventionAllowed: true` show edit/override controls

**Current mapping:** The adapter (`src/models/adapters.ts`) derives governance from the existing confidence score — items with confidence < 90 require approval.

---

## 4. Adapter Layer

The adapter bridges the current `AssistantCard` model to the proposed `WorkQueueItem`:

| Function | From → To | Key mappings |
|----------|-----------|--------------|
| `toWorkQueueItem` | `AssistantCard` → `WorkQueueItem` | Priority "N/A" → "Low", CardStatus/Outcome → WorkItemState, DraftPayload → DraftArtifact, confidence → governance |
| `toAgentActivityItem` | `CommandSideEffect` → `AgentActivityItem` | Bridges the CommandBar activity log |
| `toShellState` | `(quietMode, heldCount)` → `Partial<ShellState>` | Maps FilterBar quiet toggle |
| `toDraftArtifact` | `DraftPayload` → `DraftArtifact` | Humanized draft preferred over raw |

Source: `src/models/adapters.ts`

---

## 5. Scenario Moments

The Work OS organizes the day into five moments:

| Moment ID | Label | Purpose |
|-----------|-------|---------|
| `morning_briefing` | Morning briefing | Start-of-day summary with priorities and focus windows |
| `protected_focus` | Protected focus | Deep work with quiet mode and interruption filtering |
| `triage_interruption` | Triage interruption | Critical items that break through quiet mode |
| `meeting_briefing` | Meeting briefing | Pre-meeting context assembly |
| `end_of_day_review` | End-of-day review | Close open loops, carry forward to tomorrow |

**Current state:** The shipped UI implements these concepts through `BriefingType` (`MORNING` | `END_OF_DAY` | `MEETING_PREP`) and the quiet mode toggle, but not as a unified scenario rail.

---

## 6. File Index

### TypeScript Models (`src/models/`)

| File | Key types |
|------|-----------|
| `shared.ts` | `SourceSystem`, `PriorityLevel`, `GovernanceState`, `PrimaryAction`, `AgentProducerRef` |
| `scenario.ts` | `ScenarioMomentId`, `ScenarioState`, `ShellState`, `SessionContext` |
| `queue.ts` | `WorkQueueItem` |
| `messaging.ts` | `MessageDecisionItem`, `InterruptionWorkbenchModel` |
| `briefings.ts` | `BriefingPackModel`, `BriefingSection` |
| `review.ts` | `CloseOfDayReviewModel`, `FocusLaneModel`, `ResumeMarker` |
| `activity.ts` | `AgentActivityItem` |
| `copilot.ts` | `CopilotPanelModel` |
| `workOsViewModel.ts` | `WorkOsViewModel`, `SurfaceRegistry` |
| `adapters.ts` | `toWorkQueueItem`, `toAgentActivityItem`, `toShellState` |
| `index.ts` | Barrel re-exports |

### JSON Schemas (`schemas/workos/`)

| File | Validates |
|------|-----------|
| `shared-defs.schema.json` | All shared $defs (12 types) |
| `work-queue-item.schema.json` | `WorkQueueItem` payloads |
| `message-decision-item.schema.json` | `MessageDecisionItem` payloads |
| `briefing-pack.schema.json` | `BriefingPackModel` payloads |
| `close-of-day-review.schema.json` | `CloseOfDayReviewModel` payloads |
| `agent-activity-item.schema.json` | `AgentActivityItem` payloads |
| `copilot-panel.schema.json` | `CopilotPanelModel` payloads |
| `work-os-view-model.schema.json` | Full `WorkOsViewModel` payloads |

### Mock Data (`src/mock-data/` + `mock-api/`)

Realistic typed fixtures for all surfaces. Use `mockWorkOsViewModel` for the full payload or import individual mocks per surface.

---

## 7. Non-Goals (Current Phase)

- Replacing `AssistantCard` / `AppProps` as the shipped data contract
- Building v4 components (ScenarioRail, FocusLane, InterruptionWorkbench)
- Zustand/MSW state management
- Production schema validation against Dataverse payloads
- MCP server integration or agent registry wiring

These are future-state items tracked in `architecture-enhancements.md`.
