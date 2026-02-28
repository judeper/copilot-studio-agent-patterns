# Implementability Agent -- Frontend/PCF Findings

## Summary

15 issues found: 3 deploy-blocking, 8 non-blocking, 4 known constraints.

All 14 frontend/PCF source files, 9 test files, and 6 configuration files were reviewed from the perspective of runtime behavior in a real Canvas App PCF virtual control environment. Focus: will these components, hooks, and configurations actually work when deployed?

## Methodology

1. Validated the PCF lifecycle (init/updateView/getOutputs/destroy) against the ComponentFramework.ReactControl contract
2. Verified React version compatibility (React 16.14.0 platform-provided) -- checked for React 17+ or 18+ API usage
3. Traced DataSet binding from ManifestTypes.d.ts through index.ts through useCardData to component rendering
4. Checked every component for null/undefined safety at runtime (crash-free rendering)
5. Validated build pipeline configuration (tsconfig, package.json, jest.config) for pcf-scripts compatibility
6. Assessed test infrastructure accuracy -- do mocks match the real PCF DataSet API?
7. Verified event handling and state propagation for correctness under re-render cycles

---

## Findings

### Deploy-Blocking Issues

**IMP-F01: `lastResponse` and `isProcessing` props hardcoded as null/false in App.tsx -- CommandBar has no connection to orchestrator**
- **Artifact:** App.tsx:210-211, index.ts (entire file)
- **Location:** `src/AssistantDashboard/components/App.tsx` lines 210-211
- **Issue:** App renders CommandBar with `lastResponse={null}` and `isProcessing={false}` hardcoded. The PCF index.ts class has no mechanism to receive orchestrator responses or processing state from the Canvas App host. The `onExecuteCommand` callback fires a JSON-encoded output property that triggers a Power Automate flow, but there is no input property or DataSet column for receiving the orchestrator's response. This means the CommandBar can SEND commands but NEVER receives responses -- the conversation panel will always show user messages but never assistant responses.
- **Evidence:** `<CommandBar currentCardId={currentCardId} onExecuteCommand={onExecuteCommand} onJumpToCard={handleJumpToCard} lastResponse={null} isProcessing={false} />` -- hardcoded. ManifestTypes.d.ts IInputs has no `orchestratorResponse` or `isProcessing` property.
- **Impact:** Deploy-blocking for command bar functionality. Users will type commands that appear to do nothing (no response ever shown). The command bar is functionally a one-way pipe.
- **Suggested Fix:** Add two input properties to ControlManifest.Input.xml: (1) `orchestratorResponse` (StringProperty, bound to a Canvas App variable set by the flow response), (2) `isProcessing` (TwoOptions property). Wire these through index.ts updateView into App.tsx and down to CommandBar.

**IMP-F02: No React error boundary -- any component crash takes down the entire dashboard**
- **Artifact:** index.ts, App.tsx
- **Location:** `src/AssistantDashboard/index.ts` (updateView method), `src/AssistantDashboard/components/App.tsx`
- **Issue:** Neither App.tsx nor index.ts wraps the component tree in a React error boundary. If any child component throws during rendering (e.g., BriefingCard parsing malformed JSON that bypasses the try/catch, ConfidenceCalibration dividing by zero in an edge case, CardDetail accessing a property of undefined), the entire PCF control will crash and display nothing. In a Canvas App, this means the user sees a blank space where their dashboard should be.
- **Evidence:** No class component extending `React.Component` with `componentDidCatch` or `getDerivedStateFromError` exists anywhere in the component tree. React 16.14.0 does not have function component error boundaries (that's a React 19+ feature proposal).
- **Impact:** Deploy-blocking. A single malformed card in a dataset of hundreds could crash the entire dashboard, leaving the user with no UI and no error message.
- **Suggested Fix:** Add an `ErrorBoundary` class component wrapping the App component tree (or wrapping individual sections like CardDetail, BriefingCard). Display a friendly error message with a "reload" action when caught.

**IMP-F03: `BriefingCard` schedule configuration referenced in PROJECT.md tech debt #13 is not implemented -- schedule state is not persisted**
- **Artifact:** BriefingCard.tsx
- **Location:** `src/AssistantDashboard/components/BriefingCard.tsx`
- **Issue:** PROJECT.md tech debt #13 states "Daily briefing schedule stored in component state (lost on refresh)." Upon inspection, BriefingCard.tsx has NO schedule configuration UI at all -- there is no schedule picker, no time selector, no state management for schedule preferences. The only state is `fyiExpanded` (boolean for FYI section toggle). This means the tech debt item describes a feature that was either removed or never fully implemented. If the briefing schedule was supposed to be configurable from the PCF control, it is completely missing.
- **Evidence:** BriefingCard.tsx lines 131-132: `const [fyiExpanded, setFyiExpanded] = useState(false);` -- only local state. No schedule-related props, state, or UI elements. No `onConfigureSchedule` callback in the component or in AppProps.
- **Impact:** Deploy-blocking for the schedule configuration feature. Users cannot configure when they receive their daily briefing from within the dashboard. The briefing schedule would need to be set elsewhere (e.g., a separate configuration page or environment variable).
- **Suggested Fix:** Either (a) implement schedule configuration in BriefingCard with persistence via a PCF output property, or (b) document that schedule configuration is managed outside the PCF control and remove the tech debt reference, or (c) defer to a future sprint with an explicit backlog item.

### Non-Blocking Issues

**IMP-F04: `useCardData` dataset parameter typed as local interface, not actual PCF DataSet type**
- **Artifact:** useCardData.ts:4-13
- **Location:** `src/AssistantDashboard/hooks/useCardData.ts` lines 4-13
- **Issue:** The hook defines its own `DataSet` and `DataSetRecord` interfaces rather than importing from `ComponentFramework.PropertyTypes.DataSet`. The local interfaces have only `sortedRecordIds`, `records`, `getRecordId()`, `getValue()`, and `getFormattedValue()`. The real PCF DataSet API includes additional properties: `paging` (for pagination), `sorting`, `filtering`, `columns`, `linking`, `loading`, `error`, etc. While the cast in index.ts (`props.dataset as Parameters<typeof useCardData>[0]`) makes this work, it means the hook cannot access pagination or other DataSet features.
- **Evidence:** Lines 4-13 define minimal interfaces. The real `ComponentFramework.PropertyTypes.DataSet` interface is much broader. Index.ts line 28-30 uses a type assertion to bridge.
- **Impact:** Non-blocking for basic rendering. Blocking for pagination (see IMP-F05).
- **Suggested Fix:** Either import the real type and narrow the hook's usage, or document the intentional subset.

**IMP-F05: DataSet paging not implemented -- only first page of records rendered**
- **Artifact:** useCardData.ts, index.ts
- **Location:** `src/AssistantDashboard/hooks/useCardData.ts`
- **Issue:** The DataSet API provides paging via `dataset.paging.hasNextPage` and `dataset.paging.loadNextPage()`. Neither useCardData nor index.ts call `loadNextPage()`. This means if the Dataverse view returns more records than the default page size (typically 50 or 250 depending on configuration), only the first page is rendered. The delegation limit for Canvas Apps is 2000 records, but the PCF control may never reach that limit because it doesn't load beyond page 1.
- **Evidence:** No reference to `paging`, `loadNextPage`, or `hasNextPage` in any source file. The hook iterates `dataset.sortedRecordIds` which only contains the current page.
- **Impact:** Non-blocking for initial deployment with small datasets. Would become blocking at scale (>50 cards without paging configured higher).
- **Suggested Fix:** In `updateView`, check `dataset.paging.hasNextPage` and call `loadNextPage()` to accumulate all records. Alternatively, increase the default page size in the DataSet configuration.

**IMP-F06: `ConfidenceCalibration` performs all analytics client-side -- performance risk with large datasets**
- **Artifact:** ConfidenceCalibration.tsx:45-143
- **Location:** `src/AssistantDashboard/components/ConfidenceCalibration.tsx` lines 45-143
- **Issue:** Four `useMemo` computations iterate the full cards array on every render: `resolvedCards` filter, `accuracyBuckets` aggregation, `triageStats` aggregation, `topSenders` Map construction + sort. For small datasets (<100 cards), this is negligible. For larger datasets (1000+ cards), these O(n) computations on every render could cause noticeable lag. The code comment on line 36-37 acknowledges this: "For production use with large datasets, this should be replaced with server-side aggregation."
- **Evidence:** Four separate `useMemo` hooks each iterating `resolvedCards` or `cards`. No memoization of intermediate results across tabs (all computed regardless of active tab).
- **Impact:** Non-blocking. Performance is acceptable for typical deployment sizes (<500 cards). The component already documents this as a known limitation.
- **Suggested Fix:** Only compute metrics for the active tab (lazy evaluation), or move aggregation server-side via a Power Automate flow returning pre-computed metrics.

**IMP-F07: `CommandBar` conversation history stored in React state -- lost on every `updateView` call**
- **Artifact:** CommandBar.tsx:36
- **Location:** `src/AssistantDashboard/components/CommandBar.tsx` line 36
- **Issue:** `const [conversation, setConversation] = useState<ConversationEntry[]>([])` stores conversation history in local state. In a PCF virtual control, `updateView` is called whenever the Canvas App re-renders the control (e.g., when a dataset refresh occurs, when a variable changes, when the user navigates). Each `updateView` call creates a new React element tree, but because the CommandBar component key doesn't change, React preserves its state across re-renders. However, if the user navigates away from the screen and back, or if the Canvas App re-creates the control, the conversation history is lost.
- **Evidence:** `useState<ConversationEntry[]>([])` -- local state with no persistence mechanism.
- **Impact:** Non-blocking. Conversation history is inherently ephemeral in a Canvas App context. Users can re-ask questions. The clear button already allows intentional reset.
- **Suggested Fix:** Accept as known behavior. Optionally persist to sessionStorage or a Canvas App variable if conversation continuity is desired.

**IMP-F08: `BriefingCard` parseBriefing casts draft_payload as DailyBriefing without field validation**
- **Artifact:** BriefingCard.tsx:17-35
- **Location:** `src/AssistantDashboard/components/BriefingCard.tsx` lines 17-35
- **Issue:** `parseBriefing` parses the JSON string and casts it directly to `DailyBriefing` (`as DailyBriefing`). If the JSON is valid but has the wrong shape (e.g., missing `action_items` array, `total_open_items` is a string instead of number), the component will render with undefined values that could cause runtime errors in child components (e.g., `briefing.action_items.map()` would throw if action_items is undefined, though the `hasActions` guard on line 149 prevents this for the array).
- **Evidence:** Line 27: `return JSON.parse(card.draft_payload) as DailyBriefing` -- no shape validation. However, line 149: `const hasActions = briefing.action_items && briefing.action_items.length > 0` provides runtime null-check.
- **Impact:** Non-blocking. The component has sufficient null guards (`hasActions`, `hasFyi`, `hasStale`) to prevent crashes from missing arrays. Missing scalar fields (briefing_date, total_open_items, day_shape) would render as `undefined` in the UI, which is ugly but not a crash.
- **Suggested Fix:** Add basic shape validation after parsing: check that `briefing_type === "DAILY"` and `typeof briefing.total_open_items === "number"` before accepting the cast.

**IMP-F09: `CardDetail.tsx` renders raw `card.created_on` without date formatting**
- **Artifact:** CardDetail.tsx (no explicit rendering of created_on)
- **Location:** `src/AssistantDashboard/components/CardDetail.tsx`
- **Issue:** CardDetail does not render the `created_on` field at all. CardItem.tsx renders it in the footer (line 73-75) using the raw `getFormattedValue("createdon")` string from Dataverse, which is locale-formatted by the platform. This is actually correct behavior -- Dataverse formats dates according to the user's locale settings.
- **Reclassification:** Not an issue. Dataverse-formatted date strings are appropriately locale-aware.

**IMP-F10: `index.ts` does not call `dataset.paging.setPageSize()` to control record count**
- **Artifact:** index.ts:108
- **Location:** `src/AssistantDashboard/index.ts` line 108
- **Issue:** The control reads `context.parameters.cardDataset` but never calls `setPageSize()` to control how many records are returned per page. The default page size varies by configuration (50-250). Combined with IMP-F05 (no pagination), this means the control shows a potentially arbitrary number of records.
- **Evidence:** No reference to `setPageSize` in any source file.
- **Impact:** Non-blocking. The control will display whatever records the platform provides. For small deployments, the default page size is sufficient.
- **Suggested Fix:** Call `dataset.paging.setPageSize(100)` in `init()` to set a reasonable default, or implement full pagination (IMP-F05).

**IMP-F11: Build pipeline uses `pcf-scripts` with React 16 types -- `@testing-library/react` v16.3.2 expects React 18+**
- **Artifact:** package.json:22-23
- **Location:** `enterprise-work-assistant/src/package.json` lines 22-23
- **Issue:** `@testing-library/react: ^16.3.2` is designed for React 18+ and uses `createRoot` and `act` from React 18. However, `@types/react: ~16.14.0` pins React 16 types. This version mismatch works because: (1) pcf-scripts provides React at runtime so no React package is installed, (2) ts-jest uses skipLibCheck to avoid type conflicts, (3) the test library falls back to the legacy rendering API when React 18 APIs aren't available, OR (4) the actual React version available during testing may differ from the type declarations.
- **Evidence:** `@testing-library/react: ^16.3.2` (latest) vs `@types/react: ~16.14.0` (React 16). The `skipLibCheck: true` in tsconfig.json suppresses type conflicts.
- **Impact:** Non-blocking. Tests pass because of skipLibCheck and runtime compatibility layers. However, the version mismatch could cause confusing failures if skipLibCheck is ever disabled.
- **Suggested Fix:** Pin `@testing-library/react` to a version compatible with React 16 (v12.x or v13.x), or document the skipLibCheck dependency explicitly.

### Known Constraints

**IMP-FC01: PCF virtual controls cannot use ReactDOM.render() -- must use updateView() return pattern**
- **Artifact:** index.ts
- **Location:** `src/AssistantDashboard/index.ts`
- **Constraint:** PCF virtual controls (React-based) must return `React.ReactElement` from `updateView()`. They cannot call `ReactDOM.render()` directly. The codebase correctly follows this pattern -- `updateView` returns `React.createElement(AppWrapper, {...})`.
- **Status:** Correctly handled. No action needed.

**IMP-FC02: Canvas App delegation limit of 2000 records applies to DataSet binding**
- **Artifact:** useCardData.ts
- **Location:** N/A (platform constraint)
- **Constraint:** Even with pagination implemented, the Canvas App DataSet binding is subject to the 2000-record delegation limit. If the Dataverse view returns more than 2000 records, the DataSet will be truncated. For the Enterprise Work Assistant, this is unlikely to be hit (most users won't have 2000 active cards), but it's a known ceiling.
- **Status:** Accepted risk. Document in deployment guide that card archival or cleanup is recommended for long-term use.

**IMP-FC03: PCF controls cannot access Canvas App variables directly -- must use output properties for communication**
- **Artifact:** index.ts
- **Location:** N/A (platform constraint)
- **Constraint:** The PCF control communicates back to the Canvas App host exclusively through output properties (`getOutputs()`). It cannot read or write Canvas App global variables, screen variables, or collections directly. All bidirectional communication must flow through the output property -> OnChange event -> variable assignment pattern.
- **Status:** Correctly handled via the fire-and-forget output binding pattern. The orchestrator response gap (IMP-F01) is a design gap, not a platform constraint -- input properties CAN receive data from Canvas App variables.

**IMP-FC04: React 16.14.0 limitations -- no Suspense for data fetching, no concurrent features, no useId, no useTransition**
- **Artifact:** All .tsx files
- **Location:** N/A (platform constraint)
- **Constraint:** The PCF platform provides React 16.14.0. This means: no `useId()` (React 18), no `useTransition()` (React 18), no `useDeferredValue()` (React 18), no Suspense for data fetching (React 18), no automatic batching of state updates (React 18). The codebase correctly avoids all React 18+ APIs.
- **Status:** Correctly handled. All components use React 16-compatible APIs (useState, useEffect, useMemo, useCallback, useRef).

---

### Validated (No Issues)

1. **PCF ReactControl interface implementation** -- AssistantDashboard class correctly implements init, updateView, getOutputs, destroy
2. **React.createElement usage** -- updateView correctly returns React.createElement (not JSX) for the entry point
3. **Dataset version counter** -- datasetVersion++ in updateView forces useMemo recomputation in useCardData
4. **Stable callback references** -- All handler functions created once in init(), stored as class properties, never recreated
5. **Output property reset** -- getOutputs() clears action properties after reading to prevent stale re-fires
6. **Container resize tracking** -- `context.mode.trackContainerResize(true)` called in init for responsive layout
7. **Width/height fallbacks** -- `width > 0 ? width : 800` prevents zero-dimension rendering
8. **FluentProvider theme switching** -- usePrefersDarkMode correctly uses matchMedia with cleanup
9. **matchMedia cleanup** -- addEventListener/removeEventListener pattern prevents memory leaks
10. **React.useMemo for filtered cards** -- Prevents recomputation on unrelated re-renders
11. **React.useCallback for handlers** -- Stable references prevent child re-renders
12. **CardDetail state reset on card change** -- useEffect resets local state when card.id changes
13. **CardDetail sending timeout** -- 60-second timer prevents stuck "sending" state
14. **useCardData error handling** -- try/catch per record prevents one bad record from crashing the gallery
15. **useCardData empty dataset handling** -- Returns [] for undefined, null sortedRecordIds, or empty array
16. **urlSanitizer try/catch** -- URL constructor failures return false, not throw
17. **BriefingCard parseBriefing try/catch** -- JSON.parse failures return null, triggering error state UI
18. **BriefingCard null guards** -- hasActions, hasFyi, hasStale all check for truthy + length > 0
19. **CommandBar duplicate response guard** -- Prevents appending same response twice
20. **CardGallery empty state** -- Renders friendly message when cards.length === 0
21. **TypeScript strict mode** -- tsconfig.json has `strict: true`, `noImplicitAny: true`, `noUnusedLocals: true`
22. **Jest configuration** -- Correctly targets __tests__ directories with ts-jest transform and jsdom environment
23. **jest.setup.ts mocks** -- matchMedia and ResizeObserver mocks prevent jsdom crashes
24. **renderWithProviders helper** -- Wraps components in FluentProvider matching runtime environment
25. **createMockDataset factory** -- Accurately simulates getValue/getFormattedValue/getRecordId API surface
26. **Test fixtures** -- Realistic card data matching actual agent output shapes (all tiers represented)
27. **ESLint configuration** -- TypeScript parser with recommended rules, no-explicit-any as warning
