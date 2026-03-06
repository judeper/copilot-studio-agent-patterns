# Roadmap: Enterprise Work Assistant

## Milestones

- ✅ **v1.0 Production Readiness** — Phases 1-9 (shipped 2026-02-22)
- ✅ **v2.0 Second Brain Evolution** — Sprints 1A-4 (shipped 2026-02-28)
- ✅ **v2.1 Pre-Deployment Audit** — Phases 10-13 (shipped 2026-03-01)
- ✅ **v2.2 Tech Debt Cleanup (POC Scope)** — Phases 14-19 (POC complete)

## Phases

<details>
<summary>✅ v1.0 Production Readiness (Phases 1-9) — SHIPPED 2026-02-22</summary>

- [x] Phase 1: Output Schema Contract (2/2 plans) — completed 2026-02-20
- [x] Phase 2: Table Naming Consistency (1/1 plan) — completed 2026-02-20
- [x] Phase 3: PCF Build Configuration (1/1 plan) — completed 2026-02-21
- [x] Phase 4: PCF API Correctness (1/1 plan) — completed 2026-02-21
- [x] Phase 5: PCF Security Hardening (1/1 plan) — completed 2026-02-21
- [x] Phase 6: PowerShell Script Fixes (1/1 plan) — completed 2026-02-21
- [x] Phase 7: Documentation Accuracy (2/2 plans) — completed 2026-02-21
- [x] Phase 8: Test Infrastructure and Unit Tests (2/2 plans) — completed 2026-02-22
- [x] Phase 9: Tech Debt Cleanup (1/1 plan) — completed 2026-02-22

Full details: milestones/v1.0-ROADMAP.md

</details>

<details>
<summary>✅ v2.0 Second Brain Evolution (Sprints 1A-4) — SHIPPED 2026-02-28</summary>

- [x] Sprint 1A: Outcome Tracking + Send-As-Is Email Flow — completed 2026-02-28
- [x] Sprint 1B: Conversation Clustering + Sender Profiles — completed 2026-02-28
- [x] Sprint 2: Daily Briefing Agent + Inline Editing + Staleness Monitor — completed 2026-02-28
- [x] Sprint 3: Command Bar + Orchestrator Agent — completed 2026-02-28
- [x] Sprint 4: Sender Intelligence + Adaptive Triage + Confidence Calibration — completed 2026-02-28
- [x] Review: End-to-End Bug Fixes + Documentation Corrections — completed 2026-02-28

Full details: milestones/v2.0-ROADMAP.md

</details>

<details>
<summary>✅ v2.1 Pre-Deployment Audit (Phases 10-13) — SHIPPED 2026-03-01</summary>

- [x] **Phase 10: Platform Architecture Review** - AI Council reviews Dataverse, Power Automate, and Copilot Studio layers (completed 2026-02-28)
- [x] **Phase 11: Frontend / PCF Review** - AI Council reviews React components, hooks, state management, and test coverage (completed 2026-02-28)
- [x] **Phase 12: Integration / E2E Review** - AI Council reviews cross-layer contracts, user workflows, error handling, and security model (completed 2026-02-28)
- [x] **Phase 13: Remediation** - Fix deploy-blocking issues, document deferrals, and validate final state (completed 2026-03-01)

Full details: milestones/v2.1-REQUIREMENTS.md, v2.1-MILESTONE-AUDIT.md

</details>

### ✅ v2.2 Tech Debt Cleanup — POC Scope (Phases 14-19)

**Milestone Goal:** Resolve high-value tech debt from the v2.1 audit for POC readiness. Production-grade items (full a11y audit, i18n, optimistic concurrency, DataSet paging, capacity planning) are out of scope — this is a POC, not a production build.

- [x] **Phase 14: Sender Intelligence Completion** - Wire SENDER_PROFILE to agent, fix race conditions, and add full edit distance tracking (completed 2026-03-01)
- [x] **Phase 15: Workflow Completeness** - Add reminder firing flow, briefing schedule configuration, and complete trigger type coverage (completed 2026-03-01)
- [x] **Phase 16: Fluent UI Migration and UX Polish** - Replace plain HTML with Fluent UI components and fix UX gaps (loading, navigation, empty states) (completed 2026-03-01)
- [ ] **Phase 17: Accessibility (POC scope)** - Escape key closes overlays (ARIA/screen reader audit and i18n deferred — POC only)
- [ ] **Phase 18: Operational Resilience (POC scope)** - Draft edit persistence and basic retry on dismiss (optimistic concurrency, field truncation, DataSet paging deferred — POC only)
- [ ] **Phase 19: Deployment Documentation (POC scope)** - PAC CLI versioning, knowledge source setup, license/role matrix (timeout tuning, capacity planning deferred — POC only)

## Phase Details

<details>
<summary>Phase 10-13 Details (v2.1 — completed)</summary>

### Phase 10: Platform Architecture Review
**Goal**: Every platform-layer artifact (Dataverse definitions, Power Automate flow specs, Copilot Studio configs, deployment scripts) is validated as correct, buildable, and complete by three independent AI Council agents
**Depends on**: Nothing (first phase of v2.1)
**Requirements**: PLAT-01, PLAT-02, PLAT-03, PLAT-04, PLAT-05
**Success Criteria** (what must be TRUE):
  1. Every Dataverse table and column definition has been verified as valid and creatable in a real Power Platform environment (correct types, relationships, constraints)
  2. Every Power Automate flow spec maps to concrete connector actions and expressions that exist in the current platform
  3. Copilot Studio agent configurations reference valid topics, actions, and entity definitions with no orphaned references
  4. Deployment scripts execute a valid sequence of operations against real PAC CLI / Power Platform Admin APIs
  5. Any platform limitation that contradicts the design is identified with a specific remediation path or documented as a known constraint
**Plans**: 2 plans

Plans:
- [x] 10-01-PLAN.md — AI Council: 3 agents (Correctness, Implementability, Gaps) review all platform architecture files independently
- [x] 10-02-PLAN.md — Reconciliation: merge, deduplicate, resolve disagreements, produce unified verdict

### Phase 11: Frontend / PCF Review
**Goal**: The entire PCF layer (component architecture, state management, hooks, data flow, error handling, test coverage) is validated as sound, complete, and ready for deployment
**Depends on**: Phase 10
**Requirements**: PCF-01, PCF-02, PCF-03, PCF-04, PCF-05
**Success Criteria** (what must be TRUE):
  1. Component architecture follows consistent patterns for state, props, and hooks with no structural anti-patterns
  2. Every v2.0 tech debt item is categorized as either deploy-blocking (must fix before deployment) or deferrable (with documented rationale)
  3. Test coverage is assessed against all user-facing components and critical hooks, with gaps identified and prioritized
  4. Data flow from Dataverse response through useCardData hook to component render is traced and verified as correct at every transformation step
  5. Error states, loading states, and edge cases are handled in every user-facing component with no raw error strings or unhandled rejections visible to users
**Plans**: 2 plans

Plans:
- [x] 11-01-PLAN.md — AI Council: 3 agents (Correctness, Implementability, Gaps) review all PCF source files, tests, and configs independently
- [x] 11-02-PLAN.md — Reconciliation: merge, deduplicate, resolve disagreements, classify tech debt, produce unified verdict

### Phase 12: Integration / E2E Review
**Goal**: Cross-layer contracts are consistent, every user workflow completes end-to-end without gaps, and the security model is complete
**Depends on**: Phase 11
**Requirements**: INTG-01, INTG-02, INTG-03, INTG-04, INTG-05
**Success Criteria** (what must be TRUE):
  1. Schema field names, types, and nullability are consistent across output-schema.json, agent prompts, Dataverse column definitions, Power Automate expressions, and TypeScript interfaces
  2. Every user workflow (triage, draft editing, email send, outcome tracking, briefing, command execution, reminder creation) has been traced from trigger to completion with no missing steps
  3. Error handling exists at every layer boundary (agent-to-Dataverse, Dataverse-to-PCF, PCF-to-Power Automate) with defined fallback behavior
  4. Security model covers authentication, row-level data access, XSS prevention, and prompt injection defense with no unprotected surfaces
  5. Async flows (polling, fire-and-forget output bindings, concurrent agent calls) have no race conditions, resource leaks, or timing assumptions that break under load
**Plans**: 2 plans

Plans:
- [x] 12-01-PLAN.md — AI Council: 3 parallel agents (Correctness, Implementability, Gaps) review integration/E2E concerns
- [x] 12-02-PLAN.md — Reconciliation: resolve disagreements, produce unified findings

### Phase 13: Remediation
**Goal**: All deploy-blocking issues from Phases 10-12 are fixed, non-blocking issues are documented with deferral rationale, and the final state passes validation
**Depends on**: Phase 12
**Requirements**: FIX-01, FIX-02, FIX-03, FIX-04
**Success Criteria** (what must be TRUE):
  1. Every disagreement between council agents across all three review phases has been researched and resolved with a documented decision (not left ambiguous)
  2. All issues classified as deploy-blocking are fixed in the actual source files (code, docs, configs, scripts) with the fix verified
  3. All issues classified as non-blocking are documented in a deferral log with severity, rationale for deferral, and suggested resolution timeline
  4. Final validation pass confirms no regressions from fixes and the solution is clean for deployment (type-check passes, tests pass, no known deploy-blockers remain)
**Plans**: 4 plans (wave-aligned)

Plans:
- [x] 13-01-PLAN.md — Wave 1: Schema/contract fixes + audit wiring gap resolution
- [x] 13-02-PLAN.md — Wave 2: Missing flow specifications
- [x] 13-03-PLAN.md — Wave 3: Frontend fixes + test coverage
- [x] 13-04-PLAN.md — Deferral log + final validation

</details>

### Phase 14: Sender Intelligence Completion
**Goal**: The agent fully leverages sender behavioral data for triage decisions, with race-safe profile updates and accurate edit distance tracking
**Depends on**: Nothing (first phase of v2.2)
**Requirements**: SNDR-01, SNDR-02, SNDR-03, QUAL-01
**Success Criteria** (what must be TRUE):
  1. The main triage agent receives SENDER_PROFILE JSON as an input variable and its system prompt references sender behavior data when making priority decisions
  2. Concurrent sender profile updates from simultaneous agent calls resolve correctly via Dataverse Upsert with alternate key (no duplicate rows, no lost updates)
  3. SENT_EDITED outcomes record a Levenshtein edit distance ratio between original draft and edited version, replacing the previous boolean flag
  4. ESLint react-hooks plugin is installed and configured, and the codebase passes with zero hook dependency warnings
**Plans**: TBD

### Phase 15: Workflow Completeness
**Goal**: Every workflow path in the system completes end-to-end with no dead ends -- reminders fire on schedule, briefing schedule persists across sessions, and all trigger types route correctly
**Depends on**: Phase 14
**Requirements**: WKFL-01, WKFL-02, WKFL-03
**Success Criteria** (what must be TRUE):
  1. A scheduled Power Automate flow queries SELF_REMINDER cards with due dates in the past and surfaces them to the user as active cards
  2. Users can configure the Daily Briefing schedule via Canvas App UI, the schedule persists in a Dataverse BriefingSchedule table, and the briefing flow reads it at execution time
  3. The Trigger Type Compose action in the main triage flow correctly maps all 6 trigger types (EMAIL, TEAMS_CHAT, CALENDAR, DAILY_BRIEFING, SELF_REMINDER, COMMAND_RESULT) to their downstream processing branches
**Plans**: 2 plans

Plans:
- [ ] 15-01-PLAN.md — Reminder firing flow (Flow 10) + fix Trigger Type Compose expression to map all 6 types
- [ ] 15-02-PLAN.md — BriefingSchedule Dataverse table + Flow 6 schedule-aware trigger + Canvas App schedule UI

### Phase 16: Fluent UI Migration and UX Polish
**Goal**: All four identified components use Fluent UI v9 components instead of plain HTML, with consistent theming, loading states, and navigation patterns
**Depends on**: Phase 14 (ESLint catches hook issues during component rewrites)
**Requirements**: UIUX-01, UIUX-04, UIUX-05, UIUX-06
**Success Criteria** (what must be TRUE):
  1. BriefingCard, ConfidenceCalibration, CommandBar, and App components use Fluent UI v9 components (Button, Card, Input, Spinner, Tab, etc.) with zero plain HTML interactive elements remaining
  2. Data loading states display a Fluent UI Spinner or Shimmer placeholder instead of blank content or layout shift
  3. BriefingCard detail view includes a visible Back button that returns the user to the briefing summary list
  4. Analytics views (ConfidenceCalibration tabs) display "No data available" text for empty buckets instead of misleading 0% values
**Plans**: 2 plans

Plans:
- [ ] 16-01-PLAN.md — BriefingCard + ConfidenceCalibration Fluent UI migration, Back button, empty analytics fix
- [ ] 16-02-PLAN.md — CommandBar Fluent UI migration, App loading Spinner, Agent Performance button, onBack wiring

### Phase 17: Accessibility (POC Scope)
**Goal**: Escape key closes overlays for basic keyboard navigation
**Depends on**: Phase 16
**Requirements**: UIUX-03
**POC Scope Note**: Full ARIA/screen reader audit (UIUX-02) and i18n strategy (UIUX-08) are out of scope — this is a POC, not a production build. Fluent UI v9 components already provide baseline accessibility.
**Success Criteria** (what must be TRUE):
  1. Pressing Escape closes any open detail panel, edit panel, or command bar overlay, returning focus to the previously active element
**Plans**: TBD

### Phase 18: Operational Resilience (POC Scope)
**Goal**: Draft edits persist across sessions and dismiss actions don't silently fail
**Depends on**: Phase 15
**Requirements**: OPER-03, OPER-04
**POC Scope Note**: Field truncation (OPER-01), optimistic concurrency (OPER-02), dead-letter evaluation (OPER-05), and DataSet paging (UIUX-07) are out of scope — this is a POC, not a production build.
**Success Criteria** (what must be TRUE):
  1. Draft edits written via the inline edit panel persist to the Dataverse cr_editeddraft column and survive browser refresh
  2. Dismiss action includes basic retry logic (1-2 attempts) to prevent silent failures
**Plans**: TBD

### Phase 19: Deployment Documentation (POC Scope)
**Goal**: Admins can reproduce the POC deployment with documented prerequisites and configuration steps
**Depends on**: Nothing (documentation is independent of code phases)
**Requirements**: DOCS-01, DOCS-02, DOCS-03, DOCS-04, DOCS-08
**POC Scope Note**: Agent timeout tuning (DOCS-05), API rate limit guidance (DOCS-06), and capacity planning (DOCS-07) are out of scope — this is a POC, not a production build. Use platform defaults.
**Success Criteria** (what must be TRUE):
  1. The deployment guide specifies the minimum PAC CLI version, includes a NuGet restore step in deploy-solution.ps1, and documents managed vs. unmanaged solution guidance
  2. Knowledge source configuration steps (which documents to upload, how to configure the agent's knowledge base) are documented
  3. A license and role requirements matrix lists every Power Platform license, Dataverse security role, and connector permission needed to deploy the POC
**Plans**: TBD

## Items Removed from Scope (POC Decision)

The following items were removed from the v2.2 roadmap because this is a POC, not a production build. They can be revisited if the solution is productionized.

| Removed Item | Original Phase | Reason for Removal |
|-------------|---------------|-------------------|
| Full ARIA/screen reader audit | Phase 17 | Fluent UI v9 provides baseline a11y; full audit is weeks of work |
| i18n strategy & string externalization | Phase 17 | English-only is sufficient for POC |
| Field truncation with Left() | Phase 18 | Edge case for extreme input lengths; Power Automate auto-truncates |
| Optimistic concurrency (ETag) | Phase 18 | Race conditions unlikely with <10 demo users |
| Dead-letter mechanism | Phase 18 | Power Automate provides built-in failure notifications |
| DataSet paging for 100+ cards | Phase 18 | POC won't have 100+ active cards |
| Agent timeout tuning guide | Phase 19 | Default 120s timeout is adequate for POC |
| API rate limit guidance | Phase 19 | Platform limits documented by Microsoft; not POC-specific |
| Capacity planning guidance | Phase 19 | No usage data available yet; not applicable to demo |

## Progress

**Execution Order:**
Phases execute in numeric order: 14 -> 15 -> 16 -> 17 -> 18 -> 19
(Phase 19 can execute in parallel with 17-18 since documentation is independent)

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Output Schema Contract | v1.0 | 2/2 | Complete | 2026-02-20 |
| 2. Table Naming Consistency | v1.0 | 1/1 | Complete | 2026-02-20 |
| 3. PCF Build Configuration | v1.0 | 1/1 | Complete | 2026-02-21 |
| 4. PCF API Correctness | v1.0 | 1/1 | Complete | 2026-02-21 |
| 5. PCF Security Hardening | v1.0 | 1/1 | Complete | 2026-02-21 |
| 6. PowerShell Script Fixes | v1.0 | 1/1 | Complete | 2026-02-21 |
| 7. Documentation Accuracy | v1.0 | 2/2 | Complete | 2026-02-21 |
| 8. Test Infrastructure and Unit Tests | v1.0 | 2/2 | Complete | 2026-02-22 |
| 9. Tech Debt Cleanup | v1.0 | 1/1 | Complete | 2026-02-22 |
| 10. Platform Architecture Review | v2.1 | 2/2 | Complete | 2026-02-28 |
| 11. Frontend / PCF Review | v2.1 | 2/2 | Complete | 2026-02-28 |
| 12. Integration / E2E Review | v2.1 | 2/2 | Complete | 2026-02-28 |
| 13. Remediation | v2.1 | 4/4 | Complete | 2026-03-01 |
| 14. Sender Intelligence Completion | v2.2 | 2/2 | Complete | 2026-03-01 |
| 15. Workflow Completeness | v2.2 | 2/2 | Complete | 2026-03-01 |
| 16. Fluent UI Migration and UX Polish | v2.2 | 2/2 | Complete | 2026-03-01 |
| 17. Accessibility (POC scope) | v2.2 | 0/TBD | Not started | - |
| 18. Operational Resilience (POC scope) | v2.2 | 0/TBD | Not started | - |
| 19. Deployment Documentation (POC scope) | v2.2 | 0/TBD | Not started | - |
