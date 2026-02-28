# Reconciled Frontend/PCF Findings

## Summary

**Total unique issues: 33 (8 BLOCK, 14 WARN, 7 INFO, 4 FALSE)**

- Issues from three independent agents: 60 raw findings (21 Correctness + 15 Implementability + 28 Gaps, including validations)
- After filtering validations and deduplicating: 33 unique issues
- Agents agreed on severity for 26 issues, disagreed on 7 issues
- 4 findings reclassified as FALSE (validated as correct, not actual issues)

## Reconciliation Methodology

1. **Extract**: Every issue from all three agent reports was catalogued with source agent(s), artifact, severity, and description.
2. **Deduplicate**: Issues describing the same underlying problem from different agent perspectives were merged into single entries. When multiple agents flagged the same issue, the most detailed description was preserved and all source agents noted. Multi-agent agreement strengthens the signal.
3. **Resolve disagreements**: For each severity disagreement, the specific artifact was re-read, the agent arguments weighed, and a final ruling made based on: (a) whether the issue actually prevents correct runtime behavior, (b) whether it affects user experience critically, and (c) the principle "when genuinely ambiguous, classify as BLOCK."
4. **Classify**: Each reconciled issue assigned exactly one category: BLOCK, WARN, INFO, or FALSE.
5. **Map**: Each issue tagged with affected PCF requirement(s).

---

## Tech Debt Classification (PCF-02)

All 7 known v2.0 tech debt items (#7-#13) classified with final disposition.

| # | Item | Classification | Rationale |
|---|------|---------------|-----------|
| 7 | Staleness polling (setInterval) lacks cleanup on unmount | **DEFER** | No setInterval exists anywhere in the 14 PCF source files. The Staleness Monitor is a server-side Power Automate scheduled flow, not a client-side polling mechanism. This tech debt item describes a problem that does not exist in the PCF layer. The item should be removed from PROJECT.md or reclassified as "resolved/not applicable to PCF." Not deploy-blocking -- there is no code to fix. |
| 8 | BriefingView test coverage thin on schedule logic | **DEFER** | The "schedule logic" referenced does not exist in BriefingCard.tsx (see #13). Current test coverage (10 test cases) is adequate for implemented functionality: rendering, interaction, state, error handling. Deferrable -- add tests when/if schedule UI is implemented. |
| 9 | Command bar error states show raw error strings | **DEFER** | The CommandBar response channel does not exist yet (see F-02 below). Error handling should be implemented alongside the response channel. Deferrable -- fix when CommandBar response path is built. |
| 10 | No E2E flow coverage for send-email or set-reminder paths | **DEFER** | E2E testing requires a running Power Platform environment, which is out of scope per PROJECT.md constraints. Unit tests cover the PCF output binding (CardDetail send flow, index.ts getOutputs reset). Deferrable -- validate during deployment testing. |
| 11 | Confidence calibration thresholds hardcoded | **DEFER** | Hardcoded values (90/70/40 accuracy buckets, 70/40 color thresholds) are reasonable defaults that produce meaningful analytics. Making these configurable would require additional PCF input properties. Deferrable -- a calibration improvement, not a correctness issue. |
| 12 | Sender profile 30-day window not configurable | **DEFER** | The 30-day window is a server-side concern (Sender Profile Analyzer flow). The PCF control displays whatever the DataSet view provides. Making the window configurable at the PCF level would duplicate server-side logic. Deferrable -- not a PCF-layer concern. |
| 13 | Daily briefing schedule stored in component state (lost on refresh) | **BLOCK** | The schedule configuration UI described by this tech debt item does not exist in BriefingCard.tsx. The component has only one local state (`fyiExpanded` toggle). This is not "state lost on refresh" -- it is a feature that was never implemented. Deploy-blocking as a documentation accuracy issue: the tech debt item implies a feature exists that does not. Must either implement the schedule configuration or reclassify this item as "feature not yet built" and remove from tech debt list. |

**Summary: 1 of 7 items is deploy-blocking (#13 -- feature missing). 6 items are deferrable.** Item #7 describes a problem that does not exist in the PCF layer and should be removed from the tech debt list.

---

## BLOCK -- Deploy-Blocking Issues

These must be fixed in Phase 13 before deployment.

| ID | Requirement | Artifact | Issue | Flagged By | Remediation |
|----|-------------|----------|-------|------------|-------------|
| F-01 | PCF-04 | useCardData.ts, output-schema.json | NUDGE status mismatch + inconsistent ingestion strategy | Correctness | Read card_status from discrete column, or add NUDGE to output-schema.json |
| F-02 | PCF-05, PCF-01 | App.tsx, index.ts, ManifestTypes.d.ts | CommandBar response channel missing (lastResponse/isProcessing hardcoded) | Implementability, Gaps | Add orchestratorResponse + isProcessing input properties to manifest |
| F-03 | PCF-05, PCF-01 | All components, index.ts | No React error boundary -- any render crash takes down entire dashboard | Implementability, Gaps | Add ErrorBoundary class component wrapping App |
| F-04 | PCF-03 | ConfidenceCalibration.tsx | Zero test coverage on 324-line analytics component with math calculations | Gaps | Create ConfidenceCalibration.test.tsx covering all tabs and edge cases |
| F-05 | PCF-03 | index.ts | PCF entry point lifecycle methods untested (output reset logic critical) | Gaps | Create index.test.ts; remove explicit coverage exclusion |
| F-06 | PCF-04 | useCardData.ts | useMemo dependency array missing dataset (only tracks version) | Correctness | Add dataset to dependency array: [dataset, version] |
| F-07 | PCF-02 | BriefingCard.tsx, PROJECT.md | Tech debt #13: briefing schedule configuration feature missing entirely | Implementability, Gaps | Implement schedule config, or reclassify tech debt item |
| F-08 | PCF-02 | PROJECT.md | Tech debt #7: staleness polling setInterval not found in PCF source | Gaps | Investigate and resolve: remove stale tech debt item or locate code |

### F-01: NUDGE status mismatch and inconsistent ingestion strategy

**Source issues:** COR-F01, COR-F02

**Problem:** Two related issues forming a single correctness gap:

1. **NUDGE not in output-schema.json**: TypeScript `CardStatus` includes `"NUDGE"` but output-schema.json only has `["READY", "LOW_CONFIDENCE", "SUMMARY_ONLY", "NO_OUTPUT"]`. The Dataverse table DOES include NUDGE (value 100000004). The Staleness Monitor flow would set NUDGE directly in the `cr_cardstatus` column, but the agent cannot output NUDGE per the schema contract.

2. **Inconsistent ingestion**: useCardData reads `card_status` from `cr_fulljson` (the JSON blob), not from the discrete `cr_cardstatus` column. But flows update the discrete column without updating `cr_fulljson`. So even if the Staleness Monitor sets `cr_cardstatus = NUDGE`, the PCF control would display the original status from the JSON blob.

**Evidence verified:** useCardData.ts lines 58-73 use `parsed.X` (from cr_fulljson) for most fields. Lines 74-83 use `record.getValue()` or `record.getFormattedValue()` for discrete columns. `card_status` is read from the JSON blob (line 64), not the discrete column.

**Final ruling: BLOCK.** Runtime state divergence is expected, not theoretical. The Staleness Monitor and Card Outcome Tracker flows update discrete columns without touching `cr_fulljson`. The NUDGE status would never reach the UI through the current data path.

**Remediation:** Read `card_status` from the discrete Dataverse column via `getFormattedValue("cr_cardstatus")` instead of from `cr_fulljson`. This aligns the ingestion strategy: mutable fields (that flows update) from discrete columns, immutable agent output fields from JSON. Also add NUDGE to output-schema.json for completeness, or document that NUDGE is set only by flows (not agents).

---

### F-02: CommandBar response channel missing

**Source issues:** IMP-F01, GAP-F02

**Problem:** The CommandBar component receives `lastResponse={null}` and `isProcessing={false}` hardcoded in App.tsx. There is no input property in the PCF manifest (`ManifestTypes.d.ts` IInputs) for receiving orchestrator responses. The `onExecuteCommand` callback fires a PCF output property that triggers a Power Automate flow, but there is no return path for the flow's response. The CommandBar can SEND commands but NEVER receives responses.

**Evidence verified:** App.tsx lines 210-211 hardcode null/false. ManifestTypes.d.ts IInputs has no orchestrator response property. Index.ts updateView does not read any response-related input. The CommandBar component IS fully built to handle responses (conversation history, card links, side effects), but the infrastructure to deliver those responses does not exist.

**Final ruling: BLOCK.** Both Implementability and Gaps agents independently identified this. The command bar is a Sprint 3 feature. Deploying it without response capability means users type commands that produce no visible result -- a broken user experience.

**Remediation:** Add two input properties to ControlManifest.Input.xml: (1) `orchestratorResponse` (StringProperty, bound to a Canvas App variable set by the flow response), (2) `isProcessing` (TwoOptions or StringProperty). Wire these through index.ts `updateView` into App.tsx and down to CommandBar.

---

### F-03: No React error boundary

**Source issues:** IMP-F02, GAP-F01

**Problem:** Neither App.tsx nor index.ts wraps the component tree in a React error boundary. If any child component throws during rendering (e.g., BriefingCard parsing malformed JSON that bypasses try/catch, ConfidenceCalibration dividing by zero, CardDetail accessing a property of undefined), the entire PCF control crashes and displays nothing. Users see a blank space where their dashboard should be.

**Evidence verified:** No class component extending `React.Component` with `componentDidCatch` or `getDerivedStateFromError` exists anywhere. React 16.14.0 requires class components for error boundaries (not available as a hook).

**Final ruling: BLOCK.** Both Implementability and Gaps agents independently identified this with identical reasoning. A single malformed card in a dataset of hundreds could crash the entire dashboard, leaving the user with no UI and no error message.

**Remediation:** Create an `ErrorBoundary.tsx` class component. Wrap at minimum the main content area in App.tsx. Display a user-friendly error message with a "Retry" button that resets the boundary state. Consider wrapping individual high-risk sections (BriefingCard, ConfidenceCalibration) separately.

---

### F-04: ConfidenceCalibration zero test coverage

**Source issues:** GAP-F03

**Problem:** ConfidenceCalibration is the largest component (324 lines) with four `useMemo` computations (accuracy buckets, triage stats, draft stats, top senders), four tab panels, and conditional rendering. No test file exists. The `jest.config.ts` per-file 80% coverage threshold would fail for this file if `--coverage` is run.

**Evidence verified:** No ConfidenceCalibration.test.tsx in `__tests__/` directory. The component performs mathematical calculations (percentages, ratios, sorting) that could silently produce incorrect results.

**Final ruling: BLOCK.** 324 lines of untested analytics math including division operations. Division-by-zero edge cases (0 resolved cards, 0 full cards, 0 sent cards, 0 senders) are guarded with ternary checks but unverified by tests. The jest coverage threshold would fail.

**Remediation:** Create `ConfidenceCalibration.test.tsx` with tests for: empty cards array, single card, cards with all outcomes, division-by-zero safety, sender deduplication, tab switching, all four analytics tabs.

---

### F-05: index.ts PCF entry point untested

**Source issues:** GAP-F04

**Problem:** The PCF entry point class (AssistantDashboard) implements init, updateView, getOutputs, and destroy. None are tested. The `jest.config.ts` explicitly excludes index.ts from coverage collection (`'!AssistantDashboard/index.ts'`). The output property reset pattern in `getOutputs()` is critical for fire-and-forget action correctness -- if a regression changes the reset order, all actions would silently fail.

**Evidence verified:** jest.config.ts excludes index.ts. No test file exists.

**Final ruling: BLOCK.** Only Gaps flagged this, but the reasoning is sound. The output property reset pattern is a correctness-critical behavior. A simple integration test would prevent silent regressions.

**Remediation:** Create `index.test.ts` testing: init creates stable callbacks, updateView increments version and returns React element, getOutputs returns and clears properties, destroy does not throw. Remove the coverage exclusion from jest.config.ts.

---

### F-06: useMemo dependency array missing dataset reference

**Source issues:** COR-F03

**Problem:** The `useMemo` dependency array in useCardData is `[version]`, not `[dataset, version]`. The comment explains this is intentional (the PCF platform mutates the same dataset object in place), which is correct at runtime. However, it violates the React rules of hooks: all external values read inside useMemo should be in the dependency array.

**Evidence verified:** useCardData.ts line 95: `return React.useMemo(() => { ... }, [version]);` -- dataset not in deps. The hook reads `dataset` inside the memo.

**Final ruling: BLOCK.** The Correctness agent is right that this violates React hook rules. While the PCF runtime mitigates this (version always increments before render), adding dataset to the dependency array is safe and correct. Since the PCF platform mutates the object in place, reference equality means adding it to deps won't cause extra renders. The fix is trivial and improves correctness.

**Remediation:** Change dependency array from `[version]` to `[dataset, version]`. This is a one-character change with no behavioral impact in the PCF runtime.

---

### F-07: Briefing schedule configuration feature missing (Tech Debt #13)

**Source issues:** IMP-F03, GAP-F06

**Problem:** PROJECT.md tech debt #13 states "Daily briefing schedule stored in component state (lost on refresh)." But BriefingCard.tsx has NO schedule configuration UI at all -- no schedule picker, no time selector, no state management for schedule preferences. The only state is `fyiExpanded` (boolean). The tech debt item describes a feature that was either removed or never implemented.

**Evidence verified:** BriefingCard.tsx lines 131-132 show only `fyiExpanded` local state. No schedule-related props, state, or UI elements anywhere in the component.

**Final ruling: BLOCK.** Both Implementability and Gaps agents independently identified this. The tech debt item implies a feature exists that does not. This is either: (a) a missing feature that needs implementation, or (b) a stale tech debt item that needs correction to avoid confusion.

**Remediation:** Either (a) implement schedule configuration in BriefingCard with persistence via PCF output property, or (b) remove/reclassify tech debt #13 in PROJECT.md as "feature not implemented" and add to Phase 13 backlog as a deferred feature, or (c) document that schedule configuration is managed at the Power Automate flow level (not the PCF control).

---

### F-08: Staleness polling setInterval not found (Tech Debt #7)

**Source issues:** GAP-F05

**Problem:** Tech debt #7 references "Staleness polling (setInterval) lacks cleanup on unmount." No setInterval call exists in any of the 14 PCF source files. The staleness monitoring is a Power Automate scheduled flow (per the platform architecture), not a client-side polling mechanism.

**Evidence verified:** Searched all source files -- no setInterval usage found. The Staleness Monitor is documented as a server-side flow.

**Final ruling: BLOCK (for investigation).** The tech debt item describes a problem in code that does not exist. This creates documentation confusion. Must determine if: (a) the code was removed and the tech debt item is stale, (b) the code exists outside the PCF source files, or (c) it was never implemented. The resolution is to update PROJECT.md accordingly.

**Remediation:** Remove tech debt #7 from PROJECT.md or reclassify as "resolved -- staleness monitoring implemented server-side via Power Automate flow, not client-side polling." No code fix needed.

---

## WARN -- Non-Blocking Issues

Should be fixed but deployment can proceed.

| ID | Requirement | Artifact | Issue | Flagged By | Remediation |
|----|-------------|----------|-------|------------|-------------|
| F-09 | PCF-01 | BriefingCard.tsx | Uses plain HTML elements instead of Fluent UI v9 | Correctness | Migrate to Fluent UI components |
| F-10 | PCF-01 | ConfidenceCalibration.tsx | Uses plain HTML elements instead of Fluent UI v9 | Correctness | Migrate to Fluent UI components |
| F-11 | PCF-01 | CommandBar.tsx | Uses plain HTML elements instead of Fluent UI v9 | Correctness | Migrate to Fluent UI components |
| F-12 | PCF-01 | App.tsx | Calibration link uses plain `<button>` instead of Fluent UI Button | Correctness | Replace with `<Button appearance="subtle">` |
| F-13 | PCF-05 | App.tsx | Missing loading state -- no Spinner while DataSet loads | Gaps | Add loading check from DataSet API and show Spinner |
| F-14 | PCF-05 | App.tsx, BriefingCard.tsx | BriefingCard in detail view has no Back button (UX trap) | Gaps | Add onBack prop to BriefingCard or wrap with Back button |
| F-15 | PCF-01 | CardItem.tsx | statusAppearance and statusColor maps missing NUDGE entry | Correctness | Add NUDGE entries to both maps |
| F-16 | PCF-01 | CardItem.tsx | triggerIcons map missing DAILY_BRIEFING, SELF_REMINDER, COMMAND_RESULT | Correctness | Add entries for remaining trigger types |
| F-17 | PCF-05 | All components | Missing accessibility -- no ARIA labels, roles, or keyboard landmarks | Gaps | Add ARIA landmarks and labels to major sections |
| F-18 | PCF-05 | App.tsx, CardDetail.tsx | Missing keyboard navigation -- Escape key does not dismiss panels | Gaps | Add global keydown listener in App.tsx |
| F-19 | PCF-05 | ConfidenceCalibration.tsx | Division by zero produces misleading 0% instead of "N/A" for empty states | Gaps | Show "N/A" or "No data yet" when denominator is 0 |
| F-20 | PCF-04 | useCardData.ts, index.ts | DataSet paging not implemented -- only first page rendered | Implementability | Implement loadNextPage() or increase default page size |
| F-21 | PCF-03 | App.test.tsx | Missing tests for calibration view navigation and briefing rendering | Gaps | Add test cases for ViewState.calibration path |
| F-22 | PCF-01 | .eslintrc.json | Missing eslint-plugin-react and eslint-plugin-react-hooks | Gaps | Add React-specific ESLint plugins |

### F-09: BriefingCard uses plain HTML instead of Fluent UI v9

**Source issues:** COR-F07

BriefingCard.tsx imports from React only -- no Fluent UI components. Uses plain `<div>`, `<h2>`, `<h3>`, `<p>`, `<span>`, `<button>` throughout. This creates visual inconsistency with CardDetail (which uses Fluent UI Button, Badge, Text, Link, Textarea, Spinner, MessageBar).

**Remediation:** Migrate to Fluent UI v9 components: `<Text>` for text, `<Button>` for buttons, `<Badge>` for status indicators, `<Card>` for container.

---

### F-10: ConfidenceCalibration uses plain HTML instead of Fluent UI v9

**Source issues:** COR-F08

Same pattern as F-09. Uses plain `<div>`, `<h2>`, `<button>`, `<table>`, `<p>`, `<span>`. No Fluent UI imports.

**Remediation:** Migrate to Fluent UI v9 Table, Button, Text, Card components.

---

### F-11: CommandBar uses plain HTML instead of Fluent UI v9

**Source issues:** COR-F09

Same pattern. Uses plain `<div>`, `<input>`, `<button>`. No Fluent UI imports. The chip-style quick actions could use `<Tag>` or `<Button appearance="outline" size="small">`.

**Remediation:** Migrate to Fluent UI v9 Input, Button components.

---

### F-12: Calibration link uses plain HTML button

**Source issues:** COR-F06

App.tsx renders `<button className="calibration-link">` instead of Fluent UI `<Button>`. Inconsistent with all other interactive elements which use Fluent UI Button.

**Remediation:** Replace with `<Button appearance="subtle" onClick={handleShowCalibration}>Agent Performance</Button>`.

---

### F-13: Missing loading state

**Source issues:** GAP-F12

When the DataSet is loading, useCardData returns an empty array. App shows "No cards match the current filters" which is misleading. The DataSet API provides a `loading` property, but the hook's minimal interface does not include it.

**Remediation:** Add `loading` check in index.ts (`dataset.loading`) and pass as prop. Show `<Spinner label="Loading cards..." />` when loading.

---

### F-14: BriefingCard detail view has no Back button

**Source issues:** GAP-F21

When a DAILY_BRIEFING card is selected, App renders `<BriefingCard>` without a Back button. The only way out is to dismiss the briefing (which changes card_outcome) or wait for the card to be removed. This is a UX trap.

**Remediation:** Add `onBack` prop to BriefingCard or wrap the briefing detail view with a Back button header.

---

### F-15: CardItem status maps missing NUDGE entry

**Source issues:** COR-F10

`statusAppearance` and `statusColor` maps include entries for READY, LOW_CONFIDENCE, SUMMARY_ONLY, NO_OUTPUT but not NUDGE. Falls back to `?? "outline"` and `?? "informative"` defaults.

**Remediation:** Add `NUDGE: "tint"` to statusAppearance and `NUDGE: "warning"` to statusColor.

---

### F-16: CardItem trigger icon map incomplete

**Source issues:** COR-F11

`triggerIcons` map only includes EMAIL, TEAMS_MESSAGE, CALENDAR_SCAN. Missing DAILY_BRIEFING, SELF_REMINDER, COMMAND_RESULT. Falls back to MailRegular icon which is semantically incorrect.

**Remediation:** Add entries for remaining trigger types with appropriate Fluent icons.

---

### F-17: Missing accessibility (ARIA labels, roles, landmarks)

**Source issues:** GAP-F13

No ARIA attributes beyond Fluent UI defaults. No `role="navigation"` on FilterBar, no `aria-label` on plain HTML buttons, no `aria-live` on CommandBar response panel, no skip navigation link.

**Remediation:** Priority: (1) aria-label on all plain HTML buttons, (2) aria-live="polite" on command response panel, (3) role landmarks on major sections.

---

### F-18: Missing keyboard navigation (Escape key)

**Source issues:** GAP-F14

No keyboard handler for Escape key to navigate back from detail view, dismiss panels, or close expanded command bar. Only keyboard handler is Enter in CommandBar.

**Remediation:** Add global keydown listener in App.tsx: Escape returns to gallery from detail view.

---

### F-19: Misleading 0% for empty analytics states

**Source issues:** GAP-F15

When there are 0 resolved cards, calculations return 0 via ternary guards. Displaying "0% accuracy" when there are no cards is misleading (0% suggests all were wrong, not "no data").

**Remediation:** Show "N/A" or "No data yet" instead of 0% when denominator is 0.

---

### F-20: DataSet paging not implemented

**Source issues:** IMP-F05, IMP-F10

Only the first page of DataSet records is rendered. Neither useCardData nor index.ts calls `loadNextPage()` or `setPageSize()`. Default page size varies (50-250).

**Remediation:** In `updateView`, check `dataset.paging.hasNextPage` and call `loadNextPage()`. Or increase default page size via `setPageSize()` in `init()`.

---

### F-21: Missing tests for calibration view and briefing rendering in App

**Source issues:** GAP-F17

App.test.tsx tests filter logic (7 tests) and gallery/detail navigation (2 tests), but does not test calibration view navigation, return from calibration, or briefing card rendering path.

**Remediation:** Add tests for calibration navigation and briefing card rendering in gallery mode.

---

### F-22: Missing React-specific ESLint rules

**Source issues:** GAP-F19

ESLint config has only `@typescript-eslint` plugin. Missing `eslint-plugin-react` and `eslint-plugin-react-hooks`. The useMemo dependency issue (F-06) would have been caught by eslint-plugin-react-hooks exhaustive-deps rule.

**Remediation:** Add `eslint-plugin-react` and `eslint-plugin-react-hooks` to devDependencies and ESLint config.

---

## INFO -- Known Constraints

Documented constraints or known limitations. No fix needed.

| ID | Requirement | Artifact | Constraint | Flagged By |
|----|-------------|----------|------------|------------|
| F-23 | PCF-01 | index.ts | PCF virtual controls must return React.ReactElement from updateView (no ReactDOM.render) | Implementability |
| F-24 | PCF-04 | useCardData.ts | Canvas App delegation limit of 2000 records | Implementability |
| F-25 | PCF-01 | index.ts | PCF controls communicate via output properties only (no direct variable access) | Implementability |
| F-26 | PCF-01 | All .tsx files | React 16.14.0 limitations: no Suspense, no concurrent features, no useId | Implementability |
| F-27 | PCF-01 | package.json | TypeScript 4.9.5 pinned by pcf-scripts; skipLibCheck required for Fluent UI v9 | Gaps |
| F-28 | PCF-01 | package.json | pcf-scripts controls build pipeline; limited webpack customization | Gaps |
| F-29 | PCF-01 | N/A | Canvas App PCF controls are desktop-only; no mobile responsiveness needed | Gaps |

These are all accepted platform constraints documented by the Implementability and Gaps agents. The codebase correctly handles all of them. No action needed.

---

## FALSE -- False Positives

Issues flagged by agents that are not actual problems upon investigation.

| ID | Source | Issue | Why False |
|----|--------|-------|-----------|
| F-30 | COR-F04 | OutcomeAction type referenced in plan checklist does not exist | Plan documentation reference error, not a code defect. The plan's checklist mentions a type name that was never created. No code impact. |
| F-31 | COR-F14 | index.ts updateView return type incorrect for React 16 | Validated as correct. `React.createElement` returns `React.ReactElement` which matches the `ReactControl` interface contract. |
| F-32 | COR-F15 | index.ts getOutputs() reset creates race condition | Validated as correct. This is the documented fire-and-forget PCF output binding pattern, validated in Phase 5. The Canvas App reads output once via OnChange event; clearing prevents stale re-fires. |
| F-33 | IMP-F09 | CardDetail renders raw created_on without formatting | Validated as correct. `getFormattedValue("createdon")` returns locale-formatted date strings from the Dataverse platform. This IS the correct formatting approach. |

---

## Disagreement Log

| Issue | Agent A Said | Agent B Said | Resolution | Reasoning |
|-------|-------------|-------------|------------|-----------|
| **F-01: NUDGE mismatch** | Correctness: Deploy-blocking (COR-F01, COR-F02) | No other agent flagged | **BLOCK** | Correctness is right. The data flow gap is real: useCardData reads card_status from cr_fulljson, but flows update the discrete column. NUDGE would never reach the UI. |
| **F-06: useMemo deps** | Correctness: Deploy-blocking (COR-F03) | No other agent flagged | **BLOCK** | Correctness is right about the React rules violation. The fix is trivial (add dataset to deps array) and the current behavior is correct only by accident (PCF lifecycle always increments version). Safe to fix. |
| **F-08: Tech debt #7** | Gaps: Deploy-blocking for investigation (GAP-F05) | No other agent flagged | **BLOCK (investigation)** | Gaps is right that the tech debt item creates confusion. No code fix needed, but the documentation must be corrected. Reclassified as BLOCK for documentation accuracy. |
| **F-20: Paging** | Implementability: Non-blocking (IMP-F05) | Gaps: Not flagged directly | **WARN** | Agreed with Implementability. Default page size (50-250) is sufficient for initial deployment. Would become blocking at scale. |
| **F-04: ConfidenceCalibration tests** | Gaps: Deploy-blocking (GAP-F03) | No other agent flagged | **BLOCK** | Gaps is right. 324 lines of math with zero tests and division-by-zero edge cases is a deploy risk. The jest coverage threshold would also fail. |
| **F-05: index.ts tests** | Gaps: Deploy-blocking (GAP-F04) | No other agent flagged | **BLOCK** | Gaps is right. The output property reset pattern is correctness-critical. The explicit coverage exclusion in jest.config.ts hides this gap. |
| **F-09/F-10/F-11: Plain HTML** | Correctness: Non-blocking (COR-F07/F08/F09) | No other agent flagged | **WARN** | Agreed with Correctness. Visual inconsistency is real but does not break functionality. Fluent UI migration is a styling improvement, not a correctness fix. |

### Issues where multiple agents agreed

The following issues were independently identified by 2+ agents, confirming their significance:

- **F-02 (CommandBar response gap)**: Implementability (IMP-F01) and Gaps (GAP-F02) -- both classified as deploy-blocking. **Agreed: BLOCK.**
- **F-03 (Missing error boundary)**: Implementability (IMP-F02) and Gaps (GAP-F01) -- both classified as deploy-blocking. **Agreed: BLOCK.**
- **F-07 (Briefing schedule missing)**: Implementability (IMP-F03) and Gaps (GAP-F06) -- both classified as deploy-blocking. **Agreed: BLOCK.**

Multi-agent agreement on these three issues provides high confidence in their BLOCK classification.

---

## PCF Requirement Mapping

### PCF-01: Component Architecture
Issues: F-01 (BLOCK), F-02 (BLOCK), F-03 (BLOCK), F-06 (BLOCK), F-09 (WARN), F-10 (WARN), F-11 (WARN), F-12 (WARN), F-15 (WARN), F-16 (WARN), F-22 (WARN)

### PCF-02: Tech Debt Categorization
Issues: F-07 (BLOCK), F-08 (BLOCK), tech debt table above (all 7 items classified)

### PCF-03: Test Coverage Assessment
Issues: F-04 (BLOCK), F-05 (BLOCK), F-21 (WARN)

### PCF-04: Data Flow Correctness
Issues: F-01 (BLOCK), F-06 (BLOCK), F-20 (WARN)

### PCF-05: Error Handling and UX Gaps
Issues: F-02 (BLOCK), F-03 (BLOCK), F-13 (WARN), F-14 (WARN), F-17 (WARN), F-18 (WARN), F-19 (WARN)

---

## Additional Non-Categorized Findings

The following minor findings were noted during review but do not warrant individual tracking:

- **confidence_score integer vs number gap** (COR-F18): TypeScript `number` encompasses both integers and floats; agent always produces integers. Accepted as low-risk type gap.
- **verified_sources tier range unvalidated** (COR-F19): Per-item validation would add complexity without benefit since agent produces valid values.
- **FluentProvider targetDocument** (COR-F13): Virtual controls render in main document tree, not shadow DOM. Default is correct.
- **@testing-library/react version mismatch** (IMP-F11): Works via skipLibCheck compatibility. Documented concern only.
- **DataSet interface subset** (IMP-F04): Intentional minimal interface in useCardData. Non-blocking for basic rendering.
- **CommandBar conversation state ephemeral** (IMP-F07): Inherently ephemeral in Canvas App context. Accepted behavior.
- **BriefingCard parseBriefing lacks shape validation** (IMP-F08): Null guards (hasActions, hasFyi, hasStale) prevent crashes. Non-blocking.
- **ConfidenceCalibration client-side performance** (IMP-F06): Acceptable for typical deployment sizes (<500 cards). Documented limitation.
- **Dead fields: conversation_cluster_id, source_signal_id** (GAP-F16): Populated for future clustering features. Accepted.
- **FilterBar naming** (COR-F12): Display-only filter bar. Name is a known simplification.
- **AppProps missing onShowCalibration** (COR-F05): Architecturally minor -- calibration nav is internal to App.
- **Missing N/A temporal_horizon test** (GAP-F22): Minor test gap. Priority conversion is tested.
- **CardDetail test edge cases** (GAP-F18): Minor -- 24 tests provide good coverage.
- **No development preview mode** (GAP-F20): Nice-to-have, not a correctness concern.
- **Fluent UI v9 bundle size** (GAP-FC05): Accepted platform constraint.
- **DataSet locale formatting** (GAP-FC06): Feature, not a bug.
