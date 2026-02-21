# Requirements: Enterprise Work Assistant — Production Readiness

**Defined:** 2026-02-20
**Core Value:** Every artifact in the solution must be correct and consistent — schemas match prompts, code compiles without errors, docs accurately describe the implementation, and scripts work when run.

## v1 Requirements

Requirements for production readiness. Each maps to roadmap phases.

### Schema & Contract Consistency

- [x] **SCHM-01**: Dataverse primary column cr_itemsummary handles SKIP-tier items without null violation (use placeholder text)
- [x] **SCHM-02**: Dataverse table schema (dataverse-table.json) includes cr_triagetier Choice column with SKIP/LIGHT/FULL values
- [x] **SCHM-03**: confidence_score field template uses integer type consistently (no quoted strings) across prompts and schema
- [x] **SCHM-04**: key_findings and verified_sources nullability rules are consistent between main agent prompt, humanizer prompt, and output-schema.json
- [x] **SCHM-05**: Humanizer handoff object includes draft_type discriminator field for format determination
- [x] **SCHM-06**: draft_payload uses a single convention (null, not "N/A") for non-draft cases across all artifacts
- [ ] **SCHM-07**: Table logical name uses consistent singular/plural convention (cr_assistantcard) across all files — schema, scripts, docs, and code

### PCF Component Code

- [ ] **PCF-01**: ControlManifest.Input.xml platform-library version updated to 9.46.2 (current ceiling)
- [ ] **PCF-02**: Badge component uses valid Fluent UI v9 size prop values (small/medium/large, not tiny)
- [ ] **PCF-03**: Color tokens use correct Fluent UI v9 names (colorPaletteMarigoldBorder2, not colorPaletteYellowBorder2)
- [ ] **PCF-04**: CardDetail.tsx sanitizes external URLs before rendering to prevent XSS
- [ ] **PCF-05**: Fluent UI token imports use @fluentui/react-components (platform-shared), not @fluentui/react-theme
- [ ] **PCF-06**: @fluentui/react-components version pinned to compatible ceiling (^9.46.0) in package.json

### Documentation & Deployment

- [ ] **DOC-01**: Deployment guide specifies correct Copilot Studio UI path for enabling JSON output mode
- [ ] **DOC-02**: Agent-flows.md includes concrete Power Automate expression examples for Choice value mapping (e.g., integer conversion)
- [ ] **DOC-03**: Agent-flows.md documents how to locate and configure the Copilot Studio connector "Run a prompt" action
- [ ] **DOC-04**: Deployment guide includes research tool action registration guidance
- [ ] **DOC-05**: deploy-solution.ps1 polling logic checks import operation status (not solution existence)
- [ ] **DOC-06**: create-security-roles.ps1 accepts publisher prefix as parameter instead of hardcoding 'cr_'
- [ ] **DOC-07**: Documentation specifies Node.js >= 20 prerequisite

### Testing

- [ ] **TEST-01**: Jest and React Testing Library configured with PCF-compatible setup (transforms, mocks)
- [ ] **TEST-02**: Unit tests for useCardData hook cover JSON parsing, malformed data, empty datasets, and tier-specific behavior
- [ ] **TEST-03**: Unit tests for App.tsx filter logic cover category, priority, and triage tier filtering
- [ ] **TEST-04**: Component render tests for CardItem, CardDetail, CardGallery, and FilterBar verify rendering with valid data

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Optimization

- **OPT-01**: useMemo optimization to skip recomputation on resize-only updateView calls (check context.updatedProperties)
- **OPT-02**: Pin @fluentui/react-icons to tested version to avoid semver patch-break risk

### Documentation Enhancements

- **DOCE-01**: Canvas App 500-record delegation limit documented as known limitation
- **DOCE-02**: FluentProvider nesting behavior documented (needs runtime validation)
- **DOCE-03**: Filter dropdowns include N/A values for Priority and Temporal Horizon
- **DOCE-04**: Expand jargon (RLS, PCF) on first use throughout docs

## Out of Scope

| Feature | Reason |
|---------|--------|
| New capabilities or features | This is a fix-only remediation pass |
| Architecture redesign | Current architecture is sound per research |
| Runtime/integration testing | No local Power Platform environment available |
| TypeScript 5.x upgrade | Low risk but not a fix — improvement for a separate pass |
| Mobile responsiveness | Not relevant to Canvas App PCF dashboard |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SCHM-01 | Phase 1 | Complete |
| SCHM-02 | Phase 1 | Complete |
| SCHM-03 | Phase 1 | Complete |
| SCHM-04 | Phase 1 | Complete |
| SCHM-05 | Phase 1 | Complete |
| SCHM-06 | Phase 1 | Complete |
| SCHM-07 | Phase 2 | Pending |
| PCF-01 | Phase 3 | Pending |
| PCF-02 | Phase 4 | Pending |
| PCF-03 | Phase 4 | Pending |
| PCF-04 | Phase 5 | Pending |
| PCF-05 | Phase 3 | Pending |
| PCF-06 | Phase 3 | Pending |
| DOC-01 | Phase 7 | Pending |
| DOC-02 | Phase 7 | Pending |
| DOC-03 | Phase 7 | Pending |
| DOC-04 | Phase 7 | Pending |
| DOC-05 | Phase 6 | Pending |
| DOC-06 | Phase 6 | Pending |
| DOC-07 | Phase 7 | Pending |
| TEST-01 | Phase 8 | Pending |
| TEST-02 | Phase 8 | Pending |
| TEST-03 | Phase 8 | Pending |
| TEST-04 | Phase 8 | Pending |

**Coverage:**
- v1 requirements: 24 total
- Mapped to phases: 24
- Unmapped: 0

---
*Requirements defined: 2026-02-20*
*Last updated: 2026-02-20 after roadmap creation*
