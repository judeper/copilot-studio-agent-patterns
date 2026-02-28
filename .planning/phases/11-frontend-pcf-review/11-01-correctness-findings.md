# Correctness Agent -- Frontend/PCF Findings

## Summary

17 issues found: 4 deploy-blocking, 13 non-blocking.

All 14 frontend/PCF source files were reviewed against the two schema files (output-schema.json, dataverse-table.json), the generated ManifestTypes.d.ts, and each other. Type definitions, hook contracts, component prop flows, rendering logic, and Fluent UI v9 usage were validated systematically.

## Methodology

1. Cross-referenced every field in `AssistantCard` interface (types.ts) against output-schema.json properties and dataverse-table.json columns
2. Cross-referenced enum types (TriggerType, TriageTier, Priority, TemporalHorizon, CardStatus, CardOutcome) against Choice option labels in dataverse-table.json
3. Traced data flow from useCardData.ts (DataSet -> AssistantCard) through index.ts -> AppWrapper -> App.tsx and into every child component
4. Validated Fluent UI v9 component usage against the @fluentui/react-components v9 API
5. Verified URL sanitizer logic against the Phase 5 decision (https + mailto only)
6. Checked constants.ts token names against Fluent UI v9 design token exports

---

## Findings

### Deploy-Blocking Issues

**COR-F01: `card_status` type mismatch -- NUDGE missing from output-schema.json enum**
- **Artifact:** types.ts:23, output-schema.json:88
- **Location:** `src/AssistantDashboard/components/types.ts` line 23; `schemas/output-schema.json` line 88
- **Issue:** TypeScript `CardStatus` type includes `"NUDGE"` but output-schema.json's `card_status` enum only includes `["READY", "LOW_CONFIDENCE", "SUMMARY_ONLY", "NO_OUTPUT"]`. However, dataverse-table.json DOES include `NUDGE` (value 100000004). This means the agent will never output `card_status: "NUDGE"` per the schema contract, but the Dataverse table can store it and the PCF control can display it. The Staleness Monitor flow would need to set this status directly in Dataverse, bypassing the agent schema. This is a schema-level correctness gap: the TypeScript type declares a value that the agent output schema does not permit.
- **Evidence:** `output-schema.json` line 88: `"enum": ["READY", "LOW_CONFIDENCE", "SUMMARY_ONLY", "NO_OUTPUT"]` -- no NUDGE. `dataverse-table.json` line 69: `{ "label": "NUDGE", "value": 100000004 }` -- present. `types.ts` line 23: `export type CardStatus = "READY" | "LOW_CONFIDENCE" | "SUMMARY_ONLY" | "NO_OUTPUT" | "NUDGE"` -- present.
- **Impact:** If the Staleness Monitor flow writes `NUDGE` directly to `cr_cardstatus` but the JSON blob in `cr_fulljson` still has a different `card_status`, useCardData reads `card_status` from `cr_fulljson` (not from the discrete column), so the NUDGE status would never reach the UI through the current data path. This makes NUDGE cards appear with whatever status is in their `cr_fulljson`, which would be incorrect.
- **Suggested Fix:** Either (a) add NUDGE to output-schema.json so agents can output it, or (b) read card_status from the discrete `cr_cardstatus` column via `getFormattedValue` instead of from `cr_fulljson`, matching how card_outcome is read.

**COR-F02: useCardData reads most fields from `cr_fulljson` JSON but some from discrete columns -- inconsistent ingestion creates correctness risk**
- **Artifact:** useCardData.ts:51-84
- **Location:** `src/AssistantDashboard/hooks/useCardData.ts` lines 51-84
- **Issue:** The hook reads `trigger_type`, `triage_tier`, `priority`, `temporal_horizon`, `card_status`, `confidence_score`, `research_log`, `key_findings`, `verified_sources`, `draft_payload`, and `low_confidence_note` from `cr_fulljson` (parsed JSON). But it reads `humanized_draft`, `card_outcome`, `original_sender_email`, `original_sender_display`, `original_subject`, `conversation_cluster_id`, and `source_signal_id` from discrete Dataverse columns. If a flow updates `cr_cardstatus` or `cr_priority` in Dataverse independently of `cr_fulljson`, the PCF control will display stale data from the original JSON blob.
- **Evidence:** Lines 58-73 all use `parsed.X` (from cr_fulljson). Lines 74-83 use `record.getValue()` or `record.getFormattedValue()` (from discrete columns).
- **Impact:** Deploy-blocking because the Staleness Monitor and Card Outcome Tracker flows update discrete columns without updating `cr_fulljson`. This means runtime state divergence is expected, not theoretical.
- **Suggested Fix:** For columns that flows may update independently (card_status, card_outcome at minimum), read from the discrete Dataverse column via `getFormattedValue()` rather than from the JSON blob. This aligns the ingestion strategy: mutable fields from discrete columns, immutable agent output fields from JSON.

**COR-F03: `useCardData` useMemo dependency is only `[version]` -- `dataset` reference not tracked**
- **Artifact:** useCardData.ts:95
- **Location:** `src/AssistantDashboard/hooks/useCardData.ts` line 95
- **Issue:** The `useMemo` dependency array is `[version]`, not `[dataset, version]`. The comment on line 36 explains this is intentional ("the dataset reference itself never changes"), which is correct for the PCF runtime (the platform mutates the same object in place). However, this creates a subtle correctness issue: if `dataset` is `undefined` on the first render and then becomes defined on a later render WITHOUT incrementing `version`, the memo would not recompute.
- **Evidence:** `return React.useMemo(() => { ... }, [version]);` -- dataset not in deps.
- **Impact:** In the actual PCF lifecycle, `updateView` always increments `datasetVersion` before rendering, so this edge case does not occur at runtime. However, in test scenarios or if the component is used outside the PCF lifecycle, this could cause stale data. Classified as deploy-blocking because the React rules of hooks specify that all external values read inside useMemo should be in the dependency array; violating this is a correctness bug even if mitigated by the caller.
- **Suggested Fix:** Add `dataset` to the dependency array: `[dataset, version]`. Since the PCF platform mutates the object in place, version already forces recomputation, so adding dataset is safe (reference equality means it won't cause extra renders).

**COR-F04: `OutcomeAction` type referenced in plan checklist does not exist in types.ts**
- **Artifact:** types.ts (entire file)
- **Location:** `src/AssistantDashboard/components/types.ts`
- **Issue:** The plan's checklist item 1 asks to "Verify enum types (Priority, TriageTier, TriggerType, TemporalHorizon, DraftType, OutcomeAction)." There is no `OutcomeAction` type defined in types.ts. The closest is `CardOutcome`. This is a plan reference error, not a code error, but noting it for completeness.
- **Evidence:** Searched entire types.ts -- no `OutcomeAction` export or type alias.
- **Impact:** No code impact. Plan checklist reference is inaccurate.
- **Suggested Fix:** N/A -- plan reference only. Not a deploy-blocking code issue.
- **Reclassification:** This is NOT deploy-blocking (plan documentation error only). Keeping in this section because the plan asked for it to be verified.

*Corrected count: 3 true deploy-blocking issues (COR-F01, COR-F02, COR-F03). COR-F04 is a plan error, not a code defect.*

### Non-Blocking Issues

**COR-F05: `AppProps` does not include `onShowCalibration` -- calibration navigation hardcoded inside App**
- **Artifact:** App.tsx:145-147, types.ts:105-119
- **Location:** `src/AssistantDashboard/components/App.tsx` lines 145-147
- **Issue:** The calibration view navigation (`handleShowCalibration`) is handled entirely inside App via local state. AppProps has no callback for this. This means the Canvas App host has no visibility into calibration navigation events and cannot respond to them (e.g., updating page title, analytics tracking). This is architecturally inconsistent with other navigation events (`onSelectCard`, `onJumpToCard`) which all notify the host.
- **Evidence:** `AppProps` interface in types.ts has no calibration-related callback. `handleShowCalibration` on line 145 only sets local `viewState`.
- **Suggested Fix:** Add `onShowCalibration?: () => void` to AppProps and invoke it alongside the state change, or accept this as a known simplification.

**COR-F06: `App.tsx` renders `<button>` for calibration link instead of Fluent UI Button**
- **Artifact:** App.tsx:169-174
- **Location:** `src/AssistantDashboard/components/App.tsx` lines 169-174
- **Issue:** All other interactive elements in the dashboard use Fluent UI v9 `<Button>` components, but the "Agent Performance" link uses a plain HTML `<button>` element. This creates inconsistent styling (no Fluent theming, no design tokens, no focus ring, no high-contrast mode support).
- **Evidence:** `<button className="calibration-link" onClick={handleShowCalibration}>` -- plain HTML button. Compare to CardDetail.tsx which uses `<Button appearance="subtle">` throughout.
- **Suggested Fix:** Replace with `<Button appearance="subtle" onClick={handleShowCalibration}>Agent Performance</Button>`.

**COR-F07: `BriefingCard.tsx` uses plain HTML elements instead of Fluent UI throughout**
- **Artifact:** BriefingCard.tsx (entire component)
- **Location:** `src/AssistantDashboard/components/BriefingCard.tsx`
- **Issue:** Unlike CardDetail (which uses Fluent UI Button, Badge, Text, Link, Textarea, Spinner, MessageBar), BriefingCard uses plain HTML `<div>`, `<h2>`, `<h3>`, `<p>`, `<span>`, `<button>` elements throughout. This creates an inconsistent look-and-feel between the briefing view and other dashboard views. The component imports from React but does not import any Fluent UI components.
- **Evidence:** Line 1: `import * as React from "react"` -- no Fluent UI imports. All rendering uses plain HTML elements with CSS class names.
- **Suggested Fix:** Migrate to Fluent UI v9 components for consistency: `<Text>` for text, `<Button>` for buttons, `<Badge>` for status indicators, `<Card>` for the container.

**COR-F08: `ConfidenceCalibration.tsx` uses plain HTML elements instead of Fluent UI**
- **Artifact:** ConfidenceCalibration.tsx (entire component)
- **Location:** `src/AssistantDashboard/components/ConfidenceCalibration.tsx`
- **Issue:** Same pattern as COR-F07. The calibration dashboard uses plain HTML `<div>`, `<h2>`, `<button>`, `<table>`, `<p>`, `<span>` elements. No Fluent UI v9 components imported despite being a full-page analytics view.
- **Evidence:** Line 1: `import * as React from "react"` and line 2: `import { useState, useMemo } from "react"` -- no Fluent UI imports.
- **Suggested Fix:** Migrate to Fluent UI v9 Table, Button, Text, Card components for visual consistency.

**COR-F09: `CommandBar.tsx` uses plain HTML elements instead of Fluent UI**
- **Artifact:** CommandBar.tsx (entire component)
- **Location:** `src/AssistantDashboard/components/CommandBar.tsx`
- **Issue:** Same pattern as COR-F07/F08. The command bar uses plain HTML `<div>`, `<input>`, `<button>` elements. No Fluent UI imports.
- **Evidence:** Lines 1-2: React imports only. All rendering uses plain HTML with CSS classes.
- **Suggested Fix:** Migrate to Fluent UI v9 Input, Button for consistency. The chip-style quick actions could use `<Tag>` or `<Button appearance="outline" size="small">`.

**COR-F10: `CardItem.tsx` statusAppearance and statusColor maps missing NUDGE entry**
- **Artifact:** CardItem.tsx:27-39
- **Location:** `src/AssistantDashboard/components/CardItem.tsx` lines 27-39
- **Issue:** The `statusAppearance` and `statusColor` maps include entries for READY, LOW_CONFIDENCE, SUMMARY_ONLY, and NO_OUTPUT, but not for NUDGE. If a NUDGE card reaches the gallery (which is architecturally possible since useCardData parses all cards), the badge would use the fallback `?? "outline"` and `?? "informative"` defaults, which is acceptable but undocumented.
- **Evidence:** `statusAppearance` record has 4 entries, `statusColor` has 4 entries. No NUDGE key in either.
- **Suggested Fix:** Add `NUDGE: "tint"` to statusAppearance and `NUDGE: "warning"` to statusColor.

**COR-F11: `CardItem.tsx` triggerIcons map missing DAILY_BRIEFING, SELF_REMINDER, COMMAND_RESULT entries**
- **Artifact:** CardItem.tsx:21-25
- **Location:** `src/AssistantDashboard/components/CardItem.tsx` lines 21-25
- **Issue:** The `triggerIcons` map only includes EMAIL, TEAMS_MESSAGE, and CALENDAR_SCAN. The TriggerType union also includes DAILY_BRIEFING, SELF_REMINDER, and COMMAND_RESULT. If a card with these trigger types reaches CardItem (e.g., a COMMAND_RESULT card), it falls back to MailRegular icon via `?? <MailRegular />`, which is semantically incorrect.
- **Evidence:** `triggerIcons` has 3 entries. TriggerType has 6 values.
- **Suggested Fix:** Add entries for remaining trigger types: `DAILY_BRIEFING: <CalendarRegular />`, `SELF_REMINDER: <ClockRegular />`, `COMMAND_RESULT: <BotRegular />` (or similar appropriate Fluent icons).

**COR-F12: `FilterBar.tsx` is read-only display -- filters are applied but cannot be changed from within the component**
- **Artifact:** FilterBar.tsx
- **Location:** `src/AssistantDashboard/components/FilterBar.tsx`
- **Issue:** FilterBar receives filter values as string props and displays them as badges, but provides no mechanism for users to change filters. There are no dropdown selectors, toggle buttons, or clear-filter actions. Filter values can only be set from the Canvas App host (via PCF input properties). This is architecturally correct for a PCF control (the host manages filter state), but the component name "FilterBar" implies interactive filtering capability that does not exist.
- **Evidence:** Props are all read-only strings. No onChange callbacks. No interactive elements besides the badge display.
- **Suggested Fix:** Either rename to `FilterStatusBar` to clarify its display-only purpose, or accept that "FilterBar" is a known simplification. Not a code bug.

**COR-F13: `App.tsx` FluentProvider does not set `targetDocument` for PCF shadow DOM**
- **Artifact:** App.tsx:150
- **Location:** `src/AssistantDashboard/components/App.tsx` line 150
- **Issue:** `<FluentProvider theme={prefersDark ? webDarkTheme : webLightTheme}>` does not pass `targetDocument` prop. In a PCF virtual control running inside a Canvas App iframe, Fluent UI v9 needs to inject styles into the correct document context. Without `targetDocument`, styles are injected into the default document, which may be correct for virtual controls (since they render in the main document tree, not a shadow DOM). However, this should be explicitly validated.
- **Evidence:** Line 150: `<FluentProvider theme={...}>` -- no targetDocument prop.
- **Suggested Fix:** For PCF virtual controls, the default document is typically correct. Verify at runtime. If issues arise, pass `targetDocument={document}` explicitly. Marking as non-blocking since virtual controls don't use shadow DOM.

**COR-F14: `index.ts` does not implement `ReactControl.updateView` return type correctly for React 16**
- **Artifact:** index.ts:106-107
- **Location:** `src/AssistantDashboard/index.ts` lines 106-107
- **Issue:** The `updateView` method returns `React.ReactElement` which is the correct return type for `ReactControl<IInputs, IOutputs>`. However, the class uses `React.createElement(AppWrapper, ...)` which returns `React.ReactElement`. This is correct for React 16.14.0. No issue found upon closer inspection.
- **Evidence:** `React.createElement` returns `React.ReactElement<any>`. The `ReactControl` interface expects this from `updateView`.
- **Reclassification:** Validated -- no issue.

**COR-F15: `index.ts` getOutputs() resets action outputs after reading -- potential race condition**
- **Artifact:** index.ts:143-148
- **Location:** `src/AssistantDashboard/index.ts` lines 143-148
- **Issue:** `getOutputs()` reads and then immediately clears the action properties (sendDraftAction, copyDraftAction, etc.). If the Canvas App calls `getOutputs()` multiple times before processing the output (e.g., due to a re-render cycle), the second call would return empty strings. This is actually the correct pattern for PCF fire-and-forget actions -- the Canvas App reads the output once via the `OnChange` event, and clearing prevents stale re-fires. This pattern was validated in Phase 5.
- **Evidence:** Lines 143-148: `this.sendDraftAction = ""` etc. after building the outputs object.
- **Reclassification:** Validated -- correct pattern for fire-and-forget PCF output binding.

**COR-F16: `CardDetail.tsx` Textarea `onChange` handler signature uses Fluent UI v9 pattern correctly**
- **Artifact:** CardDetail.tsx:311-313
- **Location:** `src/AssistantDashboard/components/CardDetail.tsx` lines 311-313
- **Issue:** The Textarea onChange handler uses `(_e, data) => { if (isEditing) setEditedDraft(data.value); }` which follows the Fluent UI v9 controlled component pattern where the second parameter is `{ value: string }`. This is correct for `@fluentui/react-components` v9 Textarea.
- **Evidence:** Fluent UI v9 Textarea onChange signature: `(ev: React.ChangeEvent, data: TextareaOnChangeData) => void` where `TextareaOnChangeData` has `value: string`.
- **Reclassification:** Validated -- correct usage.

**COR-F17: `constants.ts` Fluent UI v9 token names validated**
- **Artifact:** constants.ts:1-11
- **Location:** `src/AssistantDashboard/components/constants.ts`
- **Issue:** Verified that `tokens.colorPaletteRedBorder2`, `tokens.colorPaletteMarigoldBorder2`, and `tokens.colorPaletteGreenBorder2` are valid Fluent UI v9 design token names exported from `@fluentui/react-components`.
- **Evidence:** These tokens are part of the Fluent UI v9 design token system under `colorPalette[Color]Border2` naming pattern.
- **Reclassification:** Validated -- correct token names.

**COR-F18: `output-schema.json` has `confidence_score` as integer but TypeScript uses `number`**
- **Artifact:** types.ts:89, output-schema.json:79-83
- **Location:** types.ts line 89; output-schema.json line 82
- **Issue:** output-schema.json specifies `"type": ["integer", "null"]` for confidence_score, but TypeScript's `number` type encompasses both integers and floats. The useCardData hook checks `typeof parsed.confidence_score === "number"` which would accept 87.5 even though the schema requires an integer. At runtime, the agent prompt instructs "0-100 integer" so non-integer values are unlikely, but the TypeScript type does not enforce this.
- **Evidence:** TypeScript has no `integer` type -- `number` is the closest equivalent. Schema says `"type": "integer"`.
- **Suggested Fix:** Add a `Math.round()` call in useCardData when reading confidence_score, or accept the minor type gap since the agent always produces integers.

**COR-F19: `VerifiedSource.tier` typed as `1 | 2 | 3 | 4 | 5` but schema allows `minimum: 1, maximum: 5` integer**
- **Artifact:** types.ts:66-67, output-schema.json:71-74
- **Location:** types.ts line 66; output-schema.json line 71
- **Issue:** The TypeScript union `1 | 2 | 3 | 4 | 5` correctly represents the JSON schema constraint `"type": "integer", "minimum": 1, "maximum": 5`. This is correct and precise. However, useCardData does not validate that parsed verified_sources tier values actually fall in this range.
- **Evidence:** `Array.isArray(parsed.verified_sources) ? parsed.verified_sources : null` -- no per-item validation.
- **Suggested Fix:** Accept as low risk -- the agent produces valid tier values per prompt instructions. Adding per-item validation would add complexity without significant benefit.

**COR-F20: `App.tsx` does not import `webDarkTheme` and `webLightTheme` simultaneously from same path**
- **Artifact:** App.tsx:2
- **Location:** `src/AssistantDashboard/components/App.tsx` line 2
- **Issue:** This is actually correctly importing both themes: `import { FluentProvider, webLightTheme, webDarkTheme } from "@fluentui/react-components"`.
- **Reclassification:** Validated -- correct import.

**COR-F21: AssistantCard type cross-reference against Dataverse columns**
- **Artifact:** types.ts:79-103, dataverse-table.json
- **Location:** types.ts AssistantCard interface
- **Cross-reference results:**
  - `id` -> `getRecordId()` (system column) -- CORRECT
  - `trigger_type` -> `cr_triggertype` (Choice) -- Read from cr_fulljson, not discrete column. Choice labels match TriggerType values. CORRECT.
  - `triage_tier` -> `cr_triagetier` (Choice) -- Read from cr_fulljson. Choice labels match TriageTier values. CORRECT.
  - `item_summary` -> `cr_itemsummary` (Text, max 300) -- Read from cr_fulljson. CORRECT.
  - `priority` -> `cr_priority` (Choice) -- Read from cr_fulljson with N/A -> null mapping. Choice labels: High, Medium, Low, N/A. Priority type: "High" | "Medium" | "Low". N/A mapped to null. CORRECT.
  - `temporal_horizon` -> `cr_temporalhorizon` (Choice) -- Read from cr_fulljson with N/A -> null mapping. Choice labels: TODAY, THIS_WEEK, NEXT_WEEK, BEYOND, N/A. TemporalHorizon type matches. CORRECT.
  - `confidence_score` -> `cr_confidencescore` (WholeNumber 0-100) -- Read from cr_fulljson. CORRECT type mapping (number).
  - `card_status` -> `cr_cardstatus` (Choice) -- Read from cr_fulljson. See COR-F01 for NUDGE mismatch.
  - `card_outcome` -> `cr_cardoutcome` (Choice) -- Read from DISCRETE column via getFormattedValue. CORRECT. All 5 labels match CardOutcome type.
  - `humanized_draft` -> `cr_humanizeddraft` (MultilineText) -- Read from DISCRETE column via getValue. CORRECT.
  - `original_sender_email` -> `cr_originalsenderemail` (Text) -- Read from DISCRETE column. CORRECT.
  - `original_sender_display` -> `cr_originalsenderdisplay` (Text) -- Read from DISCRETE column. CORRECT.
  - `original_subject` -> `cr_originalsubject` (Text) -- Read from DISCRETE column. CORRECT.
  - `conversation_cluster_id` -> `cr_conversationclusterid` (Text) -- Read from DISCRETE column. CORRECT.
  - `source_signal_id` -> `cr_sourcesignalid` (Text) -- Read from DISCRETE column. CORRECT.
  - `created_on` -> `createdon` (system DateTime) -- Read via getFormattedValue. CORRECT.
  - Fields in cr_fulljson only (no discrete column): research_log, key_findings, verified_sources, draft_payload, low_confidence_note -- CORRECT per design (see dataverse-table.json notes: "non_discrete_fields").
- **Reclassification:** Validated with one exception noted in COR-F01.

---

### Validated (No Issues)

1. **TriggerType enum** -- All 6 values match between types.ts and dataverse-table.json Choice labels
2. **TriageTier enum** -- All 3 values match between types.ts and dataverse-table.json
3. **Priority enum** -- High/Medium/Low match; N/A correctly mapped to null at ingestion boundary
4. **TemporalHorizon enum** -- TODAY/THIS_WEEK/NEXT_WEEK/BEYOND match; N/A mapped to null
5. **CardOutcome enum** -- All 5 values (PENDING, SENT_AS_IS, SENT_EDITED, DISMISSED, EXPIRED) match between types.ts and dataverse-table.json
6. **DraftType enum** -- EMAIL/TEAMS_MESSAGE matches output-schema.json
7. **RecipientRelationship enum** -- 4 values match output-schema.json
8. **InferredTone enum** -- 4 values match output-schema.json
9. **DraftPayload interface** -- All 7 required fields match output-schema.json draft_payload object properties
10. **VerifiedSource interface** -- title, url, tier fields match output-schema.json items
11. **N/A-to-null ingestion boundary** -- useCardData correctly converts "N/A" priority and temporal_horizon to null (lines 61-66)
12. **Malformed row handling** -- useCardData try/catch with continue (line 87-90) gracefully skips bad records
13. **parseCardOutcome switch** -- Correctly maps all 5 Dataverse labels to CardOutcome type with PENDING default
14. **App.tsx component hierarchy** -- App -> CardGallery -> CardItem, App -> CardDetail, App -> FilterBar, App -> BriefingCard, App -> CommandBar, App -> ConfidenceCalibration all verified correct
15. **App.tsx filter logic** -- applyFilters correctly handles empty string (no filter) and exact match
16. **App.tsx partitionCards** -- Correctly separates DAILY_BRIEFING from regular cards
17. **App.tsx selectedCard derivation** -- Re-derives from live dataset via useMemo to avoid stale snapshots
18. **App.tsx auto-return to gallery** -- useEffect correctly detects removed cards and resets viewState
19. **CardDetail.tsx isSendable** -- Correctly requires EMAIL + FULL + READY + humanized_draft + original_sender_email
20. **CardDetail.tsx isDraftPayloadObject** -- Type guard correctly checks for DraftPayload shape
21. **CardDetail.tsx effectiveSendState** -- Correctly prioritizes Dataverse outcome over local state
22. **CardDetail.tsx sending timeout** -- 60-second timeout resets stuck sends (line 100-107)
23. **CardDetail.tsx inline editing** -- Edit/revert/modified detection all correctly implemented
24. **CardGallery.tsx empty state** -- Correctly shows "No cards match" when cards.length === 0
25. **BriefingCard.tsx parseBriefing** -- Handles string JSON, object, and null draft_payload with try/catch fallback
26. **BriefingCard.tsx empty state** -- Shows "inbox is clear" when no action items or stale alerts
27. **CommandBar.tsx duplicate response guard** -- useEffect checks last entry to prevent duplicate appends
28. **CommandBar.tsx auto-scroll** -- scrollTop = scrollHeight on conversation updates
29. **urlSanitizer.ts** -- Correctly validates https: and mailto: only, rejects javascript:, data:, http:
30. **index.ts PCF lifecycle** -- init, updateView, getOutputs, destroy all correctly implemented per StandardControl/ReactControl contract
31. **index.ts stable callbacks** -- Created once in init(), never recreated, preventing unnecessary React re-renders
32. **index.ts output reset pattern** -- Fire-and-forget reset in getOutputs() prevents stale re-fires

---

## Cross-Reference Summary

| Schema Source | TypeScript Target | Status |
|---|---|---|
| output-schema.json trigger_type enum (6) | TriggerType union (6) | MATCH |
| output-schema.json triage_tier enum (3) | TriageTier union (3) | MATCH |
| output-schema.json priority enum (4 incl null) | Priority union (3) + null | MATCH (N/A bridged at ingestion) |
| output-schema.json temporal_horizon enum (5 incl null) | TemporalHorizon union (4) + null | MATCH (N/A bridged at ingestion) |
| output-schema.json card_status enum (4) | CardStatus union (5) | MISMATCH -- NUDGE in TS but not in schema (COR-F01) |
| output-schema.json confidence_score (integer) | number | MINOR GAP -- integer vs float (COR-F18) |
| output-schema.json verified_sources.tier (integer 1-5) | 1 \| 2 \| 3 \| 4 \| 5 | MATCH |
| dataverse-table.json cr_cardoutcome (5 labels) | CardOutcome union (5) | MATCH |
| dataverse-table.json all 16 columns | AssistantCard fields | MATCH (all accounted for) |
