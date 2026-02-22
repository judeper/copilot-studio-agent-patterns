# Phase 9: Tech Debt Cleanup - Research

**Researched:** 2026-02-21
**Domain:** Schema consistency, documentation accuracy, version annotations
**Confidence:** HIGH

## Summary

Phase 9 resolves four non-blocking inconsistencies identified during the v1.0 milestone audit. All four items are straightforward, scoped text edits -- no library installation, no new code, no architecture changes. The fixes touch four files across two directories (schemas, docs) plus one planning file (REQUIREMENTS.md) and one planning file (PROJECT.md).

The most technically nuanced item is the schema enum convention change (replacing "N/A" string with null in output-schema.json). This requires understanding JSON Schema draft-07 nullable enum syntax and awareness of downstream artifacts that still use "N/A" (agent prompt, Dataverse Choice columns, Power Automate expressions). Per user decision, the scope is strictly the schema file -- the ingestion boundary in useCardData.ts already bridges the convention gap at runtime.

**Primary recommendation:** Execute all four fixes in a single plan with one task per fix, validating each with a targeted check (JSON Schema syntax validation, relative path resolution, string match, text comparison).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Follow the null convention already established in Phase 1 (types.ts contract) -- no new decisions needed
- Align output-schema.json enums with how types.ts represents nullable fields
- Claude decides the specific JSON Schema pattern (null in enum array vs nullable type) based on best alignment with the Phase 1 contract
- Strictly fix only the 4 audit items -- do not fix additional issues discovered while editing
- Exception: DOC-03 "Run a prompt" -> "Execute Agent and wait" fix should be applied across ALL planning docs, not just REQUIREMENTS.md
- Any new issues discovered during fixes should be logged in v1.0-MILESTONE-AUDIT.md for tracking
- Schema fix: validate JSON Schema syntax AND confirm alignment with types.ts contract (both checks required)
- Path fix: run a script to verify the relative path from agent-flows.md location resolves to an existing file
- Document verification results in commit messages (e.g., "verified: schema validates, path resolves")

### Claude's Discretion
- Specific JSON Schema pattern for nullable enums (best fit for the established Phase 1 convention)
- Exact verification script implementation
- Order of fixes within the single plan

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope

</user_constraints>

## Standard Stack

No libraries or tools to install. This phase involves only text/JSON edits validated by:

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| JSON Schema draft-07 | draft-07 | Schema definition language for output-schema.json | Already in use; `$schema` declared at line 2 of output-schema.json |
| Node.js / Bun | Any | Run path resolution verification script | Already installed in project |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `ajv` or inline JSON.parse | Validate JSON Schema syntax after edit | Schema fix verification step |
| `path.resolve` / `fs.existsSync` | Verify relative path resolves to existing file | Path fix verification step |

### Alternatives Considered
None -- no technology choices to make.

## Architecture Patterns

### Fix 1: Schema Enum Convention (output-schema.json)

**Current state:** Lines 37-39 and 41-44 of `enterprise-work-assistant/schemas/output-schema.json`:
```json
"priority": {
  "type": "string",
  "enum": ["High", "Medium", "Low", "N/A"],
  "description": "Priority level. Title case. N/A for SKIP or items where priority is not applicable."
}
"temporal_horizon": {
  "type": "string",
  "enum": ["TODAY", "THIS_WEEK", "NEXT_WEEK", "BEYOND", "N/A"],
  "description": "Temporal horizon for calendar items. N/A for non-calendar triggers or SKIP."
}
```

**Target state (types.ts contract):** Lines 3-4 of `enterprise-work-assistant/src/AssistantDashboard/components/types.ts`:
```typescript
export type Priority = "High" | "Medium" | "Low";
export type TemporalHorizon = "TODAY" | "THIS_WEEK" | "NEXT_WEEK" | "BEYOND";
```
And in the AssistantCard interface (lines 31-32):
```typescript
priority: Priority | null;
temporal_horizon: TemporalHorizon | null;
```

**Recommended JSON Schema pattern:** Use `type` array + `null` in enum (draft-07 standard):
```json
"priority": {
  "type": ["string", "null"],
  "enum": ["High", "Medium", "Low", null],
  "description": "Priority level. Title case. Null for SKIP or items where priority is not applicable."
}
"temporal_horizon": {
  "type": ["string", "null"],
  "enum": ["TODAY", "THIS_WEEK", "NEXT_WEEK", "BEYOND", null],
  "description": "Temporal horizon for calendar items. Null for non-calendar triggers or SKIP."
}
```

**Why this pattern:**
- Matches how other nullable fields in the same schema work (e.g., `research_log`, `key_findings`, `confidence_score` all use `"type": ["string", "null"]` or `"type": ["integer", "null"]`)
- JSON Schema draft-07 requires `null` to be in BOTH the `type` array AND the `enum` array for a nullable enum to validate correctly
- Directly mirrors the types.ts contract: `Priority | null` and `TemporalHorizon | null`
- Source: [JSON Schema spec issue #258](https://github.com/json-schema-org/json-schema-spec/issues/258) confirms null must be explicitly in enum array

**Confidence:** HIGH -- this pattern is already used for other fields in the same file and is the standard draft-07 approach.

**Downstream awareness (NOT in scope to fix):**
- The main agent prompt (`prompts/main-agent-system-prompt.md`) still tells the LLM to output `"N/A"` strings (lines 72, 146-147, 189, 195-196, 299-300)
- The Dataverse table (`schemas/dataverse-table.json`) has N/A as a Choice option with integer values (100000003 for Priority, 100000004 for Temporal Horizon)
- The Power Automate expressions in `docs/agent-flows.md` map "N/A" strings to integer values (lines 196, 208, 412, 414)
- The ingestion boundary in `useCardData.ts` (lines 47-51) converts "N/A" strings to null at runtime -- this bridge remains necessary

Per user decision: "Strictly fix only the 4 audit items -- do not fix additional issues discovered while editing. Any new issues discovered during fixes should be logged in v1.0-MILESTONE-AUDIT.md for tracking." The prompt/Dataverse/PA expression divergence should be noted in the audit log but NOT fixed in this phase.

### Fix 2: Broken Relative Path (agent-flows.md)

**Current state:** Line 58 of `enterprise-work-assistant/docs/agent-flows.md`:
```markdown
See [`schemas/output-schema.json`](../../schemas/output-schema.json) for the canonical contract.
```

**Directory structure:**
```
enterprise-work-assistant/
  docs/agent-flows.md          <-- FROM here
  schemas/output-schema.json   <-- TO here
```

**Correct relative path:** `../schemas/output-schema.json` (one `../` to go from `docs/` up to `enterprise-work-assistant/`, then into `schemas/`)

The current path `../../schemas/output-schema.json` goes up TWO levels (to the repo root `copilot-studio-agent-patterns/`), where no `schemas/` directory exists.

**Verification:** Run `node -e "const p = require('path'); const from = '<repo>/enterprise-work-assistant/docs'; console.log(require('fs').existsSync(p.resolve(from, '../schemas/output-schema.json')))"` -- should return `true`.

**Confidence:** HIGH -- directory structure directly verified.

### Fix 3: Bun Version Annotation (deployment-guide.md)

**Current state:** Line 9 of `enterprise-work-assistant/docs/deployment-guide.md`:
```markdown
- [ ] **Bun** >= 1.x (Tested with Bun 1.2.x)
```

**Correct state:** Phase 3 tested with Bun 1.3.8 (confirmed in STATE.md: "[Phase 03]: Bun 1.3.8 generates bun.lock (text) not bun.lockb (binary)")

**Fix:**
```markdown
- [ ] **Bun** >= 1.x (Tested with Bun 1.3.8)
```

**Confidence:** HIGH -- version confirmed in project STATE.md decision log.

### Fix 4: DOC-03 Stale Requirement Text (REQUIREMENTS.md + planning docs)

**Current state:** Line 33 of `.planning/REQUIREMENTS.md`:
```markdown
- [x] **DOC-03**: Agent-flows.md documents how to locate and configure the Copilot Studio connector "Run a prompt" action
```

**Correct state:** The implementation (completed in Phase 7) documents "Execute Agent and wait" from the Microsoft Copilot Studio connector, not "Run a prompt" (which is an AI Builder action).

**Fix for REQUIREMENTS.md:**
```markdown
- [x] **DOC-03**: Agent-flows.md documents how to locate and configure the Microsoft Copilot Studio connector "Execute Agent and wait" action
```

**Additional files with stale DOC-03 / "Run a prompt" text (per user decision to fix across ALL planning docs):**

1. `.planning/PROJECT.md` line 22:
   - Current: `"Run a prompt" action location`
   - Fix: `"Execute Agent and wait" action location`

These are the only two planning docs where "Run a prompt" appears as an *instruction* (not as a historical reference or distinction note). Other occurrences in planning docs are:
- Phase 7 plans, summaries, research, verification -- these are historical records documenting the fix journey from "Run a prompt" to "Execute Agent and wait". They should NOT be edited (they accurately describe what happened).
- `agent-flows.md` lines 14 and 154 -- these correctly use "Run a prompt" only in warning/distinction context ("Do not confuse this with..."). No fix needed.
- STATE.md line 80 -- historical decision log. No fix needed.
- ROADMAP.md line 119 -- describes Phase 7 success criteria accurately. No fix needed.
- v1.0-MILESTONE-AUDIT.md -- audit findings describing the stale text. No fix needed (the audit log is a historical record).

**Confidence:** HIGH -- verified by grep across entire repository.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON Schema validation | Custom parser | `JSON.parse()` + ajv or `node --check` | JSON syntax validation is trivially built-in; ajv handles schema-level validation |
| Path resolution check | Manual string manipulation | `path.resolve()` + `fs.existsSync()` | Node.js path module handles platform-specific path resolution correctly |

**Key insight:** All four fixes are text edits. Verification is the only part that benefits from tooling, and even that is minimal (a few lines of Node.js).

## Common Pitfalls

### Pitfall 1: Changing schema without updating description text
**What goes wrong:** The enum values change from "N/A" to null, but the description still says "N/A for SKIP..." leading to a description/value mismatch.
**Why it happens:** Description text is easy to overlook when focusing on the structural change.
**How to avoid:** When changing enum values, always update the corresponding description field in the same edit.
**Warning signs:** Description text containing the old convention after the fix.

### Pitfall 2: Fixing "Run a prompt" in historical documents
**What goes wrong:** Phase 7 plans, summaries, and verification files describe the journey from "Run a prompt" to "Execute Agent and wait". Editing these creates inaccurate history.
**Why it happens:** Grep finds many matches, and the instinct is to fix them all.
**How to avoid:** Only fix files where "Run a prompt" appears as a *current instruction* or *requirement description* -- not in historical records or distinction/warning context.
**Warning signs:** Editing any file in `.planning/phases/07-*` directory.

### Pitfall 3: Scope creep from discovered issues
**What goes wrong:** While editing output-schema.json, discovering that the agent prompt, Dataverse table, and PA expressions also use "N/A" and trying to fix those too.
**Why it happens:** Natural instinct to fix related inconsistencies.
**How to avoid:** Per user decision: strictly fix only the 4 audit items. Log any new findings in v1.0-MILESTONE-AUDIT.md.
**Warning signs:** Editing files not in the explicit fix list (output-schema.json, agent-flows.md, deployment-guide.md, REQUIREMENTS.md, PROJECT.md).

### Pitfall 4: JSON syntax error after schema edit
**What goes wrong:** Missing comma, extra comma, or unbalanced brackets after editing enum arrays in output-schema.json.
**Why it happens:** JSON is unforgiving about trailing commas and bracket balance.
**How to avoid:** Run `JSON.parse()` on the file after editing. Better: use `ajv` to validate the schema is both syntactically valid JSON and structurally valid JSON Schema.
**Warning signs:** Any file modification to .json files should be followed by a parse validation step.

## Code Examples

### JSON Schema Nullable Enum (draft-07)
```json
// Pattern: nullable enum field
// Source: JSON Schema draft-07 specification, verified against existing
// patterns in output-schema.json (research_log, key_findings, etc.)
{
  "priority": {
    "type": ["string", "null"],
    "enum": ["High", "Medium", "Low", null],
    "description": "Priority level. Title case. Null for SKIP or items where priority is not applicable."
  }
}
```

### Path Resolution Verification Script
```javascript
// Verify relative path from agent-flows.md resolves to output-schema.json
const path = require("path");
const fs = require("fs");
const docsDir = path.resolve(__dirname, "enterprise-work-assistant/docs");
const target = path.resolve(docsDir, "../schemas/output-schema.json");
console.log("Resolves to:", target);
console.log("Exists:", fs.existsSync(target));
```

### Verification via commit message pattern
```
fix(09): resolve schema enum divergence, broken path, version annotation, stale text

verified: output-schema.json validates as JSON Schema draft-07
verified: ../schemas/output-schema.json resolves from docs/ directory
verified: Bun version matches Phase 3 tested version (1.3.8)
verified: DOC-03 text says "Execute Agent and wait"
```

## Files to Modify

| # | File | Change | Lines Affected |
|---|------|--------|---------------|
| 1 | `enterprise-work-assistant/schemas/output-schema.json` | Replace "N/A" enum convention with null for priority and temporal_horizon | Lines 37-44 (type, enum, description for both fields) |
| 2 | `enterprise-work-assistant/docs/agent-flows.md` | Fix relative path from `../../schemas/output-schema.json` to `../schemas/output-schema.json` | Line 58 |
| 3 | `enterprise-work-assistant/docs/deployment-guide.md` | Change "Tested with Bun 1.2.x" to "Tested with Bun 1.3.8" | Line 9 |
| 4 | `.planning/REQUIREMENTS.md` | Change DOC-03 text from "Run a prompt" to "Execute Agent and wait" | Line 33 |
| 5 | `.planning/PROJECT.md` | Change "Run a prompt" to "Execute Agent and wait" in active requirements | Line 22 |

**Files to potentially update (logging only):**
| # | File | Change |
|---|------|--------|
| 6 | `.planning/v1.0-MILESTONE-AUDIT.md` | Log any newly discovered issues (e.g., prompt/Dataverse/PA still use "N/A" after schema change) |

## State of the Art

Not applicable -- this phase involves no technology choices, only text corrections.

## Open Questions

1. **Should the newly created schema/prompt divergence be logged as tech debt?**
   - What we know: After fixing output-schema.json to use null, the agent prompt will still tell the LLM to output "N/A". The ingestion boundary bridges this, but the prompt and schema now describe different contracts.
   - What's unclear: Whether this is acceptable long-term or should be a v2 tech debt item.
   - Recommendation: Log it in v1.0-MILESTONE-AUDIT.md per user instruction. The ingestion boundary (useCardData.ts) handles the conversion at runtime, so this is non-blocking.

2. **Should the Dataverse table Choice values for N/A be noted?**
   - What we know: `dataverse-table.json` has N/A as a Choice option for Priority (100000003) and Temporal Horizon (100000004). The PA expressions map "N/A" strings to these values. If the agent someday outputs null instead of "N/A", the PA expression would fall through to a default case.
   - What's unclear: Whether this constitutes a new tech debt item.
   - Recommendation: Note in audit log but do not fix -- the Dataverse table and PA expressions are operationally correct because the agent prompt still outputs "N/A" strings.

## Sources

### Primary (HIGH confidence)
- `enterprise-work-assistant/schemas/output-schema.json` -- current schema with N/A in enums (read directly)
- `enterprise-work-assistant/src/AssistantDashboard/components/types.ts` -- TypeScript contract with null convention (read directly)
- `enterprise-work-assistant/docs/agent-flows.md` -- broken relative path on line 58 (read directly)
- `enterprise-work-assistant/docs/deployment-guide.md` -- stale Bun version on line 9 (read directly)
- `.planning/REQUIREMENTS.md` -- stale DOC-03 text on line 33 (read directly)
- `.planning/PROJECT.md` -- stale "Run a prompt" text on line 22 (read directly)
- `.planning/STATE.md` -- Phase 3 Bun 1.3.8 decision (read directly)
- `.planning/v1.0-MILESTONE-AUDIT.md` -- four tech debt items (read directly)
- `enterprise-work-assistant/src/AssistantDashboard/hooks/useCardData.ts` -- ingestion boundary N/A-to-null conversion (read directly)
- `enterprise-work-assistant/prompts/main-agent-system-prompt.md` -- agent outputs "N/A" strings (grep verified)
- `enterprise-work-assistant/schemas/dataverse-table.json` -- N/A Choice values (read directly)

### Secondary (MEDIUM confidence)
- [JSON Schema spec issue #258](https://github.com/json-schema-org/json-schema-spec/issues/258) -- confirms null must be in enum array for nullable enums

## Metadata

**Confidence breakdown:**
- Schema fix pattern: HIGH -- verified against existing nullable fields in the same file and JSON Schema draft-07 specification
- Path fix: HIGH -- directory structure directly verified
- Version fix: HIGH -- version confirmed in STATE.md decision log
- DOC-03 fix: HIGH -- text verified by grep; scope of "all planning docs" determined by searching the entire repo
- Downstream impact awareness: HIGH -- all affected files identified and documented

**Research date:** 2026-02-21
**Valid until:** indefinite (text corrections, no technology dependencies)
