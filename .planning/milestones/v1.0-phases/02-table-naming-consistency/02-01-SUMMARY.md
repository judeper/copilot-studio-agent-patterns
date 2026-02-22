---
phase: 02-table-naming-consistency
plan: 01
subsystem: infra
tags: [powershell, dataverse, naming-conventions, audit, cr_assistantcard]

# Dependency graph
requires:
  - phase: 01-output-schema-contract
    provides: Correct schema definitions (tableName, entitySetName) as source of truth
provides:
  - Reusable PowerShell audit script for table naming convention validation
  - Zero-violation confirmation of cr_assistantcard singular/plural naming across codebase
affects: [06-powershell-script-fixes, 08-test-infrastructure-and-unit-tests]

# Tech tracking
tech-stack:
  added: []
  patterns: [context-sensitive pattern classification, PowerShell Get-ChildItem + regex audit]

key-files:
  created:
    - enterprise-work-assistant/scripts/audit-table-naming.ps1
  modified: []

key-decisions:
  - "Audit script self-excludes by filename match rather than pattern exclusion"
  - "Write-Host display strings classified as EXCLUDED (prose) even when containing functional logical name"
  - "All markdown file references classified as EXCLUDED regardless of inline code blocks"

patterns-established:
  - "Context-sensitive naming audit: classify references by surrounding API context, not just string matching"
  - "Audit script convention: colored output (Green=correct, Red=violation, DarkGray=excluded), summary counts, non-zero exit on violations"

requirements-completed: [SCHM-07]

# Metrics
duration: 3min
completed: 2026-02-21
---

# Phase 2 Plan 01: Table Naming Audit Summary

**PowerShell audit script validates cr_assistantcard singular/plural naming across 27 files with context-sensitive classification -- zero violations confirmed**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-21T05:49:04Z
- **Completed:** 2026-02-21T05:51:48Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Created `audit-table-naming.ps1` with context-sensitive classification that distinguishes metadata (singular), OData (plural), primary key, application-level, and prose contexts
- Audit scans 27 files, identifies 16 with references, classifies 97 total matches (23 correct, 74 excluded, 0 violations)
- Confirmed zero violations across all schema files, PowerShell scripts, TypeScript code, and documentation
- Script follows existing project conventions (comment-based help, param block, section separators, colored Write-Host output)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create PowerShell audit script for table naming conventions** - `3a7e477` (feat)
2. **Task 2: Run audit and fix any violations discovered** - No commit (zero violations found, no file changes)

## Files Created/Modified
- `enterprise-work-assistant/scripts/audit-table-naming.ps1` - Reusable naming convention audit script with context-sensitive classification

## Decisions Made
- **Self-exclusion approach:** The audit script excludes itself by filename match rather than trying to classify its own pattern-definition strings. This is simpler and more reliable than trying to parse string literals vs. functional references within the script itself.
- **Write-Host classification:** Lines with `Write-Host` are classified as EXCLUDED (prose) even when displaying functional values like the logical name. The net correctness impact is the same (not a violation), and prose exclusion is the safer default.
- **Markdown blanket exclusion:** All references in .md files are classified as EXCLUDED since markdown is documentation prose, not functional code. This avoids false positives on inline code examples in documentation.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- SCHM-07 satisfied: table naming consistency verified by automated audit
- Audit script can be re-run after future changes to catch regressions
- Phase 3 (PCF Build Configuration) and Phase 6 (PowerShell Script Fixes) can proceed

## Self-Check: PASSED

- FOUND: enterprise-work-assistant/scripts/audit-table-naming.ps1
- FOUND: 02-01-SUMMARY.md
- FOUND: commit 3a7e477

---
*Phase: 02-table-naming-consistency*
*Completed: 2026-02-21*
