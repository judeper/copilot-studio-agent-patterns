---
phase: 15-workflow-completeness
plan: 02
subsystem: database, flows, ui
tags: [dataverse, power-automate, canvas-app, briefing-schedule, per-user-config]

# Dependency graph
requires:
  - phase: 15-01
    provides: "Reminder firing flow and trigger type Compose fix"
  - phase: 14-02
    provides: "Sender profile upsert pattern in Dataverse"
provides:
  - "BriefingSchedule Dataverse table schema (briefingschedule-table.json)"
  - "Per-user schedule-aware Flow 6 with 15-minute recurrence"
  - "Canvas App briefing schedule configuration UI (section 11)"
  - "Provisioning script creates BriefingSchedule table + cr_reminderdue column"
affects: [phase-16-fluent-ui-migration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-user schedule via Dataverse table + frequent polling flow"
    - "Timezone-aware time matching in Power Automate (convertTimeZone)"
    - "Canvas App upsert pattern with Patch + LookUp fallback"

key-files:
  created:
    - "enterprise-work-assistant/schemas/briefingschedule-table.json"
  modified:
    - "enterprise-work-assistant/docs/agent-flows.md"
    - "enterprise-work-assistant/docs/canvas-app-setup.md"
    - "enterprise-work-assistant/docs/deployment-guide.md"
    - "enterprise-work-assistant/scripts/provision-environment.ps1"

key-decisions:
  - "15-minute polling interval for Flow 6 balances timeliness vs Power Automate run quota"
  - "One row per user in BriefingSchedule table with Owner field as user link"
  - "Deduplication built into per-user loop (steps 2d-2e) instead of separate pre-check"

patterns-established:
  - "Per-user config table pattern: Dataverse table with Owner field, Canvas App upsert UI, flow reads at execution time"
  - "Timezone-aware scheduling: convertTimeZone + day-of-week matching in Power Automate"

requirements-completed: [WKFL-02]

# Metrics
duration: 5min
completed: 2026-02-28
---

# Phase 15 Plan 02: BriefingSchedule Table & Per-User Daily Briefing Summary

**BriefingSchedule Dataverse table with per-user schedule config, 15-minute polling Flow 6, and Canvas App schedule UI**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-01T02:05:59Z
- **Completed:** 2026-03-01T02:11:36Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Created BriefingSchedule Dataverse table schema with 6 columns (user display name, schedule hour, schedule minute, schedule days, timezone, enabled flag)
- Rewrote Flow 6 from fixed weekly recurrence to 15-minute polling with per-user schedule matching, timezone-aware time comparison, and built-in deduplication
- Added Canvas App briefing schedule configuration section with hour/minute/day/timezone controls and Patch upsert formula
- Updated provisioning script with BriefingSchedule table creation (section 4b) and cr_reminderdue column for AssistantCards table (section 3e)
- Updated deployment guide to replace BriefingScheduleTime cron env var with BriefingSchedule table reference

## Task Commits

Each task was committed atomically:

1. **Task 1: Create BriefingSchedule Dataverse table schema and update provisioning** - `7cf1ccf` (feat)
2. **Task 2: Update Flow 6 to read schedule from Dataverse and add Canvas App UI instructions** - `4059e20` (feat)

## Files Created/Modified
- `enterprise-work-assistant/schemas/briefingschedule-table.json` - BriefingSchedule Dataverse table definition with 6 columns
- `enterprise-work-assistant/scripts/provision-environment.ps1` - Added BriefingSchedule table creation (section 4b) and cr_reminderdue column (section 3e)
- `enterprise-work-assistant/docs/deployment-guide.md` - Replaced BriefingScheduleTime cron var with BriefingSchedule table reference
- `enterprise-work-assistant/docs/agent-flows.md` - Rewrote Flow 6 trigger, added schedule-aware loop (steps 1-2e), renumbered existing steps (3-13), updated flow diagram and deployment checklist
- `enterprise-work-assistant/docs/canvas-app-setup.md` - Added section 11 with BriefingSchedule data source, schedule controls, Patch upsert formula, and existing schedule loading

## Decisions Made
- 15-minute polling interval for Flow 6 (same rationale as Flow 10 Reminder Firing -- balances timeliness vs run quota)
- One row per user design with Owner field linking schedule to user (matches Dataverse ownership model)
- Built deduplication into the per-user loop (steps 2d-2e) rather than keeping the old separate pre-check -- cleaner with multi-user support
- Used Dataverse Web API pattern for provisioning (consistent with existing SenderProfile table creation) rather than PAC CLI shorthand

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added cr_reminderdue column to provisioning script**
- **Found during:** Task 1 (provisioning script update)
- **Issue:** The cr_reminderdue column was defined in dataverse-table.json and referenced in agent-flows.md (Flow 10) but missing from provision-environment.ps1. Plan mentioned adding it but it needed the full Dataverse Web API column creation pattern.
- **Fix:** Added section 3e with DateTimeAttributeMetadata definition for cr_reminderdue on the AssistantCards table
- **Files modified:** enterprise-work-assistant/scripts/provision-environment.ps1
- **Verification:** grep confirms cr_reminderdue present in script
- **Committed in:** 7cf1ccf (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Auto-fix was explicitly called for in the plan. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 15 complete (both plans done)
- BriefingSchedule table ready for Phase 16 Fluent UI migration (BriefingCard.tsx React component can read schedule state)
- All Flow 6 references updated -- ready for next phase

## Self-Check: PASSED

- briefingschedule-table.json: FOUND
- 15-02-SUMMARY.md: FOUND
- Commit 7cf1ccf: FOUND
- Commit 4059e20: FOUND

---
*Phase: 15-workflow-completeness*
*Completed: 2026-02-28*
