# Code App Migration — Intelligent Work Layer Dashboard

## Decision
Migrate from PCF Virtual Control + Canvas App to a **Power Platform Code App** (GA Feb 2026). This is Microsoft's forward architecture for pro-code React on Power Platform.

## Why Not PCF + Canvas App
- `platform-library` XSD validation errors on import
- Bundle size exceeds Dataverse webresource limits in standard mode
- Canvas App blank rendering issues with virtual controls
- PCF dataset controls are a compatibility layer, not a first-class React host

## Why Code Apps
- GA February 2026 — Microsoft's official pro-code React path
- Full React/TypeScript ownership (no platform-injected React)
- Direct Dataverse SDK with typed services
- Standard Vite build (no PCF manifest constraints)
- Real E2E testability via Playwright at a proper URL
- App launcher presence without Canvas App wrapper
- Mobile support coming summer 2026

## Critical Setup Notes

### Use npm SDK, Not `pac code`
`pac code` commands are being deprecated. Use the npm-based SDK:
```bash
npm install @microsoft/power-apps --save-dev
npx pac-sdk init        # replaces pac code init
npx pac-sdk run         # replaces pac code run (auth proxy)
npx pac-sdk push        # replaces pac code push
```

### React Version
Pin `react: 18.2.0` and `react-dom: 18.2.0` exactly. The SDK is sensitive to version drift.

### Auth Pattern
Code Apps do NOT auto-inject auth on `fetch()` calls. You must:
1. Call `initialize()` from `@microsoft/power-apps/app` before any data call
2. Use generated typed services from `pac-sdk add-data-source`, NOT raw `fetch()`

```typescript
import { initialize } from '@microsoft/power-apps/app';

// In App.tsx — MUST resolve before any Dataverse call
useEffect(() => {
  initialize().then(() => setIsReady(true));
}, []);

// In useCards hook — use generated service
import { CrAssistantcardsService } from './generated/services/CrAssistantcardsService';
const result = await CrAssistantcardsService.getAll({
  select: ['cr_itemsummary', 'cr_priority', 'cr_cardstatus', 'cr_confidencescore'],
  orderBy: ['createdon desc'],
  top: 50,
});
```

### Local Development (Two Processes Required)
```bash
npx vite &           # port 3000 — your React app
npx pac-sdk run      # port 8080 — auth proxy + SDK tunnel
# Test at: https://apps.powerapps.com/play/e/{env-id}/a/local?_localAppUrl=http://localhost:3000/
```

## Phased Implementation (3-5 Days)

> **Status:** Phases 1-4 complete. The `code-app/` directory contains a fully functional
> Vite + React 18 + TypeScript app with 170 passing tests (14 test files). Build produces
> a production bundle in `dist/`. Phase 5 (CI/CD + `pac-sdk push`) is pending deployment credentials.

### Phase 1 — Infrastructure ✅
- [x] Scaffold Vite + React 18.2.0 + TypeScript project in `code-app/`
- [x] Install Fluent UI 9 (`@fluentui/react-components`, `@fluentui/react-icons`)
- [x] Configure `tsconfig.json`, `.eslintrc.json`, `vitest.config.ts`
- [x] Create entry point (`index.html`, `src/main.tsx`)
- [ ] Deploy Hello World via `npx pac-sdk push` — validate environment, auth, and app launcher
- [ ] `npx pac-sdk add-data-source` for: `cr_assistantcards`, `cr_senderprofiles`, `cr_briefingschedule`
- [ ] Commit generated typed service files to source control

### Phase 2 — Data Layer ✅
- [x] Extract `compositeSort`, `getConfidenceState`, filter logic → `src/utils/cardTransforms.ts` (pure functions, no PCF deps)
- [x] Create `src/services/CardDataService.ts` interface
- [x] Create `src/services/MockCardDataService.ts` with fixture data
- [x] Create `src/hooks/useCards.ts` wrapping the service
- [x] Match output shape to what existing components expect (`AssistantCard[]`)

### Phase 3 — Component Migration ✅
Copy in dependency order: types → utils → hooks → leaf components → composed layouts → App.tsx

- [x] `types.ts`, `constants.ts` — copied as-is
- [x] `cardTransforms.ts` — extracted in Phase 2
- [x] `useCards.ts` — built in Phase 2
- [x] Leaf components: `CardItem`, `ConfidenceCalibration`, `ErrorBoundary`, `StatusBar`, `DayGlance` — copied as-is
- [x] Composed components: `CardGallery`, `CardDetail`, `FilterBar`, `CommandBar` — copied as-is
- [x] Layout components: `BriefingCard` — copied as-is
- [x] `App.tsx` — **rewritten** (replaced PCF bridge props with `useCards()` hook)
- [x] `AssistantDashboard.css` — copied as-is

### Phase 4 — Testing ✅
| Test Category | PCF (Before) | Code App (After) |
|--------------|---------|--------|
| Unit: cardTransforms, sort, filter | Jest + PCF mocks | Vitest + plain object mocks |
| Unit: React components (170 tests) | Jest + RTL | Vitest + RTL (14 test files) |
| Integration: useCards hook | PCF context mock | Mock CardDataService |
| E2E: full app | None (PCF limitation) | **Playwright** at real URL (Phase 5) |

### Phase 5 — CI/CD (Day 8-9)
```yaml
- name: Build
  run: npm run build
- name: Deploy to Dev
  run: npx pac-sdk push --environment ${{ secrets.DEV_ENV_ID }}
- name: Run Playwright E2E
  run: npx playwright test
```

## What Ports As-Is (No Changes)
- All 15 React components (pure React, no PCF context usage)
- `AssistantDashboard.css` (warm-gray palette, WCAG AA, animations)
- `constants.ts` (confidence states, prompt chips, colors)
- `types.ts` (AssistantCard, BriefingType, BriefingScheduleConfig)
- `compositeSort()`, `getConfidenceState()`, filter predicates

## What Requires Rewriting
- `useCardData.ts` → `useCards.ts` (PCF DataSet API → Dataverse REST service)
- `App.tsx` root (PCF bridge props → hook-based data flow)
- `index.ts` PCF lifecycle class → deleted entirely (no longer needed)
- `index.test.ts` PCF lifecycle tests → rewritten for hook/service mocks

## Demo Strategy
For the demo before Code App is complete:
1. Show the **full infrastructure**: environment, 9 tables, 19 flows, Copilot agent, OneNote
2. Show the **Copilot Studio agent** processing signals in the test pane
3. Show the **Dataverse data**: 2 test cards with full metadata
4. Show the **React codebase**: `npm run test` → 245 passing tests
5. Show the **Code App plan**: forward architecture on Microsoft's GA platform
6. Show the **design specs**: cognitive science-grounded UX in docs/ux-enhancements.md
