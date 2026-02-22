# Phase 1: Output Schema Contract - Context

**Gathered:** 2026-02-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix field types, nullability, and conventions in output-schema.json and align all downstream schema consumers (types.ts, main-agent-system-prompt.md, humanizer-agent-prompt.md, dataverse-table.json). This phase makes every artifact that references the agent output contract agree on field names, types, nullability, and value conventions. No new fields or capabilities — alignment only.

</domain>

<decisions>
## Implementation Decisions

### SKIP-tier item_summary
- Agent ALWAYS generates a brief summary for SKIP items (not null)
- This means item_summary is never null in practice — every tier produces a summary
- SKIP items ARE written to Dataverse (same as LIGHT and FULL) — simplifies the Power Automate flow by removing the tier check before writing
- SKIP items are hidden by default in the dashboard — users can toggle a filter to see them
- Update dataverse-table.json notes to remove the "SKIP items are NOT written" design note — that constraint is gone
- The schema should change item_summary from `["string", "null"]` to `"string"` (required, never null)

### Null convention across tiers
- **Null means "not applicable for this tier"** — the field conceptually doesn't exist at this tier
- **A string value (even descriptive) means "applicable but empty/none found"** — e.g., key_findings = "None retrieved" means research ran but found nothing
- confidence_score: strict integer only (bare 85, not "85"). Prompt examples must reflect this. No tolerance for string variants.
- key_findings: null for SKIP/LIGHT tiers (not applicable), "None retrieved" string for FULL tier when research finds nothing
- draft_payload: null for SKIP and LOW_CONFIDENCE, populated for LIGHT and FULL per their conventions

### Claude's Discretion
- Exact SKIP-tier summary format (descriptive vs minimal — pick what makes the agent most consistent)
- Null convention details: whether to use null universally or "null for objects/arrays, N/A for strings" — pick the cleanest approach for all consumers
- draft_payload structural decision: whether to keep oneOf (null | string | object) with PA workaround, or wrap calendar briefings in an object. Pick what minimizes parsing complexity across all consumers.
- Whether humanizer handoff schema stays inline in output-schema.json or gets extracted. Pick what's best for a reference pattern.
- Strict per-tier field matrix vs general nullability rules — pick what makes the prompt and schema most maintainable

### Prompt examples
- Main-agent-system-prompt.md must include four complete JSON examples: SKIP, LIGHT, FULL (email/teams), and FULL (calendar scan)
- Each example is a complete, valid JSON object — no partial/diff examples
- This covers every branch the agent can produce, eliminating ambiguity

</decisions>

<specifics>
## Specific Ideas

- The semantic distinction between null and string values is important: null = "this tier doesn't use this field" vs string = "we tried but found nothing" (like "None retrieved" for key_findings)
- Four prompt examples total to cover every branch: SKIP, LIGHT, FULL email/teams, FULL calendar — user wants zero ambiguity in what the agent should produce
- confidence_score must be strict integer — no quoted strings, no tolerance for agent variability on this field

</specifics>

<deferred>
## Deferred Ideas

- Dashboard UI changes for SKIP-item filter toggle — belongs in Phase 4 or 5 (PCF component work), not schema phase
- SKIP-item visual de-emphasis styling — PCF component concern, not schema

</deferred>

---

*Phase: 01-output-schema-contract*
*Context gathered: 2026-02-20*
