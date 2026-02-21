# Domain Pitfalls

**Domain:** Power Platform PCF + Copilot Studio Enterprise Work Assistant
**Researched:** 2026-02-20

---

## Critical Pitfalls

Mistakes that cause rewrites, broken deployments, or major runtime failures.

---

### Pitfall 1: Fluent UI v9 Platform Library Version Pinning

**What goes wrong:** The PAC CLI `pac pcf init --framework react` scaffolds projects with a `@fluentui/react-components` version (e.g., 9.68.0) that is NOT supported by the Power Platform runtime. The platform only loads Fluent v9 versions within the range `>=9.4.0 <=9.46.2`. Attempting to deploy a control referencing an unsupported version produces the error: _"platform library fluent_9_68_0 with version 9.68.0 is not supported by the platform."_

**Why it happens:** The PAC CLI npm template tracks the latest published `@fluentui/react-components` version rather than the platform-supported ceiling. The ControlManifest.Input.xml `<platform-library>` element locks the version expectation, but package.json may pull a newer version through `^` semver ranges.

**Consequences:** Solution import fails entirely. The PCF control cannot be deployed. Developers waste time debugging build-vs-deploy mismatches.

**Prevention:**
- Pin `@fluentui/react-components` to `9.46.2` (not `^9.46.0`) in `package.json`. The current project uses `^9.46.0` which could resolve to an unsupported version.
- Ensure `ControlManifest.Input.xml` declares `<platform-library name="Fluent" version="9.46.2" />`.
- After running `npm install`, verify the resolved version in `package-lock.json`.
- Reference the official supported versions table at [Microsoft Learn: React controls & platform libraries](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/react-controls-platform-libraries).

**Detection:** `pac solution import` fails with platform library version error. Locally, `npm ls @fluentui/react-components` shows a version above 9.46.2.

**Phase relevance:** PCF Component Fixes phase. Verify package.json pinning before any build/deploy attempt.

**Confidence:** HIGH -- confirmed via official Microsoft Learn docs (updated 2025-10-10) and GitHub issue #1265 on powerplatform-build-tools.

---

### Pitfall 2: React Version Mismatch Between Development and Runtime

**What goes wrong:** The PCF manifest declares `<platform-library name="React" version="16.14.0" />`, and `@types/react` is pinned to `~16.14.0`. However, at runtime, Power Apps Model-driven apps load React 17.0.2 while Canvas apps load React 16.14.0. The local test harness (`pcf-start`) uses React 16.8.6. This means developers test against a version that differs from both production environments.

**Why it happens:** The Power Platform provides React as a shared platform library. The actual version loaded at runtime is determined by the host (Canvas vs Model-driven), not by the manifest declaration. The `pcf-start` development server bundles its own React copy.

**Consequences:** Subtle behavioral differences between dev and production. React 17 changed event delegation (events attach to root instead of document), which can break event handlers in certain edge cases. Components that work in the test harness may fail in production.

**Prevention:**
- Accept React 16.14.0 as the baseline and code to its API surface (no React 17/18 features).
- Do not use `createRoot` (React 18) or rely on event delegation behavior changes from React 17.
- Test in an actual Canvas App, not just the PCF test harness, before considering the control production-ready.
- The current `@types/react: "~16.14.0"` pinning is correct -- do not upgrade it.

**Detection:** Components behave differently in the test harness vs. deployed Canvas App. Event handlers fire differently or state updates batch differently.

**Phase relevance:** PCF Component Fixes and Testing phases.

**Confidence:** HIGH -- confirmed via official Microsoft Learn docs listing exact runtime versions.

---

### Pitfall 3: Power Automate Parse JSON Does Not Support oneOf/anyOf/allOf

**What goes wrong:** The canonical `output-schema.json` uses `oneOf` for the `draft_payload` field (it can be null, a string, or an object). Power Automate's Parse JSON action silently rejects schemas containing `oneOf`, `anyOf`, or `allOf`. If someone copies the canonical schema into a Parse JSON action, the flow will fail at runtime on every agent invocation.

**Why it happens:** Power Automate's JSON schema parser implements a subset of JSON Schema Draft-07. Polymorphic type unions are not in that subset. This is poorly documented -- there is no explicit error at design time, only at runtime.

**Consequences:** Every flow run fails. Agent output is never written to Dataverse. The entire pipeline is broken with no obvious error message pointing to the schema as the cause.

**Prevention:**
- The project already documents a simplified schema in `docs/agent-flows.md` that uses `{}` (empty schema, accepts any value) for `draft_payload` and `verified_sources`. This is the correct approach.
- Add a prominent warning in `schemas/output-schema.json` noting the Parse JSON incompatibility (already partially done in the description field).
- Never use `oneOf`/`anyOf`/`allOf` in any schema intended for Power Automate consumption.
- For downstream type safety, use expression-based type checking in the flow (e.g., `if(equals(body('Parse_JSON')?['draft_payload'], null), ...)`) rather than relying on schema validation.

**Detection:** Flow runs fail at the Parse JSON step. Error message references schema validation failure but does not specifically call out `oneOf`.

**Phase relevance:** Schema/Prompt Consistency phase. Ensure docs clearly separate "canonical schema" from "Power Automate schema."

**Confidence:** HIGH -- confirmed via Microsoft Learn known issues for Copilot extensibility and multiple community reports.

---

### Pitfall 4: Dataverse Primary Column Cannot Be Null

**What goes wrong:** The `cr_assistantcard` table uses `cr_itemsummary` as its primary column (`PrimaryNameAttribute`). Dataverse requires the primary column to be non-null on every row. The agent schema allows `item_summary: null` for SKIP-tier items. If a SKIP item is written to Dataverse, the insert fails with a constraint violation.

**Why it happens:** Dataverse enforces that the primary name attribute always has a value -- this is a platform-level constraint that cannot be overridden even by setting `RequiredLevel` to `None`. The agent's SKIP tier deliberately sets `item_summary` to null because no summary is meaningful.

**Consequences:** If the Power Automate flow does not check `triage_tier` before writing to Dataverse, SKIP items cause runtime errors. Even if the flow filters correctly today, a future maintainer could remove the check and introduce silent failures.

**Prevention:**
- The project already handles this correctly: the `dataverse-table.json` notes explain that SKIP items are NOT written to Dataverse, and the flow checks `triage_tier != 'SKIP'` before the "Add a new row" action.
- Add a code comment or assertion in the flow documentation making this an explicit invariant: "SKIP items MUST NOT be written to Dataverse."
- If SKIP items ever need to be tracked, use a placeholder value like "(Skipped)" instead of null for `cr_itemsummary`.

**Detection:** Flow runs fail at the "Add a new row" Dataverse step with a null constraint error.

**Phase relevance:** Schema/Prompt Consistency phase. Validate that prompt SKIP examples + flow logic + schema all agree.

**Confidence:** HIGH -- confirmed via Dataverse documentation on primary column requirements.

---

### Pitfall 5: Dataverse Table Name vs Entity Set Name Confusion

**What goes wrong:** Dataverse uses three different names for the same table, and using the wrong one in the wrong context produces silent failures or 404 errors:
- **Logical name (table name):** `cr_assistantcard` (singular, lowercase) -- used in Web API metadata operations, OData `$filter`, FetchXML, and provisioning scripts.
- **Entity set name:** `cr_assistantcards` (plural) -- used in Web API data operations (`GET/POST /api/data/v9.2/cr_assistantcards`).
- **Display name:** `Assistant Cards` -- used in Canvas App formulas and Power Automate UI.

The project's `dataverse-table.json` defines `tableName: "cr_assistantcard"` and `entitySetName: "cr_assistantcards"`, but the `docs/agent-flows.md` refers to the table as "Assistant Cards" (display name), and various scripts use `cr_assistantcard` (logical name). If anyone uses the singular logical name in a Web API data operation, or the plural entity set name in a metadata operation, the call fails.

**Why it happens:** Dataverse's naming convention is genuinely confusing. The entity set name is auto-generated as the plural of the logical name, and the display name is a separate human-readable label. Power Apps formulas use display names while APIs use logical/entity set names. The `create-security-roles.ps1` script correctly uses the logical name for privilege lookups, but a future maintainer could easily mix them up.

**Consequences:** API calls return 404. Scripts fail during provisioning. Developers waste hours debugging what appears to be authentication issues but is actually a naming mismatch.

**Prevention:**
- Centralize the authoritative name mapping in `dataverse-table.json` (already done) and reference it consistently.
- In scripts, always use `$entityLogicalName` and `$entitySetName` as variable names (not just `$tableName`) to make the distinction explicit.
- In documentation, always specify which name form is being used: "(logical name: `cr_assistantcard`)" or "(entity set name: `cr_assistantcards`)".
- In `provision-environment.ps1`, the `SchemaName` is set to `${PublisherPrefix}_assistantcard` -- this is correct; schema name == logical name for custom tables.

**Detection:** 404 errors on Dataverse Web API calls. Power Automate flows fail at the Dataverse connector step with "entity not found."

**Phase relevance:** Documentation and Deployment Script phases. Audit all name references for consistency.

**Confidence:** HIGH -- confirmed via Microsoft Learn table definitions documentation.

---

### Pitfall 6: PCF Dataset useMemo Dependency on Version Counter Instead of Dataset

**What goes wrong:** In the current `useCardData.ts` hook, the `useMemo` dependency array is `[version]` -- a counter incremented on every `updateView` call. This means the card array is recomputed on EVERY updateView, defeating the purpose of memoization entirely. The memoization provides zero optimization because the dependency changes every single time.

**Why it happens:** PCF datasets are mutated in place by the platform -- the `dataset` object reference never changes, so putting `dataset` in the dependency array would never trigger recomputation. The version counter was introduced as a workaround, but incrementing it unconditionally makes the memo equivalent to no memoization at all.

**Consequences:** On every `updateView` call (which fires frequently -- on resize, property changes, focus events), the entire dataset is re-parsed including JSON.parse on every record. For dashboards with 50+ cards, this causes visible jank.

**Prevention:**
- Keep the version counter approach (it is the correct pattern for PCF datasets where the reference is stable), but add a shallow equality check inside the memo to skip recomputation when the data has not actually changed.
- Alternatively, compare `dataset.sortedRecordIds.join(',')` to a cached value and only reparse when IDs change.
- Example:
  ```typescript
  const prevIdsRef = React.useRef<string>("");
  return React.useMemo(() => {
      const currentIds = dataset?.sortedRecordIds?.join(",") ?? "";
      if (currentIds === prevIdsRef.current) return prevCardsRef.current;
      prevIdsRef.current = currentIds;
      // ... parse cards ...
  }, [version]);
  ```
- However, note that for this reference project, the unconditional recompute is functionally correct even if suboptimal. The priority should be correctness over optimization.

**Detection:** React DevTools Profiler shows the App component re-rendering on every updateView even when data has not changed. Performance degrades with larger datasets.

**Phase relevance:** PCF Component Fixes phase (moderate priority -- correctness first, then optimization).

**Confidence:** MEDIUM -- the version counter pattern is standard practice in PCF per community guidance, but the unconditional recompute is a known suboptimality. The optimization pattern is based on React best practices, not PCF-specific official docs.

---

## Moderate Pitfalls

---

### Pitfall 7: Fluent UI v9 Badge `size` Prop Accepts Specific Values Only

**What goes wrong:** The Fluent UI v9 `Badge` component accepts these size values: `"tiny"`, `"extra-small"`, `"small"`, `"medium"`, `"large"`, `"extra-large"`. Values like `"small"` (used in the current codebase for source tier badges) and `"medium"` (used for priority/status badges) are valid. However, any typo or invalid size value will be silently ignored (no TypeScript error at build time if using string literals correctly, but the Badge renders at default size).

**Prevention:**
- Verify all Badge `size` props match the allowed union type. The current codebase uses `"small"` and `"medium"` which are both valid.
- Use TypeScript strict mode to catch invalid size literals at compile time.
- Avoid `"large"` or `"extra-large"` for inline badges in card layouts -- they will break visual consistency.

**Detection:** Badges render at unexpected sizes. TypeScript compilation succeeds but visual output looks wrong.

**Phase relevance:** PCF Component Fixes phase -- audit all Badge usages.

**Confidence:** HIGH -- confirmed via Fluent UI v9 `Badge.types.ts` on GitHub: `size?: 'tiny' | 'extra-small' | 'small' | 'medium' | 'large' | 'extra-large'`.

---

### Pitfall 8: Inconsistent Token Import Paths Between Components

**What goes wrong:** The codebase imports `tokens` from two different paths:
- `CardDetail.tsx` and `CardItem.tsx`: `import { tokens } from "@fluentui/react-components";`
- `CardGallery.tsx` and `FilterBar.tsx`: `import { tokens } from "@fluentui/react-theme";`

Both imports resolve to the same tokens object because `@fluentui/react-components` re-exports from `@fluentui/react-theme`. However, in a PCF virtual control using platform libraries, `@fluentui/react-theme` is NOT declared as a separate platform library -- only `@fluentui/react-components` is. This means `@fluentui/react-theme` gets bundled into the control's `bundle.js` instead of being shared from the platform, increasing bundle size and potentially causing token value mismatches if the bundled version differs from the platform version.

**Why it happens:** Both import paths work during local development because both packages are installed. The subtle difference only manifests in production where platform libraries are shared.

**Prevention:**
- Standardize all token imports to `import { tokens } from "@fluentui/react-components";`.
- Remove `@fluentui/react-theme` from direct dependencies if present.
- Add an ESLint rule or code review checklist item to flag imports from `@fluentui/react-theme`.

**Detection:** Bundle size is larger than expected. In production, tokens may resolve to different values than in the FluentProvider theme.

**Phase relevance:** PCF Component Fixes phase -- straightforward find-and-replace.

**Confidence:** MEDIUM -- the import equivalence is confirmed by npm package structure. The platform library bundling behavior is inferred from the PCF virtual control documentation (only declared platform libraries are shared; others are bundled).

---

### Pitfall 9: Choice Column Integer Mapping Drift Between Schema and Flow

**What goes wrong:** Dataverse Choice columns store integer values (e.g., SKIP=100000000, LIGHT=100000001, FULL=100000002). The agent outputs string labels ("SKIP", "LIGHT", "FULL"). Power Automate flows must map strings to integers using `if()` expression chains. If the mapping values in the flow drift from the values defined in `dataverse-table.json` and `provision-environment.ps1`, records are created with wrong Choice values. Dataverse will accept any integer, even invalid ones -- it does not validate against the option set at write time via the connector.

**Why it happens:** The mapping is defined in three independent places: (1) `dataverse-table.json`, (2) `provision-environment.ps1`, and (3) the Power Automate flow expressions documented in `agent-flows.md`. There is no single source of truth enforced at build time. A change in one place requires manual synchronization to the others.

**Prevention:**
- Treat `dataverse-table.json` as the single source of truth.
- In `agent-flows.md`, reference the Choice Value Mapping table (already done) and add a warning that values MUST match `dataverse-table.json`.
- Consider generating the mapping table in docs directly from `dataverse-table.json` as part of a build step or documentation generation script.
- When adding new Choice options, update all three locations simultaneously.

**Detection:** Cards appear with wrong filter values in the Canvas App. Choice columns show unexpected labels in the Dataverse table viewer.

**Phase relevance:** Schema/Prompt Consistency phase.

**Confidence:** HIGH -- this is a well-documented Dataverse pattern. The current project handles it correctly but lacks automated consistency enforcement.

---

### Pitfall 10: XSS Risk in Source URL Rendering

**What goes wrong:** The `CardDetail.tsx` component renders source URLs as `<Link href={...}>` elements. The current code includes a regex check (`/^https?:\/\//.test(source.url)`) to validate URLs before rendering them as clickable links. However, the agent prompt allows non-HTTP URLs in `verified_sources` (e.g., `outlook://message/AAMkADQ3...`, `teams://thread/19:abc123...`, `planner://task/abc-def-123`). These are scheme-based URIs, not HTTP URLs, and the regex correctly falls them back to `href="#"`. However, a malicious or hallucinated source could contain `javascript:` URLs -- while the regex check blocks these, the defense is a single regex rather than an allowlist of safe schemes.

**Why it happens:** The agent is instructed to cite sources from internal tools (Outlook, Teams, Planner, SharePoint) which use custom URI schemes. The URL validation needs to balance allowing legitimate internal schemes while blocking dangerous ones.

**Prevention:**
- Replace the regex check with an explicit allowlist of safe schemes: `https:`, `http:`, `outlook:`, `teams:`, `planner:`, `sharepoint:`.
- Example:
  ```typescript
  const SAFE_SCHEMES = /^(https?|outlook|teams|planner|sharepoint):\/\//i;
  const href = SAFE_SCHEMES.test(source.url) ? source.url : "#";
  ```
- Add `rel="noopener noreferrer"` on all external links (already done in current code).

**Detection:** Code review catches the pattern. Security audit flags single-regex URL validation.

**Phase relevance:** PCF Component Fixes phase.

**Confidence:** MEDIUM -- the current regex check is functional but not defense-in-depth. The risk is moderate because LLM-generated URLs are unlikely to contain `javascript:` schemes, but a reference pattern should demonstrate best practices.

---

### Pitfall 11: Power Automate Row Ownership for RLS

**What goes wrong:** Power Automate flows run under the connection owner's identity. By default, every Dataverse row created by the flow is owned by the service account or admin account that authenticated the Dataverse connector -- NOT the end user whose email/message triggered the flow. Without explicitly setting the Owner field, all users' cards are owned by the same account, and Row-Level Security (RLS) either shows all cards to everyone or no cards to anyone.

**Why it happens:** This is counterintuitive behavior. Most developers assume the flow "runs as" the triggering user, but it runs as the connection owner. The Owner field must be explicitly set using the triggering user's Azure AD Object ID.

**Prevention:**
- The project already documents this in `agent-flows.md` under "Important: Row Ownership" and includes the expression `@{outputs('Get_my_profile_(V2)')?['body/id']}`.
- Add a verification step in the flow that asserts the Owner field was set (e.g., after the "Add a new row" action, verify the row's owner matches the expected user).
- Include this in the testing checklist: "Verify that cards created by the flow are owned by the triggering user, not the connection owner."

**Detection:** All cards appear for all users (or no users). Dataverse table view shows a single owner for all rows.

**Phase relevance:** Flow Documentation phase. Already documented but should be verified in testing.

**Confidence:** HIGH -- confirmed via Microsoft Learn Dataverse connector documentation and Power Automate flow identity model.

---

### Pitfall 12: Copilot Studio JSON Output Mode Schema Enforcement

**What goes wrong:** Copilot Studio's JSON output mode uses a JSON example (not a JSON Schema) to guide output structure. The model may:
1. Wrap JSON in markdown code fences (````json ... ````).
2. Add explanatory text before/after the JSON object.
3. Omit nullable fields entirely instead of setting them to null.
4. Return `"N/A"` as a string where null is expected (or vice versa).

**Why it happens:** LLMs generate text probabilistically. Even with JSON output mode enabled, the model may not perfectly follow the schema on every invocation. The JSON example format in Copilot Studio cannot express nullability or union types.

**Consequences:** Parse JSON step in Power Automate fails. Or parsing succeeds but downstream logic breaks due to missing fields or unexpected types.

**Prevention:**
- The system prompt already includes the instruction "Your response must begin with `{` and end with `}`. Do not add any text, labels, or code fences." This is the correct mitigation.
- Also add: "Don't include JSON markdown in your answer" (recommended by Copilot Studio FAQ for exactly this issue).
- In the Power Automate flow, add a Compose step before Parse JSON that strips any leading/trailing non-JSON content using an expression like:
  ```
  @{trim(replace(replace(outputs('Invoke_agent')?['text'], '```json', ''), '```', ''))}
  ```
- Always include few-shot examples in the prompt showing the exact null field patterns (already done -- Examples 2 and 4 show null patterns).

**Detection:** Intermittent Parse JSON failures in Power Automate. Agent responses contain markdown formatting around JSON.

**Phase relevance:** Schema/Prompt Consistency phase.

**Confidence:** MEDIUM -- confirmed via Copilot Studio JSON output docs FAQ section. The intermittent nature of the issue makes it hard to catch in limited testing.

---

## Minor Pitfalls

---

### Pitfall 13: PowerShell Script `az account get-access-token` Dependency

**What goes wrong:** The `provision-environment.ps1` and `create-security-roles.ps1` scripts use `az account get-access-token --resource $OrgUrl` to get a Dataverse API token. This requires Azure CLI to be installed AND authenticated (`az login`) separately from PAC CLI authentication. Developers who have authenticated with `pac auth create` assume they are ready to run the scripts, but `az` is a separate auth context.

**Prevention:**
- Add a prerequisite check at the top of each script that validates both `pac` and `az` are authenticated.
- The `provision-environment.ps1` already has a comment about this, but it should be a hard check (try `az account show` and fail with a clear message).
- Document in the deployment guide that TWO separate authentication steps are required.

**Detection:** Scripts fail with "Failed to get access token" after PAC CLI auth succeeds.

**Phase relevance:** Deployment Script Fixes phase.

**Confidence:** HIGH -- directly observable in the script code.

---

### Pitfall 14: `datasetVersion++` Increments on Every updateView Including Resizes

**What goes wrong:** In `index.ts`, `this.datasetVersion++` fires on every `updateView` call. The `updateView` method is called not just when data changes, but also on container resizes (because `trackContainerResize(true)` is enabled), property changes, focus events, and other platform events. Each increment triggers `useMemo` recomputation in `useCardData`, causing unnecessary JSON parsing.

**Prevention:**
- Only increment the version counter when dataset-related properties have actually changed. Check `context.updatedProperties` for `"dataset"`:
  ```typescript
  if (context.updatedProperties.includes("dataset")) {
      this.datasetVersion++;
  }
  ```
- Note: In Canvas Apps, `context.updatedProperties` is not always populated reliably. Test thoroughly and fall back to unconditional increment if needed.

**Detection:** Performance profiling shows `useCardData` recomputing on window resize events.

**Phase relevance:** PCF Component Fixes phase (low priority -- optimization, not correctness).

**Confidence:** MEDIUM -- `updatedProperties` behavior is confirmed for Model-driven apps but may be unreliable in Canvas Apps per community reports.

---

### Pitfall 15: Controlled Textarea Without onChange Handler Warning

**What goes wrong:** In `CardDetail.tsx`, the humanized draft `Textarea` uses `readOnly` with a no-op `onChange` handler:
```tsx
onChange={() => { /* readOnly -- no-op */ }}
```
While this suppresses the React controlled component warning, it is an anti-pattern. The second `Textarea` (for pending drafts) omits the `onChange` handler entirely, which will produce a React warning in the console.

**Prevention:**
- Use the `defaultValue` prop instead of `value` for truly read-only textareas, which avoids the controlled component issue entirely.
- Or consistently add the no-op `onChange` to all read-only controlled textareas.

**Detection:** React console warnings about controlled components without onChange handlers.

**Phase relevance:** PCF Component Fixes phase (cosmetic).

**Confidence:** HIGH -- standard React controlled component behavior.

---

### Pitfall 16: `create-security-roles.ps1` Privilege Name Convention

**What goes wrong:** The script constructs privilege names using the pattern `prv{Action}{entityName}` where `entityName = "${PublisherPrefix}_assistantcard"`. Dataverse privilege names for custom entities follow the pattern `prvCreate${SchemaName}` where SchemaName uses the original casing. If the publisher prefix or entity name uses different casing than what Dataverse expects, the privilege lookup returns empty results and role configuration silently fails.

**Why it happens:** Dataverse privilege naming is case-sensitive for custom entities. The script uses all-lowercase (`cr_assistantcard`), which should match because custom table schema names are stored lowercase. However, this assumption breaks if someone creates the table manually with PascalCase naming.

**Prevention:**
- The script already handles the "privilege not found" case gracefully (writes a warning).
- Add a note that the privilege names depend on the exact SchemaName used during table creation.
- If the table was created by the provisioning script (which uses lowercase), the privilege names will be correct.

**Detection:** "Privilege 'prvCreatecr_assistantcard' not found" warnings during script execution.

**Phase relevance:** Deployment Script Fixes phase.

**Confidence:** MEDIUM -- Dataverse privilege naming conventions are documented but the case-sensitivity behavior is based on community knowledge rather than explicit official documentation.

---

### Pitfall 17: FluentProvider Theme Not Inheriting from Host App

**What goes wrong:** The `App.tsx` component wraps the entire dashboard in a `FluentProvider` with a hardcoded theme selection based on `prefers-color-scheme` media query. This ignores the host Canvas App's theme settings. If the Power App uses a custom theme or the user has set a specific theme in Power Apps, the PCF control will show a different visual style.

**Prevention:**
- For a reference pattern, the `prefers-color-scheme` approach is acceptable as a reasonable default.
- For production deployments, investigate whether the PCF context provides theme information that can be mapped to a Fluent theme.
- The Power Platform's Fluent modern theming preview may provide theme tokens directly to PCF controls in the future.
- Document this as a known limitation.

**Detection:** Visual mismatch between the PCF control and the surrounding Canvas App UI.

**Phase relevance:** Documentation phase -- document as a known limitation rather than a bug.

**Confidence:** LOW -- Power Platform's Fluent modern theming for PCF is in preview and may change. The current approach is the best available pattern for Canvas Apps.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Schema/Prompt Fixes | `item_summary` null for SKIP vs. primary column NOT NULL constraint | Ensure SKIP items never written to Dataverse (Pitfall 4) |
| Schema/Prompt Fixes | `oneOf` in canonical schema vs. Parse JSON limitation | Maintain separate simplified schema for Power Automate (Pitfall 3) |
| Schema/Prompt Fixes | `draft_payload` can be null, string, or object | PCF code must handle all three types; flow must use `{}` schema (Pitfalls 3, 12) |
| PCF Component Fixes | Fluent UI version pinning | Pin to 9.46.2 exactly, verify ControlManifest.Input.xml (Pitfall 1) |
| PCF Component Fixes | Token import path inconsistency | Standardize to `@fluentui/react-components` (Pitfall 8) |
| PCF Component Fixes | Badge size/color token correctness | Audit against Fluent UI v9 type definitions (Pitfall 7) |
| PCF Component Fixes | URL scheme allowlist for sources | Replace regex with scheme allowlist (Pitfall 10) |
| PCF Component Fixes | useMemo recomputation on every updateView | Add dataset change detection (Pitfall 6, 14) |
| Deployment Scripts | Dual auth requirement (PAC CLI + Azure CLI) | Validate both auth contexts at script start (Pitfall 13) |
| Deployment Scripts | Privilege name case sensitivity | Ensure SchemaName matches exactly between table creation and privilege lookup (Pitfall 16) |
| Flow Documentation | Choice column integer mapping drift | Reference `dataverse-table.json` as single source of truth (Pitfall 9) |
| Flow Documentation | Row ownership for RLS | Explicit Owner field in every "Add a new row" (Pitfall 11) |
| Testing | React version mismatch dev vs. runtime | Test in actual Canvas App, not just test harness (Pitfall 2) |
| Testing | JSON output intermittent formatting | Add JSON sanitization step before Parse JSON (Pitfall 12) |

---

## Sources

### Official Documentation (HIGH confidence)
- [React controls & platform libraries - Microsoft Learn](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/react-controls-platform-libraries) -- Platform library versions, virtual control requirements
- [JSON output - Copilot Studio - Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-copilot-studio/process-responses-json-output) -- JSON output mode limitations and FAQ
- [Table definitions in Dataverse - Microsoft Learn](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/entity-metadata) -- Logical name, schema name, entity set name distinctions
- [Dataverse naming conventions - Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-365/community/cds-and-model-driven-apps-standards-and-naming-conventions) -- Naming standards
- [Troubleshoot Dataverse known issues - Microsoft Learn](https://learn.microsoft.com/en-us/power-automate/dataverse/known-issues) -- Known issues with Dataverse connector
- [Known Issues in M365 Copilot Extensibility - Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-365-copilot/extensibility/known-issues) -- oneOf/anyOf/allOf not supported

### GitHub / Package Sources (HIGH confidence)
- [Fluent UI Badge.types.ts - GitHub](https://github.com/microsoft/fluentui/blob/master/packages/react-components/react-badge/library/src/components/Badge/Badge.types.ts) -- Badge size type definition
- [Wrong version of FluentUI - Issue #1265](https://github.com/microsoft/powerplatform-build-tools/issues/1265) -- PAC CLI version mismatch bug

### Community / Blog Sources (MEDIUM confidence)
- [UpdateView optimization in Virtual PCF - Dianamics PCF Lady](https://dianabirkelbach.wordpress.com/2022/05/06/updateview-in-virtual-pcf-components-and-how-to-optimize-rendering/) -- Rendering optimization patterns
- [Virtual PCFs with Fluent UI 9 after GA](https://dianabirkelbach.wordpress.com/2024/12/06/virtual-pcfs-with-fluent-ui-9-after-ga/) -- Post-GA platform library guidance
- [Handling Choice columns dynamically - Amey Holden](https://www.ameyholden.com/articles/dataverse-choice-power-automate-dynamic-no-switch) -- Choice column mapping patterns
- [Dataverse Tips and Gotchas - Compass 365](https://compass365.com/microsoft-dataverse-tips-and-gotchas/) -- Common Dataverse mistakes
- [How naming works in Power Platform - Jukka Niiranen](https://jukkaniiranen.com/2020/11/how-naming-works-in-the-power-platform-universe/) -- Naming convention deep dive
