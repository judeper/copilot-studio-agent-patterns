# Copilot Instructions

## Architecture

This repo contains production-ready patterns for building autonomous agents on the Microsoft Copilot Studio + Power Platform stack. Each solution is a self-contained folder with prompts, schemas, provisioning scripts, and UI components.

The primary solution is **Enterprise Work Assistant** (`enterprise-work-assistant/`), an AI assistant that triages emails, Teams messages, and calendar events. The data flow is:

1. **Power Automate Agent Flows** (3 triggers: Email, Teams, Calendar) intercept signals, extract payloads, and invoke the Copilot Studio agent
2. **Copilot Studio Agent** triages (SKIP/LIGHT/FULL), researches across 5 tiers, scores confidence, and returns structured JSON
3. **Humanizer Connected Agent** rewrites drafts for FULL-tier items with confidence ≥ 40
4. **Dataverse** (`AssistantCards` table) persists results with ownership-based row-level security
5. **Canvas App + PCF React Dashboard** renders a single-pane-of-glass UI

The PCF component is a **virtual** React control (shares the platform React tree — does not bundle its own React). It uses a **dataset-type** binding where the Canvas app handles the Dataverse connection and passes pre-filtered records.

The **Agent Cost Governance — PAYGO** solution (`agent-cost-governance-paygo/`) is a Tier-2 Cross-Cutting Governance solution providing leadership-quality PAYGO cost visibility for Copilot Studio agents. It uses Azure Cost Management + Power BI (no PCF component). Key artifacts: DAX measures, PowerShell billing policy script (Power Platform REST API), ARM budget alert template, and FSI regulatory alignment documents (GLBA, SOX, FINRA, OCC). Known limitation: Azure Cost Management reports at environment level, not per-agent.

## Build, Test, and Lint (PCF Component)

All commands run from `enterprise-work-assistant/src/`:

```shell
npm install          # also runs postinstall to patch manifest schema
npm run build        # pcf-scripts build
npm run lint         # eslint AssistantDashboard --ext .ts,.tsx
npm run test         # jest (all tests)
npm run test:coverage # jest with 80% per-file threshold

# Single test file:
npx jest --config test/jest.config.ts AssistantDashboard/components/__tests__/CardItem.test.tsx

# Deploy solution (from enterprise-work-assistant/scripts/):
pwsh deploy-solution.ps1 -EnvironmentId "<env-id>"
```

## Key Conventions

### Schema-Prompt-Code Contract

The output JSON schema (`schemas/output-schema.json`), agent prompts (`prompts/`), TypeScript types (`src/AssistantDashboard/components/types.ts`), and Dataverse table definitions (`schemas/dataverse-table.json`) must all stay in sync. When changing a field, update all four locations.

### PCF Component Patterns

- **Platform React**: The control uses `<platform-library name="React">` and `<platform-library name="Fluent">` — never add React or Fluent UI to `dependencies` in package.json (they belong in `devDependencies` only for types/testing).
- **Fluent UI v9**: All UI uses `@fluentui/react-components` (v9) and `@fluentui/react-icons`. Use Fluent tokens (`tokens.*`) for colors, not hardcoded values.
- **Stable callbacks**: The PCF `index.ts` creates callback references once in `init()`, not in `updateView()`, to avoid unnecessary re-renders.
- **Action outputs reset after read**: `getOutputs()` returns action strings then immediately clears them to prevent stale re-fires by the Canvas app.

### Testing

- Tests live in `__tests__/` directories colocated with the code they test (e.g., `components/__tests__/`, `hooks/__tests__/`, `utils/__tests__/`)
- Jest + jsdom + React Testing Library + `@testing-library/user-event`
- Test tsconfig: `tsconfig.test.json` (CommonJS output for Jest compatibility)
- The `test/jest.setup.ts` provides `matchMedia` and `ResizeObserver` mocks required by Fluent UI in jsdom

### Security

- URL sanitization via `utils/urlSanitizer.ts` — strict allowlist (`https:` and `mailto:` only) for any user-facing links
- Agent prompts include prompt-injection defenses: payload content is treated as DATA, not instructions
- Dataverse uses ownership-based RLS — each user sees only their own cards

### Provisioning Scripts

PowerShell 7+ scripts in `enterprise-work-assistant/scripts/` handle environment setup. They require PAC CLI (`Microsoft.PowerApps.CLI.Tool`).

### Planning Structure

The `.planning/` directory contains project management artifacts (milestones, phases, research). It uses a structured phase/plan system where each phase has numbered plans (e.g., `16-01-PLAN.md`, `16-01-SUMMARY.md`). `STATE.md` tracks current position. These files are for project context only — don't modify them when making code changes.
