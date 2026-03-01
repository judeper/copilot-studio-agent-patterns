# Requirements: Enterprise Work Assistant — Second Brain

**Defined:** 2026-02-28
**Core Value:** Every artifact in the solution must be correct and consistent — schemas match prompts, code compiles without errors, docs accurately describe the implementation, and scripts work when run. The system should learn from user behavior to improve its assistance over time.

## v2.2 Requirements

Requirements for tech debt cleanup. Each maps to roadmap phases. Source: v2.1 pre-deployment audit deferral log (27 items) + audit tech debt summary.

### Sender Intelligence

- [x] **SNDR-01**: SENDER_PROFILE JSON is passed to main agent as input variable so triage uses sender behavior data (R-17/I-14)
- [x] **SNDR-02**: Sender profile upsert uses Upsert with alternate key to prevent race conditions under concurrent signals (R-19/I-22)
- [x] **SNDR-03**: SENT_EDITED outcome uses full edit distance comparison instead of 0/1 boolean (I-21)

### Workflow Completeness

- [x] **WKFL-01**: Scheduled flow checks SELF_REMINDER cards for due reminders and surfaces them to the user (I-31)
- [x] **WKFL-02**: BriefingCard schedule is configurable via Dataverse table and Canvas App UI, persisting across sessions (R-35)
- [x] **WKFL-03**: Trigger Type Compose action covers all 6 trigger types including DAILY_BRIEFING, SELF_REMINDER, COMMAND_RESULT (R-15/I-19)

### UI / UX / Accessibility

- [ ] **UIUX-01**: BriefingCard, ConfidenceCalibration, CommandBar, and App use Fluent UI components instead of plain HTML (F-09 to F-12)
- [ ] **UIUX-02**: All interactive elements have ARIA labels, roles, and screen reader support (F-17)
- [ ] **UIUX-03**: Escape key closes detail views and panels (F-18)
- [ ] **UIUX-04**: Loading state with Spinner/Shimmer displays while data loads (F-13)
- [ ] **UIUX-05**: BriefingCard detail view has a Back navigation button (F-14)
- [ ] **UIUX-06**: Empty analytics buckets show "No data" instead of misleading 0% (F-19)
- [ ] **UIUX-07**: DataSet paging implemented for deployments with >100 active cards (F-20/I-32)
- [ ] **UIUX-08**: Localization/i18n strategy defined with string externalization pattern (I-33)

### Operational Resilience

- [ ] **OPER-01**: Power Automate Compose actions use Left() truncation for fields exceeding maxLength (R-34)
- [ ] **OPER-02**: Outcome tracker flow uses optimistic concurrency to prevent counter drift (I-23)
- [ ] **OPER-03**: Draft edits persist to Dataverse cr_editeddraft column across sessions (I-28)
- [ ] **OPER-04**: Dismiss action includes retry logic and error toast on failure (I-29)
- [ ] **OPER-05**: Dead-letter mechanism evaluated for failed flow runs with documented decision (I-30)

### Deployment Documentation

- [ ] **DOCS-01**: PAC CLI minimum version documented in deployment guide (R-14)
- [ ] **DOCS-02**: NuGet restore step added to deploy-solution.ps1 (R-20)
- [ ] **DOCS-03**: Managed vs Unmanaged solution guidance documented for production (R-21)
- [ ] **DOCS-04**: Knowledge source configuration steps documented (R-23)
- [ ] **DOCS-05**: Agent timeout tuning guidance documented (R-30)
- [ ] **DOCS-06**: API rate limit awareness section added (R-31)
- [ ] **DOCS-07**: Capacity planning section with usage-dependent guidance (R-32)
- [ ] **DOCS-08**: License and role requirements matrix documented (R-33)

### Code Quality

- [x] **QUAL-01**: ESLint react-hooks plugin installed and configured to catch hook dependency errors (F-22)

## v2.1 Requirements (Complete)

All 19 requirements satisfied. See milestones/v2.1-REQUIREMENTS.md for details.

## Future Requirements

### Deployment Execution

- **DEPLOY-01**: Dataverse tables provisioned in target environment
- **DEPLOY-02**: Power Automate flows imported and activated
- **DEPLOY-03**: Copilot Studio agent published
- **DEPLOY-04**: PCF control built and deployed to Canvas App
- **DEPLOY-05**: End-to-end smoke test in live environment

## Out of Scope

| Feature | Reason |
|---------|--------|
| New agent patterns (OOO agent, meeting prep) | Separate milestone — additive features, not tech debt |
| Runtime Power Platform testing | No local environment available — validation through code review and unit tests |
| TypeScript 5.x upgrade | Blocked by pcf-scripts pinning TS 4.9.5 |
| Mobile responsiveness | Not relevant to Canvas App PCF dashboard |
| Actual Power Platform deployment | v2.2 improves the blueprint; deployment is a future milestone |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SNDR-01 | Phase 14 | Complete |
| SNDR-02 | Phase 14 | Complete |
| SNDR-03 | Phase 14 | Complete |
| WKFL-01 | Phase 15 | Complete |
| WKFL-02 | Phase 15 | Complete |
| WKFL-03 | Phase 15 | Complete |
| UIUX-01 | Phase 16 | Pending |
| UIUX-02 | Phase 17 | Pending |
| UIUX-03 | Phase 17 | Pending |
| UIUX-04 | Phase 16 | Pending |
| UIUX-05 | Phase 16 | Pending |
| UIUX-06 | Phase 16 | Pending |
| UIUX-07 | Phase 18 | Pending |
| UIUX-08 | Phase 17 | Pending |
| OPER-01 | Phase 18 | Pending |
| OPER-02 | Phase 18 | Pending |
| OPER-03 | Phase 18 | Pending |
| OPER-04 | Phase 18 | Pending |
| OPER-05 | Phase 18 | Pending |
| DOCS-01 | Phase 19 | Pending |
| DOCS-02 | Phase 19 | Pending |
| DOCS-03 | Phase 19 | Pending |
| DOCS-04 | Phase 19 | Pending |
| DOCS-05 | Phase 19 | Pending |
| DOCS-06 | Phase 19 | Pending |
| DOCS-07 | Phase 19 | Pending |
| DOCS-08 | Phase 19 | Pending |
| QUAL-01 | Phase 14 | Complete |

**Coverage:**
- v2.2 requirements: 28 total
- Mapped to phases: 28
- Unmapped: 0

---
*Requirements defined: 2026-02-28*
*Last updated: 2026-02-28 after roadmap creation*
