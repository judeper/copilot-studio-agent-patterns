---
phase: 14-sender-intelligence-completion
plan: 02
subsystem: flows
tags: [power-automate, dataverse-upsert, sender-profile, edit-distance, sender-intelligence]

# Dependency graph
requires:
  - phase: 14-sender-intelligence-completion/01
    provides: "editDistanceRatio in PCF sendDraftAction JSON payload"
provides:
  - "All trigger flows (1-3) pass SENDER_PROFILE JSON to the main agent"
  - "All sender profile writes use Dataverse Upsert with cr_senderemail_key alternate key"
  - "Flow 5 reads pre-computed edit distance ratio (0-100) from PCF instead of 0/1 boolean"
  - "Known Gap R-17 resolved -- sender-adaptive triage is now active"
affects: [deployment-guide, sender-profile-analyzer, main-agent-prompt]

# Tech tracking
tech-stack:
  added: []
  patterns: [Dataverse Upsert with alternate key for race-safe writes, SENDER_PROFILE passthrough pattern for trigger flows]

key-files:
  created: []
  modified:
    - enterprise-work-assistant/docs/agent-flows.md
    - enterprise-work-assistant/docs/deployment-guide.md

key-decisions:
  - "Used alternate key cr_senderemail_key for all Upsert operations rather than row ID lookup"
  - "Kept running average formula unchanged for edit distance -- works identically with 0-100 range as with 0/1"
  - "Added coalesce fallback in edit distance Compose for legacy cards without cr_editdistanceratio"

patterns-established:
  - "Dataverse Upsert pattern: Use Update or add rows (V2) with alternate key to eliminate List+Condition+Add/Update race conditions"
  - "SENDER_PROFILE passthrough: Steps 3a (List) + 3b (Compose JSON) inserted before agent invocation in all trigger flows"

requirements-completed: [SNDR-01, SNDR-02, SNDR-03]

# Metrics
duration: 6min
completed: 2026-02-28
---

# Phase 14 Plan 02: Flow Specifications -- Upsert Migration, SENDER_PROFILE Passthrough, and Edit Distance Ratio Summary

**Migrated all sender profile writes to Dataverse Upsert with alternate key, wired SENDER_PROFILE passthrough in trigger flows 1-3, and updated Flow 5 to receive pre-computed Levenshtein edit distance ratio from PCF**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-01T01:18:18Z
- **Completed:** 2026-03-01T01:24:47Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- All sender profile writes across Flows 1-3 and Flow 5 now use Dataverse Upsert with alternate key cr_senderemail_key, eliminating race conditions
- Trigger flows 1-3 now look up sender profile and pass 7-field SENDER_PROFILE JSON (or null for first-time senders) to the main agent
- Flow 5 Branch A reads pre-computed editDistanceRatio (0-100 Levenshtein) from the Assistant Card row instead of computing a 0/1 boolean
- Flow 5 Branch B (DISMISSED) migrated from List+Condition+Update to Upsert
- Known Gap R-17 resolved and removed from agent-flows.md
- Deployment guide SENDER_PROFILE description updated to reflect active population by trigger flows

## Task Commits

Each task was committed atomically:

1. **Task 1: Migrate trigger flows (1-3) to Upsert + add sender profile passthrough** - `751c248` (feat)
2. **Task 2: Update Flow 5 outcome tracker to use Upsert + pre-computed edit distance ratio** - `45af8c9` (feat)

## Files Created/Modified
- `enterprise-work-assistant/docs/agent-flows.md` - Updated flow specs: Upsert pattern in Flows 1-3 step 11 and Flow 5, SENDER_PROFILE passthrough (steps 3a-3b), pre-computed edit distance, removed R-17 gap
- `enterprise-work-assistant/docs/deployment-guide.md` - Updated SENDER_PROFILE input variable description and Sprint 4 checklist

## Decisions Made
- Used alternate key `cr_senderemail_key` for all Upsert operations, matching the alternate key already defined in senderprofile-table.json schema
- Preserved the running average formula in step 2a-1b unchanged -- it works identically whether the input edit distance is 0/1 or 0-100
- Added coalesce fallback for legacy cards without `cr_editdistanceratio` column: SENT_EDITED defaults to 100 (assumes full rewrite), SENT_AS_IS defaults to 0
- Documented `cr_editdistanceratio` (WholeNumber, 0-100, nullable) as a required new column on the Assistant Cards table

## Deviations from Plan

None -- plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 14 is complete: ESLint react-hooks enforced, Levenshtein edit distance computed in PCF, all flow specs updated with Upsert + SENDER_PROFILE passthrough
- All three SNDR requirements (SNDR-01, SNDR-02, SNDR-03) are resolved
- The next phase in the v2.2 milestone can proceed

## Self-Check: PASSED

All files verified present, all commit hashes confirmed in git log.

---
*Phase: 14-sender-intelligence-completion*
*Completed: 2026-02-28*
