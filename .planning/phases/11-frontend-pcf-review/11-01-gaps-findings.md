# Gaps Agent -- Frontend/PCF Findings

## Summary

28 gaps found: 6 deploy-blocking, 16 non-blocking, 6 known constraints.

All 14 frontend/PCF source files, 9 test files, and 6 configuration files were reviewed to identify what is MISSING, what is ASSUMED but not handled, and what TECH DEBT remains. Every known v2.0 tech debt item (#7-#13) is individually classified.

## Methodology

1. Classified all 7 known v2.0 tech debt items (#7-#13) as deploy-blocking or deferrable with rationale
2. Audited every component for missing error handling paths (what happens when things go wrong?)
3. Compared source files to test files to identify untested code paths
4. Evaluated UX handling: empty states, loading states, error messages, accessibility
5. Traced data flow from DataSet through useCardData to every component that consumes card data
6. Reviewed build and development configuration for gaps

---

## Findings

### Deploy-Blocking Gaps

**GAP-F01: No React error boundary -- rendering errors crash entire dashboard with no recovery**
- **Category:** Missing error handling
- **Artifact:** All components, index.ts
- **Location:** Entire component tree
- **Gap:** No error boundary exists anywhere in the component tree. If ANY component throws during render (e.g., accessing a property of undefined, JSON.parse on corrupted data that bypasses useCardData's catch, a Fluent UI component failing), the entire PCF control renders nothing. The user sees a blank space with no error message and no way to recover without navigating away and back.
- **Evidence:** No class component with `componentDidCatch` or `getDerivedStateFromError` in any file. React 16 requires class components for error boundaries.
- **Why deploy-blocking:** A single malformed record in production data could render the entire dashboard unusable for all users until that record is fixed or removed.
- **Suggested Fix:** Create `ErrorBoundary.tsx` class component. Wrap at minimum the main content area in App.tsx. Display a user-friendly message with "Retry" button (re-renders the tree).

**GAP-F02: CommandBar has no response channel -- orchestrator commands go into a void**
- **Category:** Missing data flow connection
- **Artifact:** App.tsx:210-211, index.ts, ManifestTypes.d.ts
- **Location:** `src/AssistantDashboard/components/App.tsx` lines 210-211
- **Gap:** The CommandBar receives `lastResponse={null}` and `isProcessing={false}` hardcoded in App.tsx. There is no input property in the PCF manifest for receiving orchestrator responses. The `onExecuteCommand` callback fires a PCF output property, but the response path is missing entirely. The CommandBar component is fully built to handle responses (conversation history, card links, side effects), but the infrastructure to deliver those responses does not exist.
- **Evidence:** ManifestTypes.d.ts IInputs has no orchestrator response property. App.tsx hardcodes null/false. Index.ts updateView does not read any response-related input.
- **Why deploy-blocking:** The command bar is a Sprint 3 feature advertised in the project. Deploying it without response capability would confuse users (they type commands that produce no visible result).
- **Suggested Fix:** Add `orchestratorResponse` (StringProperty) and `isProcessing` (TwoOptions/StringProperty) to ControlManifest.Input.xml. Parse the response JSON in updateView and pass through to App.tsx.

**GAP-F03: `ConfidenceCalibration.tsx` has zero test coverage -- 324 lines of untested analytics logic**
- **Category:** Missing test coverage
- **Artifact:** ConfidenceCalibration.tsx
- **Location:** `src/AssistantDashboard/components/ConfidenceCalibration.tsx`
- **Gap:** ConfidenceCalibration is the largest component (324 lines) with four `useMemo` computations (accuracy buckets, triage stats, draft stats, top senders), four tab panels, and conditional rendering logic. There is no `ConfidenceCalibration.test.tsx` file. No test file exists in `__tests__/` for this component.
- **Evidence:** `ls enterprise-work-assistant/src/AssistantDashboard/components/__tests__/` shows: App.test.tsx, BriefingCard.test.tsx, CardDetail.test.tsx, CardGallery.test.tsx, CardItem.test.tsx, CommandBar.test.tsx, FilterBar.test.tsx. No ConfidenceCalibration test file.
- **Why deploy-blocking:** The component performs mathematical calculations (percentages, ratios, sorting) that could silently produce incorrect results. Without tests, division-by-zero edge cases (0 resolved cards, 0 full cards, 0 sent cards, 0 senders) are unverified. The per-file 80% coverage threshold in jest.config.ts would fail for this file when `--coverage` is enabled.
- **Suggested Fix:** Create `ConfidenceCalibration.test.tsx` with tests for: empty cards array, single card, cards with all outcomes, division-by-zero safety, sender deduplication, tab switching.

**GAP-F04: `index.ts` (PCF entry point) has zero test coverage -- lifecycle methods untested**
- **Category:** Missing test coverage
- **Artifact:** index.ts
- **Location:** `src/AssistantDashboard/index.ts`
- **Gap:** The PCF entry point class (AssistantDashboard) implements init, updateView, getOutputs, and destroy. None of these are tested. The jest.config.ts explicitly excludes index.ts from coverage collection (`'!AssistantDashboard/index.ts'`), but this means critical behavior is untested: callback creation, output property reset, dataset version incrementing, dimension fallbacks.
- **Evidence:** jest.config.ts line 33: `'!AssistantDashboard/index.ts'` -- explicitly excluded. No test file for index.ts exists.
- **Why deploy-blocking:** The output property reset pattern in getOutputs() is critical for fire-and-forget action correctness. If a regression changes the reset order (e.g., clearing before reading), all actions would silently fail. A simple integration test would catch this.
- **Suggested Fix:** Create `index.test.ts` testing: init creates stable callbacks, updateView increments version and returns React element, getOutputs returns and clears properties, destroy does not throw.

**GAP-F05: v2.0 Tech Debt #7 -- Staleness polling (setInterval) lacks cleanup on unmount**
- **Category:** v2.0 tech debt classification
- **Artifact:** Not found in current PCF source files
- **Location:** N/A -- referenced in PROJECT.md
- **Classification:** **Deploy-blocking (investigation needed)**
- **Rationale:** The tech debt item references a setInterval-based staleness polling mechanism. Upon reviewing all 14 source files, there is NO setInterval call anywhere in the PCF component code. The staleness monitoring is designed as a Power Automate scheduled flow (per the platform architecture), not a client-side polling mechanism. This tech debt item either: (a) was resolved and the cleanup was done, (b) refers to code outside the current PCF source files, or (c) was a planned feature that was never implemented.
- **Why deploy-blocking:** If the staleness polling code exists elsewhere (e.g., in a non-committed file or in the Canvas App formula layer), the memory leak risk is real. If it doesn't exist, this tech debt item should be removed from PROJECT.md to avoid confusion.
- **Suggested Fix:** Search the entire project for setInterval usage. If found, add cleanup in useEffect return. If not found, remove tech debt item #7 from PROJECT.md or reclassify as "resolved."

**GAP-F06: v2.0 Tech Debt #13 -- Daily briefing schedule stored in component state (lost on refresh)**
- **Category:** v2.0 tech debt classification
- **Artifact:** BriefingCard.tsx
- **Location:** `src/AssistantDashboard/components/BriefingCard.tsx`
- **Classification:** **Deploy-blocking (feature missing)**
- **Rationale:** The tech debt item implies a schedule configuration feature exists in component state. Upon inspection, BriefingCard has NO schedule configuration UI or state. The `fyiExpanded` boolean is the only local state. This means the feature described in the tech debt item either was never implemented or was removed. If schedule configuration is a v2.0 requirement, its absence is a gap.
- **Why deploy-blocking:** Without schedule configuration, users cannot control when they receive daily briefings. The briefing timing would be entirely controlled by the Power Automate flow schedule, with no user override from the dashboard.
- **Suggested Fix:** Either (a) implement a schedule configuration panel in BriefingCard with persistence via PCF output property, or (b) document that briefing schedule is managed at the flow level and remove/reclassify this tech debt item.

### Non-Blocking Gaps

**GAP-F07: v2.0 Tech Debt #8 -- BriefingView test coverage thin on schedule logic**
- **Category:** v2.0 tech debt classification
- **Artifact:** BriefingCard.test.tsx
- **Classification:** **Non-blocking (deferrable)**
- **Rationale:** BriefingCard.test.tsx has 10 test cases covering: rendering (day shape, action items, date, stale alerts, calendar correlation), interaction (jump, dismiss), state (FYI expand/collapse), and error handling (bad JSON, empty state). The "schedule logic" referenced in the tech debt item appears to not exist in the component (see GAP-F06). The existing test coverage is reasonable for the component's current functionality.
- **Current coverage:** 10 tests covering all major code paths. Missing: testing with DailyBriefing as an object (not string) in draft_payload (line 28-30 of parseBriefing).

**GAP-F08: v2.0 Tech Debt #9 -- Command bar error states show raw error strings**
- **Category:** v2.0 tech debt classification
- **Artifact:** CommandBar.tsx
- **Classification:** **Non-blocking (deferrable)**
- **Rationale:** The CommandBar component shows "Thinking..." during processing but has no explicit error state handling. If the orchestrator flow fails, the Canvas App would either (a) never update the response variable (leaving "Thinking..." stuck, but see IMP-F01 -- responses are hardcoded to null anyway), or (b) set an error string in the response variable. Since the response path doesn't exist yet (IMP-F01/GAP-F02), error display is moot until the response channel is implemented.
- **Deferral reason:** Fix alongside GAP-F02 (CommandBar response channel). When implementing the response path, include error state handling with user-friendly messages.

**GAP-F09: v2.0 Tech Debt #10 -- No E2E flow coverage for send-email or set-reminder paths**
- **Category:** v2.0 tech debt classification
- **Artifact:** N/A (integration concern)
- **Classification:** **Non-blocking (deferrable)**
- **Rationale:** The PCF control fires output properties for send-email (sendDraftAction) and set-reminder (via commandAction). The actual email sending and reminder creation happen in Power Automate flows, which are outside the PCF control's scope. E2E testing would require a running Power Platform environment, which is out of scope per PROJECT.md constraints ("No runtime testing").
- **Deferral reason:** Requires runtime Power Platform environment. Unit tests cover the PCF output binding (CardDetail send flow, index.ts getOutputs reset). Integration testing deferred to deployment validation.

**GAP-F10: v2.0 Tech Debt #11 -- Confidence calibration thresholds are hardcoded**
- **Category:** v2.0 tech debt classification
- **Artifact:** ConfidenceCalibration.tsx
- **Classification:** **Non-blocking (deferrable)**
- **Rationale:** The accuracy bucket boundaries (90, 70, 40) and the UI color thresholds (70 = good, 40 = ok, below = poor) are hardcoded in the component. Making these configurable would require additional PCF input properties and UI for threshold editing. This is a calibration improvement, not a correctness issue -- the hardcoded values are reasonable starting points.
- **Deferral reason:** The hardcoded thresholds produce meaningful analytics. Configurability is a future enhancement for fine-tuning, not a deployment blocker.

**GAP-F11: v2.0 Tech Debt #12 -- Sender profile 30-day window not configurable**
- **Category:** v2.0 tech debt classification
- **Artifact:** ConfidenceCalibration.tsx (top senders tab)
- **Classification:** **Non-blocking (deferrable)**
- **Rationale:** The top senders calculation in ConfidenceCalibration uses ALL cards, not just a 30-day window. The 30-day window referenced in the tech debt item is a server-side concern (the Sender Profile Analyzer flow filters by date range). The PCF control simply displays whatever cards are in the DataSet, which is already filtered by the Dataverse view configuration. Making the window configurable at the PCF level would duplicate server-side logic.
- **Deferral reason:** Server-side concern. The PCF control should display what the view provides, not re-implement the filtering logic.

**GAP-F12: Missing loading state -- no visual indicator while DataSet loads**
- **Category:** Missing UX handling
- **Artifact:** App.tsx, useCardData.ts
- **Location:** `src/AssistantDashboard/components/App.tsx`
- **Gap:** When the DataSet is loading (initial page load, filter change, data refresh), useCardData returns an empty array. The App then shows the gallery with "No cards match the current filters." This is misleading -- the cards haven't been filtered out, they just haven't loaded yet. There is no Spinner or loading indicator to distinguish "no data" from "loading data."
- **Evidence:** The DataSet API provides a `loading` property, but the hook's minimal interface doesn't include it. useCardData returns `[]` for undefined/empty datasets.
- **Suggested Fix:** Add a `loading` check in index.ts (`dataset.loading`) and pass it as a prop through to App.tsx. Show a `<Spinner label="Loading cards..." />` when loading is true.

**GAP-F13: Missing accessibility -- no ARIA labels, roles, or keyboard navigation landmarks**
- **Category:** Missing UX handling
- **Artifact:** All components
- **Location:** All .tsx files
- **Gap:** No component includes ARIA attributes beyond what Fluent UI v9 provides automatically. Specifically:
  - No `role="navigation"` on FilterBar
  - No `role="main"` on the dashboard content area
  - No `aria-label` on plain HTML buttons (BriefingCard, CommandBar, ConfidenceCalibration)
  - No `aria-live` on the CommandBar response panel (screen readers won't announce new responses)
  - No keyboard shortcut for common actions (Escape to go back, Enter to send)
  - No skip navigation link
- **Evidence:** Grep for `aria-` across all .tsx files returns zero matches. Grep for `role=` returns zero matches.
- **Suggested Fix:** Add ARIA landmarks and labels. Priority: (1) aria-label on all plain HTML buttons, (2) aria-live="polite" on command response panel, (3) role landmarks on major sections.

**GAP-F14: Missing keyboard navigation -- Escape key does not dismiss detail view or panels**
- **Category:** Missing UX handling
- **Artifact:** App.tsx, CardDetail.tsx
- **Location:** `src/AssistantDashboard/components/App.tsx`
- **Gap:** There is no keyboard handler for Escape key to navigate back from detail view to gallery, dismiss the confirm send panel, or close the expanded command bar. The only keyboard handler in the codebase is Enter in CommandBar (line 88).
- **Evidence:** No `onKeyDown` handler in App.tsx. No `useEffect` with keydown event listener.
- **Suggested Fix:** Add a global keydown listener in App.tsx: Escape returns to gallery from detail view, closes panels.

**GAP-F15: `ConfidenceCalibration` division by zero is handled but produces misleading 0% for empty states**
- **Category:** Missing UX handling
- **Artifact:** ConfidenceCalibration.tsx:74, 93, 96, 141
- **Location:** `src/AssistantDashboard/components/ConfidenceCalibration.tsx`
- **Gap:** When there are 0 resolved cards, 0 full cards, or 0 sent cards, the calculations return 0 (via ternary guards like `data.total > 0 ? Math.round(...) : 0`). This prevents division by zero errors, but displaying "0% FULL card action rate" when there are NO full cards is misleading. The user might think all full cards were dismissed rather than understanding there are no full cards.
- **Evidence:** `fullAccuracy: fullCards.length > 0 ? Math.round(...) : 0` -- returns 0 for "no data" and "0% accuracy" indistinguishably.
- **Suggested Fix:** Show "N/A" or "No data yet" instead of 0% when the denominator is 0. The topSenders tab already handles this correctly with a "No sender data yet" message (line 311-315).

**GAP-F16: Dead fields in AssistantCard -- `conversation_cluster_id` and `source_signal_id` never displayed**
- **Category:** Missing data flow connection
- **Artifact:** types.ts:101-102, all components
- **Location:** `src/AssistantDashboard/components/types.ts` lines 101-102
- **Gap:** `conversation_cluster_id` and `source_signal_id` are fields on AssistantCard that are parsed by useCardData from discrete Dataverse columns, but no component reads or displays these values. They exist for clustering and deduplication logic that would need to be implemented (e.g., grouping related cards, showing thread context).
- **Evidence:** Grep for `conversation_cluster_id` in .tsx files returns zero matches. Grep for `source_signal_id` in .tsx files returns zero matches. Only referenced in types.ts, useCardData.ts, and cardFixtures.ts.
- **Suggested Fix:** Either (a) add a "Related cards" section in CardDetail that uses conversation_cluster_id to show other cards in the same thread, or (b) accept as future Sprint data and document that these fields are populated for future clustering features.

**GAP-F17: Missing tests for `App.tsx` calibration view navigation**
- **Category:** Missing test coverage
- **Artifact:** App.test.tsx
- **Location:** `src/AssistantDashboard/components/__tests__/App.test.tsx`
- **Gap:** App.test.tsx tests filter logic (7 tests) and gallery/detail navigation (2 tests), but does not test: (a) navigating to calibration view via "Agent Performance" button, (b) navigating back from calibration view, (c) briefing card rendering in gallery view, (d) briefing card detail view (selecting a DAILY_BRIEFING card). The ViewState has three modes (gallery, detail, calibration) but only two are tested.
- **Evidence:** No test references `calibration`, `Agent Performance`, or the briefing card rendering path in App.test.tsx.
- **Suggested Fix:** Add tests for calibration navigation and briefing card rendering in gallery mode.

**GAP-F18: Missing tests for `CardDetail.tsx` edge cases**
- **Category:** Missing test coverage
- **Artifact:** CardDetail.test.tsx
- **Location:** `src/AssistantDashboard/components/__tests__/CardDetail.test.tsx`
- **Gap:** CardDetail.test.tsx has 24 test cases (thorough). Missing edge cases: (a) card with verified_sources containing unsafe URLs (tested once for single source, not for mixed safe/unsafe), (b) card with empty verified_sources array (length 0 vs null), (c) sending timeout behavior (60-second timer reset).
- **Suggested Fix:** Add tests for mixed safe/unsafe sources and empty array vs null distinction.

**GAP-F19: Missing ESLint rules for React-specific patterns**
- **Category:** Configuration gap
- **Artifact:** .eslintrc.json
- **Location:** `enterprise-work-assistant/src/.eslintrc.json`
- **Gap:** The ESLint configuration does not include `eslint-plugin-react` or `eslint-plugin-react-hooks`. This means: (a) React hooks rules (exhaustive-deps, rules-of-hooks) are not enforced -- the useMemo dependency issue in COR-F03 would have been caught by eslint-plugin-react-hooks, (b) React-specific patterns (key prop validation, no direct state mutation) are not linted.
- **Evidence:** `.eslintrc.json` plugins array contains only `["@typescript-eslint"]`. No react or react-hooks plugin.
- **Suggested Fix:** Add `eslint-plugin-react` and `eslint-plugin-react-hooks` to devDependencies and ESLint config.

**GAP-F20: No development preview mode for PCF control**
- **Category:** Configuration gap
- **Artifact:** package.json
- **Location:** `enterprise-work-assistant/src/package.json`
- **Gap:** The `start` script runs `pcf-scripts start` which launches the PCF test harness. However, the test harness has limited functionality for virtual controls (it can render the control but mock data setup is manual). There is no Storybook, test page, or alternative preview mechanism for rapid development iteration.
- **Evidence:** Only standard pcf-scripts commands available. No storybook config. No standalone preview HTML.
- **Suggested Fix:** Consider adding a simple `preview.html` with mock data that renders the AppWrapper directly, bypassing the PCF lifecycle, for rapid visual iteration during development.

**GAP-F21: `App.tsx` BriefingCard in detail view has no Back button**
- **Category:** Missing UX handling
- **Artifact:** App.tsx:189-194
- **Location:** `src/AssistantDashboard/components/App.tsx` lines 189-194
- **Gap:** When a DAILY_BRIEFING card is selected (detail view), App renders `<BriefingCard>` directly without the Back button that CardDetail provides. The BriefingCard component has a "Dismiss briefing" button but no navigation back to gallery. The user is stuck in the briefing view until they dismiss it (which changes the card_outcome) or the card is removed from the dataset. This is a UX trap.
- **Evidence:** Line 189-194: `selectedCard.trigger_type === "DAILY_BRIEFING" ? <BriefingCard ... />` -- no onBack prop passed, no Back button rendered.
- **Suggested Fix:** Add an onBack prop to BriefingCard, or wrap the briefing detail view with a Back button header similar to CardDetail.

**GAP-F22: Missing test for `useCardData` N/A temporal_horizon to null conversion**
- **Category:** Missing test coverage
- **Artifact:** useCardData.test.ts
- **Location:** `src/AssistantDashboard/hooks/__tests__/useCardData.test.ts`
- **Gap:** The test file tests N/A priority to null conversion (line 137-158) but does NOT test N/A temporal_horizon to null conversion. The ingestion boundary handles both, but only priority is tested.
- **Evidence:** No test case sets `temporal_horizon: "N/A"` and verifies it becomes null.
- **Suggested Fix:** Add a test case: `it('converts N/A temporal_horizon to null')`.

### Known Constraints

**GAP-FC01: No runtime testing possible -- validation is through code review and unit tests only**
- **Constraint:** Per PROJECT.md: "We cannot run the solution locally -- validation is through code review, type checking, and unit tests." This means component rendering behavior, DataSet paging, output property communication, and Canvas App integration are all unverifiable until deployed.
- **Status:** Accepted risk. Mitigated by comprehensive unit tests with realistic mocks.

**GAP-FC02: TypeScript 4.9.5 pinned by pcf-scripts -- cannot upgrade to TS 5.x**
- **Constraint:** pcf-scripts pins TypeScript to ^4.9.5. TypeScript 5.x features (satisfies, const type parameters, decorator metadata) are unavailable. skipLibCheck works around type conflicts between Fluent UI v9 (built for TS 5.x) and the pinned TS 4.9.5.
- **Status:** Accepted risk. Documented in PROJECT.md Out of Scope section.

**GAP-FC03: pcf-scripts controls the build pipeline -- limited webpack/bundler customization**
- **Constraint:** The build process is fully managed by pcf-scripts. Custom webpack configuration, tree-shaking optimization, or build-time code splitting are not available. The output is a single bundled JS file.
- **Status:** Accepted risk. Standard PCF build pipeline.

**GAP-FC04: Canvas App PCF controls run in desktop-only context -- no mobile responsiveness needed**
- **Constraint:** Canvas Apps with PCF controls are desktop-only (Power Apps mobile does not render custom PCF controls). Responsive design for mobile viewports is unnecessary.
- **Status:** Accepted constraint. Width/height are provided by the Canvas App layout engine.

**GAP-FC05: Fluent UI v9 bundles ~350KB -- PCF control will have a large initial download**
- **Constraint:** Fluent UI v9 is a large dependency. The PCF control bundle will include the Fluent UI runtime even though only a subset of components is used. Tree-shaking is limited by pcf-scripts' bundler configuration.
- **Status:** Accepted risk. Initial load time will be slower than a minimal control, but acceptable for a dashboard application that stays open during work sessions.

**GAP-FC06: DataSet API returns formatted values according to user locale -- date/number formatting varies by user settings**
- **Constraint:** `getFormattedValue("createdon")` returns locale-formatted date strings (e.g., "2/21/2026 9:15 AM" for en-US, "21.02.2026 09:15" for de-DE). The PCF control displays these strings as-is, which is correct but means date presentation varies across users.
- **Status:** Correctly handled. Locale-aware formatting is a feature, not a bug.

---

### v2.0 Tech Debt Summary Table

| # | Item | Classification | Rationale |
|---|------|---------------|-----------|
| 7 | Staleness polling setInterval lacks cleanup | **Deploy-blocking (investigate)** | No setInterval found in PCF code -- either resolved, in another layer, or never implemented. Must clarify. |
| 8 | BriefingView test coverage thin on schedule logic | **Non-blocking (deferrable)** | Schedule logic doesn't exist in BriefingCard. Current test coverage (10 tests) is adequate for implemented functionality. |
| 9 | Command bar error states show raw error strings | **Non-blocking (deferrable)** | Response channel doesn't exist yet (GAP-F02). Error handling should be added alongside the response channel implementation. |
| 10 | No E2E flow coverage for send-email or set-reminder | **Non-blocking (deferrable)** | Requires runtime Power Platform environment which is out of scope. Unit tests cover PCF output binding. |
| 11 | Confidence calibration thresholds hardcoded | **Non-blocking (deferrable)** | Hardcoded values (90/70/40) are reasonable defaults. Configurability is a future enhancement. |
| 12 | Sender profile 30-day window not configurable | **Non-blocking (deferrable)** | Server-side concern. PCF displays whatever the DataSet view provides. |
| 13 | Daily briefing schedule in component state | **Deploy-blocking (feature missing)** | Schedule configuration UI doesn't exist in BriefingCard. Either implement or reclassify as server-managed. |

---

### Test Coverage Assessment

| Source File | Test File | Tests | Coverage Assessment |
|---|---|---|---|
| App.tsx (216 lines) | App.test.tsx | 9 | **Adequate** -- filters and gallery/detail navigation tested. Missing: calibration view, briefing rendering |
| BriefingCard.tsx (235 lines) | BriefingCard.test.tsx | 10 | **Good** -- all major paths tested including error state and empty state |
| CardDetail.tsx (430 lines) | CardDetail.test.tsx | 24 | **Good** -- comprehensive coverage of send flow, editing, rendering |
| CardGallery.tsx (36 lines) | CardGallery.test.tsx | 3 | **Adequate** -- simple component, all paths covered |
| CardItem.tsx (79 lines) | CardItem.test.tsx | 6 | **Good** -- all rendering and interaction paths covered |
| CommandBar.tsx (202 lines) | CommandBar.test.tsx | 14 | **Good** -- comprehensive coverage of input, submit, responses, quick actions |
| FilterBar.tsx (41 lines) | FilterBar.test.tsx | 5 | **Good** -- all rendering paths covered |
| ConfidenceCalibration.tsx (324 lines) | NONE | 0 | **MISSING** -- no test file exists (GAP-F03) |
| useCardData.ts (96 lines) | useCardData.test.ts | 15 | **Good** -- comprehensive field mapping and edge case coverage |
| urlSanitizer.ts (34 lines) | urlSanitizer.test.ts | 12 | **Excellent** -- all protocols, edge cases, and export tested |
| index.ts (156 lines) | NONE (excluded) | 0 | **MISSING** -- explicitly excluded from coverage (GAP-F04) |
| types.ts (119 lines) | N/A | N/A | Type-only file, no runtime logic to test |
| constants.ts (11 lines) | N/A | N/A | Constant definition only |
| ManifestTypes.d.ts (20 lines) | N/A | N/A | Auto-generated type declaration |

**Overall:** 98 test cases across 9 test files. Two source files with runtime logic (ConfidenceCalibration.tsx, index.ts) have zero test coverage.
