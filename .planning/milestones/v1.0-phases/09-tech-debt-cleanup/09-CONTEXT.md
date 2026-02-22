# Phase 9: Tech Debt Cleanup - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Resolve 4 specific non-blocking inconsistencies identified during the v1.0 milestone audit: schema enum convention divergence, broken documentation path, inaccurate version annotation, and stale requirement text. Strictly fix these 4 items — no scope expansion.

</domain>

<decisions>
## Implementation Decisions

### Null convention in schema
- Follow the null convention already established in Phase 1 (types.ts contract) — no new decisions needed
- Align output-schema.json enums with how types.ts represents nullable fields
- Claude decides the specific JSON Schema pattern (null in enum array vs nullable type) based on best alignment with the Phase 1 contract

### Change scope boundaries
- Strictly fix only the 4 audit items — do not fix additional issues discovered while editing
- Exception: DOC-03 "Run a prompt" → "Execute Agent and wait" fix should be applied across ALL planning docs, not just REQUIREMENTS.md
- Any new issues discovered during fixes should be logged in v1.0-MILESTONE-AUDIT.md for tracking

### Verification approach
- Schema fix: validate JSON Schema syntax AND confirm alignment with types.ts contract (both checks required)
- Path fix: run a script to verify the relative path from agent-flows.md location resolves to an existing file
- Document verification results in commit messages (e.g., "verified: schema validates, path resolves")

### Claude's Discretion
- Specific JSON Schema pattern for nullable enums (best fit for the established Phase 1 convention)
- Exact verification script implementation
- Order of fixes within the single plan

</decisions>

<specifics>
## Specific Ideas

- "We have decided on how to handle nulls earlier" — honor Phase 1 decisions, don't re-decide
- Verification results belong in commit messages, not separate documentation

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 09-tech-debt-cleanup*
*Context gathered: 2026-02-21*
