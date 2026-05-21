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
4a. **Code App Dashboard** (`code-app/`) — forward-architecture Vite + React 18 + TypeScript app replacing the PCF + Canvas App approach. All 12 React components migrated as-is; data layer replaced with `CardDataService` interface + `useCards()` hook. 199 tests (18 files, Vitest). See `docs/code-app-migration.md`.
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

The **Copilot Agent Debug Logger** (`copilot-agent-debug-logger/`) is a maker-focused POC that fills 3 specific gaps in the native Copilot Studio + Power Automate debugging stack: Power Automate request/response payload capture, shared correlation ID stitching across CS-side topic events and PA-side flow events, and drop-in Chain-of-Thought + Conversation History topic templates from the Power CAT Custom Engine blog (Oct 2025). Key artifacts:
- **1 Dataverse table** (`cr_agenttrace`) — 13 columns, UserOwned, primary column `cr_tracelabel` is plain Text (NO formula per council decision A1; populated explicitly via Compose in the flow)
- **1 Boolean env var** (`cr_DebugLoggerEnabled`) — single global kill switch; default `false`; fail-open on read failure (deleted var = disabled)
- **2 flows** — `flow-1-log-agent-trace` (child flow callable via "Run a Child Flow") + `tool-log-agent-trace` (PVA-trigger flow mirroring `intelligent-work-layer/src/tool-search-sharepoint.json` lines 117-207 verbatim for the Compose → Respond-with-error → Terminate_Graceful pattern per council decision A2/D3)
- **4 topic YAMLs** — CoT + ConvHistory × full (with `InvokeFlowAction`) + blog-pure (zero deps) per decision D6
- **3 PowerShell scripts** — `provision-environment.ps1`, `deploy-solution.ps1`, `inject-flow-guid.ps1` (B1 placeholder substitution for `{{TOOL_LOG_AGENT_TRACE_FLOW_ID}}`)
- **Unmanaged solution scaffold** (D8 v1) + **Phase-0 manual MDA authoring** (D7 — `docs/phase-0-mda-authoring.md` walks the maker portal click-path)
- **5 docs** — native-debugging-cheatsheet, deployment-guide, maker-guide (with Patterns A-E), skills-plugin-guide, phase-0-mda-authoring
- **POC scope**: no PII redaction, no retention, no per-user roles, no PCF JSON viewer — all listed as extension points

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
npm run test         # vitest (199 tests, 18 files)
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
- **Topic definitions** (`copilot-studio/topics/*.topic.mcs.yml`): Copilot Studio Adaptive Dialog YAML in VS Code Extension format. Use `InvokeAIBuilderModelAction` for AI prompts (referenced by `aIModelId` GUID — environment-specific). Use `InvokeFlowAction` for tool actions (referenced by `flowId` GUID — environment-specific). Compatible with the [Skills for Copilot Studio](https://github.com/microsoft/skills-for-copilot-studio) plugin for terminal-based authoring, testing, and troubleshooting.
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
- PII hygiene is mandatory: never commit real customer, partner, or tenant emails, domains, UPNs, org URLs, runtime configs, logs, dumps, or generated backups. Use neutral placeholders under `example.com` for all sample addresses/domains, and if a change touches prompts, docs, mock data, fixtures, or scripts with email-like values, scan for PII before finalizing. The repo guardrail in `.github/workflows/prevent-pii-domains.yml` is the enforced baseline.

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

### Per-solution AGENTS.md convention

When working in a specific solution folder (e.g. `copilot-agent-debug-logger/`), check first for an `AGENTS.md` at the solution root. It is the AI-context companion to the human-facing `README.md` and contains: critical constraints (must-not-violate decisions), known deploy-time issues with workarounds, schema-prompt-code contract rules, operational sequence, "where to look first when something breaks" diagnostics, and explicit do-not lists. **Today only `copilot-agent-debug-logger/AGENTS.md` exists** (established in PR after #42); a backlog todo (`agentsmd-other-solutions`) covers adding equivalents for IWL, EPA, and cost-governance using the debug-logger AGENTS.md as the template. If you're contributing to a solution that lacks AGENTS.md, fall back to this file plus the solution's `README.md`.

### Copilot Agent Debug Logger — POC Constraints

- **A1 — `cr_tracelabel` is plain Text(200) primary column with NO formula.** Flow populates it explicitly via Compose: `concat(triggerBody()?['source'], '/', triggerBody()?['step_name'], ' @ ', utcNow())`. Adding `formulaDefinition` breaks the contract.
- **A2/D3 — tool flow error pattern is verbatim from IWL.** `tool-log-agent-trace`'s `Scope_Handle_Errors` mirrors `intelligent-work-layer/src/tool-search-sharepoint.json` lines 117-207. On Failed/TimedOut: `Compose_ErrorDetails` → `Respond_with_error` (PowerVirtualAgentsResponseV2, statusCode 200, body `{ "logged": false }`) → `Terminate_Graceful(Failed)`. Respond-before-terminate is non-negotiable — otherwise the calling topic hangs.
- **A3/D4 — child flow fail-open.** `flow-1-log-agent-trace`'s `Scope_Write` has `Configure run after → Failed/TimedOut → Terminate(Succeeded)` so a logger failure never propagates to the caller.
- **A4 — env-var fail-open.** Both flows treat a deleted/failed env-var read as `enabled = false`. Implementation: `Compose_EnabledFlag` with `coalesce(outputs('Get_DebugLoggerEnabled')?[...], false)` and `runAfter` covering `Succeeded, Failed, TimedOut, Skipped`.
- **A15 — payload truncation.** Both flows apply `substring(string(triggerBody()?['payload']), 0, min(900000, length(string(triggerBody()?['payload']))))` before the Dataverse write — Memo field is ~1 MB; 900 KB leaves headroom. **Do not use `left()`** — that's a Power Apps Canvas-formula function, NOT a Workflow Definition Language function (early drafts used it and the Flow Management API rejected with `'left' is not defined or not valid`; see PR #42).
- **D5/B1 — topic GUID lifecycle is Path B.** Topics ship with `{{TOOL_LOG_AGENT_TRACE_FLOW_ID}}` placeholder; `scripts/inject-flow-guid.ps1` substitutes the actual GUID into `dist/topics/*.topic.mcs.yml` after import (output dir gitignored).
- **D6 — every topic ships in TWO variants.** Full (with `InvokeFlowAction` → tool flow → cr_agenttrace) + blog-pure (Message-only / capture-only, zero deps). Modify both when changing a topic's contract.
- **D7 — MDA is Phase-0 manual.** Authored once in Maker portal then `pac solution clone --name CopilotAgentDebugLogger` extracts the MDA into the Microsoft-canonical layout `src/Solutions/src/AppModules/cr_AgentDebugConsole/` (the legacy `CanvasApps/AgentDebugConsole_*` path is no longer used). `deploy-solution.ps1` fails loudly with a pointer to `docs/phase-0-mda-authoring.md` when the MDA folder is missing.
- **D8 — unmanaged-only v1.** No managed-build artifacts; deferred to customer extension.
- **PVA tool flow cannot be deployed via Flow Management API.** `tool-log-agent-trace` JSON is a reference; the actual flow is created when added as an Action on a consumer agent in Copilot Studio. First-deploy ordering: `deploy-solution.ps1 -SkipInjectFlowGuid` → add tool flow as Action on at least one agent → re-run `deploy-solution.ps1` (no flag) to substitute placeholders.
- **Known issues from first deploy (PR #42).** Surfaced when running the POC end-to-end on a fresh tenant for the first time:
  - **`cr_sourcename` schema collision** — Dataverse Picklist `cr_source` auto-generates a Virtual reflection named `cr_sourcename` that blocks creation of the documented `Text(200)` column. Provision skips it; flows omit `item/cr_sourcename` from `CreateRecord`. The trace label encodes source/step instead. Follow-up renames to `cr_originname`.
  - **Custom `UniqueIdentifier` columns rejected by Dataverse Web API** (0x80040203). The platform auto-creates `<tablename>id` as the PK Guid; the documented `cr_traceid` column entry is informational only. Provision loop skips them.
  - **Maker portal Boolean env vars stored as `"yes"`/`"no"` strings** — `cr_DebugLoggerEnabled` toggle writes literal `"yes"`, not `"true"`. The current `Compose_EnabledFlag` only matches `'true'` so flows skip the write even when "enabled" in UI. Workaround: PATCH the value to `"true"` via Web API. Follow-up makes the Compose tolerant of `true`/`yes`/`1`.
  - **PAC CLI 2.x compat in provision script** — `pac admin list-environments` returns "Not a valid command" with exit code 0 in 2.x (was a valid command in 1.x). Provision script now uses a JSON-shape sniff (`[` / `{` prefix) before parsing, in addition to checking `$LASTEXITCODE`.
  - **Flow Management API does support manual-trigger child flows.** Despite the repo convention that "main flow JSONs are POC scaffolding requiring manual building", we verified via an ad-hoc script that `flow-1-log-agent-trace` CAN be created programmatically (mirroring `intelligent-work-layer/scripts/deploy-agent-flows.ps1`). Backlog todo `productionize-deploy-flows-script` will harvest this into `scripts/deploy-flows.ps1`. PVA-trigger flows (the tool flow) still require manual Action add.
  - **`pac solution clone` produces nested project layout** — creates `src/Solutions/<SolutionName>/<SolutionName>.cdsproj` plus full Microsoft-canonical `src/Entities`, `src/AppModules`, `src/AppModuleSiteMaps`, `src/Other`, `src/environmentvariabledefinitions` tree. The R2 scaffold expected files directly under `src/Solutions/`; PR #42 restructured to the canonical layout and `deploy-solution.ps1` auto-discovers `*.cdsproj` to handle both shapes.

