# Phase 7: Documentation Accuracy - Research

**Researched:** 2026-02-21
**Domain:** Technical documentation correctness — Copilot Studio UI paths, Power Automate expressions, connector actions, prerequisites
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Claude decides appropriate depth per section based on complexity (step-by-step where complex, concise where straightforward)
- Text-only — no screenshots or image placeholders
- "Run a prompt" action documentation goes inline in agent-flows.md where contextually relevant, not as a separate section
- Research tool action registration: full steps in deployment guide, brief mention in agent-flows.md with cross-reference link to the deployment guide
- Cover a common patterns set: Choice column integer-to-label mapping, null handling, JSON parsing — the patterns a PA developer actually needs for this solution
- Present as code block with brief explanation of what it does and when to use it
- Use real field names from the solution (triage_tier, priority, confidence_score) — directly copy-pasteable
- PA simplified schema scope: Claude decides whether to show relevant fields only or full schema based on what makes the doc most useful
- Include install commands, not just version numbers
- Cover Windows + macOS platforms (winget/choco + brew)
- List all tools needed: dev tools (Bun, Node.js, .NET SDK) plus Power Platform tools (PAC CLI, Azure CLI) and environment requirements
- Use "tested with" versions (e.g., "Tested with Bun 1.2.x, Node.js 20.x") rather than just minimum versions
- Claude decides per-path whether to use exact menu paths or function-first descriptions with path hints, based on how stable each path is
- Add "Last verified: Feb 2026" per-section dates for UI-dependent instructions so readers know freshness
- Research phase should verify current Copilot Studio UI paths against live Microsoft documentation and release notes

### Claude's Discretion
- Documentation depth per section (step-by-step vs concise reference)
- PA simplified schema scope (relevant fields vs full schema)
- UI path description style per path (exact vs function-first)
- Whether to include a brief troubleshooting section

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DOC-01 | Deployment guide specifies correct Copilot Studio UI path for enabling JSON output mode | Research verified: JSON output is configured in the Prompt builder, not agent settings. The correct path is within a prompt's output settings (select JSON in top-right, configure format). Current deployment guide text is misleading — it references "Settings > Generative AI > Structured outputs" which does not exist. See Finding 1 below. |
| DOC-02 | Agent-flows.md includes concrete PA expression examples for Choice value mapping | Research confirmed: if() expression chains are the standard Power Automate pattern for Choice column mapping. The existing doc has one example for trigger_type but needs complete examples for all five Choice columns using real field names (triage_tier, priority, etc.). See Finding 2. |
| DOC-03 | Agent-flows.md documents how to find and configure the "Run a prompt" action in the Copilot Studio connector | Research clarified a critical distinction: "Run a prompt" (AI Builder) is for running prompts; "Execute Agent" / "Execute Agent and wait" (Microsoft Copilot Studio connector) is for invoking agents. The current doc conflates these. Agent invocation should use "Execute Agent and wait". See Finding 3. |
| DOC-04 | Deployment guide includes research tool action registration guidance | Current deployment guide already has Section 2.4 with a research tools table. Needs review against CONTEXT.md decisions: full steps in deployment guide, brief mention in agent-flows.md with cross-reference. See Finding 4. |
| DOC-07 | Documentation specifies Node.js >= 20 prerequisite | Current deployment guide says "Node.js 18+". Must update to "Node.js >= 20" and add Bun version requirement. Use "tested with" format per user decision. See Finding 5. |
</phase_requirements>

## Summary

This phase corrects six documentation inaccuracies in the deployment guide and agent-flows.md. The research identified the specific corrections needed by cross-referencing Microsoft's current documentation, the project's canonical schema (output-schema.json), and previous phase decisions.

The most impactful finding is the **distinction between "Run a prompt" and "Execute Agent"** — two different Copilot Studio connector actions serving different purposes. The current agent-flows.md incorrectly directs developers to use "Run a prompt" (an AI Builder action for prompt-based text generation) when they should use **"Execute Agent and wait"** (a Microsoft Copilot Studio connector action for invoking full agents). This is a breaking error that would prevent the flows from working.

The second critical fix is the **item_summary nullability** in the PA simplified schema. Phase 1 established that item_summary is always a non-nullable string (even SKIP items get a summary), but the PA simplified schema still declares it as `["string", "null"]`.

**Primary recommendation:** Fix the six issues in order of developer impact: (1) connector action name, (2) item_summary nullability, (3) JSON output UI path, (4) Choice expression examples, (5) prerequisites, (6) research tool registration cross-reference.

## Standard Stack

This phase modifies only Markdown documentation files. No libraries or tools are needed.

### Files to Modify
| File | Changes |
|------|---------|
| `enterprise-work-assistant/docs/deployment-guide.md` | Fix JSON output UI path (Section 2.2), update prerequisites (top section), verify research tool registration (Section 2.4), add "Last verified" dates |
| `enterprise-work-assistant/docs/agent-flows.md` | Fix connector action name throughout, add complete Choice column expression examples, fix item_summary in simplified schema, add "Run a prompt" inline documentation with cross-reference to deployment guide, add "Last verified" dates |

### No New Files
Per CONTEXT.md: "No new documentation files — only corrections and additions to existing docs."

## Architecture Patterns

### Pattern 1: Copilot Studio JSON Output Configuration (DOC-01)

**What:** JSON output is configured per-prompt in Copilot Studio's Prompt builder, not in agent-level settings.

**Current doc says (INCORRECT):**
```
1. In the agent settings, navigate to the AI/model configuration section
   - In newer Copilot Studio versions: Settings → Generative AI → Structured outputs
   - In older versions: Settings → AI capabilities → JSON output
```

**Correct process (per Microsoft Learn docs, last updated 2025-11-07):**
1. Open the prompt in Copilot Studio's Prompt builder
2. In the top-right corner of the prompt response area, select **JSON** as the output format (dropdown next to "Output:")
3. To customize the format, select the **settings icon** to the left of "Output: JSON"
4. By default the format is **Auto detected** — switch to **Custom** by editing the JSON example
5. Paste the required JSON schema example
6. Select **Apply**, then **Test** to verify, then **Save custom**

**Confidence:** HIGH — verified against official Microsoft Learn page (`process-responses-json-output`, doc date 2025-11-07, last commit 2025-11-13).

**Important nuance for this project:** The Enterprise Work Assistant uses an agent with a system prompt and input variables, not a standalone prompt. The JSON output mode described above applies to the **Prompt builder** (creating prompts that can run in agents, flows, and apps). For agents with generative orchestration, the JSON output format is set when the agent's prompt configuration is saved. The deployment guide should describe this using function-first language since the exact UI may evolve: "Configure the agent's prompt to output JSON format" rather than giving a stale settings path.

**Source:** [JSON output - Microsoft Copilot Studio | Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-copilot-studio/process-responses-json-output)

### Pattern 2: Power Automate Choice Column Mapping (DOC-02)

**What:** Power Automate's "Add a new row" action for Dataverse requires integer option values for Choice columns, not string labels. The standard pattern uses nested `if()` expression chains.

**Current doc state:** agent-flows.md has ONE example (trigger_type) but defers the remaining four columns with "Repeat this pattern for Priority, Card Status, Triage Tier, and Temporal Horizon using the values from the Choice Value Mapping table." Per CONTEXT.md, we need directly copy-pasteable examples with real field names.

**Complete set of expressions needed (using real field names from this solution):**

```
// Triage Tier: SKIP=100000000, LIGHT=100000001, FULL=100000002
if(equals(body('Parse_JSON')?['triage_tier'],'SKIP'),100000000,
  if(equals(body('Parse_JSON')?['triage_tier'],'LIGHT'),100000001,100000002))

// Trigger Type: EMAIL=100000000, TEAMS_MESSAGE=100000001, CALENDAR_SCAN=100000002
if(equals(body('Parse_JSON')?['trigger_type'],'EMAIL'),100000000,
  if(equals(body('Parse_JSON')?['trigger_type'],'TEAMS_MESSAGE'),100000001,100000002))

// Priority: High=100000000, Medium=100000001, Low=100000002, N/A=100000003
if(equals(body('Parse_JSON')?['priority'],'High'),100000000,
  if(equals(body('Parse_JSON')?['priority'],'Medium'),100000001,
    if(equals(body('Parse_JSON')?['priority'],'Low'),100000002,100000003)))

// Card Status: READY=100000000, LOW_CONFIDENCE=100000001, SUMMARY_ONLY=100000002, NO_OUTPUT=100000003
if(equals(body('Parse_JSON')?['card_status'],'READY'),100000000,
  if(equals(body('Parse_JSON')?['card_status'],'LOW_CONFIDENCE'),100000001,
    if(equals(body('Parse_JSON')?['card_status'],'SUMMARY_ONLY'),100000002,100000003)))

// Temporal Horizon: TODAY=100000000, THIS_WEEK=100000001, NEXT_WEEK=100000002, BEYOND=100000003, N/A=100000004
if(equals(body('Parse_JSON')?['temporal_horizon'],'TODAY'),100000000,
  if(equals(body('Parse_JSON')?['temporal_horizon'],'THIS_WEEK'),100000001,
    if(equals(body('Parse_JSON')?['temporal_horizon'],'NEXT_WEEK'),100000002,
      if(equals(body('Parse_JSON')?['temporal_horizon'],'BEYOND'),100000003,100000004))))
```

**Additional PA expression patterns needed (per CONTEXT.md: null handling, JSON parsing):**

```
// Null handling — coalesce null confidence_score to 0 for Dataverse integer column
if(equals(body('Parse_JSON')?['confidence_score'], null), 0, body('Parse_JSON')?['confidence_score'])

// JSON parsing — serialize draft_payload object back to string for Copilot Studio input
string(body('Parse_JSON')?['draft_payload'])
```

**Confidence:** HIGH — values verified against `schemas/dataverse-table.json` and existing agent-flows.md Choice Value Mapping table. Expression syntax is standard Power Automate.

### Pattern 3: Copilot Studio Connector Actions — Execute Agent vs. Run a Prompt (DOC-03)

**What:** There are TWO different actions that people confuse:

| Action | Connector | Purpose | Use When |
|--------|-----------|---------|----------|
| **Run a prompt** | AI Builder (Copilot Studio prompt builder) | Runs a Copilot Studio prompt to generate text via GPT | You have a standalone prompt (not a full agent) |
| **Execute Agent** | Microsoft Copilot Studio | Sends a message to a Copilot Studio agent and gets a response | You want to invoke a full agent with system prompt, tools, and orchestration |
| **Execute Agent and wait** | Microsoft Copilot Studio | Same as Execute Agent but waits for completion before proceeding | You need the agent's response before the next flow step (THIS IS OUR CASE) |

**Current doc state (INCORRECT):** agent-flows.md step 4 says:
> Add the **Copilot Studio** connector (search for "Copilot" in the connector list). Select the **"Run a prompt"** action (in some environments this appears as **"Invoke a Copilot Agent"** — the exact label may vary by platform version).

**Correct instruction:** Use the **Microsoft Copilot Studio** connector and select the **"Execute Agent and wait"** action. The "Run a prompt" action is a different feature (AI Builder prompt execution) that does NOT invoke a full Copilot Studio agent.

**Execute Agent and wait — Parameters:**
| Parameter | Key | Required | Description |
|-----------|-----|----------|-------------|
| Agent | Copilot | Yes | Select the agent from dropdown |
| Message | message | No | The text message to send to the agent |
| Conversation ID | x-ms-conversation-id | No | Provide existing conversation ID to resume |
| Environment ID | environmentId | No | Optional environment ID |

**Execute Agent and wait — Returns:**
| Field | Type | Description |
|-------|------|-------------|
| lastResponse | string | The last text response from the agent |
| responses | array of string | All text responses from the agent |
| conversationId | string | Conversation ID for continuation |

**How to pass input variables:** The agent's input variables (TRIGGER_TYPE, PAYLOAD, USER_CONTEXT, CURRENT_DATETIME) are passed via the **message** parameter as a structured prompt. The agent's generative orchestration extracts the values from the message content. Alternatively, if the agent exposes input variables as parameters, they appear as additional fields in the action configuration.

**Important for downstream steps:** The response field is `lastResponse` (not `text` as the current doc assumes from `body('Invoke_agent')?['text']`). The planner should verify this field name and update all references.

**Confidence:** HIGH — verified against official Microsoft Copilot Studio connector reference (learn.microsoft.com/en-us/connectors/microsoftcopilotstudio/, updated 2026-02-06). The "Run a prompt" rename (from "Create text with GPT using a prompt") was confirmed by Microsoft Learn docs (ai-builder/use-a-custom-prompt-in-flow, updated 2026-01-14).

**Sources:**
- [Microsoft Copilot Studio Connector Reference](https://learn.microsoft.com/en-us/connectors/microsoftcopilotstudio/)
- [Use your prompt in Power Automate (AI Builder)](https://learn.microsoft.com/en-us/ai-builder/use-a-custom-prompt-in-flow)
- [Copilot Studio/Power Automate: Call an agent to run during a flow](https://rishonapowerplatform.com/2026/01/20/copilot-studio-power-automate-call-an-agent-to-run-during-a-flow/)

### Pattern 4: Research Tool Action Registration (DOC-04)

**What:** The deployment guide (Section 2.4) already documents research tool registration with a table of actions. Per CONTEXT.md decisions:
- **Deployment guide**: Full steps (already present, needs review)
- **Agent-flows.md**: Brief mention with cross-reference link to deployment guide

**Current state assessment:** Deployment guide Section 2.4 is reasonably complete. The agent-flows.md prerequisites section mentions the agent needs to be published but does NOT mention that research tool actions must be registered.

**What needs to change:**
1. Agent-flows.md prerequisites should add a bullet noting research tool actions must be registered, with a cross-reference: "Research tool actions registered (see [deployment-guide.md](deployment-guide.md), Section 2.4)"
2. Deployment guide Section 2.4 should get a "Last verified: Feb 2026" date

**Confidence:** HIGH — based on reading both files; changes are cross-reference additions only.

### Pattern 5: Prerequisites Update (DOC-07)

**What:** Current prerequisites section says "Node.js 18+" — must update to Node.js >= 20 and add Bun version. Per CONTEXT.md: use "tested with" format, include install commands for Windows + macOS, list all tools.

**Current prerequisites:**
```markdown
- [ ] **PAC CLI** installed (`dotnet tool install --global Microsoft.PowerApps.CLI.Tool`)
- [ ] **Azure CLI** installed (`az` — required for Dataverse API authentication)
- [ ] **Bun** installed (`curl -fsSL https://bun.sh/install | bash` or see https://bun.sh)
- [ ] **Node.js 18+** installed
- [ ] **PowerShell 7+** installed
- [ ] Power Platform environment with Copilot Studio capacity allocated
- [ ] Admin access to the target tenant
```

**Required changes:**
- Node.js: Change "18+" to "20+" (or "Tested with Node.js 20.x, required >= 20")
- Bun: Add version ("Tested with Bun 1.2.x, required >= 1.x")
- Add platform-specific install commands:
  - Bun macOS: `brew install oven-sh/bun/bun`
  - Bun Windows: `powershell -c "irm bun.sh/install.ps1|iex"`
  - Node.js macOS: `brew install node@20`
  - Node.js Windows: `winget install OpenJS.NodeJS.LTS` (or download from nodejs.org)
- Add .NET SDK to the prerequisites (it is already required by deploy-solution.ps1 but not listed)
- Group into categories per CONTEXT.md: dev tools (Bun, Node.js, .NET SDK), Power Platform tools (PAC CLI, Azure CLI), environment requirements

**Why Node.js 20:** Node.js 18 reached end of life on 2025-04-30. Node.js 20 is the current LTS (active until 2026-10-31). The deploy-solution.ps1 script already checks for Node.js without version enforcement, but the documentation should specify the tested/supported version.

**Confidence:** HIGH — Node.js LTS schedule is well-documented. Bun 1.x is the stable line (1.0 released Sep 2023, current latest ~1.3.x).

### Pattern 6: item_summary Nullability Fix (Audit Addition)

**What:** The PA simplified schema in agent-flows.md declares item_summary as `"type": ["string", "null"]` but the canonical schema (output-schema.json) and Phase 1 decisions establish item_summary as a **non-nullable string**.

**Evidence chain:**
1. `output-schema.json` line 31-34: `"item_summary": { "type": "string", ... }` — NOT nullable
2. Phase 1 decision (STATE.md): "item_summary is non-nullable string across all schema files — agent always generates a summary including for SKIP tier"
3. Phase 1 decision (STATE.md): "SKIP items ARE written to Dataverse with brief summary in cr_itemsummary"
4. `dataverse-table.json` line 36-41: `cr_itemsummary` is `"required": true` with type `"Text"`

**Fix:** Change line 39 of agent-flows.md from:
```json
"item_summary": { "type": ["string", "null"] },
```
to:
```json
"item_summary": { "type": "string" },
```

**Confidence:** HIGH — directly verified against canonical schema and Phase 1 decisions.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Choice value mapping | Custom lookup table or variable | Inline `if()` expression chains | PA standard pattern; no variables needed; directly matches Dataverse option set values |
| Null coalescing | Complex condition blocks | `if(equals(x, null), default, x)` | PA's native null check pattern; avoids extra branching |
| JSON serialization | Manual string concatenation | `string()` function | PA's built-in JSON serializer; handles escaping correctly |

**Key insight:** Power Automate expressions are the entire "stack" for this phase. There are no external libraries — only correct use of PA's built-in expression language.

## Common Pitfalls

### Pitfall 1: Confusing "Run a prompt" with "Execute Agent"
**What goes wrong:** Developer adds the AI Builder "Run a prompt" action instead of the Microsoft Copilot Studio "Execute Agent and wait" action. The flow runs a generic prompt instead of invoking the full agent with its system prompt, tools, and orchestration.
**Why it happens:** The names sound similar and both appear when searching for "Copilot" in the connector list. "Run a prompt" was renamed from "Create text with GPT using a prompt" in May 2025, adding to confusion.
**How to avoid:** Explicitly document: search for the **"Microsoft Copilot Studio"** connector (not "AI Builder"), then select **"Execute Agent and wait"**.
**Warning signs:** Agent responses are generic text without the expected JSON schema structure.

### Pitfall 2: Stale UI Paths
**What goes wrong:** Documentation gives exact menu paths (e.g., "Settings > Generative AI > Structured outputs") that no longer exist after a Copilot Studio UI update.
**Why it happens:** Microsoft updates the Copilot Studio UI frequently (monthly or more). Exact menu paths become stale within weeks.
**How to avoid:** Use function-first descriptions with path hints: "Configure the prompt to output JSON format" followed by a path hint in parentheses. Add "Last verified: Feb 2026" dates.
**Warning signs:** Users report they cannot find the described menu item.

### Pitfall 3: Nullable vs. Non-Nullable Schema Mismatch
**What goes wrong:** PA simplified schema declares fields as nullable that the canonical schema declares as non-nullable (or vice versa). This causes Parse JSON to accept null for a field that the downstream Dataverse write requires as non-null.
**Why it happens:** The PA simplified schema was created as a separate artifact and may not have been updated when Phase 1 changed nullability rules.
**How to avoid:** Cross-reference every field's type in the PA simplified schema against output-schema.json and the Phase 1 decisions in STATE.md.
**Warning signs:** Dataverse write failures with "required field is null" errors on SKIP-tier items.

### Pitfall 4: Response Field Name Mismatch
**What goes wrong:** The flow references `body('Invoke_agent')?['text']` but the actual Copilot Studio connector "Execute Agent and wait" action returns `lastResponse` (not `text`).
**Why it happens:** The action was originally prototyped with a different connector version or action name, and the response field name changed.
**How to avoid:** After updating the action from "Run a prompt" to "Execute Agent and wait," verify the response field name in the dynamic content picker and update all downstream references.
**Warning signs:** Null or empty values in the Full JSON Output column.

### Pitfall 5: Missing "Tested With" Version Context
**What goes wrong:** Prerequisites say "Node.js 18+" and a developer uses Node.js 18 (EOL since April 2025), hitting compatibility issues with newer dependencies.
**Why it happens:** Minimum version without a "tested with" anchor gives no signal about what actually works.
**How to avoid:** Use "Tested with Bun 1.2.x, Node.js 20.x" format with both minimum requirement and tested version.
**Warning signs:** Mysterious build failures on older runtimes.

## Code Examples

### Complete Choice Column Mapping (Compose Actions)

Each Choice column needs its own Compose action in the flow. These are directly copy-pasteable:

**Compose — Triage Tier Value:**
```
if(equals(body('Parse_JSON')?['triage_tier'],'SKIP'),100000000,if(equals(body('Parse_JSON')?['triage_tier'],'LIGHT'),100000001,100000002))
```

**Compose — Priority Value:**
```
if(equals(body('Parse_JSON')?['priority'],'High'),100000000,if(equals(body('Parse_JSON')?['priority'],'Medium'),100000001,if(equals(body('Parse_JSON')?['priority'],'Low'),100000002,100000003)))
```

**Compose — Card Status Value:**
```
if(equals(body('Parse_JSON')?['card_status'],'READY'),100000000,if(equals(body('Parse_JSON')?['card_status'],'LOW_CONFIDENCE'),100000001,if(equals(body('Parse_JSON')?['card_status'],'SUMMARY_ONLY'),100000002,100000003)))
```

**Compose — Temporal Horizon Value:**
```
if(equals(body('Parse_JSON')?['temporal_horizon'],'TODAY'),100000000,if(equals(body('Parse_JSON')?['temporal_horizon'],'THIS_WEEK'),100000001,if(equals(body('Parse_JSON')?['temporal_horizon'],'NEXT_WEEK'),100000002,if(equals(body('Parse_JSON')?['temporal_horizon'],'BEYOND'),100000003,100000004))))
```

### Null Handling for Optional Integer Columns

```
@{if(equals(body('Parse_JSON')?['confidence_score'], null), 0, body('Parse_JSON')?['confidence_score'])}
```
Use when writing confidence_score to Dataverse — prevents null errors for SKIP/LIGHT tier items.

### Corrected PA Simplified Schema

```json
{
  "type": "object",
  "properties": {
    "trigger_type": { "type": "string" },
    "triage_tier": { "type": "string" },
    "item_summary": { "type": "string" },
    "priority": { "type": "string" },
    "temporal_horizon": { "type": "string" },
    "research_log": { "type": ["string", "null"] },
    "key_findings": { "type": ["string", "null"] },
    "verified_sources": {},
    "confidence_score": { "type": ["integer", "null"] },
    "card_status": { "type": "string" },
    "draft_payload": {},
    "low_confidence_note": { "type": ["string", "null"] }
  }
}
```

Change from current: `item_summary` changed from `["string", "null"]` to `"string"`.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| "Create text with GPT using a prompt" action | "Run a prompt" action (AI Builder) | May 2025 | Name change only — same action |
| "Invoke a Copilot Agent" / various names | "Execute Agent" / "Execute Agent and wait" (Copilot Studio connector) | 2025 | Standardized connector action names |
| Node.js 18 LTS | Node.js 20 LTS (current), Node.js 22 LTS (upcoming) | Node 18 EOL: Apr 2025 | Node 18 is no longer supported |

## Open Questions

1. **Execute Agent and wait — input variable passing**
   - What we know: The connector's `message` parameter accepts a string. The agent's input variables (TRIGGER_TYPE, PAYLOAD, etc.) were set up as agent-level input variables.
   - What's unclear: Whether Power Automate surfaces the agent's input variables as separate fields in the "Execute Agent and wait" action, or whether they must be passed as part of the message text. This depends on how the agent's variables are configured and the connector version.
   - Recommendation: The planner should note that the executor needs to verify this in the actual Power Automate designer. Document both possibilities: (a) input variables appear as separate fields, (b) pass variables as structured text in the message field.

2. **Response field name for Execute Agent and wait**
   - What we know: The connector reference says the return field is `lastResponse` (string). The current doc references `body('Invoke_agent')?['text']`.
   - What's unclear: The actual field name accessible via dynamic content in Power Automate may differ from the connector reference's field name due to how Power Automate wraps connector responses.
   - Recommendation: Document `lastResponse` as the expected field name per connector reference, but add a note to verify via the dynamic content picker. The action step name in the flow (e.g., `Execute_Agent_and_wait`) also affects the expression path.

3. **Copilot Studio JSON output for full agents (not standalone prompts)**
   - What we know: The official docs describe JSON output configuration in the context of Prompt builder (standalone prompts used in flows/apps). The current deployment guide describes it as an agent-level setting.
   - What's unclear: Whether JSON output mode for a full agent (with generative orchestration) is configured the same way as for a standalone prompt, or if there is a separate agent-level setting.
   - Recommendation: Use function-first language ("Configure the agent's output to produce JSON format") and describe the general process from the Prompt builder docs. Add a verification step: "Test the agent and confirm the response is valid JSON matching the schema."

## Sources

### Primary (HIGH confidence)
- [Microsoft Copilot Studio Connector Reference](https://learn.microsoft.com/en-us/connectors/microsoftcopilotstudio/) — verified Execute Agent / Execute Agent and wait actions and parameters (updated 2026-02-06)
- [JSON output - Microsoft Copilot Studio](https://learn.microsoft.com/en-us/microsoft-copilot-studio/process-responses-json-output) — verified JSON output configuration process (doc date 2025-11-07)
- [Use your prompt in Power Automate (AI Builder)](https://learn.microsoft.com/en-us/ai-builder/use-a-custom-prompt-in-flow) — confirmed "Run a prompt" is AI Builder action, renamed from "Create text with GPT using a prompt" in May 2025 (updated 2026-01-14)
- Project files: `output-schema.json`, `dataverse-table.json`, `agent-flows.md`, `deployment-guide.md` — verified current state of all documentation
- Project file: `.planning/STATE.md` — Phase 1 decisions on item_summary non-nullability

### Secondary (MEDIUM confidence)
- [Bun Installation Docs](https://bun.com/docs/installation) — verified install commands for macOS, Windows, Linux
- [Copilot Studio/Power Automate: Call an agent to run during a flow](https://rishonapowerplatform.com/2026/01/20/copilot-studio-power-automate-call-an-agent-to-run-during-a-flow/) — confirmed Execute Agent action workflow (Jan 2026)

### Tertiary (LOW confidence)
- Copilot Studio JSON output for full agents (vs standalone prompts) — could not find definitive documentation on whether the configuration is identical. Documented as open question.

## Metadata

**Confidence breakdown:**
- Connector action names (Execute Agent vs Run a prompt): HIGH — verified against official connector reference
- PA expression patterns: HIGH — standard Power Automate expression language, verified against existing doc
- JSON output UI path: MEDIUM — verified for Prompt builder; unclear if identical for full agents
- Prerequisites (Bun/Node versions): HIGH — well-documented LTS schedules and install commands
- item_summary nullability fix: HIGH — directly verified against canonical schema and Phase 1 decisions

**Research date:** 2026-02-21
**Valid until:** 2026-03-21 (30 days — documentation fixes against stable APIs)
