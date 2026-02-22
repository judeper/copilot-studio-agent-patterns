# Phase 8: Test Infrastructure and Unit Tests - Research

**Researched:** 2026-02-21
**Domain:** Jest + React Testing Library for PCF virtual control (TypeScript, Fluent UI v9, React)
**Confidence:** HIGH

## Summary

This phase configures Jest with ts-jest and React Testing Library to test a PCF (PowerApps Component Framework) virtual control built with TypeScript, React, and Fluent UI v9. The codebase has 11 source files under `enterprise-work-assistant/src/AssistantDashboard/` — a PCF entry point (`index.ts`), 5 React components (`App.tsx`, `CardItem.tsx`, `CardDetail.tsx`, `CardGallery.tsx`, `FilterBar.tsx`), a custom hook (`useCardData.ts`), a utility (`urlSanitizer.ts`), types, constants, and generated manifest types.

The critical technical nuance is that this is a **PCF virtual control** — the platform provides React 16.14.0 at runtime, but the project's `node_modules` contains React 19.2.4 (pulled in by Fluent UI v9 dependencies). TypeScript types are pinned to `@types/react@~16.14.0`. Tests will execute against the React 19 runtime in node_modules, which is acceptable since the component code only uses React 16-compatible APIs. The `ComponentFramework` global namespace used in `index.ts` and `ManifestTypes.d.ts` requires mocking.

**Primary recommendation:** Use Jest 29 + ts-jest 29 + `@testing-library/react@16` + `jest-environment-jsdom`, with a dedicated `test/` directory for shared setup (mocks, fixtures, helpers). Create a lightweight custom `ComponentFramework` mock rather than using the heavy `@shko.online/componentframework-mock` library, since we are testing individual React components and hooks — not the full PCF lifecycle.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions
- Dedicated `test/` directory for shared setup: jest config, PCF mocks, test utilities, fixture files
- Mock data must mirror the actual Copilot Studio JSON output format — realistic test data
- Shared fixture files in a central location (e.g., `test/fixtures/`)
- Fixtures include both valid data AND edge-case variants as named exports (validItems, malformedJson, emptyDataset, etc.)
- Fixtures include data for all three triage tiers: tier1Items, tier2Items, tier3Items with tier-specific fields
- Enforce 80% minimum coverage threshold per-file (not overall average)
- Render real Fluent UI components in tests (not mocked) — catches integration issues, more realistic
- Create a custom `renderWithProviders()` helper that wraps components in FluentProvider for theming
- Document PCF mock setup with comments explaining why each mock exists — this is a reference pattern
- Test the urlSanitizer utility in addition to the 4 required test areas (TEST-01 through TEST-04)

### Claude's Discretion
- Test file location (co-located vs separate `__tests__` dir)
- Test file naming convention (.test.tsx vs .spec.tsx)
- Test runner scripts (npm scripts vs npx jest only)
- ComponentFramework mock implementation (factory function vs static object)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TEST-01 | Jest and React Testing Library configured with PCF-compatible setup (transforms, mocks) | Standard Stack section provides exact packages, versions, and jest.config.js settings. Architecture Patterns section covers PCF mock structure and FluentProvider wrapper. |
| TEST-02 | Unit tests for useCardData hook cover JSON parsing, malformed data, empty datasets, and tier-specific behavior | Code Examples section shows renderHook pattern from `@testing-library/react`. Hook accepts DataSet interface that needs mock implementation. Fixture patterns cover all edge cases. |
| TEST-03 | Unit tests for App.tsx filter logic cover category, priority, and triage tier filtering | The `applyFilters` function is a pure function inside App.tsx (not exported). Tests should render App with filter props and verify filtered card output. Code Examples section covers this pattern. |
| TEST-04 | Component render tests for CardItem, CardDetail, CardGallery, and FilterBar verify rendering with valid data | Each component needs FluentProvider wrapping via `renderWithProviders()` helper. Components use Fluent UI v9 components (Card, Badge, Text, Button, Link, Textarea, etc.) which render as real DOM elements. |

</phase_requirements>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| jest | ^29.7.0 | Test runner and assertion library | Industry standard for React/TS projects; ts-jest 29 requires jest 29; stable and well-supported |
| ts-jest | ^29.2.0 | TypeScript preprocessor for Jest | Compiles .ts/.tsx files for Jest without separate build step; aligns major version with jest 29 |
| @testing-library/react | ^16.1.0 | React component rendering and querying for tests | Official React testing recommendation; includes `renderHook` for hook testing; supports React 19 runtime |
| @testing-library/jest-dom | ^6.6.0 | Custom Jest matchers for DOM assertions (toBeInTheDocument, etc.) | Standard companion to Testing Library; provides readable DOM assertions |
| jest-environment-jsdom | ^29.7.0 | Browser-like DOM environment for Jest | Required separately since Jest 28+; provides window, document, etc. for component rendering |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| @types/jest | ^29.5.0 | TypeScript type definitions for Jest globals | Always — provides types for describe, it, expect, jest.fn(), etc. |
| identity-obj-proxy | ^3.0.0 | CSS module mock for Jest | Only if CSS imports appear in test paths; currently no CSS imports in component TS files, but good defensive measure |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ts-jest | babel-jest + @babel/preset-typescript | babel-jest is faster but loses type checking; ts-jest catches type errors during test compilation |
| Custom PCF mocks | @shko.online/componentframework-mock | Full lifecycle mocking library; heavyweight for this use case where we test React components individually, not the PCF control lifecycle |
| jest-environment-jsdom | happy-dom | happy-dom is faster but less browser-compatible; jsdom is the battle-tested standard |

**Installation:**
```bash
bun add -d jest ts-jest @types/jest jest-environment-jsdom @testing-library/react @testing-library/jest-dom identity-obj-proxy
```

**Note on bun:** Project uses bun 1.3.8 for package management (bun.lock exists). Use `bun add -d` instead of `npm install --save-dev`.

## Architecture Patterns

### Recommended Project Structure

```
enterprise-work-assistant/src/
├── AssistantDashboard/          # existing source
│   ├── components/
│   ├── hooks/
│   ├── utils/
│   └── generated/
├── test/                        # NEW — shared test infrastructure
│   ├── jest.config.ts           # Jest configuration
│   ├── jest.setup.ts            # setupFilesAfterSetup — imports jest-dom
│   ├── mocks/
│   │   └── componentFramework.ts  # ComponentFramework namespace mock
│   ├── fixtures/
│   │   └── cardFixtures.ts      # Named exports: validItems, tier1Items, etc.
│   └── helpers/
│       └── renderWithProviders.tsx  # FluentProvider wrapper
├── AssistantDashboard/
│   ├── components/
│   │   └── __tests__/           # Component tests co-located in __tests__ dirs
│   │       ├── App.test.tsx
│   │       ├── CardItem.test.tsx
│   │       ├── CardDetail.test.tsx
│   │       ├── CardGallery.test.tsx
│   │       └── FilterBar.test.tsx
│   ├── hooks/
│   │   └── __tests__/
│   │       └── useCardData.test.ts
│   └── utils/
│       └── __tests__/
│           └── urlSanitizer.test.ts
├── package.json
└── tsconfig.json
```

**Rationale for `__tests__` directories:** Co-locating test files near source makes navigation easy while keeping them in dedicated directories avoids cluttering source folders. The `test/` root directory holds shared infrastructure (mocks, fixtures, helpers) per user decision.

### Pattern 1: Jest Configuration for PCF + TypeScript + Fluent UI v9

**What:** A `jest.config.ts` that handles TypeScript compilation, jsdom environment, module resolution, and coverage thresholds.

**Key considerations:**
- `ts-jest` compiles .ts/.tsx with the existing tsconfig settings
- `testEnvironment: "jest-environment-jsdom"` provides browser globals
- `@fluentui/react-components` ships CJS builds (`lib-commonjs/`), so no `transformIgnorePatterns` overrides needed
- `@fluentui/react-icons` ships CJS builds (`lib-cjs/`), so also safe
- CSS files referenced in ControlManifest.Input.xml are NOT imported in TypeScript — no CSS mock needed for component tests (but include a defensive moduleNameMapper anyway)

**Configuration:**
```typescript
// test/jest.config.ts
import type { Config } from 'jest';

const config: Config = {
    rootDir: '..',
    testEnvironment: 'jest-environment-jsdom',
    preset: 'ts-jest',
    setupFilesAfterSetup: ['<rootDir>/test/jest.setup.ts'],

    // Match test files
    testMatch: ['<rootDir>/AssistantDashboard/**/__tests__/**/*.test.ts?(x)'],

    // TypeScript transform
    transform: {
        '^.+\\.tsx?$': ['ts-jest', {
            tsconfig: '<rootDir>/tsconfig.json',
        }],
    },

    // Module resolution
    moduleNameMapper: {
        '\\.(css|less|scss)$': 'identity-obj-proxy',
    },

    // Coverage
    collectCoverage: true,
    collectCoverageFrom: [
        'AssistantDashboard/**/*.{ts,tsx}',
        '!AssistantDashboard/generated/**',
        '!AssistantDashboard/index.ts',
    ],
    coverageThreshold: {
        global: {
            branches: 80,
            functions: 80,
            lines: 80,
            statements: 80,
        },
    },
};

export default config;
```

### Pattern 2: ComponentFramework Mock

**What:** A mock that satisfies the `ComponentFramework` global namespace used in `index.ts` and `ManifestTypes.d.ts`.
**When to use:** Every test that imports from files referencing `ComponentFramework` types.
**Why custom:** The `@shko.online/componentframework-mock` library mocks the entire PCF lifecycle (init, updateView, getOutputs). Our tests exercise React components directly — we only need the `DataSet` and `DataSetRecord` interfaces that `useCardData.ts` consumes.

**Approach — factory function (recommended):**

```typescript
// test/mocks/componentFramework.ts

/**
 * Minimal ComponentFramework mock for unit testing.
 *
 * PCF virtual controls receive data through the ComponentFramework.PropertyTypes.DataSet
 * interface. The useCardData hook defines its own DataSet/DataSetRecord interfaces that
 * mirror this API surface. This mock creates dataset objects that satisfy those interfaces.
 *
 * Why a factory: Each test gets a fresh dataset instance, avoiding shared mutable state
 * between tests. The factory accepts an array of record data and builds the sortedRecordIds
 * and records map automatically.
 */
export interface MockRecordData {
    id: string;
    values: Record<string, string | number | null>;
    formattedValues?: Record<string, string>;
}

export function createMockDataset(records: MockRecordData[]) {
    return {
        sortedRecordIds: records.map(r => r.id),
        records: Object.fromEntries(
            records.map(r => [
                r.id,
                {
                    getRecordId: () => r.id,
                    getValue: (col: string) => r.values[col] ?? null,
                    getFormattedValue: (col: string) => r.formattedValues?.[col] ?? '',
                },
            ])
        ),
    };
}
```

### Pattern 3: renderWithProviders Helper

**What:** Custom render function wrapping components in `FluentProvider` with a theme.
**Why:** Fluent UI v9 components (Card, Badge, Text, Button, etc.) require FluentProvider in their ancestor tree. Without it, token-based styling breaks silently.

```tsx
// test/helpers/renderWithProviders.tsx
import * as React from 'react';
import { render, RenderOptions } from '@testing-library/react';
import { FluentProvider, webLightTheme } from '@fluentui/react-components';

/**
 * Wraps the component under test in FluentProvider with webLightTheme.
 *
 * All Fluent UI v9 components require a FluentProvider ancestor to resolve
 * design tokens (colors, spacing, typography). Tests that render Fluent
 * components without this wrapper will silently produce unstyled output.
 */
function Wrapper({ children }: { children: React.ReactNode }) {
    return (
        <FluentProvider theme={webLightTheme}>
            {children}
        </FluentProvider>
    );
}

export function renderWithProviders(
    ui: React.ReactElement,
    options?: Omit<RenderOptions, 'wrapper'>,
) {
    return render(ui, { wrapper: Wrapper, ...options });
}
```

### Pattern 4: Fixture Data Structure

**What:** Shared test fixtures as named exports mirroring actual Copilot Studio JSON output.
**Why:** Consistent, realistic test data across all test files; named exports make edge cases discoverable.

```typescript
// test/fixtures/cardFixtures.ts
import type { AssistantCard } from '../../AssistantDashboard/components/types';

export const tier1SkipItem: AssistantCard = {
    id: 'skip-001',
    trigger_type: 'EMAIL',
    triage_tier: 'SKIP',
    item_summary: 'Marketing newsletter from Contoso Weekly — no action needed.',
    priority: null,
    temporal_horizon: null,
    research_log: null,
    key_findings: null,
    verified_sources: null,
    confidence_score: null,
    card_status: 'SUMMARY_ONLY',
    draft_payload: null,
    low_confidence_note: null,
    humanized_draft: null,
    created_on: '2/21/2026 10:30 AM',
};

export const tier2LightItem: AssistantCard = {
    id: 'light-001',
    trigger_type: 'TEAMS_MESSAGE',
    triage_tier: 'LIGHT',
    item_summary: 'Project status update from engineering lead.',
    priority: 'Medium',
    temporal_horizon: 'THIS_WEEK',
    // ... tier-specific: no research_log, simpler key_findings
};

export const tier3FullItem: AssistantCard = {
    id: 'full-001',
    trigger_type: 'EMAIL',
    triage_tier: 'FULL',
    item_summary: 'Contract renewal request from Fabrikam legal team.',
    priority: 'High',
    temporal_horizon: 'TODAY',
    research_log: 'Searched: contract renewal Fabrikam...',
    key_findings: '- Contract expires March 1\n- Auto-renewal clause present',
    verified_sources: [
        { title: 'Fabrikam Contract Portal', url: 'https://fabrikam.example.com/contracts', tier: 1 },
    ],
    confidence_score: 87,
    card_status: 'READY',
    draft_payload: {
        draft_type: 'EMAIL',
        raw_draft: 'Dear Fabrikam team...',
        research_summary: 'Contract analysis complete',
        recipient_relationship: 'External client',
        inferred_tone: 'formal',
        confidence_score: 87,
        user_context: 'Renewal discussion',
    },
    low_confidence_note: null,
    humanized_draft: 'Dear Fabrikam team, regarding the upcoming contract renewal...',
    created_on: '2/21/2026 9:15 AM',
};

// Edge cases
export const malformedJsonRecord = { id: 'bad-001', values: { cr_fulljson: 'not valid json{' } };
export const emptyDataset = { sortedRecordIds: [], records: {} };
export const nullDataset = undefined;
```

### Anti-Patterns to Avoid
- **Mocking Fluent UI components:** User explicitly decided to render real Fluent components. Mocking them (e.g., `jest.mock('@fluentui/react-components')`) defeats the purpose and misses integration issues.
- **Testing implementation details:** Don't test React state internals or hook return values directly when behavior can be asserted through rendered output.
- **Shared mutable state between tests:** Each test should create its own data via factory functions or spread operators on fixture constants.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| DOM environment for tests | Custom JSDOM setup | jest-environment-jsdom | Handles window, document, navigator, matchMedia properly |
| TypeScript compilation for tests | Manual tsc + jest pipeline | ts-jest preset | Handles source maps, diagnostics, JSX transform seamlessly |
| DOM assertion matchers | Custom expect extensions | @testing-library/jest-dom | 20+ matchers (toBeInTheDocument, toHaveTextContent, etc.) battle-tested |
| Component querying | document.querySelector chains | @testing-library/react screen/queries | Accessible queries (getByRole, getByText) resist refactoring |
| Coverage reporting | Manual coverage scripts | Jest built-in coverage (--coverage) | Istanbul instrumentation, threshold enforcement, reporter output |

**Key insight:** PCF testing is unusual because the `ComponentFramework` namespace is globally declared and the dataset API uses getValue/getFormattedValue methods. However, `useCardData.ts` already defines its own `DataSet`/`DataSetRecord` interfaces internally, so mocking only needs to satisfy those interfaces — not the full `ComponentFramework.PropertyTypes.DataSet`.

## Common Pitfalls

### Pitfall 1: matchMedia Not Available in jsdom

**What goes wrong:** Components using `window.matchMedia` (like `usePrefersDarkMode` in `App.tsx`) throw "matchMedia is not a function" in jsdom.
**Why it happens:** jsdom does not implement `matchMedia` by default.
**How to avoid:** Add a `matchMedia` mock in jest.setup.ts:
```typescript
Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: jest.fn().mockImplementation(query => ({
        matches: false,
        media: query,
        onchange: null,
        addListener: jest.fn(),
        removeListener: jest.fn(),
        addEventListener: jest.fn(),
        removeEventListener: jest.fn(),
        dispatchEvent: jest.fn(),
    })),
});
```
**Warning signs:** "TypeError: window.matchMedia is not a function" during test execution.

### Pitfall 2: React Types Mismatch (React 16 Types vs React 19 Runtime)

**What goes wrong:** TypeScript compiler errors in test files because `@types/react@~16.14.0` doesn't include APIs available in React 19 (e.g., React 18+ `renderHook` types from `@testing-library/react`).
**Why it happens:** The PCF project pins `@types/react` to 16.14 for compatibility with the platform-library declaration, but `node_modules/react` contains React 19.2.4 (pulled by Fluent UI deps).
**How to avoid:** Use a separate `tsconfig.test.json` that extends the main tsconfig but overrides `typeRoots` to include `@types/jest` and `@testing-library/jest-dom` types. Alternatively, if type conflicts arise, add specific `@ts-expect-error` comments or widen the `@types/react` range for the test tsconfig only.
**Warning signs:** TS errors about missing properties on React namespace, or "renderHook" not found in types.

### Pitfall 3: Coverage Threshold Per-File Misconfiguration

**What goes wrong:** Global coverage passes 80% but individual files have low coverage; or coverage enforcement is overly strict on generated/boilerplate files.
**Why it happens:** Jest's `coverageThreshold.global` checks the aggregate, not per-file. The user wants per-file enforcement.
**How to avoid:** Use glob patterns in `coverageThreshold` to enforce per-file thresholds:
```typescript
coverageThreshold: {
    'AssistantDashboard/**/*.{ts,tsx}': {
        branches: 80,
        functions: 80,
        lines: 80,
        statements: 80,
    },
},
```
Exclude `generated/` and `index.ts` (PCF lifecycle class) from coverage with `collectCoverageFrom` negation patterns.
**Warning signs:** `jest --coverage` passes but individual file coverage columns show < 80%.

### Pitfall 4: applyFilters is Not Exported

**What goes wrong:** Attempting to directly import and test `applyFilters` from `App.tsx` fails because it's a module-private function.
**Why it happens:** `applyFilters` is declared as a plain function inside the module scope of `App.tsx`, not exported.
**How to avoid:** Test filtering behavior through the rendered `App` component — pass different `filterTriggerType`/`filterPriority` props and assert on which cards appear in the output. This is the correct Testing Library approach (test behavior, not implementation).
**Warning signs:** Import error for `applyFilters`, temptation to export it just for testing.

### Pitfall 5: Fluent UI v9 Token Values in jsdom

**What goes wrong:** Assertions on computed styles fail because Fluent UI tokens resolve to CSS custom properties, not actual color values, in jsdom.
**Why it happens:** jsdom doesn't evaluate CSS custom properties. `tokens.colorPaletteRedBorder2` resolves to `var(--colorPaletteRedBorder2)` at runtime in a real browser, but in jsdom the computed style is empty.
**How to avoid:** Don't assert on computed CSS values. Instead, assert on rendered text content, element presence, ARIA attributes, and component structure. For priority colors, assert that the inline style object contains the expected token reference.
**Warning signs:** Tests checking `getComputedStyle` return empty strings.

## Code Examples

### Example 1: useCardData Hook Test

```typescript
// AssistantDashboard/hooks/__tests__/useCardData.test.ts
import { renderHook } from '@testing-library/react';
import { useCardData } from '../useCardData';
import { createMockDataset } from '../../../test/mocks/componentFramework';

describe('useCardData', () => {
    it('parses valid JSON records into AssistantCard array', () => {
        const dataset = createMockDataset([{
            id: 'rec-1',
            values: {
                cr_fulljson: JSON.stringify({
                    trigger_type: 'EMAIL',
                    triage_tier: 'FULL',
                    item_summary: 'Test item',
                    priority: 'High',
                    confidence_score: 85,
                    card_status: 'READY',
                }),
                cr_humanizeddraft: null,
                createdon: null,
            },
            formattedValues: { createdon: '2/21/2026' },
        }]);

        const { result } = renderHook(() => useCardData(dataset, 1));
        expect(result.current).toHaveLength(1);
        expect(result.current[0].trigger_type).toBe('EMAIL');
        expect(result.current[0].priority).toBe('High');
    });

    it('returns empty array for undefined dataset', () => {
        const { result } = renderHook(() => useCardData(undefined, 1));
        expect(result.current).toEqual([]);
    });

    it('skips records with malformed JSON', () => {
        const dataset = createMockDataset([
            { id: 'bad', values: { cr_fulljson: '{invalid' } },
            { id: 'good', values: { cr_fulljson: JSON.stringify({ item_summary: 'Valid' }) } },
        ]);

        const { result } = renderHook(() => useCardData(dataset, 1));
        expect(result.current).toHaveLength(1);
        expect(result.current[0].id).toBe('good');
    });
});
```

### Example 2: Filter Logic Test via App Component

```tsx
// AssistantDashboard/components/__tests__/App.test.tsx
import { screen } from '@testing-library/react';
import { App } from '../App';
import { renderWithProviders } from '../../../test/helpers/renderWithProviders';
import { tier2LightItem, tier3FullItem } from '../../../test/fixtures/cardFixtures';

describe('App filter logic', () => {
    const cards = [tier2LightItem, tier3FullItem];

    it('shows all cards when no filters are active', () => {
        renderWithProviders(
            <App
                cards={cards}
                filterTriggerType=""
                filterPriority=""
                filterCardStatus=""
                filterTemporalHorizon=""
                width={800}
                height={600}
                onSelectCard={jest.fn()}
                onEditDraft={jest.fn()}
                onDismissCard={jest.fn()}
            />
        );
        expect(screen.getByText(tier2LightItem.item_summary)).toBeInTheDocument();
        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();
    });

    it('filters by priority', () => {
        renderWithProviders(
            <App
                cards={cards}
                filterTriggerType=""
                filterPriority="High"
                filterCardStatus=""
                filterTemporalHorizon=""
                width={800}
                height={600}
                onSelectCard={jest.fn()}
                onEditDraft={jest.fn()}
                onDismissCard={jest.fn()}
            />
        );
        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();
        expect(screen.queryByText(tier2LightItem.item_summary)).not.toBeInTheDocument();
    });
});
```

### Example 3: Component Render Test

```tsx
// AssistantDashboard/components/__tests__/CardItem.test.tsx
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { CardItem } from '../CardItem';
import { renderWithProviders } from '../../../test/helpers/renderWithProviders';
import { tier3FullItem } from '../../../test/fixtures/cardFixtures';

describe('CardItem', () => {
    it('renders card summary and status badge', () => {
        renderWithProviders(
            <CardItem card={tier3FullItem} onClick={jest.fn()} />
        );
        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();
        expect(screen.getByText('READY')).toBeInTheDocument();
    });

    it('calls onClick with card id when clicked', async () => {
        const handleClick = jest.fn();
        renderWithProviders(
            <CardItem card={tier3FullItem} onClick={handleClick} />
        );
        await userEvent.click(screen.getByText(tier3FullItem.item_summary));
        expect(handleClick).toHaveBeenCalledWith(tier3FullItem.id);
    });
});
```

### Example 4: urlSanitizer Utility Test

```typescript
// AssistantDashboard/utils/__tests__/urlSanitizer.test.ts
import { isSafeUrl, SAFE_PROTOCOLS } from '../urlSanitizer';

describe('isSafeUrl', () => {
    it('accepts https URLs', () => {
        expect(isSafeUrl('https://example.com')).toBe(true);
    });

    it('accepts mailto URLs', () => {
        expect(isSafeUrl('mailto:user@example.com')).toBe(true);
    });

    it('rejects javascript: protocol', () => {
        expect(isSafeUrl('javascript:alert(1)')).toBe(false);
    });

    it('rejects data: protocol', () => {
        expect(isSafeUrl('data:text/html,<script>alert(1)</script>')).toBe(false);
    });

    it('returns false for null/undefined/empty', () => {
        expect(isSafeUrl(null)).toBe(false);
        expect(isSafeUrl(undefined)).toBe(false);
        expect(isSafeUrl('')).toBe(false);
    });

    it('handles case-insensitive protocol', () => {
        expect(isSafeUrl('HTTPS://EXAMPLE.COM')).toBe(true);
    });
});
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Enzyme + shallow rendering | React Testing Library + real rendering | 2020-2023 migration | Tests are less brittle, test behavior not implementation |
| `@testing-library/react-hooks` (separate package) | `renderHook` built into `@testing-library/react` v13+ | RTL v13 (2022) | One fewer dependency; hook tests use same library |
| jest-environment-jsdom bundled with jest | jest-environment-jsdom as separate package | Jest 28 (2022) | Must install `jest-environment-jsdom` separately |
| `@types/testing-library__jest-dom` (DefinitelyTyped) | Types bundled in `@testing-library/jest-dom` v6+ | jest-dom v6 (2023) | No separate `@types` package needed; import in setup file |

**Deprecated/outdated:**
- Enzyme: Not compatible with React 18+; no longer maintained
- `@testing-library/react-hooks`: Deprecated; functionality merged into `@testing-library/react`
- `@testing-library/jest-dom/extend-expect`: Removed in v6; use `import '@testing-library/jest-dom'` instead

## Open Questions

1. **tsconfig.test.json necessity**
   - What we know: The main tsconfig targets ES2015 modules and extends pcf-scripts/tsconfig_base.json. Jest with ts-jest needs CommonJS module output. ts-jest can override `module` via its own config.
   - What's unclear: Whether ts-jest's `tsconfig` option can override `module: "ES2015"` to `module: "CommonJS"` without a separate tsconfig file, or if a `tsconfig.test.json` is needed.
   - Recommendation: Create a `tsconfig.test.json` that extends the main tsconfig and overrides `module` to `CommonJS` and adds test-specific `types`. This is clean and explicit.

2. **Per-file coverage threshold syntax**
   - What we know: Jest supports glob-based thresholds in `coverageThreshold`. User wants 80% per-file, not just global.
   - What's unclear: Whether glob patterns like `./AssistantDashboard/**/*.{ts,tsx}` apply per-file or as an aggregate over matched files.
   - Recommendation: Start with global threshold at 80% and verify per-file behavior during implementation. Adjust to per-file glob patterns if Jest's glob threshold applies per-file (documentation indicates it does for file paths, but glob aggregation behavior needs validation).

3. **userEvent version**
   - What we know: `@testing-library/user-event` is the standard for simulating user interactions (click, type). The latest is v14+.
   - What's unclear: Whether it's needed for the basic render tests required in this phase, or if click handlers can be tested via `fireEvent` from `@testing-library/react`.
   - Recommendation: Include `@testing-library/user-event@^14` for idiomatic click testing on CardItem and CardDetail action buttons.

## Sources

### Primary (HIGH confidence)
- Project source code inspection — all 11 source files read and analyzed for test surface
- `package.json` — confirmed dependencies: `@fluentui/react-components@^9.46.0`, `@fluentui/react-icons@^2.0.245`, `@types/react@~16.14.0`, `typescript@^4.9.5`
- `@fluentui/react-components@9.73.0` package.json — confirmed `lib-commonjs/` CJS entry point (no special Jest transforms needed)
- `@fluentui/react-icons@2.0.319` package.json — confirmed `lib-cjs/` CJS entry point
- React 19.2.4 confirmed in node_modules (test runtime)
- [Jest Configuration Docs](https://jestjs.io/docs/configuration) — coverageThreshold, testEnvironment, transform, moduleNameMapper
- [React Testing Library Setup](https://testing-library.com/docs/react-testing-library/setup/) — custom render wrapper pattern
- [React Testing Library API](https://testing-library.com/docs/react-testing-library/api/) — renderHook included in v13+

### Secondary (MEDIUM confidence)
- [Fluent UI Testing with Jest docs](https://github.com/microsoft/fluentui/blob/master/docs/react-v9/contributing/testing-with-jest.md) — confirms Jest + RTL as standard for Fluent v9 testing
- [Fluent UI Issue #32949](https://github.com/microsoft/fluentui/issues/32949) — `transformIgnorePatterns` may be needed if CJS build has class transpilation issues (version-dependent; current installed version 9.73.0 may not be affected)
- [@testing-library/react npm](https://www.npmjs.com/package/@testing-library/react) — v16.x supports React 19
- [@testing-library/jest-dom npm](https://www.npmjs.com/package/@testing-library/jest-dom) — v6+ bundles own types, no @types package needed
- [ComponentFramework-Mock](https://github.com/Shko-Online/ComponentFramework-Mock) — full PCF lifecycle mocking (evaluated but not recommended for this use case)

### Tertiary (LOW confidence)
- matchMedia mock pattern — widely used community pattern, not from official Jest docs
- Per-file coverage threshold glob behavior — needs runtime validation during implementation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — packages verified against project dependencies, CJS compatibility confirmed, version constraints validated
- Architecture: HIGH — codebase fully inspected; all 11 source files read; test targets clearly identified; patterns align with Testing Library best practices
- Pitfalls: HIGH — matchMedia, React types mismatch, and Fluent UI token issues verified against actual code inspection; applyFilters non-export confirmed by reading App.tsx

**Research date:** 2026-02-21
**Valid until:** 2026-03-21 (30 days — stable ecosystem, no rapidly moving targets)
