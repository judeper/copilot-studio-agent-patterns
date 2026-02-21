# Phase 4: PCF API Correctness - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix all Fluent UI v9 API misuse (invalid prop values, incorrect tokens) and clean up contract drift from Phase 1 (N/A guards, nullable type assertions). The phase delivers a codebase where every Fluent UI component prop and token reference is valid against the v9 API surface, and display logic aligns with the Phase 1 null convention.

</domain>

<decisions>
## Implementation Decisions

### Null priority display
- Hide the priority badge entirely when priority is null — no badge at all, not a fallback label
- Priority color map: strict entries for High/Medium/Low only — no default/fallback color for unexpected values
- Identical behavior in both CardItem (list view) and CardDetail (expanded view) — both hide on null
- Consolidate the duplicated priority color map into a shared `components/constants.ts` file — single source of truth

### Temporal horizon & draft guards
- Temporal horizon: hide badge entirely on null — same pattern as priority
- Draft payload: use truthiness check (`if (card.draft_payload)`) not explicit null check — hides on null, undefined, and empty string
- CardItem.tsx temporal_horizon guard: same truthiness pattern for consistency across both components
- Check useCardData hook for any remaining N/A string production — fix if found, not just display components

### Defensive fallback style
- Remove `?? "No summary available"` fallback from CardItem.tsx — trust the non-nullable type contract
- Simplify useCardData.ts item_summary handling — remove cascading fallback chain, trust parsed data
- Remove `String()` wrapper if parsed.item_summary is already typed as string — no redundant coercion
- Scope limited to item_summary only — don't clean up other fields' defensive patterns in this phase

### Token & badge verification scope
- Full Fluent UI v9 audit across all components — check every prop value and token reference against the API surface
- Audit includes both component props (size, appearance, etc.) AND style usage (makeStyles, tokens in inline styles)
- Fix everything found — if audit reveals any API issues beyond Badge sizes and color tokens, fix them in this phase
- Shared constants file lives at `components/constants.ts` alongside component files

### Claude's Discretion
- Exact structure of the shared constants file (what else to include beyond priority colors)
- How to handle any unexpected Fluent UI API issues discovered during the audit
- Whether to group related fixes into one plan or separate plans

</decisions>

<specifics>
## Specific Ideas

- All N/A → null migrations should use consistent truthiness checks, not explicit null comparisons
- Priority color map consolidation into `components/constants.ts` is the only structural refactor — everything else is in-place fixes
- The build must pass clean (`bun run build` and `bun run lint` with zero errors and warnings) after all changes

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-pcf-api-correctness*
*Context gathered: 2026-02-21*
