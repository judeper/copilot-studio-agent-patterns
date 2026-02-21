# Phase 4: PCF API Correctness - Research

**Researched:** 2026-02-21
**Domain:** Fluent UI v9 component API validation, contract drift cleanup, type safety
**Confidence:** HIGH

## Summary

Phase 4 addresses two categories of issues: (1) verifying all Fluent UI v9 component prop values and token references are correct against the actual API surface, and (2) cleaning up contract drift from Phase 1's null convention changes that left residual `"N/A"` string guards and defensive nullable patterns in the PCF components.

The codebase is in better shape than the requirements originally anticipated. All Badge `size` prop values currently in use (`"small"`, `"medium"`) are valid Fluent UI v9 values. All color tokens currently referenced (`colorPaletteRedBorder2`, `colorPaletteMarigoldBorder2`, `colorPaletteGreenBorder2`, `colorNeutralStroke1`, `colorNeutralForeground1`, `colorNeutralForeground3`) are valid and resolve correctly. The `colorPaletteYellowBorder2` token mentioned as incorrect in the requirement does NOT appear anywhere in the source code -- it was already fixed or never introduced. However, the contract drift issues are real and need cleaning: `CardDetail.tsx` has two residual `!== "N/A"` guards on `draft_payload`, `CardItem.tsx` and `CardDetail.tsx` both check `temporal_horizon !== "N/A"`, the `priorityColors` map is duplicated with a stale `"N/A"` entry, `CardItem.tsx` has a redundant `?? "No summary available"` fallback, and `useCardData.ts` still applies `String()` coercion with a cascading fallback chain for `item_summary`.

**Primary recommendation:** Create a single plan that (1) updates the `Priority` and `TemporalHorizon` types to use `null` instead of `"N/A"`, (2) consolidates the duplicate `priorityColors` map into `components/constants.ts`, (3) replaces all `!== "N/A"` guards with truthiness checks, (4) removes the redundant `item_summary` defensive patterns, and (5) performs a full Fluent UI v9 prop audit to confirm correctness. Verify with `bun run build` and `bun run lint` passing clean.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Hide the priority badge entirely when priority is null -- no badge at all, not a fallback label
- Priority color map: strict entries for High/Medium/Low only -- no default/fallback color for unexpected values
- Identical behavior in both CardItem (list view) and CardDetail (expanded view) -- both hide on null
- Consolidate the duplicated priority color map into a shared `components/constants.ts` file -- single source of truth
- Temporal horizon: hide badge entirely on null -- same pattern as priority
- Draft payload: use truthiness check (`if (card.draft_payload)`) not explicit null check -- hides on null, undefined, and empty string
- CardItem.tsx temporal_horizon guard: same truthiness pattern for consistency across both components
- Check useCardData hook for any remaining N/A string production -- fix if found, not just display components
- Remove `?? "No summary available"` fallback from CardItem.tsx -- trust the non-nullable type contract
- Simplify useCardData.ts item_summary handling -- remove cascading fallback chain, trust parsed data
- Remove `String()` wrapper if parsed.item_summary is already typed as string -- no redundant coercion
- Scope limited to item_summary only -- don't clean up other fields' defensive patterns in this phase
- Full Fluent UI v9 audit across all components -- check every prop value and token reference against the API surface
- Audit includes both component props (size, appearance, etc.) AND style usage (makeStyles, tokens in inline styles)
- Fix everything found -- if audit reveals any API issues beyond Badge sizes and color tokens, fix them in this phase
- Shared constants file lives at `components/constants.ts` alongside component files
- All N/A to null migrations should use consistent truthiness checks, not explicit null comparisons
- Priority color map consolidation into `components/constants.ts` is the only structural refactor -- everything else is in-place fixes
- The build must pass clean (`bun run build` and `bun run lint` with zero errors and warnings) after all changes

### Claude's Discretion
- Exact structure of the shared constants file (what else to include beyond priority colors)
- How to handle any unexpected Fluent UI API issues discovered during the audit
- Whether to group related fixes into one plan or separate plans

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PCF-02 | Badge component uses valid Fluent UI v9 size prop values (small/medium/large, not tiny) | **Pre-satisfied (verified):** All Badge components in the codebase already use valid size values (`"small"` and `"medium"` only). The Fluent UI v9 Badge API accepts `'tiny' | 'extra-small' | 'small' | 'medium' | 'large' | 'extra-large'`, confirmed from the installed `@fluentui/react-badge@9.x` type definitions. No "tiny" or other problematic size values exist in any source file. The full Fluent UI audit confirms no invalid prop values anywhere. |
| PCF-03 | Color tokens use correct Fluent UI v9 names (colorPaletteMarigoldBorder2, not colorPaletteYellowBorder2) | **Pre-satisfied (verified):** The codebase already uses `colorPaletteMarigoldBorder2` (correct) and does NOT reference `colorPaletteYellowBorder2` anywhere in source files. All six token references verified against the installed `@fluentui/tokens` package: `colorPaletteRedBorder2`, `colorPaletteMarigoldBorder2`, `colorPaletteGreenBorder2`, `colorNeutralStroke1`, `colorNeutralForeground1`, `colorNeutralForeground3` -- all valid. Note: both `colorPaletteMarigoldBorder2` and `colorPaletteYellowBorder2` exist in the token set; the project uses "Marigold" which is the semantically correct name for medium-priority amber/yellow. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @fluentui/react-components | ^9.46.0 (installed: 9.73.0) | Fluent UI v9 component library | Provides Badge, Text, tokens, and all components used in the PCF control |
| @fluentui/react-badge | 9.x (transitive) | Badge component implementation | Consumed through react-components facade; defines valid size/appearance/color prop types |
| @fluentui/tokens | 1.x (transitive) | Design token definitions | Consumed through react-components facade; defines all `colorPalette*` and `colorNeutral*` tokens |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| TypeScript | ^4.9.5 | Type checking | Enforces strict types -- will catch invalid prop values at compile time |

### Alternatives Considered
None -- this phase uses the existing stack. No new dependencies needed.

## Architecture Patterns

### Current File Structure
```
enterprise-work-assistant/src/AssistantDashboard/
├── index.ts                    # PCF entry point
├── components/
│   ├── types.ts                # NEEDS FIX: Priority/TemporalHorizon types
│   ├── constants.ts            # NEW: shared priority color map
│   ├── App.tsx                 # No changes needed
│   ├── CardDetail.tsx          # NEEDS FIX: N/A guards, priority badge null hide
│   ├── CardItem.tsx            # NEEDS FIX: N/A guards, item_summary fallback
│   ├── CardGallery.tsx         # No changes needed
│   └── FilterBar.tsx           # No changes needed
├── hooks/
│   └── useCardData.ts          # NEEDS FIX: N/A fallbacks, item_summary chain
└── styles/
    └── AssistantDashboard.css
```

### Pattern 1: Null-Based Optional Display (Priority Badge)
**What:** Hide a UI element entirely when its value is null, using a truthiness check
**When to use:** For optional display elements where null means "not applicable"
**Example:**
```typescript
// BEFORE (N/A string convention):
<Badge
    appearance="filled"
    style={{ backgroundColor: priorityColors[card.priority] }}
    size="medium"
>
    {card.priority}
</Badge>

// AFTER (null convention, hide on null):
{card.priority && (
    <Badge
        appearance="filled"
        style={{ backgroundColor: PRIORITY_COLORS[card.priority] }}
        size="medium"
    >
        {card.priority}
    </Badge>
)}
```
Source: Phase 1 null convention decision (SCHM-06); Phase 4 CONTEXT.md locked decision

### Pattern 2: Shared Constants Extraction
**What:** Move duplicated lookup maps to a shared constants file
**When to use:** When two or more components duplicate the same `Record<string, T>` map
**Example:**
```typescript
// components/constants.ts
import { tokens } from "@fluentui/react-components";

export const PRIORITY_COLORS: Record<string, string> = {
    High: tokens.colorPaletteRedBorder2,
    Medium: tokens.colorPaletteMarigoldBorder2,
    Low: tokens.colorPaletteGreenBorder2,
};
```
Source: Phase 4 CONTEXT.md locked decision

### Pattern 3: Truthiness Guards for Null Fields
**What:** Use `if (value)` instead of `value !== "N/A"` or `value !== null`
**When to use:** When checking whether to render optional display elements
**Example:**
```typescript
// BEFORE:
{card.temporal_horizon !== "N/A" && (
    <Badge appearance="outline" size="small">
        {card.temporal_horizon}
    </Badge>
)}

// AFTER:
{card.temporal_horizon && (
    <Badge appearance="outline" size="small">
        {card.temporal_horizon}
    </Badge>
)}
```
Source: Phase 4 CONTEXT.md locked decision

### Anti-Patterns to Avoid
- **Producing "N/A" strings in data hooks:** The useCardData hook should not fall back to `"N/A"` for any field. Use `null` for not-applicable values, matching the Phase 1 convention.
- **Defensive fallbacks for non-nullable fields:** `item_summary` is non-nullable per Phase 1 types.ts contract. Do not add `?? "fallback"` guards or `String()` wrappers.
- **Explicit null checks where truthiness suffices:** Per CONTEXT.md, prefer `if (card.draft_payload)` over `card.draft_payload !== null` for consistency.
- **Duplicating lookup maps across components:** Extract shared maps to `constants.ts`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Token color resolution | Custom hex color constants | `tokens.colorPalette*` from Fluent UI | Tokens auto-adapt to light/dark themes |
| Prop validation | Manual size/appearance value checks | TypeScript strict types + Fluent UI type definitions | Compiler catches invalid values at build time |
| Null convention | Custom "N/A" string sentinel values | Native `null` + TypeScript union types | Cleaner type narrowing, consistent with Phase 1 contract |

**Key insight:** With `strict: true` in tsconfig.json, TypeScript will enforce that Badge `size`, `appearance`, and `color` props only accept values in the Fluent UI union types. Invalid values cause compile errors, not runtime bugs.

## Common Pitfalls

### Pitfall 1: Type Narrowing After Truthiness Check
**What goes wrong:** After changing Priority/TemporalHorizon types to include `null`, TypeScript may require type narrowing before using the value as a Record key or JSX child.
**Why it happens:** `card.priority` has type `"High" | "Medium" | "Low" | null`. After a truthiness check (`card.priority &&`), TypeScript narrows this to `"High" | "Medium" | "Low"` inside the guarded block, which is exactly what we want for the color map lookup.
**How to avoid:** Always put the Badge rendering inside the truthiness guard block. Do not use the value outside the guard.
**Warning signs:** TypeScript errors about `null` not being a valid index or key.

### Pitfall 2: useCardData N/A Fallback Interacts with Type Changes
**What goes wrong:** Changing Priority type from `"High" | "Medium" | "Low" | "N/A"` to `"High" | "Medium" | "Low" | null` requires updating the useCardData fallback from `?? "N/A"` to `?? null`. If the fallback is not updated, TypeScript will error because `"N/A"` is no longer in the type union.
**Why it happens:** The type union change makes `"N/A"` an invalid value for the field.
**How to avoid:** Update both the type definition AND all places that produce values of that type (useCardData hook).
**Warning signs:** TypeScript error: `Type '"N/A"' is not assignable to type 'Priority'`.

### Pitfall 3: Schema vs. Types Divergence
**What goes wrong:** The output-schema.json still defines `priority` and `temporal_horizon` with `"N/A"` as valid enum values. Changing types.ts to use null creates a divergence between the JSON Schema and the TypeScript types.
**Why it happens:** The schema defines what the agent produces; types.ts defines what the PCF component consumes. The useCardData hook maps between them (converting "N/A" from parsed JSON to null for the component types).
**How to avoid:** Keep the mapping in useCardData clear: `parsed.priority === "N/A" ? null : parsed.priority` or simply rely on the existing `?? null` pattern. The schema is the agent-facing contract; types.ts is the UI-facing contract. They intentionally diverge at the mapping layer.
**Warning signs:** None at build time -- this is a design decision, not a bug. Document it in the code.

### Pitfall 4: Empty String Truthiness for draft_payload
**What goes wrong:** The CONTEXT says to use truthiness check for draft_payload (`if (card.draft_payload)`). If the agent ever produces an empty string `""` for draft_payload, a truthiness check would hide it, whereas the old `!== "N/A"` check would show it.
**Why it happens:** JavaScript truthiness: empty string is falsy, `"N/A"` is truthy.
**How to avoid:** This is the desired behavior per CONTEXT.md: "hides on null, undefined, and empty string." An empty draft_payload has no meaningful content to display.
**Warning signs:** None -- this is intentional.

### Pitfall 5: Priority Badge in CardDetail Shows Even When Null
**What goes wrong:** CardDetail currently unconditionally renders the priority badge. After the type change, `card.priority` can be null, and rendering `<Badge>{null}</Badge>` would show an empty badge.
**Why it happens:** CardDetail's priority Badge is not currently wrapped in a conditional guard because "N/A" was always a displayable string.
**How to avoid:** Wrap the priority Badge in `{card.priority && (...)}` to hide it when null.
**Warning signs:** Empty, contentless badge visible in the detail view.

## Code Examples

Verified patterns from codebase analysis:

### 1. Types Update (types.ts)
```typescript
// BEFORE:
export type Priority = "High" | "Medium" | "Low" | "N/A";
export type TemporalHorizon = "TODAY" | "THIS_WEEK" | "NEXT_WEEK" | "BEYOND" | "N/A";

// AFTER:
export type Priority = "High" | "Medium" | "Low";
export type TemporalHorizon = "TODAY" | "THIS_WEEK" | "NEXT_WEEK" | "BEYOND";
```
And in AssistantCard interface:
```typescript
// BEFORE:
priority: Priority;
temporal_horizon: TemporalHorizon;

// AFTER:
priority: Priority | null;
temporal_horizon: TemporalHorizon | null;
```
Source: Phase 1 null convention; Phase 4 CONTEXT.md

### 2. Shared Constants File (components/constants.ts)
```typescript
import { tokens } from "@fluentui/react-components";

/**
 * Priority-to-color mapping for badge border/background styling.
 * Only valid priority values have entries -- null priority hides the badge entirely.
 */
export const PRIORITY_COLORS: Record<string, string> = {
    High: tokens.colorPaletteRedBorder2,
    Medium: tokens.colorPaletteMarigoldBorder2,
    Low: tokens.colorPaletteGreenBorder2,
};
```
Source: Phase 4 CONTEXT.md locked decision

### 3. useCardData Null Fallbacks (hooks/useCardData.ts)
```typescript
// BEFORE:
priority: (parsed.priority as Priority) ?? "N/A",
temporal_horizon: (parsed.temporal_horizon as TemporalHorizon) ?? "N/A",
item_summary: String(parsed.item_summary ?? record.getValue("cr_itemsummary") ?? ""),

// AFTER:
priority: (parsed.priority as Priority) ?? null,
temporal_horizon: (parsed.temporal_horizon as TemporalHorizon) ?? null,
item_summary: parsed.item_summary ?? "",
```
Note: For priority/temporal_horizon, when the agent produces `"N/A"` in JSON, the parsed value will be the string `"N/A"`. Since `"N/A"` is no longer in the type union, we need an explicit mapping: treat `"N/A"` as null. The cleanest approach:
```typescript
priority: parsed.priority && parsed.priority !== "N/A"
    ? (parsed.priority as Priority)
    : null,
temporal_horizon: parsed.temporal_horizon && parsed.temporal_horizon !== "N/A"
    ? (parsed.temporal_horizon as TemporalHorizon)
    : null,
```
Source: Phase 4 CONTEXT.md; Phase 1 null convention

### 4. CardItem.tsx Null Guards
```typescript
// BEFORE (temporal_horizon):
{card.temporal_horizon !== "N/A" && (
    <Badge appearance="outline" size="small">
        {card.temporal_horizon}
    </Badge>
)}

// AFTER:
{card.temporal_horizon && (
    <Badge appearance="outline" size="small">
        {card.temporal_horizon}
    </Badge>
)}

// BEFORE (item_summary):
{card.item_summary ?? "No summary available"}

// AFTER:
{card.item_summary}
```
Source: Phase 4 CONTEXT.md locked decisions

### 5. CardDetail.tsx Guards
```typescript
// BEFORE (draft_payload at lines 150 and 182):
{card.draft_payload && card.draft_payload !== "N/A" && (

// AFTER:
{card.draft_payload && (

// BEFORE (temporal_horizon):
{card.temporal_horizon !== "N/A" && (

// AFTER:
{card.temporal_horizon && (

// BEFORE (priority badge -- unconditional):
<Badge
    appearance="filled"
    style={{ backgroundColor: priorityColors[card.priority] }}
    size="medium"
>
    {card.priority}
</Badge>

// AFTER (conditional, hide on null):
{card.priority && (
    <Badge
        appearance="filled"
        style={{ backgroundColor: PRIORITY_COLORS[card.priority] }}
        size="medium"
    >
        {card.priority}
    </Badge>
)}
```
Source: Phase 4 CONTEXT.md locked decisions

## Fluent UI v9 API Audit Results

Full audit of all Fluent UI v9 component prop values and token references used across all PCF source files.

### Badge Component Usage
| File | Line | Prop | Value | Valid? |
|------|------|------|-------|--------|
| CardItem.tsx | 62 | appearance | `statusAppearance[card.card_status]` (dynamic: "filled", "outline", "tint") | YES -- all in `'filled' \| 'ghost' \| 'outline' \| 'tint'` |
| CardItem.tsx | 63 | color | `statusColor[card.card_status]` (dynamic: "success", "warning", "informative", "subtle") | YES -- all in `'brand' \| 'danger' \| 'important' \| 'informative' \| 'severe' \| 'subtle' \| 'success' \| 'warning'` |
| CardItem.tsx | 64 | size | `"small"` | YES |
| CardItem.tsx | 69 | appearance | `"outline"` | YES |
| CardItem.tsx | 69 | size | `"small"` | YES |
| CardDetail.tsx | 71 | appearance | `"filled"` | YES |
| CardDetail.tsx | 73 | size | `"medium"` | YES |
| CardDetail.tsx | 78 | appearance/size | `"outline"` / `"medium"` | YES |
| CardDetail.tsx | 82 | appearance/size | `"outline"` / `"medium"` | YES |
| CardDetail.tsx | 86 | appearance/size | `"tint"` / `"medium"` | YES |
| CardDetail.tsx | 140 | appearance/size | `"outline"` / `"small"` | YES |
| FilterBar.tsx | 33 | appearance/size | `"outline"` / `"small"` | YES |

### Token References
| Token | Files Using | Exists in @fluentui/tokens? |
|-------|-------------|----------------------------|
| `colorPaletteRedBorder2` | CardItem.tsx, CardDetail.tsx | YES (verified in tokens.js line 194) |
| `colorPaletteMarigoldBorder2` | CardItem.tsx, CardDetail.tsx | YES (verified in tokens.js line 247) |
| `colorPaletteGreenBorder2` | CardItem.tsx, CardDetail.tsx | YES (verified in tokens.js line 205) |
| `colorNeutralStroke1` | CardItem.tsx, CardDetail.tsx | YES (verified in tokens.js line 145) |
| `colorNeutralForeground1` | FilterBar.tsx | YES (verified in tokens.js line 3) |
| `colorNeutralForeground3` | CardItem.tsx, CardGallery.tsx | YES (verified in tokens.js line 14) |

### Other Component Props
| Component | File | Prop | Value | Valid? |
|-----------|------|------|-------|--------|
| Card | CardItem.tsx | className | string | YES |
| Card | CardItem.tsx | style | object | YES |
| Card | CardItem.tsx | onClick | function | YES |
| Button | CardDetail.tsx | appearance | `"subtle"`, `"primary"`, `"secondary"` | YES |
| Text | multiple | size | `200`, `300`, `400`, `500` | YES (numeric sizes) |
| Text | multiple | weight | `"semibold"` | YES |
| Text | multiple | block | boolean | YES |
| Link | CardDetail.tsx | href/target/rel | standard HTML | YES |
| Textarea | CardDetail.tsx | resize | `"vertical"` | YES |
| Textarea | CardDetail.tsx | readOnly | boolean | YES |
| Spinner | CardDetail.tsx | size | `"small"` | YES |
| Spinner | CardDetail.tsx | label | string | YES |
| MessageBar | CardDetail.tsx | intent | `"warning"` | YES |
| FluentProvider | App.tsx | theme | `webLightTheme` / `webDarkTheme` | YES |

**Audit conclusion:** All Fluent UI v9 prop values and token references are correct. No invalid API usage found. PCF-02 and PCF-03 are pre-satisfied. The phase work is entirely contract drift cleanup and type alignment.

## Inventory of Changes Required

### Summary Table

| File | Issue | Fix Category |
|------|-------|-------------|
| `types.ts` | `Priority` and `TemporalHorizon` include `"N/A"` variant | Type update: remove "N/A", make fields nullable |
| `constants.ts` | Does not exist yet | New file: shared PRIORITY_COLORS map |
| `useCardData.ts:47` | `?? "N/A"` fallback for priority | Change to null with "N/A" mapping |
| `useCardData.ts:48` | `?? "N/A"` fallback for temporal_horizon | Change to null with "N/A" mapping |
| `useCardData.ts:46` | `String(parsed.item_summary ?? ...)` cascading chain | Simplify to `parsed.item_summary ?? ""` |
| `CardItem.tsx:20-25` | Duplicate `priorityColors` with "N/A" entry | Import from constants.ts, remove local map |
| `CardItem.tsx:48` | `priorityColors[card.priority] \|\| tokens.colorNeutralStroke1` | Import PRIORITY_COLORS, add null guard |
| `CardItem.tsx:68` | `card.temporal_horizon !== "N/A"` guard | Change to truthiness check |
| `CardItem.tsx:76` | `card.item_summary ?? "No summary available"` | Remove fallback, use `card.item_summary` directly |
| `CardDetail.tsx:23-28` | Duplicate `priorityColors` with "N/A" entry | Import from constants.ts, remove local map |
| `CardDetail.tsx:70-76` | Priority badge rendered unconditionally | Wrap in `{card.priority && (...)}` |
| `CardDetail.tsx:85` | `card.temporal_horizon !== "N/A"` guard | Change to truthiness check |
| `CardDetail.tsx:150` | `card.draft_payload !== "N/A"` guard | Remove (truthiness check suffices) |
| `CardDetail.tsx:182` | `card.draft_payload !== "N/A"` guard | Remove (truthiness check suffices) |

**Total: 14 changes across 5 files (4 existing + 1 new)**

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `"N/A"` string sentinel for not-applicable | `null` with TypeScript union types | Phase 1 (SCHM-06) | Cleaner type narrowing, truthiness checks |
| Nullable casts for non-nullable fields | Trust type contract, no defensive fallbacks | Phase 1 (item_summary decision) | Simpler code, fewer unnecessary null guards |
| Duplicated lookup maps across components | Shared constants file | Phase 4 (this phase) | Single source of truth, easier maintenance |

**Deprecated/outdated:**
- `"N/A"` as a string value for Priority/TemporalHorizon in types.ts: Replaced by null convention from Phase 1
- `String()` coercion on non-nullable fields: Unnecessary when type contract guarantees string

## Open Questions

1. **Schema vs. types.ts divergence for "N/A"**
   - What we know: output-schema.json defines `"N/A"` as valid enum values for `priority` and `temporal_horizon`. types.ts will remove `"N/A"` and use `null`. The mapping happens in useCardData.
   - What's unclear: Whether the schema should also be updated to use null instead of "N/A" for these fields.
   - Recommendation: Do NOT modify the schema in this phase. The schema is the agent-facing contract (what the LLM produces). The useCardData hook maps agent output to UI types. This divergence is intentional and the mapping layer handles it cleanly. Schema changes belong in a separate phase if ever needed.

2. **Other fields with "N/A" fallbacks in useCardData**
   - What we know: The CONTEXT limits item_summary cleanup scope. Priority and temporal_horizon N/A fallbacks are explicitly in scope.
   - What's unclear: Whether `card_status ?? "SUMMARY_ONLY"` and `trigger_type ?? "EMAIL"` fallbacks should also be reviewed.
   - Recommendation: Leave non-N/A fallbacks as-is per CONTEXT scope limitation. These use valid enum values as defaults, not "N/A" sentinels.

## Sources

### Primary (HIGH confidence)
- Installed `@fluentui/react-badge/dist/index.d.ts` (v9.x via react-components 9.73.0) -- Badge size type: `'tiny' | 'extra-small' | 'small' | 'medium' | 'large' | 'extra-large'`; appearance type: `'filled' | 'ghost' | 'outline' | 'tint'`; color type: `'brand' | 'danger' | 'important' | 'informative' | 'severe' | 'subtle' | 'success' | 'warning'`
- Installed `@fluentui/tokens/lib/tokens.js` -- Verified all 6 token names exist: colorPaletteRedBorder2 (line 194), colorPaletteMarigoldBorder2 (line 247), colorPaletteGreenBorder2 (line 205), colorNeutralStroke1 (line 145), colorNeutralForeground1 (line 3), colorNeutralForeground3 (line 14)
- Phase 1 verification report (01-VERIFICATION.md) -- Confirmed item_summary is non-nullable string, SCHM-06 null convention established
- Phase 3 verification report (03-VERIFICATION.md) -- Confirmed all token imports use @fluentui/react-components, build passes clean
- Milestone audit (v1.0-MILESTONE-AUDIT.md) -- Identified specific tech debt items: useCardData line 46 nullable cast, CardItem line 76 null guard, CardDetail lines 150/182 N/A guards

### Secondary (MEDIUM confidence)
- Phase 3 research (03-RESEARCH.md) -- Token name verification confirmed all 6 tokens valid; noted both colorPaletteYellowBorder2 and colorPaletteMarigoldBorder2 exist in token set

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All prop values and token names verified against installed package type definitions
- Architecture: HIGH -- All source files read in full, every change location identified with line numbers
- Pitfalls: HIGH -- Type narrowing and schema divergence patterns are well-understood TypeScript mechanics
- Fluent UI audit: HIGH -- Every component prop and token reference cross-checked against installed .d.ts files

**Research date:** 2026-02-21
**Valid until:** 2026-04-21 (60 days -- Fluent UI v9 API surface is stable, token names don't change)
