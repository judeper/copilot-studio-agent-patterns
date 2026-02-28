---
phase: 13-remediation
plan: 02
subsystem: power-automate, agent-flows
tags: [power-automate, copilot-studio, dataverse, pcf, sender-intelligence, daily-briefing, staleness-monitor]

# Dependency graph
requires:
  - phase: 13-remediation
    provides: Schema enums, prompt injection defense, PascalCase privileges, publisher validation (13-01)
  - phase: 12-integration-e2e-review
    provides: Unified remediation backlog with 20 BLOCK issues including I-02, I-03, I-05, I-15
  - phase: 10-platform-architecture-review
    provides: 4 missing flow spec BLOCK issues (R-04, R-05, R-06, R-07, R-08)
provides:
  - Flow 5 DISMISSED branch incrementing cr_dismisscount for sender analytics
  - Flow 5 SENT_EDITED branch computing edit distance for draft refinement metrics
  - Flow 6 output envelope wrapping with draft_payload enabling BriefingCard.tsx rendering (I-15)
  - Flow 7 NUDGE via discrete cr_cardstatus column enabling useCardData.ts detection (I-02)
  - Flow 7 EXPIRED setting both cr_cardoutcome and cr_cardstatus (I-03)
  - Flow 8 F-02 response format contract and R-18 Orchestrator tool action registration docs
  - Flow 9 dismiss_rate categorization with 5-interaction minimum threshold
  - R-17 known gap documented (SENDER_PROFILE not passed to agent)
affects: [13-03, 13-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Output envelope wrapping: all card types must conform to output-schema.json with draft_payload"
    - "Discrete column contract: system-managed statuses (NUDGE, EXPIRED) set via discrete Dataverse columns, not cr_fulljson"
    - "Profile-level counters: cr_responsecount/cr_dismisscount used for sender categorization (no per-query card outcome aggregation needed)"
    - "Minimum interaction threshold: 5 total interactions before sender categorization triggers"

key-files:
  created: []
  modified:
    - enterprise-work-assistant/docs/agent-flows.md

key-decisions:
  - "NUDGE status set via discrete cr_cardstatus column on both new nudge card AND original overdue card (not through cr_fulljson)"
  - "Output envelope wrapping in Flow 6 stores briefing JSON in draft_payload field so BriefingCard.tsx parseBriefing() can parse it"
  - "Sender categorization uses profile-level counters (cr_responsecount + cr_dismisscount) with 5-interaction minimum instead of per-query card outcome aggregation"
  - "SENT_EDITED edit distance uses simplified 0/1 boolean comparison for MVP (full Levenshtein deferred)"
  - "R-17 (SENDER_PROFILE not passed to agent) classified as WARN deferral -- sender analytics still provide value without agent consumption"
  - "Removed duplicate Flow 6 and Flow 7 sections, consolidated into single authoritative versions"

patterns-established:
  - "Discrete column contract: any status not produced by agent output (NUDGE, EXPIRED) must be set via discrete Dataverse column update, not through cr_fulljson"
  - "Envelope wrapping: non-standard agent outputs (briefing, command response) must be wrapped in output-schema.json envelope before Dataverse write"

requirements-completed: [FIX-01, FIX-02]

# Metrics
duration: 10min
completed: 2026-02-28
---

# Phase 13 Plan 02: Flow Specification Fixes Summary

**DISMISSED/SENT_EDITED branches in Card Outcome Tracker, output envelope wrapping for Daily Briefing, NUDGE via discrete column in Staleness Monitor, F-02 response format and R-18 tool registration for Command Execution, dismiss_rate categorization for Sender Profile Analyzer**

## Performance

- **Duration:** 10 min
- **Started:** 2026-02-28T23:33:37Z
- **Completed:** 2026-02-28T23:44:31Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Fixed Flow 5 (Card Outcome Tracker) with 3-way routing: SENT outcomes update response time + edit distance, DISMISSED increments cr_dismisscount, EXPIRED terminates without profile update
- Added output envelope wrapping to Flow 6 (Daily Briefing) so cr_fulljson conforms to output-schema.json with draft_payload field enabling BriefingCard.tsx rendering (resolves I-15)
- Updated Flow 7 (Staleness Monitor) to set NUDGE and EXPIRED via discrete cr_cardstatus column, including original card status update for frontend detection (resolves I-02, I-03)
- Enhanced Flow 8 (Command Execution) with F-02 response format contract, trigger option documentation, and R-18 Orchestrator tool action registration guide
- Updated Flow 9 (Sender Profile Analyzer) categorization to use 5-interaction minimum threshold with profile-level counters, documented R-17 known gap
- Removed duplicate Flow 6 and Flow 7 sections (consolidated from 2 versions each to single authoritative version)

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix Card Outcome Tracker + Daily Briefing + Staleness Monitor** - `26c5566` (fix)
2. **Task 2: Enhance Command Execution + Sender Profile Analyzer** - `40640a1` (feat)

## Files Created/Modified

- `enterprise-work-assistant/docs/agent-flows.md` - Fixed all 5 flow specifications: DISMISSED/SENT_EDITED branches, output envelope wrapping, NUDGE discrete column, F-02 response format, dismiss_rate categorization

## Decisions Made

- NUDGE status must be set on both the new nudge card AND the original overdue card via discrete cr_cardstatus column -- without updating the original, useCardData.ts cannot detect stale cards
- Output envelope wrapping wraps the raw briefing JSON inside the standard output-schema.json structure with draft_payload, allowing BriefingCard.tsx to parse briefing data consistently
- Sender categorization simplified to use profile-level counters (cr_responsecount + cr_dismisscount) with minimum 5 interactions threshold, avoiding per-query card outcome aggregation
- Edit distance for SENT_EDITED uses 0/1 boolean (edited vs not edited) for MVP -- full Levenshtein requires custom connector or Azure Function
- R-17 classified as WARN deferral: sender analytics categorize senders correctly, but the agent does not yet consume SENDER_PROFILE input variable for adaptive triage

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed duplicate Flow 6 and Flow 7 sections**
- **Found during:** Task 1
- **Issue:** agent-flows.md contained two complete versions each of Flow 6 (Daily Briefing) and Flow 7 (Staleness Monitor) -- earlier Sprint 2 detailed version and later Sprint 3/4 condensed version. Duplicate specs would cause confusion about which is authoritative.
- **Fix:** Removed the condensed duplicate versions, kept and enhanced the detailed versions
- **Files modified:** enterprise-work-assistant/docs/agent-flows.md
- **Committed in:** 26c5566 (Task 1 commit)

**2. [Rule 2 - Missing Critical] Updated intro text to reflect 9 flows instead of 3**
- **Found during:** Task 1
- **Issue:** File intro said "three Power Automate agent flows" but file contains 9 flows
- **Fix:** Updated intro to say "nine Power Automate flows" with description of all flow categories
- **Files modified:** enterprise-work-assistant/docs/agent-flows.md
- **Committed in:** 26c5566 (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 missing critical)
**Impact on plan:** Both fixes necessary for document accuracy and consistency. No scope creep.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Wave 2 flow spec fixes complete, unblocking Wave 3 frontend fixes (13-03)
- Flow 5 DISMISSED branch enables dismiss_rate data pipeline for sender intelligence
- Flow 6 output envelope wrapping (I-15) enables BriefingCard.tsx parseBriefing() fix in F-01
- Flow 7 NUDGE discrete column (I-02) enables useCardData.ts card_status ingestion fix in F-01
- Flow 7 EXPIRED setting (I-03) clarifies EXPIRED writer for frontend status handling
- Flow 8 response format documentation enables F-02 (CommandBar response property) fix
- Flow 9 categorization logic verified correct with 5-interaction threshold

## Self-Check: PASSED

All files verified present. Both task commits (26c5566, 40640a1) verified in git log.

---
*Phase: 13-remediation*
*Completed: 2026-02-28*
