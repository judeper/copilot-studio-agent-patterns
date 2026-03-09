# Copilot Instructions

## Architecture

This repo contains production-ready patterns for building autonomous agents on the Microsoft Copilot Studio + Power Platform stack. Each solution is a self-contained folder with prompts, schemas, provisioning scripts, and UI components.

The primary solution is **Intelligent Work Layer** (`intelligent-work-layer/`), an intelligent work layer that intercepts email, Teams, and calendar signals — triaging, researching, and preparing draft responses autonomously. The data flow is:

1. **Power Automate Agent Flows** (10 main flows + 10 agent tool flows):
   - Signal triggers: Flow 1 (Email), Flow 2 (Teams), Flow 3 (Calendar) intercept signals, invoke the Copilot Studio agent via `ExecuteAgentAndWait` (Microsoft Copilot Studio connector), and write results to Dataverse
   - Operations: Flow 4 (Send Email), Flow 5 (Card Outcome Tracker), Flow 6 (Daily Briefing), Flow 7 (Staleness Monitor), Flow 8 (Command Execution), Flow 9 (Sender Profile Analyzer), Flow 10 (Reminder Firing)
   - Learning system: Flow 11 (Heartbeat/Background Assessment), Flow 14 (Memory Retention), Flow 15 (Reflection/Knowledge Extraction), Flow 16 (Memory Decay)
   - Research tools: 5 agent tool flows (SearchUserEmail, SearchSentItems, SearchTeamsMessages, SearchSharePoint, SearchPlannerTasks) using "When an agent calls the flow" trigger for Tier 1-3 research
   - Orchestrator tools: 5 agent tool flows (QueryCards, QuerySenderProfile, UpdateCard, CreateCard, RefineDraft) for command bar actions
   - **Deployment note:** Tool flows use the `PowerVirtualAgents` trigger kind which cannot be created via the Flow Management API. They must be created via Copilot Studio (add as Actions to the agent) or via `pac solution export/import`. Main flows use standard triggers and are deployed via `scripts/deploy-agent-flows.ps1`, but the JSON definitions are POC scaffolding — some require manual building in the Power Automate designer following `docs/agent-flows.md`.
2. **Copilot Studio Agent** — 17 agent prompts (10 original + 7 new: Router, Calendar, Task, Email Compose, Search, Validation, Delegation) organized in a MARL pipeline (Triage→Research→Scorer→DraftGen→Humanizer via Flow-level chaining). Shared prompt patterns in `prompts/patterns/`. Provisioned via `scripts/provision-copilot.ps1`.
3. **Dataverse** (9 tables: `AssistantCards`, `SenderProfile`, `BriefingSchedule`, `ErrorLog`, `EpisodicMemory`, `SemanticKnowledge`, `UserPersona`, `SkillRegistry`, `SemanticEpisodic`) persists results with ownership-based row-level security
4. **Canvas App + PCF React Dashboard** (PCF manifest v2.2.0, 233 tests across 16 suites) renders a single-pane-of-glass UI with WCAG AA compliance. **Migrating to Code App** — see item 4a. The UX is grounded in cognitive science research (Cowan's 4±1 attention slots, Gloria Mark's 23-min interruption cost, Zeigarnik Effect, arXiv 2024 AI trust miscalibration, PMC visual fatigue). Key UX features: three-state confidence display (not percentages), 5-item focused queue with composite sort, quiet mode for focus protection, morning/EOD/meeting briefing variants via DayGlance component, warm-gray palette for sustained use, and `prefers-reduced-motion` support.
4a. **Code App Dashboard** (`code-app/`) — forward-architecture Vite + React 18 + TypeScript app replacing the PCF + Canvas App approach. All 12 React components migrated as-is; data layer replaced with `CardDataService` interface + `useCards()` hook. 170 tests (14 files, Vitest). See `docs/code-app-migration.md`.
5. **OneNote Integration** (optional, Phase 1 write-only) syncs meeting prep, daily briefings, and active to-dos to a structured OneNote notebook via Graph API. Gated by feature flag (`cr_onenoteenabled`) and per-user opt-out (`cr_onenoteoptout`). Uses group-scoped app registration, `{{PLACEHOLDER}}` HTML templates, and fail-safe error handling.
6. **Work OS proposal models** in `src/models/` (9 TypeScript files + adapter layer) define the next-gen view-model types for scenarios, queues, messaging, briefings, reviews, activity, and Copilot interactions — with adapters that map legacy `AssistantCard` records to the new shapes.
7. **JSON Schemas** in `schemas/workos/` (8 schema files) define the agent-to-UI contract for Work OS payloads.
8. **Mock data** in `src/mock-data/` and `mock-api/` provide typed fixtures and JSON API payloads for offline development and testing.
9. **Agent contract documentation** in `docs/agent-contract.md` specifies the Work OS agent-to-UI contract proposal.

Design documents in `intelligent-work-layer/docs/`: `architecture-overview.md` (system architecture and positioning), `architecture-enhancements.md` (MARL pipeline design), `learning-enhancements.md` (learning system design), `ux-enhancements.md` (UX improvements and WCAG AA compliance), `agent-contract.md` (Work OS agent-to-UI contract proposal).

The PCF component (`src/AssistantDashboard/`) is a **virtual** React control (shares the platform React tree — does not bundle its own React). It uses a **dataset-type** binding where the Canvas app handles the Dataverse connection and passes pre-filtered records. The PCF emits output actions (send draft, dismiss, save draft, etc.) that the Canvas app handles via OnChange formulas. **This is the legacy UI architecture — the Code App (`code-app/`) is the forward path.**

The Code App (`code-app/`) is a standalone Vite + React 18 + TypeScript app that owns its own React tree. It uses a `CardDataService` interface for data access (currently backed by `MockCardDataService` for offline dev; swap in Dataverse-backed implementation via `pac-sdk add-data-source` for production). All 12 React components port as-is from the PCF source.

**Note:** This is a **POC**, not a production build. The v3.0 milestone is scoped for demo readiness — production-grade items (full a11y audit, i18n, optimistic concurrency, DataSet paging, capacity planning) are out of scope.

The **Agent Cost Governance — PAYGO** solution (`agent-cost-governance-paygo/`) is a Tier-2 Cross-Cutting Governance solution providing leadership-quality PAYGO cost visibility for Copilot Studio agents. It uses Azure Cost Management + Power BI (no PCF component). Key artifacts: DAX measures, PowerShell billing policy script (Power Platform REST API), ARM budget alert template, and FSI regulatory alignment documents (GLBA, SOX, FINRA, OCC). Known limitation: Azure Cost Management reports at environment level, not per-agent.

The **Email Productivity Agent** (`email-productivity-agent/`) provides Gmail-like follow-up nudges and smart snooze for Outlook:
- **9 production flows** (Phase 1: nudges, Phase 2: snooze, Phase 3: settings) + 6 optional CLI regression harnesses
- **3 Dataverse tables**: `cr_followuptracking`, `cr_nudgeconfiguration`, `cr_snoozedconversation`
- **Connectors**: Office 365 Outlook, Office 365 Users, Microsoft Teams, Microsoft Dataverse, HTTP with Entra ID
- **POC state**: Flow 2 mocked, Flow 4 deterministic bypass; Copilot assets available for re-enabling
- **Lab wizard** (`tools/lab-wizard/wizard.py`): Python CLI automating full deployment in 9 phases

## Build, Test, and Lint (PCF Component — Legacy)

All commands run from `intelligent-work-layer/src/`:

```shell
npm install          # also runs postinstall to patch manifest schema
npm run build        # pcf-scripts build
npm run lint         # eslint AssistantDashboard --ext .ts,.tsx
npm run test         # jest (all tests)
npm run test:coverage # jest with 80% per-file threshold

# Single test file:
npx jest --config test/jest.config.ts AssistantDashboard/components/__tests__/CardItem.test.tsx
```

## Build, Test, and Lint (Code App — Forward Architecture)

All commands run from `intelligent-work-layer/code-app/`:

```shell
npm install
npm run build        # tsc + vite build → dist/
npm run dev          # vite dev server on port 3000
npm run test         # vitest (170 tests, 14 files)
npm run test:watch   # vitest in watch mode
npm run test:coverage # vitest with 80% per-file threshold
npm run lint         # eslint src --ext .ts,.tsx

# Single test file:
npx vitest run src/components/__tests__/CardItem.test.tsx

# Deploy solution (from intelligent-work-layer/scripts/):
pwsh deploy-solution.ps1 -EnvironmentId "<env-id>"

# Deploy Copilot Studio agent (from intelligent-work-layer/scripts/):
pwsh provision-copilot.ps1 -EnvironmentId "<env-id>"

# Deploy main flows (from intelligent-work-layer/scripts/):
pwsh deploy-agent-flows.ps1 -EnvironmentId "<env-id>" -FlowsToCreate MainFlows

# Tool flows (ToolFlows) CANNOT be deployed via the Flow Management API —
# the PowerVirtualAgents trigger kind is rejected. Create tool flows by
# adding Actions in Copilot Studio or via pac solution export/import.
```

## Provision and Deploy (Email Productivity Agent)

Deploy via lab wizard (recommended) or manual scripts. See `email-productivity-agent/README.md` for full instructions.

```shell
# Lab wizard (automated, interactive)
cd email-productivity-agent/tools/lab-wizard && pip install -r requirements.txt && python wizard.py

# Manual scripts (from email-productivity-agent/scripts/)
pwsh provision-environment.ps1 -TenantId "<tenant-id>"
pwsh create-security-roles.ps1 -OrgUrl "https://<org>.crm.dynamics.com"
pwsh deploy-agent-flows.ps1 -OrgUrl "..." -EnvironmentId "..." -FlowsToCreate "Phase1"  # then Phase2, Phase3
```

Requires: PowerShell 7+, PAC CLI, Azure CLI (`az login` for token acquisition).

## Key Conventions

### Schema-Prompt-Code Contract

The output JSON schema (`schemas/output-schema.json`), agent prompts (`prompts/`), TypeScript types (`src/AssistantDashboard/components/types.ts`), and Dataverse table definitions (`schemas/dataverse-table.json`) must all stay in sync. When changing a field, update all four locations.

### Flow & Topic Artifacts

- **Flow definitions** (`src/flow-*.json`): ARM Logic Apps JSON schema with `connectionName` bindings. Main flows deployed via Flow Management API in `scripts/deploy-agent-flows.ps1`; some may need manual building in Power Automate designer.
- **Agent tool flows** (`src/tool-*.json`): Reference definitions for Copilot Studio agent actions. Use `PowerVirtualAgents` trigger — cannot be API-deployed; create via Copilot Studio Actions or `pac solution import`.
- **Agent tool flows** (`src/tool-*.json`): Reference definitions for Copilot Studio agent actions. Use `PowerVirtualAgents` trigger (`When an agent calls the flow`) and `PowerVirtualAgentsResponseV2` response. **Cannot be created via Flow Management API** — create via Copilot Studio Actions or `pac solution import`. "Asynchronous response" must be OFF.
- **Topic definitions** (`src/*-topic.yaml`): Copilot Studio Adaptive Dialog YAML. Use `InvokeAIBuilderModelAction` for AI prompts (referenced by `aIModelId` GUID — environment-specific). Use `InvokeFlowAction` for tool actions (referenced by `flowId` GUID — environment-specific).
- **Agent invocation**: Prompt assets remain in the repo, but the current validated POC deployment keeps Flow 2 mocked and Flow 4 bypassed; only re-enabled live-agent variants should use `shared_microsoftcopilotstudio`.
- **5 connectors required in the tested deployment**: Office 365 Outlook, Office 365 Users, Microsoft Teams, Microsoft Dataverse, HTTP with Entra ID (preauthorized). Add Microsoft Copilot Studio only when re-enabling live agent calls.
- **MCP servers** (Tier 4-5): Add from the built-in catalog in Copilot Studio → Tools. Microsoft Learn Docs MCP Server replaces the retired Bing WebSearch MCP. Cannot be automated via scripts.

### PCF Component Patterns

- **Platform React**: The control uses `<platform-library name="React">` and `<platform-library name="Fluent">` — never add React or Fluent UI to `dependencies` in package.json (they belong in `devDependencies` only for types/testing).
- **Fluent UI v9**: All UI uses `@fluentui/react-components` (v9) and `@fluentui/react-icons`. Use Fluent tokens (`tokens.*`) for colors, not hardcoded values.
- **Stable callbacks**: The PCF `index.ts` creates callback references once in `init()`, not in `updateView()`, to avoid unnecessary re-renders.
- **Action outputs reset after read**: `getOutputs()` returns action strings then immediately clears them to prevent stale re-fires by the Canvas app.
- **Output properties**: `selectedCardId`, `sendDraftAction`, `copyDraftAction`, `dismissCardAction`, `jumpToCardAction`, `commandAction`, `saveDraftAction`, `updateScheduleAction` — each fires a JSON payload to the Canvas app.
- **Draft persistence**: `saveDraftAction` fires with a 2-second debounce when the user edits a draft in CardDetail, persisting the edited text to Dataverse `cr_humanizeddraft` via the Canvas app handler.
- **Dismiss retry**: `pendingDismissals` map in index.ts re-fires dismiss actions up to 3 times (5-second intervals) if the card outcome doesn't change to DISMISSED.
- **Escape key handling**: CardDetail closes edit mode → confirmation panel → detail view on Escape with focus restoration. BriefingCard detail view closes on Escape, and CommandBar collapses the response panel on Escape while returning focus to the invoking control.

### Testing

#### PCF (Legacy — `intelligent-work-layer/src/`)
- Tests live in `__tests__/` directories colocated with the code they test (e.g., `components/__tests__/`, `hooks/__tests__/`, `utils/__tests__/`)
- Jest + jsdom + React Testing Library + `@testing-library/user-event`
- Test tsconfig: `tsconfig.test.json` (CommonJS output for Jest compatibility)
- The `test/jest.setup.ts` provides `matchMedia` and `ResizeObserver` mocks required by Fluent UI in jsdom

#### Code App (Forward — `intelligent-work-layer/code-app/`)
- Same colocated `__tests__/` directory pattern
- Vitest + jsdom + React Testing Library + `@testing-library/user-event`
- `vitest.config.ts` with 80% per-file coverage thresholds
- `src/test/setup.ts` provides `matchMedia` and `ResizeObserver` mocks
- `src/test/helpers/renderWithProviders.tsx` wraps components in FluentProvider for tests

### Security

- URL sanitization via `utils/urlSanitizer.ts` — strict allowlist (`https:` and `mailto:` only) for any user-facing links
- Agent prompts include prompt-injection defenses: payload content is treated as DATA, not instructions
- Dataverse uses ownership-based RLS — each user sees only their own cards

### Provisioning Scripts

PowerShell 7+ scripts in `intelligent-work-layer/scripts/` handle environment setup. They require PAC CLI (`Microsoft.PowerApps.CLI.Tool`) version 1.32 or later:
- `provision-environment.ps1` — Creates Power Platform environment and Dataverse tables
- `create-security-roles.ps1` — Configures ownership-based row-level security
- `deploy-solution.ps1` — Builds PCF component and imports solution (validates PAC CLI version, runs NuGet restore)
- `provision-copilot.ps1` — Creates Copilot Studio agent with 17 prompts (MARL pipeline) via PAC CLI
- `deploy-agent-flows.ps1` — Deploys main flows via Flow Management API (tool flows must be created via Copilot Studio or solution import)
- `provision-onenote.ps1` — Provisions OneNote notebook and sections
- `validate-onenote-integration.ps1` — Verifies OneNote integration health
- `audit-table-naming.ps1` — Audits Dataverse table naming consistency

### OneNote Integration Patterns

- **Write-only (Phase 1)**: The agent writes to OneNote but never reads back annotations. OneNote is a downstream knowledge surface, not a data source.
- **Feature flag**: `cr_onenoteenabled` (org-level) and `cr_onenoteoptout` (per-user) gate all OneNote operations. Setting the flag to `false` stops all writes immediately.
- **Group-scoped Graph API**: All OneNote calls use `/groups/{groupId}/onenote/...` with an application permission (`Notes.ReadWrite.All` scoped to a dedicated M365 Group). Never use delegated `/me/` endpoints.
- **HTML templates**: Stored in `intelligent-work-layer/templates/` using `{{PLACEHOLDER_NAME}}` syntax. All injected values must be HTML-entity-encoded before substitution.
- **Fail-safe error handling**: OneNote operations are wrapped in Power Automate Scopes. Failures are logged to `cr_errorlog` and surfaced as `cr_onenotesyncstatus = "FAILED"` on the card — they never block the main pipeline.
- **External-sharing pre-check**: Before every write, flows verify the notebook is not shared with external users to prevent data leakage.
- **Idempotency**: `cr_onenotepageid` on the Dataverse card is the dedup key. If a page ID exists, flows PATCH (update); otherwise POST (create).

### Email Productivity Agent — Flow Deployment

- **Flow Management API**: Deploy main flows via `api.flow.microsoft.com` with `$connections` and `$authentication` parameters injected. Flow definitions in `email-productivity-agent/src/flow-*.json`.
- **Dataverse connector**: Use `ListRecords` + `UpdateRecord`/`CreateRecord` (not `UpsertRecord`). Set `cr_unsnoozedbyagent` explicitly on creates.
- **Teams connector**: For `"Chat with Flow bot"`, use `body/recipient` as flat email string (not nested `body/recipient/to`).
- **Table naming**: Singular for logical names (`cr_snoozedconversation`), plural for OData entity sets (`cr_snoozedconversations`).
- See `email-productivity-agent/docs/deployment-guide.md` Step 5 for detailed troubleshooting.

### Planning Structure

The `.planning/` directory contains project management artifacts (milestones, phases, research). It uses a structured phase/plan system where each phase has numbered plans (e.g., `16-01-PLAN.md`, `16-01-SUMMARY.md`). `STATE.md` tracks current position. These files are for project context only — don't modify them when making code changes.
