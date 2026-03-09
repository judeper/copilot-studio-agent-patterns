# Intelligent Work Layer — Code App Dashboard

The forward-architecture React dashboard for the Intelligent Work Layer, built as a Power Platform Code App (Vite + React 18 + TypeScript). Replaces the legacy PCF + Canvas App approach.

## Quick Start (No Power Platform Required)

```bash
npm install
npm run dev          # http://localhost:3000 — dashboard with mock data
```

That's it. The app ships with `MockCardDataService` and 9 sample cards covering email drafts, meeting prep, stale tasks, and proactive alerts. No Power Platform environment, Dataverse, or credentials needed.

## What You'll See

- **Status bar** — action count, quiet mode indicator, memory status
- **Filter bar** — filter by Email/Teams/Calendar/Proactive/Stale, sort by newest/priority/staleness, quiet mode toggle
- **Card gallery** — grouped into Action Required, Proactive Alerts, New Signals, FYI, Needs Attention
- **Card detail panel** — click any card to see research, key findings, draft editing, send/dismiss actions
- **Command bar** — "Ask IWL..." prompt with quick chips (mock orchestrator response)
- **Confidence calibration** — click Settings gear for agent performance analytics

## Commands

```bash
npm run dev          # Vite dev server on port 3000
npm run build        # tsc + vite build → dist/
npm run test         # vitest (199 tests, 18 files)
npm run test:watch   # vitest in watch mode
npm run test:coverage # vitest with 80% per-file threshold
npm run lint         # eslint src --ext .ts,.tsx

# Single test file:
npx vitest run src/components/__tests__/CardItem.test.tsx
```

## Project Structure

```
src/
├── components/         # 11 React components (App, CardGallery, CardDetail, etc.)
├── hooks/useCards.ts   # Data hook — wraps CardDataService
├── services/           # CardDataService interface + MockCardDataService
├── utils/              # compositeSort, focusUtils, levenshtein, urlSanitizer
├── fixtures/           # 9 sample AssistantCards for offline dev
├── styles/             # AssistantDashboard.css (warm-gray palette, WCAG AA)
└── test/               # Vitest setup, helpers, fixtures
```

## Connecting to Live Dataverse

To replace mock data with real Dataverse cards:

1. Provision environment: `pwsh ../scripts/provision-environment.ps1`
2. Add data source: `pac code add-data-source -a "shared_commondataserviceforapps" -c "<connection-id>" -t "cr_assistantcards"`
3. Implement `CardDataService` interface against the generated typed services
4. Deploy: `npm run build && pac code push`

See [../docs/code-app-migration.md](../docs/code-app-migration.md) for architecture details.
