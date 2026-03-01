# Phase 14: Sender Intelligence Completion - Context

**Gathered:** 2026-02-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire sender behavioral data into the main triage agent as a formal input variable, fix race conditions in concurrent sender profile updates by switching to Dataverse Upsert with alternate key, replace the simplified 0/1 edit distance boolean with a true Levenshtein edit distance ratio computed PCF-side, and install/configure ESLint react-hooks plugin with all violations fixed.

</domain>

<decisions>
## Implementation Decisions

### Edit Distance Computation
- Compute Levenshtein edit distance in the PCF React component (CardDetail) when the user clicks Send
- Use an inline Levenshtein implementation (~15 lines) — do NOT add fast-levenshtein as a production dependency
- Output as normalized ratio 0-100: `(levenshtein(original, edited) / max(len(original), len(edited))) * 100`, rounded to integer
- 0 = identical (sent as-is), 100 = complete rewrite
- Add `editDistanceRatio` to the existing `handleSendDraft` JSON payload: `{cardId, finalText, editDistanceRatio}`
- Canvas App passes editDistanceRatio to the Card Outcome Tracker flow, which stores it in `cr_avgeditdistance`
- The Power Automate flow's existing 0/1 boolean Compose expression is replaced — it now receives the pre-computed ratio from the PCF

### Sender Profile Data Shape
- Pass exactly the 7 fields already referenced in the agent prompt: `{signal_count, response_rate, avg_response_hours, dismiss_rate, avg_edit_distance, sender_category, is_internal}`
- All 3 trigger flows (Email, Teams, Calendar) fetch and pass the sender profile before invoking the agent
- First-time senders (no profile row): pass `SENDER_PROFILE = null` — the agent prompt already handles this case
- Register SENDER_PROFILE as a formal named input variable on the Copilot Studio agent topic, not injected into the prompt template string

### Upsert Migration
- Switch ALL flows that write to cr_senderprofile to use Dataverse Upsert with alternate key (cr_senderemail_key)
- This includes: Card Outcome Tracker (3 branches: SENT_AS_IS, SENT_EDITED, DISMISSED) AND trigger flows (initial profile creation on first signal)
- Upsert writes only outcome-specific fields — SENT_AS_IS updates response count + avg response hours; SENT_EDITED also updates avg edit distance; DISMISSED updates dismiss count
- Do NOT recalculate all computed fields on every write — only touch fields relevant to the specific outcome

### ESLint react-hooks
- Install `eslint-plugin-react-hooks` as a devDependency
- Enable both rules as errors: `react-hooks/rules-of-hooks: error`, `react-hooks/exhaustive-deps: error`
- Fix ALL existing hook dependency violations in the codebase — do not suppress with eslint-disable comments
- The codebase must pass lint with zero hook-related errors after this phase

### Claude's Discretion
- Exact Levenshtein implementation approach (iterative matrix vs. two-row optimization)
- How to structure the sender profile lookup query in each trigger flow (OData filter expression details)
- Whether to extract the Levenshtein utility into a shared utils file or keep it co-located with CardDetail
- Specific refactoring needed to fix any hook dependency violations discovered during ESLint setup

</decisions>

<specifics>
## Specific Ideas

- The `cr_avgeditdistance` column is WholeNumber (0-100), which aligns perfectly with the normalized ratio format
- The agent prompt's sender-adaptive confidence adjustment already checks `avg_edit_distance > 70` — the ratio format feeds directly into this logic
- The `handleSendDraft` in `index.ts:83` already has a comment noting "Canvas app uses isEdited to set SENT_AS_IS vs SENT_EDITED outcome" — this is the integration point for passing editDistanceRatio
- The senderprofile-table.json already declares the alternate key `cr_senderemail_key` on `cr_senderemail` — the Dataverse table just needs to use it via Upsert instead of List+Create

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `enterprise-work-assistant/schemas/senderprofile-table.json`: Full table schema with alternate key already defined
- `enterprise-work-assistant/prompts/main-agent-system-prompt.md`: Agent prompt with SENDER_PROFILE input variable and triage/confidence logic already written
- `enterprise-work-assistant/src/AssistantDashboard/index.ts`: `handleSendDraft` at line 83 — current send handler that builds `{cardId, finalText}` JSON
- `enterprise-work-assistant/src/AssistantDashboard/components/CardDetail.tsx`: Component where user edits drafts and clicks Send — has access to original humanized draft and edited text
- `enterprise-work-assistant/src/.eslintrc.json`: Existing ESLint config with @typescript-eslint parser and plugin

### Established Patterns
- Power Automate flows use Compose actions for intermediate calculations (running averages, etc.)
- PCF outputs to Canvas App via `notifyOutputChanged()` with JSON-stringified payloads
- Dataverse queries use OData filter expressions with owner ID scoping for user-owned tables
- The Card Outcome Tracker flow branches on outcome type (SENT_AS_IS/SENT_EDITED, DISMISSED, EXPIRED)

### Integration Points
- PCF `handleSendDraft` → Canvas App `OnChange` → Power Automate Card Outcome Tracker flow
- Trigger flows → Copilot Studio agent invocation (where SENDER_PROFILE needs to be passed)
- Card Outcome Tracker flow → cr_senderprofile table (where Upsert replaces List+Update/Create)
- `agent-flows.md` Flow 5 (Card Outcome Tracker) — primary flow spec that needs Upsert rewrite
- `agent-flows.md` Flows 1-3 (Email, Teams, Calendar triggers) — need sender profile lookup + pass to agent

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 14-sender-intelligence-completion*
*Context gathered: 2026-02-28*
