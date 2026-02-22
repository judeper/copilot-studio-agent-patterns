# Roadmap: Enterprise Work Assistant -- Production Readiness

## Overview

This roadmap takes the Enterprise Work Assistant solution from its current state (internally inconsistent, several known bugs, no tests) to production-ready reference pattern quality. The dependency chain is strict: the output schema is the root contract from which all other artifacts derive, so schema fixes come first, then code fixes (which depend on correct types), then documentation and scripts (which must reflect final schema and code), and finally unit tests (which require stable code). Within each of these layers, natural sub-boundaries allow incremental verification.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Output Schema Contract** - Fix field types, nullability, and conventions in output-schema.json and align all downstream schema consumers
- [x] **Phase 2: Table Naming Consistency** - Resolve singular/plural cr_assistantcard naming across every file in the solution
- [x] **Phase 3: PCF Build Configuration** - Pin Fluent UI version, update manifest, and lock dependency versions for correct builds
- [x] **Phase 4: PCF API Correctness** - Fix Fluent UI v9 Badge size, color token names, and clean up contract drift from earlier phases (completed 2026-02-21)
- [x] **Phase 5: PCF Security Hardening** - Sanitize external URLs in CardDetail.tsx to prevent XSS (completed 2026-02-21)
- [x] **Phase 6: PowerShell Script Fixes** - Fix deploy-solution.ps1 polling logic and parameterize create-security-roles.ps1 (completed 2026-02-21)
- [x] **Phase 7: Documentation Accuracy** - Correct deployment guide UI paths, add Power Automate expression examples, and document prerequisites (completed 2026-02-21)
- [x] **Phase 8: Test Infrastructure and Unit Tests** - Configure Jest for PCF and write unit tests for hooks, filters, and components (completed 2026-02-22)
- [x] **Phase 9: Tech Debt Cleanup** - Fix schema convention divergence, broken doc paths, version annotations, and stale requirement text from audit (completed 2026-02-22)

## Phase Details

### Phase 1: Output Schema Contract
**Goal**: Every artifact that references the agent output contract agrees on field names, types, nullability, and value conventions
**Depends on**: Nothing (first phase)
**Requirements**: SCHM-01, SCHM-02, SCHM-03, SCHM-04, SCHM-05, SCHM-06
**Success Criteria** (what must be TRUE):
  1. output-schema.json defines confidence_score as integer (not string), draft_type as a required field, draft_payload null convention (not "N/A"), and cr_itemsummary placeholder for SKIP-tier items
  2. types.ts TypeScript interfaces match every field name, type, and nullability rule in output-schema.json exactly
  3. main-agent-system-prompt.md JSON examples produce output that validates against output-schema.json without errors
  4. humanizer-agent-prompt.md handoff object includes draft_type and uses the same null/nullability conventions as output-schema.json
  5. dataverse-table.json includes cr_triagetier Choice column with SKIP/LIGHT/FULL values and all column types match the schema
**Plans**: 2 plans

Plans:
- [ ] 01-01-PLAN.md — Fix schema, types, and Dataverse table contract (output-schema.json, types.ts, dataverse-table.json)
- [ ] 01-02-PLAN.md — Align prompt instructions and examples with updated schema (main-agent-system-prompt.md, humanizer-agent-prompt.md)

### Phase 2: Table Naming Consistency
**Goal**: The table logical name cr_assistantcard (singular) and entity set name cr_assistantcards (plural) are used in the correct contexts everywhere
**Depends on**: Phase 1
**Requirements**: SCHM-07
**Success Criteria** (what must be TRUE):
  1. Every file that references the Dataverse table uses cr_assistantcard for the logical name and cr_assistantcards for the entity set name -- no mixed usage
  2. Schema files, PowerShell scripts, documentation, and PCF code all pass a grep audit for the naming convention with zero violations
**Plans**: 1 plan

Plans:
- [ ] 02-01-PLAN.md — Create naming audit script, run audit, and fix any violations (audit-table-naming.ps1)

### Phase 3: PCF Build Configuration
**Goal**: The PCF control builds successfully with the correct platform library versions and dependency pins
**Depends on**: Phase 1
**Requirements**: PCF-01, PCF-05, PCF-06
**Success Criteria** (what must be TRUE):
  1. ControlManifest.Input.xml declares platform-library version="9.46.2"
  2. package.json pins @fluentui/react-components to a version within the 9.46.2 ceiling and uses @fluentui/react-components (not @fluentui/react-theme) for all token imports
  3. bun install followed by bun run build completes without errors or warnings
**Plans**: 1 plan

Plans:
- [ ] 03-01-PLAN.md — Fix manifest version, consolidate Fluent UI imports, switch to Bun, and verify clean build

### Phase 4: PCF API Correctness
**Goal**: All Fluent UI v9 component usage matches the actual API surface -- no invalid prop values or nonexistent tokens -- and contract drift from earlier phases is cleaned up
**Depends on**: Phase 3
**Requirements**: PCF-02, PCF-03
**Audit additions**: Clean up SCHM-06 drift (N/A guards), fix nullable casts for non-nullable item_summary, remove redundant null guards
**Success Criteria** (what must be TRUE):
  1. Badge components use only valid size values (small, medium, large) -- no "tiny" or other invalid sizes anywhere in the codebase
  2. Color tokens reference correct Fluent UI v9 names (colorPaletteMarigoldBorder2 instead of colorPaletteYellowBorder2) and all tokens resolve at build time
  3. CardDetail.tsx has no residual !== "N/A" guards (contract drift from Phase 1 SCHM-06)
  4. useCardData.ts and CardItem.tsx do not treat item_summary as nullable (matches Phase 1 non-nullable contract)
  5. bun run build and bun run lint still pass with zero errors and zero warnings after all changes
**Plans**: 1 plan

Plans:
- [ ] 04-01-PLAN.md — Fix Fluent UI v9 API correctness, clean up N/A contract drift, consolidate priority colors into shared constants

### Phase 5: PCF Security Hardening
**Goal**: External URLs rendered in the PCF control cannot be exploited for XSS attacks
**Depends on**: Phase 4
**Requirements**: PCF-04
**Success Criteria** (what must be TRUE):
  1. CardDetail.tsx validates all external URLs against an explicit allowlist of safe schemes (https, mailto) before rendering as clickable links
  2. URLs with javascript:, data:, or other dangerous schemes are either stripped or rendered as plain text, never as active links
**Plans**: 1 plan

Plans:
- [ ] 05-01-PLAN.md — Create URL sanitization utility and integrate into CardDetail.tsx for XSS prevention

### Phase 6: PowerShell Script Fixes
**Goal**: Deployment scripts work correctly when run with standard parameters -- no hardcoded values, no broken polling, and build commands match the Bun package manager introduced in Phase 3
**Depends on**: Phase 2
**Requirements**: DOC-05, DOC-06
**Audit additions**: Update deploy-solution.ps1 to use bun install/bun run build instead of npm, update prerequisite check to verify Bun is installed
**Success Criteria** (what must be TRUE):
  1. deploy-solution.ps1 polls the import operation status (not solution existence) and correctly waits for completion before proceeding
  2. create-security-roles.ps1 accepts a -PublisherPrefix parameter instead of hardcoding 'cr_' and uses it for all table/column references
  3. deploy-solution.ps1 uses bun install and bun run build (not npm) for PCF build steps, consistent with Phase 3 Bun migration
  4. deploy-solution.ps1 prerequisite check verifies Bun is installed alongside Node.js
**Plans**: 1 plan

Plans:
- [ ] 06-01-PLAN.md — Fix deploy-solution.ps1 (WhatIf, Bun, logging, prereqs, exit codes), harden create-security-roles.ps1 error handling, update deployment guide Bun commands

### Phase 7: Documentation Accuracy
**Goal**: A developer following the deployment guide and agent-flows documentation can configure the solution without encountering incorrect instructions
**Depends on**: Phase 5, Phase 6
**Requirements**: DOC-01, DOC-02, DOC-03, DOC-04, DOC-07
**Audit additions**: Fix agent-flows.md PA simplified schema declaring item_summary as nullable (should document non-nullable contract from Phase 1), update prerequisites to reflect Bun requirement
**Success Criteria** (what must be TRUE):
  1. Deployment guide specifies the correct Copilot Studio UI path for enabling JSON output mode (matching the current product UI, not a stale path)
  2. Agent-flows.md includes at least one concrete Power Automate expression example for Choice column integer-to-label mapping
  3. Agent-flows.md documents how to find and configure the "Execute Agent and wait" action in the Microsoft Copilot Studio connector (clarifying the distinction from AI Builder's "Run a prompt")
  4. Deployment guide includes research tool action registration steps
  5. Documentation states Bun >= 1.x and Node.js >= 20 as prerequisites in the requirements section
  6. Agent-flows.md PA simplified schema uses non-nullable string for item_summary (consistent with Phase 1 contract)
**Plans**: 2 plans

Plans:
- [ ] 07-01-PLAN.md — Fix deployment guide: JSON output UI path, prerequisites, research tool registration freshness dates
- [ ] 07-02-PLAN.md — Fix agent-flows: connector action name, Choice column expressions, item_summary nullability, research tool cross-reference

### Phase 8: Test Infrastructure and Unit Tests
**Goal**: The PCF project has working unit tests that verify core logic and component rendering, demonstrating testing practices for the reference pattern
**Depends on**: Phase 5
**Requirements**: TEST-01, TEST-02, TEST-03, TEST-04
**Success Criteria** (what must be TRUE):
  1. Jest and React Testing Library are configured with PCF-compatible setup (ComponentFramework mocks, Fluent UI transforms) and npx jest runs without configuration errors
  2. useCardData hook tests cover JSON parsing of valid data, graceful handling of malformed JSON, empty datasets, and tier-specific field presence
  3. Filter logic tests in App.tsx verify correct filtering by category, priority, and triage tier independently and in combination
  4. CardItem, CardDetail, CardGallery, and FilterBar each have at least one render test that passes with valid mock data
**Plans**: 2 plans

Plans:
- [ ] 08-01-PLAN.md — Configure Jest, ts-jest, React Testing Library with PCF mocks, fixtures, and helpers
- [ ] 08-02-PLAN.md — Write unit tests for useCardData, urlSanitizer, App filters, and component rendering

### Phase 9: Tech Debt Cleanup
**Goal**: Resolve non-blocking inconsistencies identified during the v1.0 milestone audit — schema convention divergence, broken documentation paths, inaccurate version annotations, and stale requirement text
**Depends on**: Phase 7
**Requirements**: None (tech debt — no formal requirement IDs)
**Gap Closure:** Closes 4 tech debt items from v1.0-MILESTONE-AUDIT.md
**Success Criteria** (what must be TRUE):
  1. output-schema.json priority and temporal_horizon enums use null convention (not "N/A"), matching types.ts contract established in Phase 1
  2. agent-flows.md relative path to output-schema.json resolves correctly (../schemas/output-schema.json)
  3. Deployment guide "Tested with" annotation reflects actual tested Bun version (1.3.8)
  4. DOC-03 requirement text in REQUIREMENTS.md says "Execute Agent and wait" (not "Run a prompt")
**Plans**: 1 plan

Plans:
- [ ] 09-01-PLAN.md — Fix schema enum divergence, broken doc path, version annotation, and stale requirement text

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9
(Phases 2, 3 both depend on 1 but run sequentially. Phase 7 depends on 5 and 6. Phase 9 depends on 7.)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Output Schema Contract | 2/2 | Complete | 2026-02-20 |
| 2. Table Naming Consistency | 1/1 | Complete | 2026-02-20 |
| 3. PCF Build Configuration | 1/1 | Complete | 2026-02-21 |
| 4. PCF API Correctness | 0/TBD | Complete    | 2026-02-21 |
| 5. PCF Security Hardening | 1/1 | Complete | 2026-02-21 |
| 6. PowerShell Script Fixes | 0/TBD | Complete    | 2026-02-21 |
| 7. Documentation Accuracy | 2/2 | Complete | 2026-02-21 |
| 8. Test Infrastructure and Unit Tests | 2/2 | Complete | 2026-02-22 |
| 9. Tech Debt Cleanup | 1/1 | Complete | 2026-02-22 |
