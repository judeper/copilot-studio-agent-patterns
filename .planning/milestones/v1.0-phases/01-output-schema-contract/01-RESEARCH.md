# Phase 1: Output Schema Contract - Research

**Researched:** 2026-02-20
**Domain:** JSON Schema alignment, Dataverse column constraints, prompt-schema consistency
**Confidence:** HIGH

## Summary

Phase 1 is an alignment-only phase: five artifacts (output-schema.json, types.ts, main-agent-system-prompt.md, humanizer-agent-prompt.md, dataverse-table.json) all reference the agent output contract but currently disagree on field types, nullability rules, value conventions, and structural details. The user has made specific, locked decisions about how every discrepancy should be resolved. This research documents the exact current state of each artifact, the exact gaps between current state and the locked decisions, and the technical constraints that affect implementation.

No new fields or capabilities are added. No libraries are needed. This is pure file editing guided by a set of contract rules. The primary risk is incomplete propagation -- missing one field in one artifact -- so the research emphasizes a systematic per-field, per-artifact gap inventory.

**Primary recommendation:** Build a field-by-field truth table from the locked decisions, then walk each artifact against it, fixing every deviation. Validate the prompt JSON examples against the schema definition programmatically if possible (e.g., using ajv-cli or a simple Node script).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Agent ALWAYS generates a brief summary for SKIP items (not null)
- item_summary is never null in practice -- every tier produces a summary
- SKIP items ARE written to Dataverse (same as LIGHT and FULL) -- simplifies the Power Automate flow by removing the tier check before writing
- SKIP items are hidden by default in the dashboard -- users can toggle a filter to see them
- Update dataverse-table.json notes to remove the "SKIP items are NOT written" design note -- that constraint is gone
- The schema should change item_summary from `["string", "null"]` to `"string"` (required, never null)
- **Null means "not applicable for this tier"** -- the field conceptually doesn't exist at this tier
- **A string value (even descriptive) means "applicable but empty/none found"** -- e.g., key_findings = "None retrieved" means research ran but found nothing
- confidence_score: strict integer only (bare 85, not "85"). Prompt examples must reflect this. No tolerance for string variants.
- key_findings: null for SKIP/LIGHT tiers (not applicable), "None retrieved" string for FULL tier when research finds nothing
- draft_payload: null for SKIP and LOW_CONFIDENCE, populated for LIGHT and FULL per their conventions
- Main-agent-system-prompt.md must include four complete JSON examples: SKIP, LIGHT, FULL (email/teams), and FULL (calendar scan)
- Each example is a complete, valid JSON object -- no partial/diff examples
- Four prompt examples total to cover every branch: SKIP, LIGHT, FULL email/teams, FULL calendar
- confidence_score must be strict integer -- no quoted strings, no tolerance for agent variability

### Claude's Discretion
- Exact SKIP-tier summary format (descriptive vs minimal -- pick what makes the agent most consistent)
- Null convention details: whether to use null universally or "null for objects/arrays, N/A for strings" -- pick the cleanest approach for all consumers
- draft_payload structural decision: whether to keep oneOf (null | string | object) with PA workaround, or wrap calendar briefings in an object. Pick what minimizes parsing complexity across all consumers.
- Whether humanizer handoff schema stays inline in output-schema.json or gets extracted. Pick what's best for a reference pattern.
- Strict per-tier field matrix vs general nullability rules -- pick what makes the prompt and schema most maintainable

### Deferred Ideas (OUT OF SCOPE)
- Dashboard UI changes for SKIP-item filter toggle -- belongs in Phase 4 or 5 (PCF component work), not schema phase
- SKIP-item visual de-emphasis styling -- PCF component concern, not schema
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SCHM-01 | Dataverse primary column cr_itemsummary handles SKIP-tier items without null violation (use placeholder text) | User decided: agent ALWAYS generates a brief summary for SKIP. Schema changes item_summary to required string (never null). SKIP items ARE written to Dataverse. Gap analysis below shows current schema has `["string", "null"]` and prompt Example 4 has `null` -- both must change. |
| SCHM-02 | Dataverse table schema includes cr_triagetier Choice column with SKIP/LIGHT/FULL values | Already present in dataverse-table.json (lines 11-20). No gap. Verify during implementation. |
| SCHM-03 | confidence_score field uses integer type consistently (no quoted strings) across prompts and schema | Schema already defines `["integer", "null"]` (correct). Prompt examples already show bare integers. Gap: prompt description text says `<integer 0-100 or null>` but this is textual, not a code violation. Verify all four final examples use bare integers. |
| SCHM-04 | key_findings and verified_sources nullability rules are consistent between main agent prompt, humanizer prompt, and output-schema.json | Current schema has both as nullable (correct for SKIP/LIGHT). Gap: prompt SKIP example must show null for these. Prompt text for SKIP says "null/empty values for all other fields" but example shows explicit null -- consistent. Main concern: ensure FULL-tier "None retrieved" convention for key_findings is documented in schema description and reflected in prompt examples. |
| SCHM-05 | Humanizer handoff object includes draft_type discriminator field for format determination | Already present in output-schema.json oneOf branch (line 108-112) and humanizer-agent-prompt.md input contract (line 15). No structural gap. Ensure alignment is verified during implementation. |
| SCHM-06 | draft_payload uses null (not "N/A") for non-draft cases across all artifacts | Current schema description says "N/A for LIGHT" (line 91). Must change to null. Prompt text also says "N/A" in draft_payload description line. types.ts already uses `DraftPayload | string | null` which allows null but also string -- need to verify the semantic intent. |
</phase_requirements>

## Standard Stack

This phase requires no libraries or frameworks. It is a pure content-editing phase across five files.

### Core
| Tool | Purpose | Why Needed |
|------|---------|------------|
| Text editor | Edit JSON, TypeScript, and Markdown files | All changes are textual edits to existing files |
| ajv-cli (optional) | Validate prompt JSON examples against output-schema.json | Catches schema violations that manual review might miss |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ajv-cli validation | Manual visual comparison | Manual is error-prone for 12+ fields across 4 examples; automated is safer but requires install |
| Inline schema validation script | External validator | Inline script lives in the repo and can be reused; external tool is one-shot |

## Architecture Patterns

### Recommended Approach: Truth Table-Driven Alignment

The core pattern for this phase is building a single truth table that defines the canonical value of every field for every tier/scenario combination, then mechanically verifying every artifact against it.

**Truth Table Structure (the "contract"):**

| Field | Type | SKIP | LIGHT | FULL (email/teams) | FULL (calendar) | LOW_CONFIDENCE |
|-------|------|------|-------|---------------------|-----------------|----------------|
| trigger_type | string enum | any | any | EMAIL/TEAMS_MESSAGE | CALENDAR_SCAN | any |
| triage_tier | string enum | "SKIP" | "LIGHT" | "FULL" | "FULL" | "FULL" |
| item_summary | string (required) | brief summary | summary | summary | summary | summary |
| priority | string enum | "N/A" | varies | varies | varies | varies |
| temporal_horizon | string enum | "N/A" | "N/A" (non-calendar) | "N/A" | varies | varies |
| research_log | string or null | null | null | string | string | string |
| key_findings | string or null | null | null | string (or "None retrieved") | string (or "None retrieved") | string or null |
| verified_sources | array or null | null | null | array | array | array or null |
| confidence_score | integer or null | null | null | integer | integer | integer (0-39) |
| card_status | string enum | "NO_OUTPUT" | "SUMMARY_ONLY" | "READY" | "READY" | "LOW_CONFIDENCE" |
| draft_payload | null, string, or object | null | null | humanizer handoff object | plain-text briefing string | null |
| low_confidence_note | string or null | null | null | null | null | string |

### Pattern: Null Convention (Claude's Discretion Recommendation)

**Recommendation: Use null universally for "not applicable."**

Rationale:
- JSON null is unambiguous -- every consumer (TypeScript, Power Automate, Canvas App ParseJSON) handles null natively
- Using "N/A" strings for some fields and null for others creates two conventions to remember and two code paths to check
- The schema already uses null extensively for SKIP/LIGHT fields
- Power Automate expressions can check `empty()` or `equals(null)` cleanly
- TypeScript `| null` is cleaner than `| "N/A"` for nullable fields that aren't enums
- Exception: priority and temporal_horizon already use "N/A" as an enum value (not a null convention) -- this is different because "N/A" is a meaningful business value in those enums, not a nullability marker

**Result:** All non-enum nullable fields use JSON null (not "N/A" string) when not applicable.

### Pattern: draft_payload Structure (Claude's Discretion Recommendation)

**Recommendation: Keep oneOf (null | string | object) in the schema. Do NOT wrap calendar briefings in an object.**

Rationale:
- The schema already documents the Power Automate limitation in its description field (line 4)
- The docs/agent-flows.md is designated to contain the simplified PA schema workaround
- Wrapping calendar briefings in an object adds artificial structure that the humanizer doesn't consume and the Canvas App doesn't need
- The TypeScript types.ts already models this as `DraftPayload | string | null` which maps cleanly
- The oneOf with three branches is semantically correct: null (no draft), string (calendar briefing), object (humanizer handoff)
- Power Automate workaround: use `typeof()` expression or store the full JSON in cr_fulljson and parse downstream

### Pattern: Humanizer Handoff Schema Location (Claude's Discretion Recommendation)

**Recommendation: Keep humanizer handoff schema inline in output-schema.json.**

Rationale:
- The handoff object is structurally part of draft_payload -- it IS the object branch of the oneOf
- Extracting it to a separate file creates a cross-file dependency for a single embedded object
- JSON Schema draft-07 supports `$ref` for extraction, but it adds complexity for a reference pattern that should be easy to follow
- The humanizer-agent-prompt.md already documents the input contract independently (as it should -- the prompt is the agent's interface definition)
- Keeping it inline means output-schema.json is the single source of truth for the full output shape

### Pattern: Per-Tier Field Matrix vs General Nullability Rules (Claude's Discretion Recommendation)

**Recommendation: Use general nullability rules in the schema, with a per-tier matrix in the prompt.**

Rationale:
- JSON Schema draft-07 does not natively support "this field is null when another field equals X" (no `if/then` in this context without significantly complicating the schema)
- The schema should define which fields CAN be null (type declaration) and document the convention in descriptions
- The prompt should include a clear per-tier matrix table that the agent follows -- this is where per-tier rules live
- The four complete JSON examples in the prompt serve as the definitive per-tier reference
- This split keeps the schema simple and the prompt authoritative for business logic

### Pattern: SKIP-Tier Summary Format (Claude's Discretion Recommendation)

**Recommendation: Use a brief descriptive format for SKIP summaries.**

Example: `"Marketing newsletter from Contoso Weekly — no action needed."`

Rationale:
- Descriptive format tells the user what was skipped and why at a glance
- Minimal format (e.g., "Skipped item") provides no value on the dashboard even with a toggle
- The agent naturally produces descriptive summaries -- forcing minimal goes against the LLM's strength
- Pattern: `"[Brief description of sender/content] — [reason for SKIP classification]."`
- Keep under 100 characters for dashboard card display

### Anti-Patterns to Avoid
- **Partial propagation:** Fixing the schema but forgetting to update one prompt example or the types.ts nullability rule. The truth table prevents this.
- **"N/A" creep:** Using "N/A" string as a null substitute anywhere except the priority/temporal_horizon enums where it's an explicit business value.
- **Draft_payload description inconsistency:** The schema description currently says "N/A for LIGHT" -- this must change to "null" to match the null convention.
- **Prompt example drift:** Having examples that "almost" match the schema but differ on one field. Every example must validate against the schema.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON Schema validation | Custom comparison logic | ajv-cli or a 10-line Node script with ajv | ajv handles draft-07 including oneOf, nullable types, and enum validation correctly |
| Field-by-field diffing | Manual side-by-side reading | Structured truth table checklist | Five files times twelve fields is 60 cells to verify; a table catches gaps |

**Key insight:** This phase has zero implementation complexity but high propagation risk. The danger is not "how do I fix this?" but "did I fix it everywhere?" Systematic checklists beat manual review.

## Common Pitfalls

### Pitfall 1: Forgetting to Update Schema Descriptions
**What goes wrong:** The field type is changed but the description text still says the old convention (e.g., changing draft_payload to null but the description still says "N/A for LIGHT").
**Why it happens:** Descriptions feel like comments and get overlooked during type changes.
**How to avoid:** For every field change, check both the `type` AND the `description` properties in the schema.
**Warning signs:** A description mentioning "N/A" or "null" that contradicts the type definition.

### Pitfall 2: Prompt Example SKIP Still Using null for item_summary
**What goes wrong:** The SKIP example in the prompt still has `"item_summary": null` after the schema changes item_summary to required string.
**Why it happens:** Example 4 (SKIP) was written when SKIP items had null summaries. The decision changed this, but the example is a blob of text easy to skim past.
**How to avoid:** After editing the schema, re-validate every prompt example against the schema (manually or with ajv). The SKIP example MUST have a non-null string for item_summary.
**Warning signs:** Any prompt JSON example containing `"item_summary": null`.

### Pitfall 3: types.ts Not Reflecting item_summary Non-Nullability
**What goes wrong:** types.ts still has `item_summary: string | null` after the schema makes it required string.
**Why it happens:** The TypeScript file is in a different directory from the schema and prompt files.
**How to avoid:** Include types.ts in the same edit pass as output-schema.json. They must always change together.
**Warning signs:** `| null` on a field that the schema defines as never-null.

### Pitfall 4: draft_payload Description Using "N/A" Instead of null
**What goes wrong:** The schema and/or prompt text describes draft_payload as "N/A for LIGHT" instead of "null for LIGHT and SKIP."
**Why it happens:** The original schema was written before the null convention was locked.
**How to avoid:** Search for every occurrence of "N/A" in draft_payload descriptions across all five files and replace with "null" (except in enum values).
**Warning signs:** The string "N/A" appearing in any draft_payload description or prompt text (outside of priority/temporal_horizon enum definitions).

### Pitfall 5: Dataverse Notes Still Saying "SKIP Items NOT Written"
**What goes wrong:** The `notes.skip_items` field in dataverse-table.json still says "SKIP-tier items are NOT written to Dataverse" even though the decision reversed this.
**Why it happens:** Notes/comments are the most commonly forgotten update targets.
**How to avoid:** Explicitly include dataverse-table.json notes in the edit checklist.
**Warning signs:** Any dataverse-table.json note referencing "SKIP items are NOT written."

### Pitfall 6: Prompt Text Instructions Contradicting Prompt Examples
**What goes wrong:** The prompt body text says "return item_summary = null for SKIP" but the SKIP example shows a string summary.
**Why it happens:** The body text and examples are far apart in the file (the body is near line 69, examples near line 293).
**How to avoid:** Search the entire prompt for every mention of "item_summary" and "SKIP" to ensure consistency. Pay special attention to the triage instructions in Step 1.
**Warning signs:** The phrase "item_summary = null" or "item_summary null" appearing anywhere in the prompt.

## Detailed Gap Analysis

### File 1: output-schema.json

| Line(s) | Current State | Required Change | Requirement |
|----------|---------------|-----------------|-------------|
| 32-33 | `"type": ["string", "null"]` for item_summary | Change to `"type": "string"` (never null) | SCHM-01 |
| 34 | Description says "Null for SKIP." | Change to "1-2 sentence plain-text summary. For SKIP items, a brief description of what was skipped and why." | SCHM-01 |
| 91 | draft_payload description says "N/A for LIGHT" | Change "N/A" to "Null" throughout: "Null for SKIP, LIGHT, or LOW_CONFIDENCE." | SCHM-06 |
| — | No `draft_type` field at top level | No change needed -- draft_type is correctly inside the handoff object within oneOf | SCHM-05 (already satisfied) |
| 79-83 | confidence_score type is `["integer", "null"]` | Already correct. No change needed. | SCHM-03 (already satisfied) |
| 50-53 | key_findings description mentions "None retrieved" | Already mentions it. Verify wording matches the locked decision exactly. | SCHM-04 |

### File 2: types.ts

| Line | Current State | Required Change | Requirement |
|------|---------------|-----------------|-------------|
| 30 | `item_summary: string \| null` | Change to `item_summary: string` (remove null) | SCHM-01 |
| 36 | `confidence_score: number \| null` | Already uses `number` (TypeScript has no `integer` type). Correct. | SCHM-03 (already satisfied) |
| 38 | `draft_payload: DraftPayload \| string \| null` | Already correct for the oneOf pattern. No change needed. | SCHM-06 |

### File 3: main-agent-system-prompt.md

| Line(s) | Current State | Required Change | Requirement |
|----------|---------------|-----------------|-------------|
| 69-72 | SKIP instructions say "item_summary = null" | Change to "item_summary = brief summary of what was skipped and why" | SCHM-01 |
| 144-145 | Step 5 SKIP says "null/empty values for all other fields" | Update to reflect item_summary is a string, not null, for SKIP | SCHM-01 |
| 192 | Output schema template shows `<1-2 sentence...Null for SKIP.>` for item_summary | Change to reflect always-present summary | SCHM-01 |
| 208-210 | draft_payload description says "N/A for LIGHT" | Change to "Null for SKIP, LIGHT, or LOW_CONFIDENCE" | SCHM-06 |
| 293-306 | Example 4 (SKIP) has `"item_summary": null` | Change to a descriptive string summary | SCHM-01 |
| — | Has 4 examples already (EMAIL FULL, TEAMS LIGHT, CALENDAR FULL, EMAIL SKIP) | Good -- matches the 4-example requirement. Verify each validates against updated schema. | All |
| 295 | Example 4 SKIP has `"priority": "N/A"` | Correct -- "N/A" is an enum value, not a null convention | — |

### File 4: humanizer-agent-prompt.md

| Line(s) | Current State | Required Change | Requirement |
|----------|---------------|-----------------|-------------|
| 15 | Input contract shows `"draft_type": "EMAIL \| TEAMS_MESSAGE"` | Already present. No change needed. | SCHM-05 (already satisfied) |
| 21 | confidence_score shown as `<integer 0-100>` | Already correct (integer notation). No change needed. | SCHM-03 |
| — | No nullability issues found | The humanizer only receives the handoff object (never null/SKIP/LIGHT) | — |

### File 5: dataverse-table.json

| Line(s) | Current State | Required Change | Requirement |
|----------|---------------|-----------------|-------------|
| 11-20 | cr_triagetier Choice with SKIP/LIGHT/FULL | Already present and correct. | SCHM-02 (already satisfied) |
| 38-41 | cr_itemsummary: type Text, required true | Already correct for the new rule (required, never null). | SCHM-01 (already correct) |
| 110 | notes.skip_items says "SKIP-tier items are NOT written to Dataverse" | Must update to "SKIP-tier items ARE written to Dataverse with a brief summary. Hidden by default in the dashboard." | SCHM-01 |
| 83-89 | cr_confidencescore: type WholeNumber | Already correct (WholeNumber = integer in Dataverse). | SCHM-03 (already satisfied) |

## Code Examples

### Example 1: Updated item_summary in output-schema.json
```json
"item_summary": {
  "type": "string",
  "maxLength": 300,
  "description": "1-2 sentence plain-text summary of the triggering item. For SKIP items, a brief description of what was skipped and why (e.g., 'Marketing newsletter from Contoso Weekly — no action needed.')."
}
```

### Example 2: Updated SKIP Example in Prompt
```json
{
  "trigger_type": "EMAIL",
  "triage_tier": "SKIP",
  "item_summary": "Marketing newsletter from Contoso Weekly — no action needed.",
  "priority": "N/A",
  "temporal_horizon": "N/A",
  "research_log": null,
  "key_findings": null,
  "verified_sources": null,
  "confidence_score": null,
  "card_status": "NO_OUTPUT",
  "draft_payload": null,
  "low_confidence_note": null
}
```

### Example 3: Updated draft_payload Description
```json
"draft_payload": {
  "description": "For EMAIL/TEAMS_MESSAGE FULL-tier items with confidence >= 40: humanizer handoff object. For CALENDAR_SCAN FULL-tier items: plain-text meeting briefing. Null for SKIP, LIGHT, and LOW_CONFIDENCE.",
  "oneOf": [
    { "type": "null" },
    { "type": "string" },
    { ... }
  ]
}
```

### Example 4: Updated types.ts item_summary
```typescript
export interface AssistantCard {
    id: string;
    trigger_type: TriggerType;
    triage_tier: TriageTier;
    item_summary: string;           // Changed: no longer nullable
    priority: Priority;
    temporal_horizon: TemporalHorizon;
    research_log: string | null;
    key_findings: string | null;
    verified_sources: VerifiedSource[] | null;
    confidence_score: number | null;
    card_status: CardStatus;
    draft_payload: DraftPayload | string | null;
    low_confidence_note: string | null;
    humanized_draft: string | null;
    created_on: string;
}
```

### Example 5: Updated dataverse-table.json Notes
```json
"notes": {
    "design_rationale": "Full JSON blob in cr_fulljson plus discrete columns only for server-side filtering...",
    "skip_items": "SKIP-tier items ARE written to Dataverse with a brief summary in cr_itemsummary. SKIP items are hidden by default in the dashboard — users can toggle a filter to view them.",
    "non_discrete_fields": "...",
    "security": "...",
    "system_columns": "..."
}
```

## Discretion Decisions Summary

| Decision Area | Recommendation | Rationale |
|---------------|----------------|-----------|
| SKIP-tier summary format | Descriptive: "[sender/content] -- [reason for SKIP]." | Gives dashboard value even when toggled visible; natural for LLM to produce |
| Null convention | Use JSON null universally for "not applicable" | Simpler than mixed null/"N/A"; every consumer handles null natively. "N/A" only in enum values. |
| draft_payload structure | Keep oneOf (null/string/object) | Semantically correct; PA workaround documented elsewhere; avoids artificial wrapping |
| Humanizer handoff location | Keep inline in output-schema.json | Single source of truth; avoids cross-file $ref complexity |
| Per-tier rules | General nullability in schema + per-tier matrix in prompt | JSON Schema lacks conditional nullability; prompt is the right place for business logic |

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| SKIP items NOT written to Dataverse | SKIP items ARE written to Dataverse | Removes conditional logic in Power Automate flow; requires item_summary to always be non-null |
| item_summary nullable for SKIP | item_summary always required string | Dataverse primary column constraint satisfied without workaround |
| draft_payload "N/A" for LIGHT | draft_payload null for all non-draft cases | Single null convention; no string-vs-null ambiguity |

## Open Questions

1. **Validation tooling availability**
   - What we know: ajv-cli can validate JSON against JSON Schema draft-07 including oneOf
   - What's unclear: Whether the project has Node.js available for running a validation script (PROJECT.md mentions PCF/Node stack, so likely yes)
   - Recommendation: Optionally add a validation step but do not block on it -- manual verification against the truth table is sufficient

2. **LIGHT-tier draft_payload**
   - What we know: User decision says "draft_payload: null for SKIP and LOW_CONFIDENCE, populated for LIGHT and FULL per their conventions." But the current schema and prompt both say LIGHT does NOT produce a draft (LIGHT = summary only).
   - What's unclear: The CONTEXT.md statement "populated for LIGHT and FULL per their conventions" may be a generalization. Looking at the actual prompt and schema, LIGHT explicitly does not produce a draft. The LIGHT example (Example 2) shows `"draft_payload": null`.
   - Recommendation: Treat LIGHT draft_payload as null (matching current prompt and schema behavior). The CONTEXT.md "populated for LIGHT" likely refers to "LIGHT has its own convention" which IS null. The prompt is authoritative here.

3. **draft_payload description in prompt output schema template**
   - What we know: The prompt has both inline text descriptions AND a schema template block that describes draft_payload
   - What's unclear: Whether the prompt schema template is normative or illustrative
   - Recommendation: Update both the schema template AND the Step 5 prose to use consistent "null" language. Both are read by the agent.

## Sources

### Primary (HIGH confidence)
- `/enterprise-work-assistant/schemas/output-schema.json` -- current schema definition, directly examined
- `/enterprise-work-assistant/src/AssistantDashboard/components/types.ts` -- current TypeScript interfaces, directly examined
- `/enterprise-work-assistant/prompts/main-agent-system-prompt.md` -- current prompt with 4 examples, directly examined
- `/enterprise-work-assistant/prompts/humanizer-agent-prompt.md` -- current humanizer input contract, directly examined
- `/enterprise-work-assistant/schemas/dataverse-table.json` -- current Dataverse table definition, directly examined
- `.planning/phases/01-output-schema-contract/01-CONTEXT.md` -- user-locked decisions

### Secondary (MEDIUM confidence)
- [JSON Schema draft-07 specification](https://json-schema.org/draft-07/draft-handrews-json-schema-validation-01) -- oneOf, nullable type patterns
- [Dataverse primary column constraints](https://blog.davidyack.com/properly-configure-a-dataverse-table-primary-column/) -- primary column cannot be null
- [Power Automate Parse JSON limitations](https://erpsoftwareblog.com/2023/11/the-benefits-and-limitations-to-using-parse-json-power-automate-and-dynamics-365-business-central/) -- oneOf not fully supported in Parse JSON

## Metadata

**Confidence breakdown:**
- Gap analysis: HIGH -- all five artifacts directly examined and compared field-by-field
- Discretion recommendations: HIGH -- based on direct analysis of consumer constraints (TypeScript, Power Automate, Dataverse)
- Pitfalls: HIGH -- derived from the specific structure of the files being edited
- Validation approach: MEDIUM -- ajv-cli validation is standard but untested in this project context

**Research date:** 2026-02-20
**Valid until:** Indefinite (this is a file-editing phase, not a library-version-dependent phase)
