# Architecture Patterns

**Domain:** Power Platform solution with Copilot Studio agents, PCF React dashboard, Power Automate flows, and Dataverse storage
**Researched:** 2026-02-20

## Recommended Architecture

### System Overview

The Enterprise Work Assistant is a five-layer architecture where each layer has a single responsibility and communicates with adjacent layers through well-defined contracts.

```
[Signal Sources]  -->  [Power Automate Flows]  -->  [Copilot Studio Agents]
                              |                           |
                              v                           v
                        [Dataverse]  <---  [PCF React Dashboard via Canvas App]
```

**Data flows in one direction for writes** (signal -> flow -> agent -> Dataverse) and **one direction for reads** (Dataverse -> Canvas App dataset -> PCF control -> React components). The only bidirectional path is between the Canvas App and Dataverse for write-back actions (dismiss, status updates).

### Component Boundaries

| Component | Responsibility | Communicates With | Boundary Rule |
|-----------|---------------|-------------------|---------------|
| **Power Automate Flows** (x3) | Signal interception, pre-filtering, agent invocation, Dataverse writes | Signal sources (Outlook, Teams, Calendar), Copilot Studio agents, Dataverse | Flows own all external connector orchestration. Agents never call connectors directly. |
| **Main Agent** (Copilot Studio) | Triage, research, confidence scoring, draft generation | Flow (receives input variables, returns JSON), Humanizer Agent (via flow or connected agent) | Agent owns all LLM reasoning. Returns a single JSON object per invocation. Never writes to Dataverse. |
| **Humanizer Agent** (Copilot Studio) | Tone calibration and draft polishing | Main Agent (receives draft_payload), Flow (returns plain text) | Single-purpose downstream processor. Receives structured input, returns plain text. |
| **Dataverse Table** (cr_assistantcard) | Persistent storage of agent output cards | Power Automate (writes), Canvas App/PCF (reads), Canvas App (write-back for dismiss) | Single table with discrete columns for filtering + full JSON blob for rendering. |
| **Canvas App** | Filter UI, dataset binding, event routing, navigation | Dataverse (data source), PCF control (embedded component) | Canvas App owns filter state (dropdowns) and dataset queries. Delegates rendering to PCF. |
| **PCF Virtual Control** | React-based card rendering, user interaction capture | Canvas App (receives dataset + filter inputs, emits output events) | PCF owns all visual rendering. Never calls Dataverse directly. Communicates via properties only. |

### Data Flow

#### Write Path (Signal Processing)

```
1. Signal arrives (email/Teams message/calendar event)
   |
2. Power Automate trigger fires
   |
3. Flow pre-filters (skip no-reply, bots, low-value events)
   |
4. Flow composes PAYLOAD + USER_CONTEXT
   |
5. Flow invokes Main Agent via Copilot Studio connector
   |-- Input: TRIGGER_TYPE, PAYLOAD, USER_CONTEXT, CURRENT_DATETIME
   |-- Output: Single JSON object matching output-schema.json
   |
6. Flow parses JSON (simplified schema -- no oneOf)
   |
7. Flow checks triage_tier != SKIP
   |-- If SKIP: terminate (no Dataverse write)
   |
8. Flow maps string enum values -> Choice integer values
   |
9. Flow writes row to Dataverse (cr_assistantcard)
   |-- CRITICAL: Sets Owner field to triggering user's AAD Object ID
   |-- Stores raw JSON in cr_fulljson column
   |-- Maps discrete fields to Choice columns for server-side filtering
   |
10. Flow checks humanizer handoff condition
    |-- tier=FULL AND confidence>=40 AND trigger!=CALENDAR_SCAN
    |
11. Flow invokes Humanizer Agent (string-serialized draft_payload)
    |
12. Flow updates Dataverse row with humanized_draft
```

#### Read Path (Dashboard Rendering)

```
1. Canvas App loads, queries Dataverse
   |-- Filter: Owner.'Primary Email' = User().Email
   |-- Sort: createdon Descending
   |
2. Dataset bound to PCF control's cardDataset property
   |
3. PCF updateView() fires with new context
   |-- Increments datasetVersion counter
   |-- Passes dataset + filter props to AppWrapper
   |
4. useCardData hook processes dataset
   |-- Iterates sortedRecordIds
   |-- For each record: parses cr_fulljson (full agent output)
   |-- Falls back to discrete columns for display fields
   |-- Reads cr_humanizeddraft from discrete column
   |-- Skips malformed records (try/catch)
   |
5. React component tree renders
   |-- App -> FilterBar + CardGallery (gallery mode)
   |-- App -> CardDetail (detail mode)
   |-- FluentProvider wraps everything for theming
```

#### Action Path (User Interactions)

```
1. User clicks card in gallery
   |-- CardItem.onClick -> App.handleSelectCard
   |-- App sets viewState to detail mode
   |-- PCF onSelectCard callback fires
   |-- PCF sets selectedCardId, calls notifyOutputChanged()
   |-- Canvas App receives selectedCardId via output property
   |
2. User clicks "Edit & Copy Draft"
   |-- CardDetail -> onEditDraft callback
   |-- PCF sets editDraftAction, calls notifyOutputChanged()
   |-- Canvas App OnChange handler detects editDraftAction
   |-- Canvas App navigates to scrEditDraft screen
   |
3. User clicks "Dismiss Card"
   |-- CardDetail -> onDismissCard callback
   |-- PCF sets dismissCardAction, calls notifyOutputChanged()
   |-- Canvas App OnChange handler detects dismissCardAction
   |-- Canvas App patches Dataverse row (Card Status -> SUMMARY_ONLY)
   |-- Reset: PCF clears action outputs after getOutputs() returns
```

---

## Patterns to Follow

### Pattern 1: PCF Virtual Control Lifecycle (React)

**What:** Virtual controls implement `ComponentFramework.ReactControl<IInputs, IOutputs>` instead of the standard `ComponentFramework.StandardControl`. The `updateView` method returns a `React.ReactElement` instead of manipulating DOM directly. The platform manages the React tree -- no `ReactDOM.render` or `ReactDOM.unmountComponentAtNode` calls needed.

**When:** All new PCF controls that use React should use the virtual control pattern. It shares the platform's React and Fluent UI instances, reducing bundle size and eliminating version conflicts.

**Lifecycle:**
```
init() -> Called once. Store notifyOutputChanged callback.
          Set up trackContainerResize. Create stable callback
          references (handlers that don't change identity).

updateView() -> Called on every property/dataset change.
                Returns React.ReactElement.
                DO NOT do side effects here.
                Increment dataset version counter to force
                useMemo recomputation.

getOutputs() -> Called by platform after notifyOutputChanged().
                Return current output property values.
                Reset one-shot action values after reading.

destroy() -> Called when control removed.
             Cleanup handled by React (virtual control).
             No ReactDOM.unmountComponentAtNode needed.
```

**Example (stable callback pattern from this solution):**
```typescript
// In init() -- create once, never recreated
this.handleSelectCard = (cardId: string) => {
    this.selectedCardId = cardId;
    this.notifyOutputChanged();
};

// In updateView() -- pass stable reference, not new arrow function
return React.createElement(AppWrapper, {
    dataset: dataset,
    onSelectCard: this.handleSelectCard,  // stable reference
    // ...
});
```

**Confidence:** HIGH -- Verified against Microsoft Learn official documentation for React controls and platform libraries.

### Pattern 2: Dataset Version Counter for useMemo Invalidation

**What:** The PCF platform mutates the dataset object in place -- the reference never changes. React's `useMemo` cannot detect changes by reference equality alone. A version counter incremented in each `updateView()` call forces recomputation.

**When:** Any PCF dataset control using React hooks to transform dataset records.

**Example:**
```typescript
// In the PCF class
private datasetVersion: number = 0;

public updateView(context): React.ReactElement {
    this.datasetVersion++;  // Force hook to recompute
    return React.createElement(AppWrapper, {
        dataset: context.parameters.cardDataset,
        datasetVersion: this.datasetVersion,
    });
}

// In the hook
export function useCardData(dataset: DataSet, version: number): AssistantCard[] {
    return React.useMemo(() => {
        // Transform dataset records into typed objects
    }, [version]);  // Recompute when version changes
}
```

**Confidence:** HIGH -- This is a documented necessity because the PCF dataset API mutates objects in place. The official best practices confirm that `updatedProperties` or similar mechanisms are needed to detect changes.

### Pattern 3: Dual-Storage Schema (Discrete Columns + Full JSON Blob)

**What:** Store the complete agent JSON output in a single Multiline Text column (`cr_fulljson`, 1MB max), while also extracting key filterable dimensions into discrete Choice columns. The Canvas App and PCF read the full JSON for rendering; Dataverse queries filter on the discrete columns for server-side efficiency.

**When:** The agent output contains nested objects, arrays, and polymorphic fields (like `draft_payload` which can be null, string, or object) that cannot be represented as discrete Dataverse columns, but you need server-side filtering on a few key dimensions.

**Why not all-discrete columns:** Dataverse has no native JSON column type, and complex nested structures (verified_sources array, draft_payload union type) would require multiple related tables, adding unnecessary complexity. The dual-storage pattern avoids schema drift -- when the agent schema evolves, only `cr_fulljson` changes; the discrete filter columns remain stable.

**Discrete columns in this solution:**
- `cr_triagetier` (Choice) -- for excluding SKIP items
- `cr_triggertype` (Choice) -- for filtering by signal source
- `cr_priority` (Choice) -- for filtering by urgency
- `cr_cardstatus` (Choice) -- for filtering by processing state
- `cr_temporalhorizon` (Choice) -- for filtering calendar items by time
- `cr_confidencescore` (WholeNumber) -- for confidence-based queries
- `cr_humanizeddraft` (Multiline Text) -- populated asynchronously after initial write

**Confidence:** MEDIUM -- This is the pattern chosen for this solution and is sound engineering practice. The alternative (fully normalized related tables) is valid for large-scale systems but adds deployment complexity disproportionate to the use case.

### Pattern 4: SKIP Items Never Written to Dataverse

**What:** When the agent triages an item as SKIP, the flow terminates without writing a Dataverse row. This avoids the constraint that `cr_itemsummary` (the primary name column, which is required and cannot be null in Dataverse) would need a placeholder value for SKIP items whose `item_summary` is null in the agent output.

**When:** Any Copilot Studio agent pattern where the agent can decide "no action needed" for an input signal.

**Confidence:** HIGH -- The primary name attribute in Dataverse is always required (ApplicationRequired level). Verified via Microsoft Learn entity metadata documentation.

### Pattern 5: Choice Column Integer Mapping in Power Automate

**What:** Copilot Studio agents output string enum values (e.g., "EMAIL", "FULL", "High"). Dataverse Choice columns store integer option values (e.g., 100000000, 100000002, 100000000). Power Automate flows must map strings to integers using `if()` expression chains before writing to Dataverse.

**When:** Any flow that bridges between a Copilot Studio agent's string output and Dataverse Choice columns.

**Example:**
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

**Confidence:** HIGH -- This is the standard Dataverse pattern. Choice columns store integers internally; the display labels are metadata. Verified across multiple sources.

### Pattern 6: Simplified Parse JSON Schema (No oneOf/anyOf)

**What:** Power Automate's Parse JSON action does not support JSON Schema `oneOf` or `anyOf` keywords. When the canonical agent output schema uses `oneOf` for polymorphic fields like `draft_payload`, a simplified schema must be used in flows where those fields use `{}` (empty schema, accepts anything) instead.

**When:** Any Power Automate flow parsing Copilot Studio agent output that contains union/polymorphic types.

**Canonical schema (for development/documentation):**
```json
"draft_payload": {
  "oneOf": [
    { "type": "null" },
    { "type": "string" },
    { "type": "object", "properties": { ... } }
  ]
}
```

**Flow-safe schema:**
```json
"draft_payload": {}
```

**Confidence:** MEDIUM -- The `oneOf` limitation is widely reported in Power Automate community forums and is consistent with the platform's JSON Schema subset support. The specific `{}` workaround is the approach used in this solution and documented in agent-flows.md.

### Pattern 7: Row Ownership for Row-Level Security

**What:** Power Automate flows run under the connection owner's identity, not the end user. To enforce per-user data isolation, every "Add a new row" action must explicitly set the Owner field to the triggering user's AAD Object ID (retrieved via "Get my profile V2").

**When:** Any Dataverse table with UserOwned ownership type where flows create records on behalf of different users.

**Confidence:** HIGH -- This is a fundamental Dataverse security model requirement. Without explicit Owner assignment, all rows would belong to the service account running the flow.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Agent Calling Connectors Directly

**What:** Having the Copilot Studio agent use connector actions (Outlook, Teams, Dataverse) directly to write results or send messages.
**Why bad:** Agents should be pure reasoning/generation engines. Side effects in the agent make error handling impossible -- if the agent partially succeeds, you cannot retry or roll back. Flows provide explicit control flow, error scoping, and retry logic.
**Instead:** Agent returns structured JSON. Flow handles all writes, sends, and side effects.

### Anti-Pattern 2: Creating New Arrow Functions in updateView

**What:** Creating new callback functions in `updateView()` that are passed as props to React components.
```typescript
// BAD
public updateView(context): React.ReactElement {
    return React.createElement(App, {
        onSelectCard: (id: string) => {  // new function every render
            this.selectedCardId = id;
            this.notifyOutputChanged();
        }
    });
}
```
**Why bad:** Every `updateView()` call creates new function references, causing all React children to re-render even when props have not meaningfully changed. This defeats React's memoization and causes performance degradation, especially with large datasets.
**Instead:** Create stable callback references once in `init()` and pass them through in `updateView()`.

### Anti-Pattern 3: Storing Complex Nested Data as Discrete Dataverse Columns

**What:** Creating separate Dataverse columns (or related tables) for every field in the agent output, including arrays like `verified_sources` and objects like `draft_payload`.
**Why bad:** Dataverse does not have native JSON or array column types. You would need multiple related tables (VerifiedSources, DraftPayloads), making the schema brittle to agent output changes and complicating both the flow logic and the PCF data retrieval.
**Instead:** Use the dual-storage pattern: store full JSON in one memo column, extract only filterable dimensions as discrete columns.

### Anti-Pattern 4: Calling dataset.refresh() in Response to Every Interaction

**What:** Calling `context.parameters.cardDataset.refresh()` inside event handlers or updateView.
**Why bad:** Each `refresh()` call triggers a full server round-trip to Dataverse, causing visible loading delays and consuming API entitlement. The official Microsoft best practices explicitly warn against unnecessary refresh calls.
**Instead:** Let the Canvas App manage data refresh cadence. The PCF control renders whatever dataset the platform provides.

### Anti-Pattern 5: Using window.localStorage in PCF Controls

**What:** Persisting user preferences, filter state, or cache data in browser localStorage or sessionStorage from within a PCF control.
**Why bad:** Officially unsupported by Microsoft. Data is not secure, not guaranteed available across sessions, and breaks in embedded scenarios (Teams, mobile app). Microsoft's best practices documentation explicitly advises against this.
**Instead:** Use Canvas App variables for transient UI state. Use Dataverse for persistent state.

### Anti-Pattern 6: Deploying Development Builds to Dataverse

**What:** Running `pcf-scripts build` without production mode and importing the resulting solution.
**Why bad:** Development builds include source maps, unminified code, and debugging aids that dramatically increase bundle size and can be blocked from deployment. Microsoft's best practices documentation explicitly warns against this.
**Instead:** Always use production builds for deployment (`npm run build` with production config).

---

## Dataverse Schema Design Patterns

### Table Naming Convention

Per Microsoft Learn documentation (verified 2026-02-11 revision):

| Property | Convention | This Solution |
|----------|-----------|---------------|
| SchemaName | PascalCase, singular, with publisher prefix | `cr_assistantcard` |
| LogicalName | All lowercase, singular | `cr_assistantcard` |
| EntitySetName | Plural of LogicalName (auto-generated) | `cr_assistantcards` |
| DisplayName | Human-readable singular | "Assistant Card" |
| DisplayCollectionName | Human-readable plural | "Assistant Cards" |

**Key rule:** Schema names must be singular. The EntitySetName (used by Web API) is automatically pluralized. The `cr_` prefix comes from the solution publisher's customization prefix.

**Confidence:** HIGH -- Verified against Microsoft Learn "Table definitions in Microsoft Dataverse" documentation updated 2026-02-11.

### Column Naming Convention

| Column Type | SchemaName Pattern | LogicalName | Example |
|-------------|-------------------|-------------|---------|
| Choice (Picklist) | `{prefix}_{descriptivename}` | All lowercase | `cr_triagetier` |
| Text (String) | `{prefix}_{descriptivename}` | All lowercase | `cr_itemsummary` |
| Multiline Text (Memo) | `{prefix}_{descriptivename}` | All lowercase | `cr_fulljson` |
| Whole Number (Integer) | `{prefix}_{descriptivename}` | All lowercase | `cr_confidencescore` |

### Primary Name Column

Every Dataverse table must have a `PrimaryNameAttribute` -- a string column that serves as the human-readable identifier for records. In this solution, `cr_itemsummary` serves as the primary name. This means:

1. It is always required (ApplicationRequired) and cannot be null
2. It appears as the record identifier in lookups and views
3. SKIP items (where item_summary is null) cannot be written to Dataverse

### Choice Column Value Conventions

Dataverse Choice (OptionSet) values start at 100000000 for custom options:

| Column | Option Label | Integer Value |
|--------|-------------|---------------|
| cr_triagetier | SKIP | 100000000 |
| cr_triagetier | LIGHT | 100000001 |
| cr_triagetier | FULL | 100000002 |
| cr_triggertype | EMAIL | 100000000 |
| cr_triggertype | TEAMS_MESSAGE | 100000001 |
| cr_triggertype | CALENDAR_SCAN | 100000002 |
| cr_priority | High | 100000000 |
| cr_priority | Medium | 100000001 |
| cr_priority | Low | 100000002 |
| cr_priority | N/A | 100000003 |
| cr_cardstatus | READY | 100000000 |
| cr_cardstatus | LOW_CONFIDENCE | 100000001 |
| cr_cardstatus | SUMMARY_ONLY | 100000002 |
| cr_cardstatus | NO_OUTPUT | 100000003 |
| cr_temporalhorizon | TODAY | 100000000 |
| cr_temporalhorizon | THIS_WEEK | 100000001 |
| cr_temporalhorizon | NEXT_WEEK | 100000002 |
| cr_temporalhorizon | BEYOND | 100000003 |
| cr_temporalhorizon | N/A | 100000004 |

**Convention note:** 100000000 is the default starting value for custom option sets in Dataverse. The solution uses this standard convention.

---

## Agent Prompt Architecture

### Two-Agent Pipeline

```
[Main Agent]  --draft_payload-->  [Humanizer Agent]
     |                                  |
     | Single JSON object               | Plain text only
     | (structured output mode)         | (no JSON wrapper)
     |                                  |
     v                                  v
  Power Automate stores           Power Automate updates
  cr_fulljson + discrete          cr_humanizeddraft column
  columns in Dataverse            on same Dataverse row
```

**Main Agent responsibilities:**
- Triage classification (SKIP/LIGHT/FULL)
- 5-tier research hierarchy execution
- Confidence scoring (0-100)
- Draft generation (email reply, Teams response, or meeting briefing)
- Output: exactly one JSON object

**Humanizer Agent responsibilities:**
- Tone calibration based on recipient relationship
- Draft type formatting (EMAIL with subject/greeting/close, TEAMS_MESSAGE concise)
- Confidence-aware hedging language
- Output: plain text only (no JSON, no markdown)

**Why two agents instead of one:** Separation of concerns. The main agent specializes in research and structured reasoning. The humanizer specializes in natural language tone calibration. This also allows the humanizer to be swapped or A/B tested independently.

### Prompt-Schema Contract

The main agent's system prompt, the output-schema.json, the dataverse-table.json, and the PCF types.ts must all agree on:

1. **Field names:** `trigger_type`, `triage_tier`, `item_summary`, etc.
2. **Enum values:** Exact string matches (e.g., "EMAIL" not "email", "High" not "HIGH")
3. **Nullability rules:** Which fields can be null and under what conditions (e.g., item_summary is null only for SKIP)
4. **Type constraints:** confidence_score is integer 0-100 (not float, not string)

Any inconsistency between these four artifacts causes runtime failures in the flow (Parse JSON validation) or the PCF control (type assertions).

---

## Power Automate Flow Architecture

### Three Parallel Flows (Not One Combined Flow)

Each signal type has its own dedicated flow:

| Flow | Trigger | Cadence | Special Handling |
|------|---------|---------|-----------------|
| EMAIL | When a new email arrives (V3) | Per-email (Split On enabled) | Pre-filter no-reply senders |
| TEAMS_MESSAGE | When someone is mentioned | Per-mention | Pre-filter bots and self-mentions |
| CALENDAR_SCAN | Recurrence (daily at 7 AM) | Daily batch | Apply to each event, 5-second delay between iterations |

**Why three flows:** Each signal type has a different trigger connector, different payload shape, and different pre-filtering logic. A single flow would require complex branching that is harder to debug and maintain.

### Shared Flow Pattern (Steps 4-12)

All three flows share the same pattern after payload composition:

```
Scope: Process Signal
  |-- Invoke Main Agent (Copilot Studio connector)
  |-- Parse JSON (simplified schema)
  |-- Condition: triage_tier != SKIP
  |     |-- YES:
  |     |     |-- Compose: Map string enums -> Choice integers (x5)
  |     |     |-- Add row to Dataverse (with Owner field)
  |     |     |-- Condition: Humanizer handoff needed?
  |     |     |     |-- YES: Invoke Humanizer Agent
  |     |     |     |        Update Dataverse row (humanized_draft)
  |     |-- NO: Terminate
  |
  (on failure) --> Scope: Handle Error
                     |-- Log/notify
```

### Error Handling

Wrap agent invocation + downstream processing in a Scope action. Add a parallel Scope with "Run after: has failed" for error handling. This pattern provides:
- Isolation: A failure in one step does not prevent error logging
- Visibility: Failed flow runs surface in Power Automate run history
- Recoverability: The error scope can send notifications or log to an error table

---

## PCF Control Internal Architecture

### Component Hierarchy

```
AssistantDashboard (PCF class)
  |-- manages lifecycle, outputs, callbacks
  |
  +-- AppWrapper (functional bridge component)
       |-- calls useCardData hook to transform dataset
       |-- passes typed cards + props to App
       |
       +-- App (main UI component)
            |-- FluentProvider (theme: light/dark auto-detect)
            |-- ViewState: gallery | detail
            |
            +-- [Gallery Mode]
            |     +-- FilterBar (displays active filter badges + count)
            |     +-- CardGallery (maps cards -> CardItem list)
            |           +-- CardItem (per-card: icon, badges, summary, date)
            |
            +-- [Detail Mode]
                  +-- CardDetail (full card view)
                        |-- Priority/confidence/trigger/horizon badges
                        |-- Item summary
                        |-- Low confidence warning (MessageBar)
                        |-- Key findings (parsed bullet list)
                        |-- Research log (pre-formatted)
                        |-- Verified sources (links with tier badges)
                        |-- Draft section (humanized > raw > briefing)
                        |-- Action buttons (Edit & Copy, Dismiss)
```

### State Management

The PCF control uses a minimal state model:

| State | Owner | Persistence |
|-------|-------|-------------|
| View mode (gallery/detail) | React `useState` in App | Transient (resets on updateView) |
| Selected card | React `useState` in App + PCF class field | Transient + output property |
| Filter values | Canvas App dropdowns -> PCF input properties | Canvas App session |
| Card data | Dataverse -> dataset -> useCardData hook | Dataverse persistent |
| Dark mode preference | React hook (matchMedia) | Browser preference |

**No local state persistence in the PCF control.** All persistent state lives in Dataverse. All UI configuration state lives in Canvas App variables. The PCF control is a pure rendering engine.

---

## Scalability Considerations

| Concern | At 50 users | At 1,000 users | At 10,000 users |
|---------|-------------|----------------|-----------------|
| Dataverse storage | Minimal (cards age out) | Configure 30-day retention policy | Retention + archival strategy |
| Flow execution volume | ~150 flow runs/day | ~3,000 flow runs/day | Throttling risk -- stagger calendar scans, increase delay |
| Agent invocations | Copilot Studio capacity sufficient | Monitor consumption-based licensing | May need dedicated capacity allocation |
| PCF dataset loading | No delegation concerns | Add server-side filters to dataset query | Pagination via dataset.paging API |
| Canvas App delegation | Not a factor | Choice column filters not delegable -- acceptable at this scale | Consider model-driven app or custom page for larger datasets |

---

## Build Order Implications

The architecture has a clear dependency chain that dictates build/deploy order:

```
1. Dataverse Table (provision-environment.ps1)
   |-- No dependencies. Must exist before anything else.
   |
2. Security Roles (create-security-roles.ps1)
   |-- Depends on: Dataverse table existing
   |
3. Copilot Studio Agents (manual setup)
   |-- Main Agent: depends on research tool actions being registered
   |-- Humanizer Agent: no dependencies beyond environment
   |-- Must be published before flows can invoke them
   |
4. Power Automate Flows (manual setup per agent-flows.md)
   |-- Depends on: Dataverse table, published agents, connectors
   |-- Test each flow individually before connecting all three
   |
5. PCF Component (deploy-solution.ps1)
   |-- Depends on: npm dependencies, TypeScript compilation
   |-- Independent of Dataverse schema at build time
   |-- Must be imported to environment before Canvas App can use it
   |
6. Canvas App (manual setup per canvas-app-setup.md)
   |-- Depends on: Dataverse table (data source), PCF component (imported)
   |-- Last to deploy because it ties everything together
```

**Remediation pass implication:** For a fix-only pass on existing files, the build order matters less than the **contract alignment order**: fix schemas first (output-schema.json + dataverse-table.json), then prompts, then code, then docs. Schema disagreements cascade into every downstream artifact.

---

## Sources

- [Best practices for code components - Power Apps | Microsoft Learn](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/code-components-best-practices) -- HIGH confidence (official docs, updated 2025-05-07)
- [React controls & platform libraries - Power Apps | Microsoft Learn](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/react-controls-platform-libraries) -- HIGH confidence (official docs, updated 2025-10-10)
- [Table definitions in Microsoft Dataverse - Power Apps | Microsoft Learn](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/entity-metadata) -- HIGH confidence (official docs, updated 2026-02-11)
- [Agent flows overview - Microsoft Copilot Studio | Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-copilot-studio/flows-overview) -- HIGH confidence (official docs, updated 2025-11-21)
- [Dataverse and Model-Driven Apps Standards and Naming Conventions | Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-365/community/cds-and-model-driven-apps-standards-and-naming-conventions) -- MEDIUM confidence (community docs on Microsoft Learn)
- [Apply generative orchestration capabilities - Microsoft Copilot Studio | Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-copilot-studio/guidance/generative-orchestration) -- MEDIUM confidence (guidance doc, Copilot Studio evolving rapidly)
- [Copilot Studio/Power Automate: Call an agent to run during a flow](https://rishonapowerplatform.com/2026/01/20/copilot-studio-power-automate-call-an-agent-to-run-during-a-flow/) -- LOW confidence (community blog, but corroborated by official docs)
