# Second Brain Evolution Roadmap

**Project:** Enterprise Work Assistant → Second Brain
**Baseline:** v1.0 Production Readiness (shipped 2026-02-22)
**Vision:** Transform the Enterprise Work Assistant from a reactive signal processor into a true second brain — one that captures everything, surfaces the right thing at the right time, learns from user behavior, and reduces cognitive load to near zero.
**Planned:** 2026-02-27

---

## Design Principles

1. **Prepare, never act.** The system prepares drafts, briefings, and recommendations. The human decides, edits, and sends. Every sprint preserves this boundary.
2. **Learn from behavior, not configuration.** The system should get smarter from what the user does (send, edit, dismiss, ignore) — not from settings screens.
3. **Compound intelligence.** Each sprint builds on the last. Feedback data from Sprint 1 powers the briefing agent in Sprint 2. The briefing agent feeds the command bar in Sprint 3. Sender intelligence in Sprint 4 refines everything.
4. **Ship incrementally.** Each sprint delivers a complete, usable capability. The system gets meaningfully better after each sprint, not only after all four are done.

---

## Architecture Evolution

```
v1.0 (Current)                          v2.0 (Second Brain)
─────────────────                        ─────────────────────────────────────

Email ──┐                                Email ──────┐
Teams ──┼→ Agent → Dataverse → Dashboard Teams Chat ─┼→ Agent → Dataverse ──→ Dashboard
Cal ────┘                                Calendar ───┤    ↑ feedback loop        ↑
                                         Doc Share ──┤    │                      │
                                         Tasks ──────┘    │               Command Bar
                                                          │                      │
                                         SenderProfile ───┘               Orchestrator
                                              ↑                            Agent
                                         Feedback ←── CardOutcome ←── User Actions
                                              │
                                         Daily Briefing Agent ──→ Briefing Card
                                              │
                                         Staleness Monitor ──→ Nudge Cards
```

---

## Sprint 1 — Memory Foundation

**Goal:** Give the system a feedback loop so it can learn from user behavior.
**Duration:** ~1 week
**Dependency:** v1.0 stable and deployed

### Why This First

Without behavioral data, the brain can't learn. Every other sprint depends on knowing what the user actually did with each card. This is the equivalent of building the hippocampus before building higher cognition.

### 1.1 Schema Changes

#### New Columns on `cr_assistantcard`

| Column | Logical Name | Type | Description |
|--------|-------------|------|-------------|
| Card Outcome | `cr_cardoutcome` | Choice | What the user did with this card |
| Outcome Timestamp | `cr_outcometimestamp` | DateTime | When the user acted |
| Draft Edit Distance | `cr_drafteditdistance` | WholeNumber (0-100) | How much the user changed the draft before sending (0 = sent as-is, 100 = complete rewrite) |
| Conversation Cluster ID | `cr_conversationclusterid` | Text (200) | Groups related cards by email conversationId, Teams threadId, or subject similarity hash |
| Source Signal ID | `cr_sourcesignalid` | Text (500) | Original email internetMessageId, Teams message ID, or calendar event ID — for deduplication and threading |

#### CardOutcome Choice Values

| Label | Value | Meaning |
|-------|-------|---------|
| PENDING | 100000000 | Default — user hasn't acted yet |
| SENT_AS_IS | 100000001 | User sent the draft without edits |
| SENT_EDITED | 100000002 | User sent the draft after editing |
| DISMISSED | 100000003 | User explicitly dismissed the card |
| EXPIRED | 100000004 | Card aged out without action (set by staleness flow in Sprint 2) |
| ACKNOWLEDGED | 100000005 | User opened and read but no send action required (LIGHT/CALENDAR cards) |

#### New Table: `cr_senderprofile`

> **Note:** This table is provisioned in Sprint 1 but populated incrementally. Sprint 4 builds the analysis flows that fill it. Sprint 1 starts with a simple write: every time a card is created, upsert the sender into `cr_senderprofile` with a last-seen timestamp and increment the signal count.

| Column | Logical Name | Type | Description |
|--------|-------------|------|-------------|
| Sender Email | `cr_senderemail` | Text (320) | Primary column, unique per user |
| Sender Display Name | `cr_senderdisplayname` | Text (200) | Last known display name |
| Signal Count | `cr_signalcount` | WholeNumber | Total signals received from this sender |
| Response Count | `cr_responsecount` | WholeNumber | Times user responded (SENT_AS_IS + SENT_EDITED) |
| Average Response Hours | `cr_avgresponsehours` | Decimal | Mean hours between signal arrival and user action |
| Last Signal Date | `cr_lastsignaldate` | DateTime | Most recent signal from this sender |
| Sender Category | `cr_sendercategory` | Choice | AUTO_HIGH / AUTO_MEDIUM / AUTO_LOW / USER_OVERRIDE |
| Is Internal | `cr_isinternal` | Boolean | Whether sender is within the tenant |

### 1.2 Flow Changes

#### Modify Existing Flows (EMAIL, TEAMS_MESSAGE, CALENDAR_SCAN)

1. **Add `cr_conversationclusterid`** to the "Add a new row" action:
   - EMAIL: Use `conversationId` from the trigger payload
   - TEAMS_MESSAGE: Use `threadId` (replyToId) from the trigger payload
   - CALENDAR_SCAN: Use a hash of `subject + organizer` (normalized, lowercased)

2. **Add `cr_sourcesignalid`** to the "Add a new row" action:
   - EMAIL: Use `internetMessageId` from the trigger payload
   - TEAMS_MESSAGE: Use the message ID from the trigger
   - CALENDAR_SCAN: Use the event ID from the Outlook connector

3. **Add `cr_cardoutcome`** with default value `100000000` (PENDING)

4. **Upsert sender to `cr_senderprofile`** after the Dataverse card write:
   - Use a "Get rows" action filtered by `cr_senderemail` = sender email
   - If exists: Update row (increment `cr_signalcount`, update `cr_lastsignaldate`)
   - If not: Add new row with initial values (`cr_signalcount` = 1, `cr_sendercategory` = AUTO_MEDIUM)

#### New Flow: Card Outcome Tracker

> **Trigger:** When a row is modified in Dataverse (cr_assistantcard table), filtered to changes on `cr_cardoutcome` column.

This flow fires when the Canvas app updates a card's outcome and performs downstream bookkeeping:

1. **If outcome = SENT_AS_IS or SENT_EDITED:**
   - Calculate response time: `outcometimestamp - createdon`
   - Update the sender's `cr_senderprofile`: increment `cr_responsecount`, recalculate `cr_avgresponsehours`

2. **If outcome = SENT_EDITED:**
   - The `cr_drafteditdistance` is set by the Canvas app (see 1.3 below)

3. **If outcome = DISMISSED:**
   - No sender profile update (dismissal is ambiguous — could mean low-value sender OR low-value topic)

### 1.3 Canvas App / PCF Changes

#### Track User Actions

Update the existing `onDismissCard` and `onEditDraft` callbacks to write outcome data back to Dataverse:

- **Dismiss button:** Patch the card row with `cr_cardoutcome = DISMISSED`, `cr_outcometimestamp = Now()`
- **Send button (new):** After the user finalizes a draft, Patch with `cr_cardoutcome = SENT_AS_IS` or `SENT_EDITED`, plus `cr_outcometimestamp = Now()`
- **Edit distance calculation:** When the user modifies a draft and sends it, compute a simple Levenshtein ratio between the original humanized draft and the final text. Store as 0-100 in `cr_drafteditdistance`. This can be a lightweight Power Fx calculation or a Compose action in a helper flow.
- **Card opened (ACKNOWLEDGED):** When the user expands a LIGHT or CALENDAR card, Patch with `cr_cardoutcome = ACKNOWLEDGED`

#### New PCF Props

Add to `AppProps` in `types.ts`:

```typescript
onSendDraft: (cardId: string, finalText: string, editDistance: number) => void;
onAcknowledgeCard: (cardId: string) => void;
```

### 1.4 Provisioning Script Updates

- Update `provision-environment.ps1` to create the new columns on `cr_assistantcard` and the new `cr_senderprofile` table
- Update `create-security-roles.ps1` to add `cr_senderprofile` permissions (UserOwned, same RLS pattern)
- Update `audit-table-naming.ps1` to verify the new columns/table

### 1.5 Deliverables Checklist

- [ ] Schema: New columns added to `dataverse-table.json`
- [ ] Schema: New `sender-profile-table.json` created
- [ ] Schema: `output-schema.json` unchanged (agent output contract is stable)
- [ ] Provisioning: `provision-environment.ps1` updated
- [ ] Provisioning: `create-security-roles.ps1` updated
- [ ] Flows: All 3 existing flows updated with cluster ID, signal ID, default outcome
- [ ] Flows: Sender profile upsert added to all 3 flows
- [ ] Flow: New "Card Outcome Tracker" flow created
- [ ] PCF: `types.ts` updated with new callback props
- [ ] PCF: `CardDetail.tsx` updated with Send and Acknowledge actions
- [ ] Canvas App: New Patch() formulas for outcome tracking
- [ ] Tests: Unit tests for edit distance calculation
- [ ] Docs: Updated `dataverse-table.json` notes section

---

## Sprint 2 — Daily Briefing Agent

**Goal:** Synthesize across all open cards to produce a prioritized daily action plan.
**Duration:** ~1 week
**Dependency:** Sprint 1 (needs CardOutcome and ConversationClusterID)

### Why This Second

This is the first feature that makes the system feel proactive rather than reactive. Instead of the user browsing cards and deciding what to do, the system tells them: "Here are the 5 things that matter today, in order." This is where the second brain starts *thinking* across signals.

### 2.1 New Agent: Daily Briefing Agent

**Location:** `prompts/daily-briefing-agent-prompt.md`

**Input contract:**

```json
{
  "open_cards": [/* Array of AssistantCard JSON objects with cr_cardoutcome = PENDING */],
  "stale_cards": [/* Cards with cr_cardoutcome = PENDING older than threshold */],
  "today_calendar": [/* Today's calendar events for temporal context */],
  "sender_profiles": [/* SenderProfile rows for senders appearing in open_cards */],
  "user_context": "DisplayName, JobTitle, Department",
  "current_datetime": "ISO 8601"
}
```

**Processing logic the prompt must encode:**

1. **Cluster related cards.** Group cards sharing the same `cr_conversationclusterid` into threads. Present threads as single items with the most recent card as the lead.

2. **Rank by composite score.** For each item/thread, compute a priority rank from:
   - Card priority (High > Medium > Low)
   - Sender importance (from `cr_senderprofile`: response rate, average response time)
   - Staleness (hours since creation with no action — older = more urgent)
   - Calendar correlation (is there a meeting today/tomorrow with this sender or topic?)
   - Confidence score (higher confidence = more actionable = higher rank)

3. **Produce a structured briefing.** Output format:

```json
{
  "briefing_type": "DAILY",
  "briefing_date": "2026-02-28",
  "total_open_items": 12,
  "action_items": [
    {
      "rank": 1,
      "card_ids": ["id1", "id2"],
      "thread_summary": "CFO budget review request — 2 related emails, 48hrs without response",
      "recommended_action": "Reply to Sarah's email with updated figures",
      "urgency_reason": "Your avg response time to Leadership is 4hrs; this is 48hrs overdue",
      "related_calendar": "Budget Review meeting tomorrow 2 PM"
    }
  ],
  "fyi_items": [/* Lower-priority items that need no action but user should know about */],
  "stale_alerts": [
    {
      "card_id": "id5",
      "summary": "Compliance doc review from US Bank — 5 days with no action",
      "recommended_action": "Review or delegate to team member"
    }
  ],
  "day_shape": "You have 4 meetings today (2 external). 3 action items need responses before your 2 PM call with Northwind."
}
```

4. **Day shape narrative.** A 1-2 sentence summary that tells the user what their day looks like and what's most critical. This is the "second brain talking to you" moment.

**Output:** Single JSON object. Stored in Dataverse as a special card with `cr_triggertype = DAILY_BRIEFING` (new choice value).

### 2.2 New Flow: Daily Briefing Flow

**Trigger:** Recurrence — Daily at 7:00 AM (user's timezone), weekdays only

**Actions:**

1. **Get open cards** — Query Dataverse: `cr_cardoutcome = PENDING` AND owner = current user, ordered by `createdon desc`, top 50
2. **Get stale cards** — Query Dataverse: `cr_cardoutcome = PENDING` AND `createdon < addHours(utcNow(), -24)` AND `cr_priority != N/A`, top 20
3. **Get today's calendar** — Office 365 Outlook: Get events for today
4. **Get sender profiles** — Query `cr_senderprofile` for all senders appearing in open cards
5. **Compose input JSON** — Assemble the input contract
6. **Invoke Daily Briefing Agent** — Copilot Studio "Execute Agent and wait"
7. **Parse JSON** — Simplified schema for briefing output
8. **Write briefing card to Dataverse** — New row with `cr_triggertype = DAILY_BRIEFING`

### 2.3 New Flow: Staleness Monitor

**Trigger:** Recurrence — Every 4 hours, weekdays only

**Actions:**

1. **Get overdue cards** — Query: `cr_cardoutcome = PENDING` AND `cr_priority = High` AND `createdon < addHours(utcNow(), -24)`
2. **For each overdue card:**
   - Check if a nudge card already exists for this source signal ID (avoid duplicate nudges)
   - If not: Create a nudge card in Dataverse with `cr_cardstatus = LOW_CONFIDENCE` and `cr_itemsummary = "Reminder: [original summary] — [X] hours without action"`
3. **Expire abandoned cards** — Update cards where `cr_cardoutcome = PENDING` AND `createdon < addDays(utcNow(), -7)` to `cr_cardoutcome = EXPIRED`

### 2.4 Schema Changes

#### New Choice Value on `cr_triggertype`

| Label | Value |
|-------|-------|
| DAILY_BRIEFING | 100000003 |

#### New Choice Value on `cr_cardstatus`

| Label | Value |
|-------|-------|
| NUDGE | 100000004 |

### 2.5 PCF Changes

#### Briefing Card Renderer

New component: `BriefingCard.tsx` — renders the daily briefing in a distinct visual format:
- Day shape narrative at the top (prominent, different visual weight than regular cards)
- Numbered action items with "Jump to card" links
- FYI section (collapsible)
- Stale alerts section with amber/red indicators

The briefing card should be pinned to the top of the gallery when present (filter by today's date).

### 2.6 Deliverables Checklist

- [ ] Prompt: `daily-briefing-agent-prompt.md` written with full input/output contract and few-shot examples
- [ ] Schema: New choice values added to `cr_triggertype` and `cr_cardstatus`
- [ ] Schema: Briefing output schema documented
- [ ] Flow: Daily Briefing Flow created and tested
- [ ] Flow: Staleness Monitor flow created and tested
- [ ] Agent: Daily Briefing Agent created in Copilot Studio, published
- [ ] PCF: `BriefingCard.tsx` component created
- [ ] PCF: Gallery updated to pin briefing card at top
- [ ] Canvas App: Updated to display briefing cards
- [ ] Tests: Unit tests for BriefingCard component

---

## Sprint 3 — Command Bar (Conversational Interface)

**Goal:** Add a natural language command surface to the dashboard so the user can talk to their work.
**Duration:** ~1.5 weeks
**Dependency:** Sprint 2 (command bar queries open cards and briefings)

### Why This Third

The command bar transforms the dashboard from a notification inbox into an interactive work surface. It's the interface that makes the second brain feel like a *partner* rather than a *feed*. It depends on Sprints 1-2 because the most valuable commands operate on behavioral data (Sprint 1) and synthesized views (Sprint 2).

### 3.1 New Agent: Orchestrator Agent

**Location:** `prompts/orchestrator-agent-prompt.md`

**Role:** Conversational agent that can read across the user's card data, synthesize, refine drafts, and create follow-up actions. This agent is invoked interactively (not by a scheduled flow) via a Power Automate instant flow triggered from the Canvas app.

**Capabilities (tool actions):**

| Capability | Implementation | Description |
|-----------|----------------|-------------|
| Query Cards | Dataverse query action | Search open cards by keyword, sender, date range, priority |
| Summarize Thread | LLM reasoning | Synthesize all cards in a conversation cluster into a narrative |
| Refine Draft | Humanizer Agent (connected) | Iteratively edit a draft based on user instruction |
| Create Reminder | Dataverse write action | Create a new card with future timestamp as a self-reminder |
| Look Up Sender | Dataverse query on `cr_senderprofile` | Return interaction history with a specific person |
| Cross-Reference Calendar | Office 365 Outlook action | Find meetings related to a topic or person |

**Example interactions:**

```
User: "What needs my attention right now?"
→ Queries PENDING cards, ranks by composite score, returns top 5 with reasons

User: "Summarize everything about Northwind Traders this week"
→ Queries cards by cluster ID matching Northwind, synthesizes across all

User: "Make the draft for Sarah's email more concise and add the Q3 numbers"
→ Retrieves the card, passes current draft + instruction to Humanizer, returns updated draft

User: "Remind me to follow up on the compliance review Friday morning"
→ Creates a new card with cr_triggertype = SELF_REMINDER, temporal_horizon = THIS_WEEK

User: "How often do I respond to Tom Reed? What's my average response time?"
→ Queries cr_senderprofile for Tom Reed, returns stats

User: "What should I prep for my 2 PM meeting?"
→ Queries today's calendar for 2 PM meeting, cross-references cards mentioning attendees or related topics
```

**Input:** Natural language text from the command bar
**Output:** Natural language response (rendered in the response panel) + optional side effects (card updates, new cards created)

### 3.2 New Flow: Command Execution Flow

**Trigger:** Instant (manually triggered from Canvas app via `PowerAutomate.Run()`)

**Input:** Command text (string), User ID (string), Current Card ID (string, optional — for context-aware commands)

**Actions:**

1. **Get user profile** — Office 365 Users
2. **Compose context** — Current card JSON (if provided), recent briefing summary, user context string
3. **Invoke Orchestrator Agent** — Pass command text + context
4. **Return response** — The flow response feeds back to the Canvas app

**Important:** This flow runs synchronously from the Canvas app's perspective. The user types a command, the app calls `PowerAutomate.Run()`, and displays the response when it returns. Timeout should be set to 120 seconds to accommodate multi-step agent reasoning.

### 3.3 PCF Changes

#### New Component: `CommandBar.tsx`

**Layout:**

```
┌──────────────────────────────────────────────────────────┐
│ ┌──────────────────────────────────────────────┐ [Send] │
│ │ Type a command...                             │        │
│ └──────────────────────────────────────────────┘        │
│                                                          │
│ ┌──────────────────────────────────────────────────────┐│
│ │ Response panel (scrollable)                          ││
│ │                                                      ││
│ │ "You have 3 high-priority items..."                  ││
│ │                                                      ││
│ │ [Jump to card: CFO email] [Jump to card: QBR prep]   ││
│ └──────────────────────────────────────────────────────┘│
│                                                          │
│ Quick actions: [What's urgent?] [Draft status] [My day] │
└──────────────────────────────────────────────────────────┘
```

**Behavior:**
- Text input with Enter-to-send (or Send button)
- Loading state while waiting for flow response (spinner + "Thinking...")
- Response rendered as markdown-ish plain text with card links
- Quick action chips for common commands (configurable)
- Conversation history within the session (cleared on app close — not persisted)
- Context awareness: if a card is currently expanded in the detail view, the command bar automatically includes it as context

#### New PCF Props

```typescript
onExecuteCommand: (command: string, currentCardId: string | null) => Promise<string>;
```

The Canvas app implements this by calling `PowerAutomate.Run()` on the Command Execution Flow and returning the response string.

#### Integration into App.tsx

The command bar is a persistent bottom panel — visible in both gallery and detail views. In gallery view, it has no card context. In detail view, it includes the current card ID for context-aware commands.

### 3.4 Schema Changes

#### New Choice Values

| Table | Column | Label | Value |
|-------|--------|-------|-------|
| `cr_assistantcard` | `cr_triggertype` | SELF_REMINDER | 100000004 |
| `cr_assistantcard` | `cr_triggertype` | COMMAND_RESULT | 100000005 |

### 3.5 Deliverables Checklist

- [ ] Prompt: `orchestrator-agent-prompt.md` with full capability spec and few-shot examples
- [ ] Agent: Orchestrator Agent created in Copilot Studio with tool actions registered
- [ ] Agent: Humanizer Agent connected as a sub-agent (for draft refinement commands)
- [ ] Flow: Command Execution Flow (instant trigger) created and tested
- [ ] Schema: New choice values added
- [ ] PCF: `CommandBar.tsx` component created
- [ ] PCF: `App.tsx` updated with command bar integration
- [ ] Canvas App: `PowerAutomate.Run()` integration for command execution
- [ ] Tests: Unit tests for CommandBar component
- [ ] Tests: Integration test for command → flow → agent → response round-trip

---

## Sprint 4 — Sender Intelligence & Adaptive Triage

**Goal:** Use accumulated behavioral data to personalize triage, surface sender patterns, and continuously improve accuracy.
**Duration:** ~1.5 weeks
**Dependency:** Sprint 1 (CardOutcome data must be accumulating for at least 2-3 weeks)

### Why This Last

This sprint requires historical behavioral data to be meaningful. By Sprint 4, the system has been tracking card outcomes (Sprint 1) for weeks, the user has been interacting with briefings (Sprint 2) and commands (Sprint 3), and the `cr_senderprofile` table has real data. Now the system can actually learn.

### 4.1 New Flow: Sender Profile Analyzer

**Trigger:** Recurrence — Weekly (Sunday evening)

**Actions:**

1. **Query all card outcomes from the past 30 days** — Join cards with sender profiles
2. **For each sender with ≥ 3 signals:**
   - Calculate response rate: `(SENT_AS_IS + SENT_EDITED) / total signals`
   - Calculate average response time
   - Calculate dismiss rate: `DISMISSED / total signals`
   - Calculate edit distance average (for senders where drafts were edited)
3. **Auto-categorize senders:**
   - Response rate > 80% AND avg response time < 8hrs → `AUTO_HIGH`
   - Response rate 40-80% OR avg response time 8-24hrs → `AUTO_MEDIUM`
   - Response rate < 40% OR dismiss rate > 60% → `AUTO_LOW`
4. **Update `cr_senderprofile`** rows with new stats and category (unless `cr_sendercategory = USER_OVERRIDE`)

### 4.2 Main Agent Prompt Enhancement

**Modify `main-agent-system-prompt.md`** to accept an optional `SENDER_PROFILE` input variable:

```
{{SENDER_PROFILE}}    : JSON object with sender stats from cr_senderprofile (or null if first-time sender)
                        { "signal_count": 47, "response_rate": 0.92, "avg_response_hours": 3.2,
                          "sender_category": "AUTO_HIGH", "is_internal": true }
```

**Updated triage rules:**

- If `sender_category = AUTO_HIGH` → Bias toward FULL tier (lower the threshold for upgrading LIGHT → FULL)
- If `sender_category = AUTO_LOW` → Bias toward LIGHT tier (higher threshold needed to reach FULL)
- If `sender_category = USER_OVERRIDE` → Always respect the user's explicit categorization
- If `sender_category = null` (first-time sender) → Use existing signal-based triage (no bias)

**Updated confidence scoring:**

- If `avg_response_hours < 6` for this sender and the card is `> 12hrs old`, add urgency weight to the confidence score
- If `draft_edit_distance` averages > 70 for this sender's cards, reduce confidence by 10 points (the user consistently rewrites drafts for this sender — the agent's drafting is less calibrated here)

### 4.3 Flow Changes

**Modify all 3 existing flows** to pass sender profile data to the agent:

1. After the pre-filter, **query `cr_senderprofile`** for the sender's email
2. If found, serialize as JSON string and pass as `SENDER_PROFILE` input variable
3. If not found, pass `null`

### 4.4 Command Bar Enhancement

Add sender intelligence commands to the Orchestrator Agent:

```
User: "Who are my most important contacts this month?"
→ Queries cr_senderprofile ordered by response_rate * signal_count, returns top 10

User: "I always want to prioritize emails from Sarah Chen"
→ Updates cr_senderprofile for Sarah Chen: cr_sendercategory = USER_OVERRIDE (mapped to AUTO_HIGH)

User: "Show me senders I've been ignoring"
→ Queries cr_senderprofile where dismiss_rate > 60%, returns list with context

User: "How accurate have my drafts been for external clients?"
→ Queries cards where recipient_relationship = "External client", computes avg edit distance
```

### 4.5 Confidence Calibration Dashboard

Add a new view to the PCF component (accessible via command bar or a settings gear):

- **Predicted vs. actual accuracy:** Chart showing agent confidence score vs. actual card outcome (SENT_AS_IS = accurate, heavy edit = less accurate)
- **Triage accuracy:** % of FULL cards that were acted on vs. FULL cards that were dismissed
- **Draft quality trend:** Average edit distance over time (should decrease as the system improves)
- **Top senders by engagement:** Visual ranking of most-responded-to contacts

This is an analytics view, not an operational view. It helps the user understand how well their second brain is performing.

### 4.6 Deliverables Checklist

- [ ] Flow: Sender Profile Analyzer (weekly) created and tested
- [ ] Prompt: `main-agent-system-prompt.md` updated with SENDER_PROFILE input and adaptive triage rules
- [ ] Flows: All 3 existing flows updated to pass sender profile data
- [ ] Agent: Orchestrator Agent updated with sender intelligence commands
- [ ] PCF: Confidence calibration dashboard component
- [ ] Tests: Unit tests for sender categorization logic
- [ ] Docs: Updated deployment guide with Sprint 4 configuration

---

## Input Coverage Expansion (Cross-Cutting — Any Sprint)

These additional signal sources can be added independently at any point. Each follows the same pattern as the existing flows: trigger → compose payload → invoke agent → write to Dataverse.

| Signal Source | Trigger | Priority | Notes |
|--------------|---------|----------|-------|
| Teams 1:1 Chats | "When a new chat message is added" | High | Highest-value untracked signal. Requires Graph `/me/chats` or Teams connector. Add pre-filter to exclude bot messages and self-messages. |
| Document Sharing | SharePoint "When a file is shared with me" or Graph notification | Medium | Catches "someone shared a doc with you" signals that don't always generate email. |
| Planner Task Assignment | "When a task is assigned to me" (Planner connector) | Medium | Explicit action requests. Map to FULL tier by default. |
| Approvals | "When an approval is requested" (Approvals connector) | Medium | Time-sensitive action items. Always FULL tier. |
| Teams Missed Calls | Graph notification | Low | Low frequency but high signal. Requires Graph subscriptions. |

**Recommendation:** Add Teams 1:1 Chats as part of Sprint 1 or 2. The others can be added opportunistically.

---

## GitHub Copilot Development Strategy

GitHub Copilot accelerates every sprint. Here's the specific integration plan:

### Repository Setup

1. **Create `.github/agents/work-assistant-dev.agent.md`** — Custom agent that knows this project's architecture, naming conventions (`cr_` prefix, Choice value patterns, PCF virtual control constraints, platform React 16.14.0 limitations), and file organization.

2. **Create `.github/skills/`** for reusable patterns:
   - `pcf-component/SKILLS.md` — How to scaffold a new PCF React component in this project (types, CSS, test file, manifest entry)
   - `dataverse-schema/SKILLS.md` — How to add columns/tables following project conventions (JSON schema → provisioning script → types.ts → flow mapping)
   - `copilot-studio-prompt/SKILLS.md` — How to write agent prompts following project patterns (input contract, processing logic, output contract, few-shot examples)

### Per-Sprint Usage

| Sprint | Copilot Accelerators |
|--------|---------------------|
| Sprint 1 | Generate provisioning script updates for new columns/table. Generate TypeScript interface updates. Scaffold unit tests for edit distance calculation. |
| Sprint 2 | Draft the Daily Briefing Agent prompt (then manually refine). Generate `BriefingCard.tsx` scaffold from types. Generate flow expression chains for Dataverse queries. |
| Sprint 3 | Major PCF work — `CommandBar.tsx`, response panel, quick action chips. Generate Canvas app Power Fx formulas for `PowerAutomate.Run()`. Scaffold the Orchestrator Agent prompt. |
| Sprint 4 | Generate sender analysis queries. Update main agent prompt with adaptive triage rules. Build calibration dashboard charts. |

### Copilot CLI Workflow

For each sprint:

```bash
# Start with the custom agent that knows the project
copilot --agent=work-assistant-dev

# Use the coding agent for scaffolding
# (assign issues, let it create PRs, review and merge)

# Use agent mode in VS Code for iterative PCF development
# (edit → build → test cycle with live feedback)
```

---

## Risk Register

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Agent compute cost at scale (100+ emails/day × 4 sprints of features) | High | High | Sprint 1: Add lightweight pre-classifier before full agent invocation. Monitor Copilot Studio capacity consumption weekly. |
| Dataverse table growth (thousands of rows/user/month) | Medium | High | Implement 30-day retention policy for EXPIRED/DISMISSED cards. Archive to secondary table for analytics. Sprint 2 staleness flow handles expiration. |
| MCP tool timeouts in research tier | Medium | Medium | Add per-tool timeout handling in flows. The agent prompt already says "proceed to next tier on failure" but flows need explicit timeout actions. |
| Canvas app delegation limit (500 records) | Medium | Medium for power users | Flagged in v1.0 as known limitation. Sprint 2 mitigates by having the briefing agent synthesize across cards (user doesn't need to scroll 500 cards if the briefing tells them what matters). |
| Command bar latency (synchronous flow → agent → response) | Medium | High | Set 120s timeout. Add loading state in PCF. Consider caching recent briefing data in Canvas app variables so common queries ("what's urgent?") can be answered partly from cache. |
| Sender categorization cold start (no data for weeks) | Low | Certain | Sprint 1 provisions the table but Sprint 4 populates it. During Sprints 1-3, sender intelligence is absent. The system works fine without it — just not personalized yet. |

---

## Success Metrics

| Metric | Baseline (v1.0) | Sprint 2 Target | Sprint 4 Target |
|--------|-----------------|-----------------|-----------------|
| Cards acted on / total cards | Unknown (no tracking) | Measurable | > 70% |
| Average draft edit distance | Unknown | Measurable | < 30 (agent drafts need minimal editing) |
| Time from signal to user action | Unknown | Measurable | < 4hrs for High priority |
| Triage accuracy (FULL cards acted on) | Unknown | > 60% | > 80% |
| User opens dashboard proactively | Reactive only | Daily (briefing pull) | Multiple times/day (command bar usage) |

---

## Timeline Summary

| Sprint | Duration | Key Deliverable | Builds On |
|--------|----------|----------------|-----------|
| Sprint 1 — Memory Foundation | ~1 week | Feedback loop, outcome tracking, sender table, conversation clustering | v1.0 |
| Sprint 2 — Daily Briefing Agent | ~1 week | Morning briefing, staleness alerts, proactive nudges | Sprint 1 |
| Sprint 3 — Command Bar | ~1.5 weeks | Conversational command surface, Orchestrator Agent, draft refinement | Sprint 2 |
| Sprint 4 — Sender Intelligence | ~1.5 weeks | Adaptive triage, sender profiling, confidence calibration | Sprint 1 data + Sprint 3 |

**Total estimated duration:** ~5 weeks from start of Sprint 1 to Sprint 4 complete.

---

*Planned: 2026-02-27*
*Baseline: v1.0 Production Readiness (shipped 2026-02-22)*
*Next action: Review this plan, then begin Sprint 1 schema changes*
