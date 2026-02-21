# Feature Landscape

**Domain:** Power Platform reference pattern (PCF control + Copilot Studio agent + Power Automate flows + deployment automation)
**Researched:** 2026-02-20
**Context:** Remediation pass on an existing Enterprise Work Assistant solution -- assessing what "production-ready" and "complete" means for each component type in a reference pattern that others will clone and follow.

---

## Table Stakes

Features users (developers cloning this pattern) expect. Missing = the reference pattern is incomplete or untrustworthy.

### PCF Control (React Virtual Component)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Compiles without errors under strict TypeScript** | A reference pattern that does not compile is worse than no pattern at all. `strict: true` is already set in tsconfig; all code must pass. | Low | Current solution has known type issues (Badge size prop, color token names) that must be fixed. |
| **Correct ControlManifest.Input.xml** | Manifest is the contract between the PCF runtime and the component. Input/output properties must match the code exactly. | Low | Current manifest looks correct; verify resx keys match. |
| **Proper PCF lifecycle implementation** | `init`, `updateView`, `getOutputs`, `destroy` must follow documented patterns. Stable callback references (no re-creation on each render), correct dataset version tracking. | Med | Current implementation uses good patterns (stable callbacks in `init`, version counter for dataset). Verify `destroy` cleanup is sufficient. |
| **Correct Fluent UI v9 usage** | Virtual controls share platform React/Fluent. Using wrong APIs, deprecated props, or invalid token names will crash or render incorrectly. | Med | Known issues: Badge `size` prop may not accept all values in v9; some `colorPalette*` token names need verification against current Fluent v9 API. |
| **XSS prevention in rendered URLs** | Reference patterns that render user-controlled URLs without sanitization teach bad practices. Source URLs from agent output must be validated before rendering as `href`. | Med | Current CardDetail.tsx has a regex check (`/^https?:\/\//`) -- verify this is sufficient and applied consistently. Non-HTTP URLs fall back to `#`. |
| **Graceful handling of malformed data** | PCF controls receive data from Dataverse (user-generated content via AI agent). Parsing failures must not crash the entire gallery. | Low | `useCardData` already wraps parsing in try/catch and skips bad rows with a console.warn. This is correct. |
| **Dataset-bound filtering and sorting** | The control must respect filter inputs from the Canvas app host and display filtered results correctly. | Low | Current implementation filters in-memory via `applyFilters()`. This is correct for the pattern since server-side filtering happens at the Canvas app `Filter()` level. |
| **Output property signaling** | Actions (select card, edit draft, dismiss) must fire output properties back to the Canvas app host correctly. Output reset after read to prevent stale re-fires. | Low | Current implementation resets action outputs in `getOutputs()`. This is the correct pattern. |
| **Dark mode / theme support** | Virtual controls inherit the platform theme. A reference should demonstrate theme-aware rendering. | Low | Current App.tsx detects `prefers-color-scheme: dark` via matchMedia and switches between `webLightTheme` / `webDarkTheme`. Correct pattern. |
| **Localization resource file (resx)** | PCF controls must have a resx file for all display-name and description keys referenced in the manifest. | Low | Current resx file covers all keys. Verify no keys are missing. |
| **CSS using Fluent design tokens** | Styles should use Fluent CSS custom properties (e.g., `var(--colorNeutralStroke2)`) rather than hardcoded colors, ensuring theme compatibility. | Low | Current CSS correctly uses Fluent CSS variables. |

### Copilot Studio Agent Prompts

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Internally consistent output schema** | The JSON schema, system prompt examples, TypeScript types, Dataverse table definition, and Power Automate Parse JSON schema must all agree on field names, types, and nullability. | High | This is the #1 known issue. Multiple inconsistencies identified in prior audit (confidence_score type, item_summary null constraints, draft_type field presence, draft_payload null vs "N/A"). |
| **Valid JSON schema (draft-07)** | The output-schema.json must be valid JSON Schema and parseable by standard tools. | Low | Current schema is valid draft-07. The `oneOf` for draft_payload is correct JSON Schema but incompatible with Power Automate Parse JSON -- this is already documented. |
| **Simplified schema for Power Automate** | Power Automate Parse JSON does not support `oneOf`/`anyOf`. A separate simplified schema must be provided and documented. | Low | Already provided in agent-flows.md. Verify it matches the canonical schema for all non-oneOf fields. |
| **Few-shot examples that match the schema exactly** | Every example in the system prompt must validate against the output schema. Field names, value types, enum values, and null/non-null patterns must be consistent. | Med | Verify all four examples in the prompt. Known concern: SKIP example has `item_summary: null` but Dataverse marks `cr_itemsummary` as required (resolved by not writing SKIP items to Dataverse, but the schema allows null). |
| **Clear triage decision boundaries** | The SKIP/LIGHT/FULL classification rules must be unambiguous, with an explicit ambiguity-resolution rule. | Low | Current prompt has clear rules with "default to LIGHT" as ambiguity resolver. Complete. |
| **Security constraints in prompt** | Delegated identity, no fabrication, PII handling, no cross-user access -- these are table stakes for any enterprise agent pattern. | Low | Current prompt has a dedicated IDENTITY & SECURITY CONSTRAINTS section. Complete. |
| **Research tool registration guidance** | The prompt references MCP tools for 5-tier research. The docs must explain which Copilot Studio actions map to which research tiers and how to register them. | Med | agent-flows.md and deployment-guide.md cover this. Verify action names match prompt references. |
| **Humanizer agent prompt with clear input/output contract** | The downstream Humanizer must have an explicit input schema, tone rules, and format rules that match the draft_payload structure from the main agent. | Low | Current humanizer prompt is well-structured. Verify `draft_payload` fields match. |

### Power Automate Flows (Documentation)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Step-by-step build guide for all three flows** | This is a reference pattern, not a runnable app. The docs ARE the deliverable for flows. Each flow needs trigger config, actions, expressions, and field mappings. | High | agent-flows.md covers EMAIL, TEAMS_MESSAGE, and CALENDAR_SCAN flows with step-by-step detail. This is the strongest part of the current solution. |
| **Choice value mapping table** | Dataverse Choice columns require integer values. The mapping from agent string output to integer value must be documented completely and consistently across all files. | Med | Mapping table exists in agent-flows.md. Verify values match dataverse-table.json and provision-environment.ps1. |
| **Row Ownership documentation** | Without explicit Owner field setting, RLS is broken. This is the most common gotcha in Power Automate + Dataverse patterns. | Med | Documented in agent-flows.md with the exact expression. This is correct and well-placed. |
| **Error handling pattern** | Production flows must have try/catch (Scope-based) error handling with logging/notification. | Med | agent-flows.md documents the Scope-based pattern with error handling flow. Microsoft Learn confirms this as the official recommended pattern. |
| **Pre-filter expressions for each trigger** | Calling a Copilot Studio agent for every single email/message is expensive (consumes AI capacity). Pre-filters reduce unnecessary invocations. | Med | All three flows have pre-filter conditions documented with complete expressions. |
| **Parse JSON schema (simplified)** | Must be provided ready to paste, matching the agent output but without unsupported `oneOf`/`anyOf`. | Low | Provided in agent-flows.md. |
| **Humanizer handoff condition** | The condition for when to invoke the Humanizer (FULL tier + confidence >= 40 + not CALENDAR_SCAN) must be documented with the exact expression. | Low | Documented in agent-flows.md step 8 with the nested `and()` pattern for compatibility. |

### Deployment Scripts (PowerShell)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Prerequisite validation** | Scripts should check for required tools (PAC CLI, Node.js, Azure CLI) before attempting operations. | Low | deploy-solution.ps1 validates Node.js, PAC CLI, and PAC auth. provision-environment.ps1 relies on PAC CLI implicitly. |
| **Parameterized with sensible defaults** | Scripts must not hardcode tenant IDs, environment names, or publisher prefixes. All configurable values should be parameters with documented defaults. | Low | All three scripts use `param()` blocks with defaults. `PublisherPrefix` defaults to "cr". |
| **Idempotent where possible** | Running a script twice should not fail or corrupt state. Table/role creation should handle "already exists" gracefully. | Med | provision-environment.ps1 and create-security-roles.ps1 wrap creation calls in try/catch with "may already exist" warnings. deploy-solution.ps1 removes old zip before repacking. |
| **Clear error messages with remediation steps** | PowerShell `throw` messages should tell the user what went wrong AND what to do about it. | Low | deploy-solution.ps1 has good error messages ("PAC CLI is not installed. Install via: ..."). Other scripts are similar. |
| **Manual step documentation** | Steps that cannot be automated (enable PCF for Canvas apps, create connections) must be clearly documented with exact UI paths. | Low | provision-environment.ps1 prints manual steps. deployment-guide.md covers these. Verify UI paths are current. |
| **Consistent publisher prefix usage** | All scripts must use the same prefix parameter, and it must match the schemas and docs. | Med | Known issue: create-security-roles.ps1 had a hardcoded prefix in some places. Must verify all scripts use `$PublisherPrefix` consistently. |

### Schemas and Data Contracts

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Single source of truth for output schema** | output-schema.json is the canonical contract. All other files (prompt, types.ts, simplified schema, docs) must derive from it. | High | This is the core consistency requirement. Currently has known inconsistencies. |
| **Dataverse table definition matching the schema** | dataverse-table.json column types, required flags, and option values must be consistent with output-schema.json. | Med | Mostly consistent. Verify `cr_itemsummary` required=true aligns with the SKIP behavior (SKIP items not written to Dataverse). |
| **TypeScript types matching the schema** | types.ts interfaces must have the same field names, types, and nullability as output-schema.json. | Med | Known inconsistencies to verify: `confidence_score` type (number vs integer), `draft_payload` union type. |
| **Table naming consistency** | The table logical name, entity set name, and all references must be consistent (singular `cr_assistantcard` vs plural `cr_assistantcards`). | Low | Known issue flagged in PROJECT.md. Both are valid (singular for logical name, plural for entity set) but references across files must be consistent about which to use where. |

### Documentation

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **End-to-end deployment guide** | A reference pattern must be deployable by following a single guide from zero to working solution. | Med | deployment-guide.md covers 7 phases with a verification checklist. This is solid. |
| **Canvas app setup guide** | The Canvas app is not code -- it must be configured manually. Step-by-step with exact Power Fx formulas. | Med | canvas-app-setup.md is comprehensive with formulas, property bindings, and testing checklist. |
| **Architecture README** | The top-level README must explain what the pattern does, its components, and how they fit together. | Low | README.md and enterprise-work-assistant/README.md exist. Verify they accurately describe the current architecture. |
| **Verification checklist** | After deployment, users need a way to confirm everything works. A checklist with specific things to test. | Low | deployment-guide.md has a verification checklist at the bottom. |

---

## Differentiators

Features that set this reference pattern apart from typical samples. Not expected, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Unit tests for React components** | Most PCF samples have zero tests. Including Jest tests for components and hooks demonstrates testing practices and proves correctness. | High | No tests exist currently. PROJECT.md lists this as an active requirement. Need Jest + React Testing Library setup compatible with the PCF build pipeline. |
| **Prompt evaluation test cases** | Copilot Studio now supports prompt evaluations (test sets). Including sample test cases that validate schema compliance for each triage tier would be exceptional. | High | Not in current solution. Copilot Studio guidance hub documents this capability. Would require manual configuration in Copilot Studio but documenting the approach adds value. |
| **Accessibility (keyboard navigation, ARIA)** | Most PCF samples ignore accessibility. Demonstrating keyboard navigation, focus management, and ARIA attributes in a reference pattern sets a high bar. | Med | Current components use Fluent UI v9 which has built-in accessibility for standard components (Button, Card, Badge). Custom navigation (gallery -> detail -> back) needs keyboard support verification. |
| **Solution environment variable support** | Using environment variables instead of hardcoded values in deployment scripts enables proper ALM (dev/test/prod promotion). | Med | Current scripts use parameters but do not generate solution-aware environment variables or connection references. Documenting this as a "production readiness" enhancement adds value. |
| **Error logging Dataverse table** | Documenting a pattern for an error logging table where failed flow runs write diagnostic information, rather than just email notifications. | Med | agent-flows.md mentions error scopes but does not detail the logging table pattern. |
| **Managed vs Unmanaged solution guidance** | Explaining when to use managed vs unmanaged solutions and how to switch between them for ALM. | Low | deployment-guide.md mentions changing SolutionPackageType but does not elaborate on the ALM implications. |
| **DLP policy documentation with specific connector groups** | The deployment guide lists required connector combinations but does not provide step-by-step DLP configuration. | Low | Partially covered in deployment-guide.md Phase 7. |
| **Performance budget documentation** | Documenting expected message consumption, AI capacity usage, and Dataverse storage per user per day helps with capacity planning. | Med | Not in current solution. The Copilot Studio guidance hub emphasizes capacity planning for production. |

---

## Anti-Features

Features to explicitly NOT build in this remediation pass.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **New functional capabilities** | This is a fix-only pass. Adding features introduces new untested surface area and scope creep. The existing feature set (triage, research, draft, humanize, display) is comprehensive. | Fix what exists. Ensure every existing feature works correctly and consistently. |
| **Automated email/Teams sending** | Explicitly marked as Phase 2 in the agent prompt. Including this would violate the "prepare but never send" safety model. | Document as a future capability in the README but do not implement. |
| **Per-user tone profile learning** | Marked as Phase 2. Requires historical data analysis and changes the agent architecture. | Keep the static tone rules in the Humanizer prompt. |
| **Cross-user or manager-level views** | Breaks the single-user security model. Requires a fundamentally different RLS strategy. | Maintain ownership-based RLS where each user sees only their own cards. |
| **Direct Graph API calls in the PCF control** | PCF virtual controls should not make API calls directly. Data flows through Dataverse, which is the correct pattern. | Continue using the dataset-bound approach where the Canvas app queries Dataverse and passes data to the PCF control. |
| **Custom connector for MCP tools** | Building a custom connector is a separate, complex project. The reference pattern should document which built-in connectors to use and mention custom connectors as an advanced option. | Keep the current approach: document connector-based actions and mention MCP plugins as an alternative. |
| **CI/CD pipeline definitions** | Azure DevOps or GitHub Actions pipeline YAML is environment-specific and adds maintenance burden to a reference pattern. | Document the ALM approach and commands; let users create their own pipelines. |
| **Solution packaging automation** | Creating a fully automated packaging pipeline that generates managed solutions is beyond remediation scope. | Keep the existing deploy-solution.ps1 which builds and imports. Document the managed solution switch. |
| **Interactive PowerShell scripts** | Scripts that prompt for input (`Read-Host`) are harder to automate and test. | Keep the current parameter-based approach where all inputs are script parameters. |
| **Runtime PCF test harness** | Building a standalone test harness that simulates the PCF runtime is a significant project. | Use Jest for unit testing components in isolation. Document how to use `pcf-scripts start` for the built-in test harness. |

---

## Feature Dependencies

```
Output Schema (output-schema.json) is the root dependency:
  output-schema.json --> types.ts (TypeScript types must match)
  output-schema.json --> main-agent-system-prompt.md (examples must validate against schema)
  output-schema.json --> dataverse-table.json (column types/options must align)
  output-schema.json --> agent-flows.md simplified schema (must match non-oneOf fields)
  output-schema.json --> humanizer-agent-prompt.md (draft_payload contract must match)

Dataverse table is the integration point:
  dataverse-table.json --> provision-environment.ps1 (script creates exactly these columns)
  dataverse-table.json --> create-security-roles.ps1 (references table logical name)
  dataverse-table.json --> agent-flows.md Choice mapping (integer values must match)
  dataverse-table.json --> useCardData.ts (column names used in getValue() calls)
  dataverse-table.json --> canvas-app-setup.md (Power Fx references column names)

PCF control depends on types and schema:
  types.ts --> all React components (CardDetail, CardItem, CardGallery, FilterBar, App)
  types.ts --> useCardData.ts (hook returns AssistantCard[])
  ControlManifest.Input.xml --> index.ts (property names must match)
  ControlManifest.Input.xml --> resx file (all display-name-key values must have entries)

Deployment is sequential:
  provision-environment.ps1 --> create-security-roles.ps1 (needs environment + table)
  provision-environment.ps1 --> deploy-solution.ps1 (needs environment ID)
  deploy-solution.ps1 --> Canvas app setup (needs PCF component imported)
  Agent setup --> Flow creation (flows invoke the published agent)

Unit tests depend on the component code:
  types.ts + components --> test files (tests import from the same modules)
```

---

## Remediation Priority (MVP for "production-ready reference pattern")

**Priority 1 -- Schema/Contract Consistency (blocks everything else):**
1. Fix all output-schema.json inconsistencies
2. Align types.ts with the corrected schema
3. Align system prompt examples with the corrected schema
4. Align dataverse-table.json with the corrected schema
5. Align simplified Parse JSON schema in agent-flows.md
6. Resolve table naming consistency (singular vs plural)

**Priority 2 -- Code Correctness:**
1. Fix Fluent UI v9 API issues (Badge size, color tokens)
2. Fix XSS concerns in CardDetail URL rendering
3. Fix deploy-solution.ps1 polling logic (if still broken)
4. Fix create-security-roles.ps1 hardcoded prefix
5. Verify all PowerShell scripts work with parameterized prefix

**Priority 3 -- Documentation Accuracy:**
1. Correct JSON output mode UI path in deployment-guide.md
2. Add missing Power Automate expression examples
3. Verify all file cross-references are accurate
4. Update READMEs to reflect current state

**Priority 4 -- Testing (Differentiator):**
1. Set up Jest + React Testing Library in the PCF project
2. Write unit tests for useCardData hook (most critical -- data transformation logic)
3. Write unit tests for applyFilters function in App.tsx
4. Write rendering tests for CardItem, CardDetail, CardGallery
5. Write tests for PCF lifecycle (index.ts getOutputs reset behavior)

**Defer:**
- Prompt evaluation test cases: Document the approach but do not build test sets
- Accessibility audit: Verify Fluent UI v9 provides baseline; document keyboard nav expectations
- Performance budget: Document estimated capacity consumption
- ALM guidance: Mention managed solutions and environment variables as next steps

---

## Sources

- [Microsoft Learn: Power Apps Component Framework overview](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/overview) -- MEDIUM confidence (official docs, verified)
- [Microsoft Learn: React controls & platform libraries](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/react-controls-platform-libraries) -- HIGH confidence (official docs)
- [Microsoft Learn: Copilot Studio guidance documentation](https://learn.microsoft.com/en-us/microsoft-copilot-studio/guidance/) -- HIGH confidence (official docs, updated 2026-02-10)
- [Microsoft Learn: JSON output in Copilot Studio](https://learn.microsoft.com/en-us/microsoft-copilot-studio/process-responses-json-output) -- HIGH confidence (official docs, updated 2025-11-07)
- [Microsoft Learn: Design your Copilot Studio production environment strategy](https://learn.microsoft.com/en-us/microsoft-copilot-studio/guidance/project-design-production-environment-strategy) -- HIGH confidence (official docs)
- [Microsoft Learn: Power Automate error handling guidance](https://learn.microsoft.com/en-us/power-automate/guidance/coding-guidelines/error-handling) -- HIGH confidence (official docs, updated 2025-08-27)
- [Microsoft Learn: PAC CLI solution commands](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/solution) -- HIGH confidence (official docs)
- [Microsoft Learn: Dataverse table definitions](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/entity-metadata) -- HIGH confidence (official docs)
- [Microsoft Copilot Blog: Guidance hubs for enterprise-ready agents](https://www.microsoft.com/en-us/microsoft-copilot/blog/copilot-studio/new-resources-and-guidance-to-plan-build-and-operate-enterprise-ready-agents/) -- MEDIUM confidence (official blog)
- [Matthew Devaney: Power Automate Coding Standards](https://www.matthewdevaney.com/power-automate-coding-standards-for-cloud-flows/) -- LOW confidence (community, but widely referenced)
- [GitHub: scottdurow/pcf-react](https://github.com/scottdurow/pcf-react) -- LOW confidence (community pattern for PCF testing with Jest)
- Project codebase analysis: all 28 files reviewed directly -- HIGH confidence (primary source)
