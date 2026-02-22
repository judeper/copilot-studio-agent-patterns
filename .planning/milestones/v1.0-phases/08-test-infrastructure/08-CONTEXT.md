# Phase 8: Test Infrastructure and Unit Tests - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Configure Jest and React Testing Library for the PCF project, then write unit tests for the useCardData hook, App.tsx filter logic, and component rendering (CardItem, CardDetail, CardGallery, FilterBar). Also covers the urlSanitizer utility from Phase 5. This phase delivers working tests and test infrastructure — no new features or component changes.

</domain>

<decisions>
## Implementation Decisions

### Test file organization
- Dedicated `test/` directory for shared setup: jest config, PCF mocks, test utilities, fixture files
- Test runner command and naming convention are Claude's discretion

### Mock data approach
- Mock data must mirror the actual Copilot Studio JSON output format — realistic test data
- Shared fixture files in a central location (e.g., `test/fixtures/`)
- Fixtures include both valid data AND edge-case variants as named exports (validItems, malformedJson, emptyDataset, etc.)
- Fixtures include data for all three triage tiers: tier1Items, tier2Items, tier3Items with tier-specific fields

### Coverage expectations
- Enforce 80% minimum coverage threshold
- Threshold applies per-file, not as an overall average — every file must meet the bar individually
- Test the urlSanitizer utility in addition to the 4 required test areas (TEST-01 through TEST-04)

### PCF mock strategy
- Render real Fluent UI components in tests (not mocked) — catches integration issues, more realistic
- Create a custom `renderWithProviders()` helper that wraps components in FluentProvider for theming
- Document PCF mock setup with comments explaining why each mock exists — this is a reference pattern for other developers
- ComponentFramework mock approach is Claude's discretion (factory vs static)

### Claude's Discretion
- Test file location (co-located vs separate `__tests__` dir)
- Test file naming convention (.test.tsx vs .spec.tsx)
- Test runner scripts (npm scripts vs npx jest only)
- ComponentFramework mock implementation (factory function vs static object)

</decisions>

<specifics>
## Specific Ideas

- This is a reference pattern — tests should demonstrate best practices that other developers can learn from
- PCF mock documentation matters because the ComponentFramework mocking setup is non-obvious and PCF-specific

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-test-infrastructure*
*Context gathered: 2026-02-21*
