---
phase: 12-integration-e2e-review
plan: 01
subsystem: integration
tags: [cross-layer-audit, ai-council, correctness, implementability, gaps, security, async, prompt-injection]

# Dependency graph
requires:
  - phase: 10-platform-architecture-review
    provides: "Platform-layer BLOCK/WARN issues (R-01 through R-09) for cross-layer correlation"
  - phase: 11-frontend-pcf-review
    provides: "Frontend-layer BLOCK/WARN issues (F-01 through F-08) for cross-layer correlation"
provides:
  - "Correctness Agent findings: 22 cross-layer field/enum tracing issues (8 BLOCK, 14 non-blocking)"
  - "Implementability Agent findings: 19 end-to-end workflow tracing issues (7 BLOCK, 12 non-blocking)"
  - "Gaps Agent findings: 21 security/async/integration gap issues (6 BLOCK, 10 non-blocking, 5 known constraints)"
affects: [12-02-reconciliation-verdict, 13-remediation]

# Tech tracking
tech-stack:
  added: []
  patterns: [cross-layer-contract-tracing, end-to-end-workflow-tracing, security-domain-audit, async-timing-analysis]

key-files:
  created:
    - ".planning/phases/12-integration-e2e-review/12-01-correctness-findings.md"
    - ".planning/phases/12-integration-e2e-review/12-01-implementability-findings.md"
    - ".planning/phases/12-integration-e2e-review/12-01-gaps-findings.md"
  modified: []

key-decisions:
  - "N/A vs null mismatch (R-01) confirmed as cross-layer integration issue spanning prompt-schema-frontend"
  - "NUDGE card_status unreachable via cr_fulljson path confirmed as cross-layer root cause (Phase 10 R-07 + Phase 11 F-01)"
  - "Prompt injection classified as deploy-blocking -- no agent prompt has injection defense"
  - "Sender-adaptive triage classified as silently disabled -- SENDER_PROFILE never passed to agent"
  - "Daily Briefing flow steps 7-10 missing makes BriefingCard data path undefined"
  - "Card Outcome Tracker DISMISSED omission breaks dismiss_count/dismiss_rate/AUTO_LOW categorization chain"

patterns-established:
  - "5-layer contract tracing: prompt -> schema -> Dataverse -> flow -> TypeScript for every field and enum"
  - "End-to-end workflow tracing with PASS/FAIL/MISSING per step across all layer transitions"
  - "4-domain security audit: authentication, row-level access, XSS, prompt injection"
  - "Async timing analysis: polling, fire-and-forget, concurrent calls, timing assumptions"

requirements-completed: [INTG-01, INTG-02, INTG-03, INTG-04, INTG-05]

# Metrics
duration: 11min
completed: 2026-02-28
---

# Phase 12 Plan 01: Integration AI Council Findings Summary

**Three AI Council agents (Correctness, Implementability, Gaps) produced 62 cross-layer integration findings (21 BLOCK, 36 non-blocking, 5 known constraints) spanning all seams between agent, schema, Dataverse, flow, and frontend layers.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-02-28T22:23:06Z
- **Completed:** 2026-02-28T22:34:46Z
- **Tasks:** 3
- **Files created:** 3

## Accomplishments

- Traced every field and every enum value across all 5 integration layers with complete cross-layer tracing tables (Correctness)
- Traced all 7 user workflows from trigger to completion with step-by-step PASS/FAIL/MISSING assessment and built error handling matrix for all 4 layer boundaries (Implementability)
- Audited security model across 4 domains (auth PASS, RLS CONDITIONAL PASS, XSS PASS, prompt injection FAIL) and analyzed all async patterns for race conditions, feedback gaps, and timing assumptions (Gaps)
- Confirmed 5 Phase 10 BLOCK issues (R-01, R-02, R-04, R-07, R-08) and 3 Phase 11 BLOCK issues (F-01, F-02, F-03) have cross-layer integration implications beyond their original scope
- Identified 3 NEW deploy-blocking issues not found in Phases 10-11: prompt injection vulnerability, missing staleness refresh mechanism, missing monitoring strategy

## Task Commits

Each task was committed atomically:

1. **Task 1: Correctness Agent -- cross-layer contract tracing** - `b6e2c95` (feat)
2. **Task 2: Implementability Agent -- end-to-end workflow tracing** - `b622ccb` (feat)
3. **Task 3: Gaps Agent -- security, async, and integration gaps** - `bda9d99` (feat)

## Files Created/Modified

- `.planning/phases/12-integration-e2e-review/12-01-correctness-findings.md` - 22 issues from cross-layer field/enum tracing across 5 layers
- `.planning/phases/12-integration-e2e-review/12-01-implementability-findings.md` - 19 issues from 7 workflow traces and 4 layer boundary error audits
- `.planning/phases/12-integration-e2e-review/12-01-gaps-findings.md` - 21 issues from security audit, async analysis, and integration gap identification

## Decisions Made

1. **N/A vs null classified as cross-layer BLOCK**: The prompt instructs "N/A" but the schema enum excludes it. useCardData compensates by converting N/A to null, but the schema contract is broken. This affects automated validation tools.
2. **Prompt injection classified as deploy-blocking**: No agent prompt contains injection defense instructions. Untrusted email/Teams content is passed directly to agents. Copilot Studio's built-in safeguards provide baseline protection but not against sophisticated injection.
3. **NUDGE root cause identified as cross-layer**: The Staleness Monitor (missing spec) would set NUDGE via discrete column, but useCardData reads card_status from cr_fulljson. Both the flow spec (R-07) and the ingestion path (F-01) must be fixed.
4. **Sender-adaptive triage entirely disabled**: SENDER_PROFILE not passed in any trigger flow. USER_VIP/USER_OVERRIDE mismatch would break it even if passed. Both must be fixed for Sprint 4 features to work.
5. **Daily Briefing data path undefined**: BriefingCard expects briefing data in card.draft_payload but the briefing schema has no draft_payload field. The flow must wrap the briefing in a standard output envelope.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Three independent findings documents ready for Plan 02 reconciliation and verdict
- All 5 INTG requirements covered: INTG-01 (Correctness tracing tables), INTG-02 (Implementability workflow traces + Gaps integration points), INTG-03 (Implementability error matrix + Gaps error recovery), INTG-04 (Gaps security audit), INTG-05 (Gaps async analysis)
- Combined issue counts for reconciliation: 62 raw findings (21 BLOCK, 36 non-blocking, 5 known constraints)
- Several findings overlap across agents (e.g., NUDGE, CommandBar, DISMISSED branch) -- reconciliation in Plan 02 will deduplicate and produce final verdict

## Self-Check: PASSED

All files verified:
- FOUND: 12-01-correctness-findings.md
- FOUND: 12-01-implementability-findings.md
- FOUND: 12-01-gaps-findings.md
- FOUND: 12-01-SUMMARY.md

All commits verified:
- FOUND: b6e2c95 (Correctness Agent)
- FOUND: b622ccb (Implementability Agent)
- FOUND: bda9d99 (Gaps Agent)

---
*Phase: 12-integration-e2e-review*
*Completed: 2026-02-28*
