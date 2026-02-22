# Project Research Summary

**Project:** Enterprise Work Assistant -- Production Readiness Remediation
**Domain:** Power Platform reference pattern (PCF React virtual control + Copilot Studio agents + Power Automate flows + Dataverse)
**Researched:** 2026-02-20
**Confidence:** HIGH

## Executive Summary

This project is a remediation pass on an existing Enterprise Work Assistant Power Platform solution that serves as a reference pattern for others to clone. The solution connects three signal sources (Outlook, Teams, Calendar) to a two-stage Copilot Studio agent pipeline (Main Agent for triage/research/drafting + Humanizer Agent for tone calibration), writes structured output to Dataverse, and displays results in a React-based PCF virtual control embedded in a Canvas App. The core problem is not missing features -- the feature set (triage, research, draft, humanize, display) is comprehensive -- but rather internal inconsistencies that would prevent the solution from deploying or running correctly: mismatched schemas, incorrect platform library version declarations, and code issues that fail TypeScript strict mode.

The recommended approach is a contract-first remediation: fix the output schema and its downstream consumers (types.ts, system prompt, dataverse-table.json, Power Automate simplified schema) before touching any code or documentation. Every other component in the solution derives from the schema contract, so schema drift is the root cause behind the majority of known issues. Code fixes (Fluent UI API correctness, PCF lifecycle patterns, security hardening) come second, followed by documentation accuracy, and finally the one differentiator not yet present: unit tests for PCF components.

The primary deployment risk is the Fluent UI v9 platform library version ceiling. The Power Platform runtime only supports Fluent v9 versions up to 9.46.2, but the PAC CLI scaffolding template and semver ranges can pull newer unsupported versions, causing solution import to fail entirely with a cryptic version error. This must be pinned exactly before any build or deploy attempt. The secondary risk is the oneOf/anyOf incompatibility between the canonical JSON schema and Power Automate's Parse JSON action -- the simplified schema for flows must be maintained as a separate artifact. Both risks are already known and partially mitigated in the project; the remediation pass must make those mitigations explicit and verified.

---

## Key Findings

### Recommended Stack

The PCF control is a React virtual control using the platform-managed React 16.14.0 and Fluent UI v9 instances. Almost all current package choices are correct: @fluentui/react-components at ^9.46.0, @types/react at ~16.14.0, pcf-scripts at ^1 (resolving to 1.51.1), and eslint at ^8.50.0. The one actionable upgrade is TypeScript from ^4.9.5 to ^5.5.0 (pcf-scripts 1.51.x is confirmed compatible). Node.js must be >= 20 for pcf-scripts 1.51.x. The critical manifest fix is changing the Fluent platform library declaration from `version="9.0"` to `version="9.46.2"` -- the documented allowed range is >=9.4.0 <=9.46.2.

The Copilot Studio layer uses GPT-4.1 as the default model (GA since Oct 2025) with JSON output mode configured in Prompt Builder. Power Automate uses the "Run a flow from Copilot" trigger pattern for agent-to-flow integration. Dataverse uses standard Choice column patterns with integer values starting at 100000000. PAC CLI 2.2.1 is the current release for build and deployment tooling.

**Core technologies:**
- React 16.14.0 (platform-provided): UI rendering in PCF virtual control -- cannot override; must code to this API surface
- @fluentui/react-components ^9.46.0 (pinned, not semver): Fluent v9 component library -- platform ceiling is 9.46.2, pin exactly
- pcf-scripts ^1 (1.51.1): Build tooling -- correct as-is; Node >= 20 required
- TypeScript ^5.5.0 (upgrade from 4.9.5): Type checking -- compatible with pcf-scripts 1.51.x, enables `satisfies` operator
- Copilot Studio (SaaS, GPT-4.1 default): Agent orchestration -- JSON output mode via Prompt Builder, not agent settings
- Power Automate Cloud Flows: Workflow orchestration -- simplified schema required (no oneOf/anyOf)
- Dataverse: Persistent storage -- dual-storage pattern (full JSON blob + discrete Choice columns for filtering)
- Jest ^29 + @testing-library/react ^14: Unit testing -- not yet set up; must use v14.x for React 16 compatibility
- PAC CLI 2.2.1: Build and deploy tooling -- .NET Tool install recommended for cross-platform use

### Expected Features

The feature landscape for this remediation pass is clearly bounded: fix what exists, do not add new capabilities. The solution already implements a complete feature set. "Production-ready reference pattern" requires that every existing feature is internally consistent, correctly coded, and well-documented.

**Must have (table stakes):**
- Clean TypeScript compilation under strict mode -- reference pattern that fails to compile is worse than none
- Correct ControlManifest.Input.xml (Fluent version 9.46.2, all property/resx keys verified)
- Schema consistency across all five artifacts: output-schema.json, types.ts, system prompt examples, dataverse-table.json, Power Automate simplified schema
- Correct Fluent UI v9 API usage (Badge size/color props, token import paths standardized to @fluentui/react-components)
- XSS prevention via explicit URL scheme allowlist (replace single regex with named scheme allowlist)
- Row ownership explicitly set in all Dataverse write actions (Owner = triggering user's AAD Object ID)
- SKIP items never written to Dataverse (primary column null constraint enforcement)
- Table naming consistency (singular `cr_assistantcard` for logical name; plural `cr_assistantcards` for entity set name -- used in the right contexts)
- Parameterized PowerShell scripts with no hardcoded publisher prefixes
- End-to-end deployment guide that can be followed from zero to working solution

**Should have (differentiators):**
- Unit tests for React components (Jest + @testing-library/react ^14) -- most PCF samples have zero tests
- Accessibility baseline verification (Fluent v9 provides built-in a11y for standard components; custom navigation needs keyboard support check)
- Performance optimization for useCardData hook (dataset change detection before triggering useMemo recompute)

**Defer (v2+):**
- Automated email/Teams sending (explicitly Phase 2 in current design; violates "prepare but never send" safety model)
- Per-user tone profile learning (requires historical data analysis, architectural change)
- CI/CD pipeline definitions (environment-specific, adds maintenance burden to reference pattern)
- Prompt evaluation test cases in Copilot Studio (document the approach; do not build test sets in this pass)
- Performance budget documentation (capacity planning numbers)
- ALM guidance for managed vs. unmanaged solutions (mention as next steps, do not elaborate)

### Architecture Approach

The solution implements a five-layer architecture with unidirectional data flow. Writes flow from signal sources through Power Automate flows to the Copilot Studio agent to Dataverse. Reads flow from Dataverse through the Canvas App dataset binding to the PCF virtual control to the React component tree. The only bidirectional path is the Canvas App writing back to Dataverse for user actions (dismiss, status updates). Each layer has a single responsibility enforced by strict boundary rules: flows own all connector orchestration, agents own all LLM reasoning and never write to Dataverse, the PCF control is a pure rendering engine that never calls Dataverse directly.

**Major components:**
1. Power Automate Flows (x3: EMAIL, TEAMS_MESSAGE, CALENDAR_SCAN) -- signal interception, pre-filtering, agent invocation, Dataverse writes
2. Main Agent (Copilot Studio) -- triage classification, 5-tier research, confidence scoring, JSON draft generation
3. Humanizer Agent (Copilot Studio) -- tone calibration; receives structured draft_payload, returns plain text
4. Dataverse Table (cr_assistantcard) -- dual-storage: full JSON blob in cr_fulljson + discrete Choice columns for server-side filtering
5. Canvas App -- filter UI, dataset binding, event routing; delegates all rendering to the PCF control
6. PCF Virtual Control (React) -- card gallery and detail rendering, user interaction capture via output properties

**Key patterns:**
- Stable callback references created once in PCF `init()`, never recreated in `updateView()` -- prevents all-children re-renders
- Dataset version counter in PCF class incremented in `updateView()` to force useMemo recomputation (since dataset object is mutated in place)
- Dual-storage Dataverse schema: avoids brittle normalized tables for complex nested JSON while preserving server-side filterability on key dimensions
- Simplified Power Automate Parse JSON schema using `{}` for polymorphic fields instead of `oneOf` (which PA does not support)
- SKIP items never written to Dataverse to satisfy primary column NOT NULL constraint

### Critical Pitfalls

1. **Fluent UI v9 version ceiling (9.46.2 hard limit)** -- Pin @fluentui/react-components to exactly 9.46.2 in package.json (not `^9.46.0`). Update ControlManifest.Input.xml to declare `version="9.46.2"`. Verify package-lock.json after npm install. Violation causes solution import to fail with an opaque platform library version error.

2. **Power Automate Parse JSON does not support oneOf/anyOf/allOf** -- Maintain the simplified schema (already in agent-flows.md) as the authoritative schema for all Power Automate flows. Never paste the canonical output-schema.json directly into a Parse JSON action. Use `{}` for draft_payload and verified_sources. Violation causes every flow run to fail silently.

3. **Output schema contract inconsistencies cascade into all downstream artifacts** -- Fix output-schema.json first, then align types.ts, system prompt examples, dataverse-table.json, and simplified PA schema in that order. Field name mismatches (e.g., `confidence_score` as number vs. integer), nullability disagreements, and enum case mismatches (e.g., "High" vs. "HIGH") all cause runtime Parse JSON failures or PCF type assertion errors.

4. **Row ownership for row-level security must be set explicitly** -- Power Automate flows run under the connection owner's identity. Every "Add a new row" Dataverse action must set the Owner field to the triggering user's AAD Object ID via `outputs('Get_my_profile_(V2)')?['body/id']`. Without this, all records are owned by the service account and RLS is broken.

5. **SKIP items must never be written to Dataverse** -- The cr_itemsummary column is the primary name attribute and cannot be null. SKIP-tier items produce null item_summary. The flow's `triage_tier != 'SKIP'` condition gate must never be removed. This is an invariant, not an optimization.

---

## Implications for Roadmap

Based on research, the dependency chain is unambiguous: schema consistency is the root; code correctness and documentation accuracy are downstream; testing is independent but requires correct code. The remediation pass has four natural phases.

### Phase 1: Schema and Contract Consistency

**Rationale:** The output-schema.json is the root dependency for all other artifacts in the solution. Five separate files (types.ts, system prompt, dataverse-table.json, agent-flows.md simplified schema, humanizer prompt) must agree on field names, types, nullability, and enum values. Any inconsistency here causes runtime failures in the flow pipeline. This must be fixed before code can be verified as correct, because the code type-checks against types.ts which depends on the schema.

**Delivers:** A single agreed-upon contract for all agent output fields. All five downstream artifacts aligned. Choice column integer mapping verified against dataverse-table.json as single source of truth.

**Addresses:** Schema/contract consistency table stakes from FEATURES.md (Priority 1 items: output-schema.json fixes, types.ts alignment, system prompt example alignment, dataverse-table.json alignment, simplified PA schema alignment, table naming resolution).

**Avoids:** Pitfalls 3 (oneOf in PA), 4 (primary column null constraint), 5 (table naming confusion), 9 (Choice column drift), 12 (JSON output mode schema enforcement).

### Phase 2: PCF Component Fixes

**Rationale:** With the schema and TypeScript types correct, the PCF component code can be audited against the actual API contracts. This phase is ordered after Phase 1 because fixing type errors before the types are correct would require rework.

**Delivers:** A PCF virtual control that compiles under strict TypeScript, uses correct Fluent UI v9 APIs, implements the stable callback pattern, handles XSS with an explicit URL scheme allowlist, and has standardized token import paths. TypeScript upgraded to ^5.5.0. ControlManifest.Input.xml updated to declare Fluent version 9.46.2.

**Addresses:** All PCF code correctness table stakes from FEATURES.md (Priority 2 items: Fluent UI API issues, XSS hardening, Badge size/color token audit, useMemo optimization, controlled textarea pattern).

**Avoids:** Pitfalls 1 (Fluent version ceiling), 2 (React version mismatch), 6 (useMemo unconditional recompute), 7 (Badge size prop values), 8 (token import path inconsistency), 10 (XSS URL rendering), 14 (datasetVersion on every updateView), 15 (controlled textarea warning).

### Phase 3: Documentation and Deployment Script Fixes

**Rationale:** Documentation accuracy and script correctness depend on the schema and code being finalized. Documenting wrong UI paths or incorrect expressions before the underlying solution is fixed creates rework. Deployment scripts must be verified against the correct schema and table names established in Phase 1.

**Delivers:** Deployment scripts with no hardcoded publisher prefixes, dual auth prerequisite validation (PAC CLI + Azure CLI), idempotent provisioning, accurate deployment guide with current Copilot Studio JSON output mode UI paths, verified canvas-app-setup.md Power Fx formulas, and updated READMEs.

**Addresses:** Documentation table stakes and deployment script table stakes from FEATURES.md (Priority 3 items: JSON output mode UI path, missing PA expressions, cross-reference accuracy, README updates; Priority 2 items: deploy-solution.ps1 polling, create-security-roles.ps1 hardcoded prefix).

**Avoids:** Pitfalls 5 (table naming in docs), 11 (row ownership in flow docs), 13 (dual auth requirement), 16 (privilege name case sensitivity).

### Phase 4: Unit Testing

**Rationale:** Testing requires stable, correct component code and types. This phase is independent of documentation but depends on Phases 1 and 2. It is the one differentiator that elevates this from a typical sample to a production reference pattern. Most PCF samples have zero tests; this is an opportunity to set a high bar.

**Delivers:** Jest + @testing-library/react ^14 configured in the PCF project. Unit tests for: useCardData hook (data transformation + error handling), applyFilters function, CardItem and CardDetail rendering, PCF lifecycle output reset behavior (getOutputs). Test configuration that coexists with pcf-scripts build pipeline.

**Addresses:** Testing differentiator from FEATURES.md (Priority 4 items). Uses Jest ^29, ts-jest ^29, @testing-library/react ^14 (v14 required for React 16 compatibility), jest-environment-jsdom.

**Avoids:** Pitfall 2 (React version mismatch) -- tests must mock the PCF ComponentFramework namespace, not rely on the test harness as a proxy for production behavior.

### Phase Ordering Rationale

- Schema first because all five downstream artifacts derive from it; fixing code against wrong types creates rework
- Code second because types must be correct before type errors can be meaningfully resolved
- Documentation third because docs should reflect the finalized schema, code, and scripts
- Testing last because tests import from component code that must be stable; also lowest urgency for reference pattern correctness (but highest for differentiation)
- This order mirrors the "contract alignment order" identified in ARCHITECTURE.md's build order implications section

### Research Flags

Phases with standard, well-documented patterns (skip deeper research):

- **Phase 1 (Schema Consistency):** The specific inconsistencies are already identified in the project audit. This is mechanical alignment work, not exploration. No additional research needed.
- **Phase 2 (PCF Component Fixes):** All Fluent UI v9 APIs are verified from source (GitHub). PCF virtual control lifecycle is confirmed from official docs. No additional research needed.
- **Phase 3 (Deployment Scripts):** PAC CLI commands and PowerShell patterns are standard. No additional research needed.

Phases that may benefit from targeted research during planning:

- **Phase 4 (Unit Testing):** The integration of Jest with pcf-scripts webpack configuration has community-reported friction. The exact jest.config.js setup for PCF virtual controls (mocking ComponentFramework, handling Fluent UI module transforms) is not in official documentation and requires community pattern validation. Recommend a brief targeted research pass on Jest configuration for PCF before writing test files.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All version constraints verified against official Microsoft Learn docs (updated 2025-10-10) and npm package registries. The Fluent v9 9.46.2 ceiling is confirmed from both official docs and GitHub issue #1265. |
| Features | HIGH | Feature scope is bounded by the existing codebase. Priorities are derived from direct code analysis plus official guidance on what constitutes a production-ready PCF reference pattern. |
| Architecture | HIGH | All architectural patterns verified from official PCF and Copilot Studio documentation. The dual-storage Dataverse pattern and two-agent pipeline are sound design choices with clear rationale. |
| Pitfalls | HIGH | All critical pitfalls are confirmed from official sources or directly observable in the codebase. Moderate pitfalls are either confirmed (HIGH) or community-corroborated (MEDIUM). |

**Overall confidence:** HIGH

### Gaps to Address

- **Jest/PCF configuration specifics:** No official documentation covers the exact jest.config.ts setup for PCF virtual controls with Fluent UI v9. Community patterns exist but vary. Validate the specific transform configuration (especially handling `@fluentui/*` ESM modules in Jest's CommonJS environment) during Phase 4 planning before writing tests.

- **Fluent UI v9 @fluentui/react-icons semver risk:** The `^2.0.245` range is noted as potentially including breaking changes in patch releases (per STACK.md). If icons behave unexpectedly after npm install, pin to the specific tested version rather than accepting whatever the range resolves to.

- **Canvas App delegation limit at scale:** The current filter approach uses Choice column filters in Canvas App which are not delegable. At >500 cards per user, the 500-record delegation limit could silently truncate results. Acceptable for a reference pattern; should be flagged as a known limitation in the README rather than fixed in this pass.

- **updatedProperties reliability in Canvas Apps:** The optimization of only incrementing datasetVersion when `context.updatedProperties.includes("dataset")` is confirmed for Model-driven apps but unreliable in Canvas Apps per community reports. If the conditional increment causes cards to stop updating, fall back to unconditional increment. This is a "try and verify" situation.

---

## Sources

### Primary (HIGH confidence)
- [React controls & platform libraries - Microsoft Learn](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/react-controls-platform-libraries) -- Updated 2025-10-10. PCF virtual control React/Fluent versions, manifest format, platform library ceiling
- [JSON output - Microsoft Copilot Studio - Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-copilot-studio/process-responses-json-output) -- Updated 2025-11-07. JSON output mode configuration, limitations, FAQ
- [Table definitions in Microsoft Dataverse - Microsoft Learn](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/entity-metadata) -- Updated 2026-02-11. Logical name, schema name, entity set name conventions
- [Best practices for code components - Microsoft Learn](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/code-components-best-practices) -- Updated 2025-05-07. Stable callbacks, no localStorage, production builds
- [Agent flows overview - Microsoft Copilot Studio - Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-copilot-studio/flows-overview) -- Updated 2025-11-21. Agent flows architecture, billing, trigger patterns
- [Known Issues in M365 Copilot Extensibility - Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-365-copilot/extensibility/known-issues) -- oneOf/anyOf/allOf not supported in Power Automate
- [Fluent UI Badge.types.ts - GitHub](https://github.com/microsoft/fluentui/blob/master/packages/react-components/react-badge/library/src/components/Badge/Badge.types.ts) -- Badge size prop type definition (source of truth)
- [design-tokens.ts - GitHub](https://github.com/microsoft/fluentui/blob/master/packages/web-components/src/theme/design-tokens.ts) -- colorPaletteRedBorder2, colorPaletteMarigoldBorder2, colorPaletteGreenBorder2 verified present
- [Wrong version of FluentUI - Issue #1265 - powerplatform-build-tools](https://github.com/microsoft/powerplatform-build-tools/issues/1265) -- PAC CLI Fluent version mismatch bug confirmation

### Secondary (MEDIUM confidence)
- [Virtual PCFs with Fluent UI 9 after GA - Diana Birkelbach](https://dianabirkelbach.wordpress.com/2024/12/06/virtual-pcfs-with-fluent-ui-9-after-ga/) -- Post-GA platform library guidance
- [UpdateView optimization in Virtual PCF - Diana Birkelbach](https://dianabirkelbach.wordpress.com/2022/05/06/updateview-in-virtual-pcf-components-and-how-to-optimize-rendering/) -- Rendering optimization patterns, version counter approach
- [Handling Choice columns dynamically - Amey Holden](https://www.ameyholden.com/articles/dataverse-choice-power-automate-dynamic-no-switch) -- Choice column integer mapping patterns in Power Automate
- [PCF controls automated testing - Roger Hill (Medium)](https://roger-hill.medium.com/pcf-controls-automated-testing-395caf9b7dfc) -- Jest setup for PCF controls

### Tertiary (LOW confidence)
- [scottdurow/pcf-react - GitHub](https://github.com/scottdurow/pcf-react) -- Community pattern for PCF testing with Jest (needs validation for Fluent v9 + pcf-scripts 1.51.x)
- Project codebase analysis (28 files reviewed directly) -- used as primary source for current state; all findings are subject to the remediation pass correcting them

---
*Research completed: 2026-02-20*
*Ready for roadmap: yes*
