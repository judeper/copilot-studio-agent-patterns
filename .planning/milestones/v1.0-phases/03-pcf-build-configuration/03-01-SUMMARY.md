---
phase: 03-pcf-build-configuration
plan: 01
subsystem: ui
tags: [pcf, fluent-ui, bun, eslint, manifest, typescript]

# Dependency graph
requires:
  - phase: 01-schema-fixes
    provides: Correct AssistantCard type definitions (item_summary is non-nullable string)
provides:
  - Clean-building PCF control with correct manifest, consolidated imports, and Bun lockfile
  - Zero-error, zero-warning build and lint pipeline
  - postinstall script for pcf-scripts manifest schema patching
affects: [04-component-code-fixes, 05-prompt-fixes, 08-tests]

# Tech tracking
tech-stack:
  added: ["@types/powerapps-component-framework ^1.3.18", "bun 1.3.8 (package manager)"]
  patterns: ["postinstall schema patching for pcf-scripts platform-library support", "consolidated Fluent UI imports from @fluentui/react-components facade"]

key-files:
  created:
    - enterprise-work-assistant/src/scripts/patch-manifest-schema.js
    - enterprise-work-assistant/src/bun.lock
  modified:
    - enterprise-work-assistant/src/AssistantDashboard/ControlManifest.Input.xml
    - enterprise-work-assistant/src/AssistantDashboard/components/FilterBar.tsx
    - enterprise-work-assistant/src/AssistantDashboard/components/CardGallery.tsx
    - enterprise-work-assistant/src/AssistantDashboard/components/CardItem.tsx
    - enterprise-work-assistant/src/AssistantDashboard/components/CardDetail.tsx
    - enterprise-work-assistant/src/.eslintrc.json
    - enterprise-work-assistant/src/package.json
    - enterprise-work-assistant/src/AssistantDashboard/hooks/useCardData.ts

key-decisions:
  - "Postinstall patch for pcf-scripts ManifestSchema.json to support platform-library elements -- pcf-scripts ^1.51.1 lacks this in its validation schema"
  - "Added @types/powerapps-component-framework for ComponentFramework namespace types -- was missing from devDependencies causing TS2503 errors"
  - "Fixed useCardData.ts item_summary type from 'as string | null' to String() coercion -- aligns with Phase 01 decision that item_summary is non-nullable"
  - "Bun generates bun.lock (text format) in v1.3.8, not bun.lockb (binary) -- equivalent purpose for deterministic installs"

patterns-established:
  - "Platform-library support: use postinstall script to patch pcf-scripts ManifestSchema.json until Microsoft adds native support"
  - "Import consolidation: all Fluent UI imports from @fluentui/react-components facade, never from @fluentui/react-theme"

requirements-completed: [PCF-01, PCF-05, PCF-06]

# Metrics
duration: 14min
completed: 2026-02-21
---

# Phase 3 Plan 1: PCF Build Configuration Summary

**Fixed manifest platform-library version to 9.46.2, consolidated all Fluent UI imports to @fluentui/react-components, switched to Bun, and achieved zero-error zero-warning build+lint**

## Performance

- **Duration:** 14 min
- **Started:** 2026-02-21T06:40:32Z
- **Completed:** 2026-02-21T06:54:40Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments
- ControlManifest.Input.xml platform-library Fluent version updated from 9.0 to 9.46.2 (current ceiling)
- All @fluentui/react-theme imports eliminated -- tokens now imported from @fluentui/react-components across all 4 affected files
- Duplicate import blocks consolidated in CardItem.tsx and CardDetail.tsx
- Bun configured as package manager with deterministic lockfile (bun.lock)
- ESLint no-console rule updated to allow console.warn for zero-warning lint
- Build and lint both pass clean with zero errors and zero warnings

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix manifest version and consolidate all Fluent UI imports** - `7549892` (fix)
2. **Task 2: Switch to Bun, fix ESLint config, and verify clean build** - `4d0b3a2` (chore)

**Plan metadata:** (pending final commit)

## Files Created/Modified
- `enterprise-work-assistant/src/AssistantDashboard/ControlManifest.Input.xml` - platform-library Fluent version 9.0 -> 9.46.2
- `enterprise-work-assistant/src/AssistantDashboard/components/FilterBar.tsx` - Consolidated imports, eliminated @fluentui/react-theme
- `enterprise-work-assistant/src/AssistantDashboard/components/CardGallery.tsx` - Consolidated imports, eliminated @fluentui/react-theme
- `enterprise-work-assistant/src/AssistantDashboard/components/CardItem.tsx` - Merged duplicate @fluentui/react-components import blocks
- `enterprise-work-assistant/src/AssistantDashboard/components/CardDetail.tsx` - Merged duplicate @fluentui/react-components import blocks
- `enterprise-work-assistant/src/.eslintrc.json` - no-console rule updated to allow console.warn
- `enterprise-work-assistant/src/package.json` - Added postinstall script, added @types/powerapps-component-framework
- `enterprise-work-assistant/src/AssistantDashboard/hooks/useCardData.ts` - Fixed item_summary type narrowing
- `enterprise-work-assistant/src/scripts/patch-manifest-schema.js` - NEW: postinstall script to patch pcf-scripts manifest schema
- `enterprise-work-assistant/src/bun.lock` - NEW: Bun lockfile for deterministic installs

## Decisions Made
- **Postinstall schema patch:** pcf-scripts ^1.51.1 does not include `platform-library` in its ManifestSchema.json validation schema, causing build failure. Added a postinstall script that patches the schema to accept platform-library elements. This is the standard community workaround for virtual PCF controls.
- **ComponentFramework types:** Added `@types/powerapps-component-framework` to devDependencies -- was missing entirely, causing 4 TS2503 namespace errors in index.ts.
- **useCardData type fix:** Changed `item_summary` assignment from `as string | null` to `String()` coercion with empty string fallback, aligning with Phase 01 decision that item_summary is a non-nullable string.
- **bun.lock vs bun.lockb:** Bun 1.3.8 generates `bun.lock` (text format) by default instead of the older `bun.lockb` (binary format). Same purpose for deterministic installs.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] pcf-scripts ManifestSchema.json missing platform-library support**
- **Found during:** Task 2 (bun run build)
- **Issue:** pcf-scripts ^1.51.1 has `additionalProperties: false` on the control schema without a `platform-library` property definition, causing `pcf-1014` manifest validation error. This was a pre-existing build failure (also fails with the original 9.0 version).
- **Fix:** Created `scripts/patch-manifest-schema.js` postinstall script that adds the platform-library property definition to ManifestSchema.json after each install.
- **Files modified:** enterprise-work-assistant/src/scripts/patch-manifest-schema.js (new), enterprise-work-assistant/src/package.json (postinstall script)
- **Verification:** `bun run build` succeeds with zero errors after patch
- **Committed in:** 4d0b3a2 (Task 2 commit)

**2. [Rule 3 - Blocking] Missing @types/powerapps-component-framework**
- **Found during:** Task 2 (bun run build)
- **Issue:** `ComponentFramework` namespace used in index.ts and generated ManifestTypes.d.ts but no type package installed, causing 4 TS2503 errors.
- **Fix:** Installed `@types/powerapps-component-framework ^1.3.18` as devDependency.
- **Files modified:** enterprise-work-assistant/src/package.json
- **Verification:** Build compiles successfully with no namespace errors
- **Committed in:** 4d0b3a2 (Task 2 commit)

**3. [Rule 1 - Bug] useCardData.ts item_summary type mismatch**
- **Found during:** Task 2 (bun run build)
- **Issue:** Line 46 cast `as string | null` assigns nullable type to non-nullable `item_summary: string` field on AssistantCard, causing TS2322 error under strict mode.
- **Fix:** Changed to `String(parsed.item_summary ?? record.getValue("cr_itemsummary") ?? "")` for safe coercion.
- **Files modified:** enterprise-work-assistant/src/AssistantDashboard/hooks/useCardData.ts
- **Verification:** Build compiles with zero type errors
- **Committed in:** 4d0b3a2 (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (1 bug, 2 blocking)
**Impact on plan:** All auto-fixes were required for a successful build. The pre-existing build failures (missing types, schema validation gap, type mismatch) blocked the zero-error build requirement. No scope creep.

## Issues Encountered
- **minimatch ReDoS vulnerability (high):** `bun audit` reports 1 high vulnerability in minimatch <10.2.1 (transitive dependency of eslint, @typescript-eslint, pcf-start). Cannot be resolved without upgrading to ESLint 9+ or @typescript-eslint 8+, which are major version changes out of scope for this phase. Documented for future consideration.
- **Bun lockfile format:** Plan specified `bun.lockb` but Bun 1.3.8 generates `bun.lock` (text format). Functionally equivalent -- text format is actually better for code review.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- PCF control builds and lints clean -- ready for component code fixes in Phase 4
- All Fluent UI imports consolidated to correct facade package
- Build pipeline is deterministic with Bun lockfile
- Known issue: minimatch vulnerability in transitive dependencies (low priority, does not affect runtime)

## Self-Check: PASSED

All 11 files verified present. Both task commits (7549892, 4d0b3a2) verified in git log.

---
*Phase: 03-pcf-build-configuration*
*Completed: 2026-02-21*
