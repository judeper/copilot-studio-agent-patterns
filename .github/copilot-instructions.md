# Copilot Instructions

## Architecture

This repo contains production-ready patterns for building autonomous agents on the Microsoft Copilot Studio + Power Platform stack. Each solution is a self-contained folder with prompts, schemas, provisioning scripts, and UI components.

The primary solution is **Enterprise Work Assistant** (`enterprise-work-assistant/`), an AI assistant that triages emails, Teams messages, and calendar events. The data flow is:

1. **Power Automate Agent Flows** (10 main flows + 10 agent tool flows, deployed via `scripts/deploy-agent-flows.ps1`):
   - Signal triggers: Flow 1 (Email), Flow 2 (Teams), Flow 3 (Calendar) intercept signals, invoke the Copilot Studio agent via `ExecuteAgentAndWait` (Microsoft Copilot Studio connector), and write results to Dataverse
   - Operations: Flow 4 (Send Email), Flow 5 (Card Outcome Tracker), Flow 6 (Daily Briefing), Flow 7 (Staleness Monitor), Flow 8 (Command Execution), Flow 9 (Sender Profile Analyzer), Flow 10 (Reminder Firing)
   - Learning system: Flow 11 (Heartbeat/Background Assessment), Flow 14 (Memory Retention), Flow 15 (Reflection/Knowledge Extraction), Flow 16 (Memory Decay)
   - Research tools: 5 agent tool flows (SearchUserEmail, SearchSentItems, SearchTeamsMessages, SearchSharePoint, SearchPlannerTasks) using "When an agent calls the flow" trigger for Tier 1-3 research
   - Orchestrator tools: 5 agent tool flows (QueryCards, QuerySenderProfile, UpdateCard, CreateCard, RefineDraft) for command bar actions
2. **Copilot Studio Agent** — 17 agent prompts (10 original + 7 new: Router, Calendar, Task, Email Compose, Search, Validation, Delegation) organized in a MARL pipeline (Triage→Research→Scorer→DraftGen→Humanizer via Flow-level chaining). Shared prompt patterns in `prompts/patterns/`. Provisioned via `scripts/provision-copilot.ps1`.
3. **Dataverse** (9 tables: `AssistantCards`, `SenderProfile`, `BriefingSchedule`, `ErrorLog`, `EpisodicMemory`, `SemanticKnowledge`, `UserPersona`, `SkillRegistry`, `SemanticEpisodic`) persists results with ownership-based row-level security
4. **Canvas App + PCF React Dashboard** (PCF manifest v2.2.0, 201 tests across 15 suites) renders a single-pane-of-glass UI with WCAG AA compliance
5. **OneNote Integration** (optional, Phase 1 write-only) syncs meeting prep, daily briefings, and active to-dos to a structured OneNote notebook via Graph API. Gated by feature flag (`cr_onenoteenabled`) and per-user opt-out (`cr_onenoteoptout`). Uses group-scoped app registration, `{{PLACEHOLDER}}` HTML templates, and fail-safe error handling.

Design documents in `enterprise-work-assistant/docs/`: `architecture-enhancements.md` (MARL pipeline design), `learning-enhancements.md` (learning system design), `ux-enhancements.md` (UX improvements and WCAG AA compliance).

The PCF component is a **virtual** React control (shares the platform React tree — does not bundle its own React). It uses a **dataset-type** binding where the Canvas app handles the Dataverse connection and passes pre-filtered records. The PCF emits output actions (send draft, dismiss, save draft, etc.) that the Canvas app handles via OnChange formulas.

**Note:** This is a **POC**, not a production build. The v3.0 milestone is scoped for demo readiness — production-grade items (full a11y audit, i18n, optimistic concurrency, DataSet paging, capacity planning) are out of scope.

The **Agent Cost Governance — PAYGO** solution (`agent-cost-governance-paygo/`) is a Tier-2 Cross-Cutting Governance solution providing leadership-quality PAYGO cost visibility for Copilot Studio agents. It uses Azure Cost Management + Power BI (no PCF component). Key artifacts: DAX measures, PowerShell billing policy script (Power Platform REST API), ARM budget alert template, and FSI regulatory alignment documents (GLBA, SOX, FINRA, OCC). Known limitation: Azure Cost Management reports at environment level, not per-agent.

The **Email Productivity Agent** (`email-productivity-agent/`) is a follow-up nudge and snooze system for Outlook emails. It tracks sent emails, detects missing replies, delivers Teams adaptive card nudges, and auto-unsnoozes conversations when replies arrive. The architecture is:

1. **7 Power Automate Flows** deployed via Flow Management API:
   - Phase 1 (Follow-Up Nudges): Flow 1 (Sent Items Tracker), Flow 2 (Response Detection), Flow 2b (Card Action Handler), Flow 5 (Data Retention)
   - Phase 2 (Snooze Auto-Removal): Flow 3 (Snooze Detection), Flow 4 (Auto-Unsnooze), Flow 6 (Snooze Cleanup)
2. **Copilot Studio Agent** with nudge topic for intelligent follow-up draft generation
3. **3 Dataverse Tables**: `cr_followuptracking`, `cr_nudgeconfiguration`, `cr_snoozedconversation` — all with alternate keys for safe upsert
4. **5 Connectors**: Office 365 Outlook, Office 365 Users, Microsoft Dataverse, Microsoft Teams, HTTP with Microsoft Entra ID (preauthorized)

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

# Deploy Copilot Studio agent (from enterprise-work-assistant/scripts/):
pwsh provision-copilot.ps1 -EnvironmentId "<env-id>"

# Deploy all 20 flows (from enterprise-work-assistant/scripts/):
pwsh deploy-agent-flows.ps1 -EnvironmentId "<env-id>"

# Or deploy in phases:
pwsh deploy-agent-flows.ps1 -EnvironmentId "<env-id>" -FlowsToCreate ToolFlows   # tool flows first
pwsh deploy-agent-flows.ps1 -EnvironmentId "<env-id>" -FlowsToCreate MainFlows   # then main flows
```

## Provision and Deploy (Email Productivity Agent)

All commands run from `email-productivity-agent/scripts/`:

```shell
# 1. Provision environment + Dataverse tables
pwsh provision-environment.ps1 -TenantId "<tenant-id>" -AdminEmail "<admin@example.com>"
pwsh create-security-roles.ps1 -OrgUrl "https://<org>.crm.dynamics.com"
pwsh assign-security-role.ps1 -OrgUrl "https://<org>.crm.dynamics.com"

# 2. Deploy Phase 1 flows (follow-up nudges)
pwsh deploy-agent-flows.ps1 -OrgUrl "https://<org>.crm.dynamics.com" -EnvironmentId "<env-id>" -FlowsToCreate "Phase1"

# 3. Deploy Phase 2 flows (snooze auto-removal)
pwsh deploy-agent-flows.ps1 -OrgUrl "https://<org>.crm.dynamics.com" -EnvironmentId "<env-id>" -FlowsToCreate "Phase2"
```

Requires: PowerShell 7+, PAC CLI, Azure CLI (`az login` for token acquisition).

## Key Conventions

### Schema-Prompt-Code Contract

The output JSON schema (`schemas/output-schema.json`), agent prompts (`prompts/`), TypeScript types (`src/AssistantDashboard/components/types.ts`), and Dataverse table definitions (`schemas/dataverse-table.json`) must all stay in sync. When changing a field, update all four locations.

### Flow & Topic Artifacts

- **Flow definitions** (`src/flow-*.json`): ARM Logic Apps JSON schema with `connectionName` bindings. Deployed via Flow Management API in `scripts/deploy-agent-flows.ps1`.
- **Agent tool flows** (`src/tool-*.json`): Use `PowerVirtualAgents` trigger (`When an agent calls the flow`) and `PowerVirtualAgentsResponseV2` response. "Asynchronous response" must be OFF.
- **Topic definitions** (`src/*-topic.yaml`): Copilot Studio Adaptive Dialog YAML. Use `InvokeAIBuilderModelAction` for AI prompts (referenced by `aIModelId` GUID — environment-specific). Use `InvokeFlowAction` for tool actions (referenced by `flowId` GUID — environment-specific).
- **Agent invocation**: Flows invoke Copilot Studio agents via `shared_microsoftcopilotstudio` connector with `ExecuteAgentAndWait` action. Input is JSON-serialized into the `message` parameter. Response is read from `body/lastResponse`.
- **6 connectors required**: Office 365 Outlook, Office 365 Users, Microsoft Teams, Microsoft Dataverse, HTTP with Entra ID (preauthorized), Microsoft Copilot Studio.
- **MCP servers** (Tier 4-5: Bing WebSearch, Microsoft Learn): UI-only configuration in Copilot Studio — cannot be automated via scripts.

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

- Tests live in `__tests__/` directories colocated with the code they test (e.g., `components/__tests__/`, `hooks/__tests__/`, `utils/__tests__/`)
- Jest + jsdom + React Testing Library + `@testing-library/user-event`
- Test tsconfig: `tsconfig.test.json` (CommonJS output for Jest compatibility)
- The `test/jest.setup.ts` provides `matchMedia` and `ResizeObserver` mocks required by Fluent UI in jsdom

### Security

- URL sanitization via `utils/urlSanitizer.ts` — strict allowlist (`https:` and `mailto:` only) for any user-facing links
- Agent prompts include prompt-injection defenses: payload content is treated as DATA, not instructions
- Dataverse uses ownership-based RLS — each user sees only their own cards

### Provisioning Scripts

PowerShell 7+ scripts in `enterprise-work-assistant/scripts/` handle environment setup. They require PAC CLI (`Microsoft.PowerApps.CLI.Tool`) version 1.32 or later:
- `provision-environment.ps1` — Creates Power Platform environment and Dataverse tables
- `create-security-roles.ps1` — Configures ownership-based row-level security
- `deploy-solution.ps1` — Builds PCF component and imports solution (validates PAC CLI version, runs NuGet restore)
- `provision-copilot.ps1` — Creates Copilot Studio agent with 17 prompts (MARL pipeline) via PAC CLI
- `deploy-agent-flows.ps1` — Deploys 20 flows via Flow Management API (supports phased deployment with `-FlowsToCreate`)
- `provision-onenote.ps1` — Provisions OneNote notebook and sections
- `validate-onenote-integration.ps1` — Verifies OneNote integration health
- `audit-table-naming.ps1` — Audits Dataverse table naming consistency

### OneNote Integration Patterns

- **Write-only (Phase 1)**: The agent writes to OneNote but never reads back annotations. OneNote is a downstream knowledge surface, not a data source.
- **Feature flag**: `cr_onenoteenabled` (org-level) and `cr_onenoteoptout` (per-user) gate all OneNote operations. Setting the flag to `false` stops all writes immediately.
- **Group-scoped Graph API**: All OneNote calls use `/groups/{groupId}/onenote/...` with an application permission (`Notes.ReadWrite.All` scoped to a dedicated M365 Group). Never use delegated `/me/` endpoints.
- **HTML templates**: Stored in `enterprise-work-assistant/templates/` using `{{PLACEHOLDER_NAME}}` syntax. All injected values must be HTML-entity-encoded before substitution.
- **Fail-safe error handling**: OneNote operations are wrapped in Power Automate Scopes. Failures are logged to `cr_errorlog` and surfaced as `cr_onenotesyncstatus = "FAILED"` on the card — they never block the main pipeline.
- **External-sharing pre-check**: Before every write, flows verify the notebook is not shared with external users to prevent data leakage.
- **Idempotency**: `cr_onenotepageid` on the Dataverse card is the dedup key. If a page ID exists, flows PATCH (update); otherwise POST (create).

### Email Productivity Agent — Flow Deployment

- **Flow Management API is mandatory**: Flows MUST be created via `api.flow.microsoft.com` (not the Dataverse `workflows` entity). Dataverse-created flows never bind connections at runtime regardless of API-level settings.
- **`state=Started`** during creation activates flows immediately but enforces strict dynamic parameter validation.
- **Teams connector**: `PostMessageToConversation` and `PostCardToConversation` require `poster` and `location` static params before dynamic `body` params. Use nested body format (`"body": { "recipient": { "to": ... }, "messageBody": ... }`), NOT flattened `body/recipient/to`.
- **Dataverse connector**: `UpsertRecord` doesn't exist — use `UpdateRecord` with alternate key in `recordId` for upsert behavior. `Terminate` action does not support `runError` when `runStatus` is `Succeeded`.
- **Owner-scoped queries**: All per-user Dataverse queries must include `cr_owneruserid` filter to prevent cross-user data leaks (defense in depth beyond RLS).
- **HTTP with Entra ID**: Connector API name is `shared_webcontents` with `InvokeHttp` operationId. Uses `request/method` and `request/url` parameters.
- **Flow JSON definitions**: Stored in `email-productivity-agent/src/flow-*.json`. Each file contains a `definition` (Logic Apps schema) and `_metadata` block with flow name, description, and required connections.

### Planning Structure

The `.planning/` directory contains project management artifacts (milestones, phases, research). It uses a structured phase/plan system where each phase has numbered plans (e.g., `16-01-PLAN.md`, `16-01-SUMMARY.md`). `STATE.md` tracks current position. These files are for project context only — don't modify them when making code changes.
