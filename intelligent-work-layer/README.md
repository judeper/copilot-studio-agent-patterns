# Intelligent Work Layer

An intelligent work layer for Microsoft 365 that triages incoming emails, Teams messages, and calendar events — conducting automated research and preparing briefings and draft responses before the user ever has to ask.

## What It Does

- **Triages** every incoming signal into SKIP / LIGHT / FULL tiers based on sender importance, urgency, and action requirements
- **Researches** across 5 tiers: personal email/Teams history, SharePoint/internal wikis, project tools, public web, official documentation
- **Scores confidence** (0-100) based on evidence strength and source reliability
- **Prepares drafts** for emails and Teams replies, calibrated to recipient relationship and tone
- **Surfaces everything** on a single-pane-of-glass dashboard — **Code App** (Vite + React 18, forward architecture) or Canvas App + PCF React component (legacy)
- **Syncs to OneNote** (optional) — meeting prep, daily briefings, and active to-dos are written to a structured OneNote notebook for offline access, annotation, and Microsoft Search indexing

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   INCOMING SIGNALS                           │
│   Email          Teams Message       Calendar (Daily)        │
│     │                 │                    │                  │
│     ▼                 ▼                    ▼                  │
│  ┌─────────────────────────────────────────────────┐        │
│  │       POWER AUTOMATE AGENT FLOWS (×3)           │        │
│  │  Extract payload → Invoke agent → Write Dataverse│        │
│  └────────────────────┬────────────────────────────┘        │
│                       ▼                                      │
│  ┌─────────────────────────────────────────────────┐        │
│  │      COPILOT STUDIO AGENT (Main)                │        │
│  │  Triage → Research → Score → JSON Output        │        │
│  └────────────────────┬────────────────────────────┘        │
│                       │                                      │
│          ┌────────────┴────────────┐                        │
│          │  FULL + confidence ≥ 40 │                        │
│          └────────────┬────────────┘                        │
│                  Yes  │  No → store as-is                    │
│                       ▼                                      │
│  ┌─────────────────────────────────────────────────┐        │
│  │      HUMANIZER AGENT (Connected Agent)          │        │
│  │  Rewrites draft in natural tone                  │        │
│  └────────────────────┬────────────────────────────┘        │
│                       ▼                                      │
│  ┌─────────────────────────────────────────────────┐        │
│  │           DATAVERSE (AssistantCards)             │        │
│  │  Ownership-based security · Full JSON + filters  │        │
│  └────────────────────┬────────────────────────────┘        │
│                       ▼                                      │
│  ┌─────────────────────────────────────────────────┐        │
│  │      CANVAS APP + PCF REACT DASHBOARD           │        │
│  │  Gallery → Detail → Edit & Send                  │        │
│  │  (Legacy — migrating to Code App below)           │        │
│  └────────────────────┬────────────────────────────┘        │
│                       │                                      │
│  ┌─────────────────────────────────────────────────┐        │
│  │     CODE APP (Vite + React 18) — Forward Path   │        │
│  │  Same components, direct Dataverse SDK access    │        │
│  └────────────────────┬────────────────────────────┘        │
│                       │ (optional, feature-flagged)          │
│                       ▼                                      │
│  ┌─────────────────────────────────────────────────┐        │
│  │      ONENOTE INTEGRATION (write-only Phase 1)   │        │
│  │  Meeting prep · Daily briefings · Active to-dos  │        │
│  └─────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## File Map

```
intelligent-work-layer/
├── code-app/                      # Forward-architecture Code App (Vite + React 18)
│   ├── src/components/            # All 12 React components (migrated from PCF)
│   ├── src/hooks/useCards.ts      # Data hook replacing PCF useCardData
│   ├── src/services/              # CardDataService interface + MockCardDataService
│   ├── src/utils/                 # focusUtils, levenshtein, urlSanitizer, cardTransforms
│   ├── src/fixtures/sampleCards.ts # 7 sample cards for offline development
│   └── src/styles/                # AssistantDashboard.css (full stylesheet)
├── docs/
│   ├── agent-flows.md            # Step-by-step flow building guide
│   ├── architecture-enhancements.md # v3.0 MARL pipeline architecture design
│   ├── architecture-overview.md  # System architecture and "Intelligent Work Layer" positioning
│   ├── canvas-app-setup.md       # Canvas app + PCF configuration
│   ├── code-app-migration.md     # Code App migration plan and status
│   ├── data-governance.md        # Data retention policies, PII handling, GDPR/CCPA erasure procedures
│   ├── deployment-guide.md       # End-to-end deployment checklist
│   ├── learning-enhancements.md  # Learning system design (episodic memory, semantic knowledge, decay)
│   ├── onenote-integration.md    # OneNote integration design (Phase 1-3)
│   ├── ux-enhancements.md        # UX improvements and WCAG AA compliance
│   └── agent-contract.md        # Work OS agent-to-UI contract proposal
├── prompts/
│   ├── main-agent-system-prompt.md    # Main agent operating instructions
│   ├── humanizer-agent-prompt.md      # Tone calibration prompt
│   ├── daily-briefing-agent-prompt.md # Daily briefing agent instructions
│   ├── orchestrator-agent-prompt.md   # Orchestrator agent instructions
│   ├── triage-agent-prompt.md         # MARL pipeline: triage classification
│   ├── research-agent-prompt.md       # MARL pipeline: 5-tier research
│   ├── confidence-scorer-prompt.md    # MARL pipeline: confidence scoring
│   ├── draft-generator-prompt.md      # MARL pipeline: draft generation
│   ├── draft-refiner-prompt.md        # MARL pipeline: draft refinement
│   ├── heartbeat-agent-prompt.md      # Background assessment agent
│   ├── edit-analyzer-agent-prompt.md  # User edit pattern analysis
│   ├── router-agent-prompt.md         # Signal routing agent (v3.0)
│   ├── calendar-agent-prompt.md       # Calendar-specific processing (v3.0)
│   ├── task-agent-prompt.md           # Task extraction and management (v3.0)
│   ├── email-compose-agent-prompt.md  # Email composition agent (v3.0)
│   ├── search-agent-prompt.md         # Search orchestration agent (v3.0)
│   ├── validation-agent-prompt.md     # Output validation agent (v3.0)
│   ├── delegation-agent-prompt.md     # Task delegation agent (v3.0)
│   └── patterns/                      # Shared prompt patterns
│       ├── error-handling.md          # Common error handling patterns
│       ├── output-format.md           # Output format conventions
│       └── security-constraints.md    # Security constraint patterns
├── scripts/
│   ├── provision-environment.ps1      # Environment + Dataverse setup
│   ├── create-security-roles.ps1      # Ownership-based RLS
│   ├── deploy-solution.ps1            # PCF build + solution import
│   ├── deploy-agent-flows.ps1         # Deploy main flows via Flow Management API (tool flows via Copilot Studio)
│   ├── provision-copilot.ps1          # Create Copilot Studio agent via PAC CLI
│   ├── provision-onenote.ps1          # OneNote notebook + section provisioning
│   ├── validate-onenote-integration.ps1 # Verify OneNote integration health
│   ├── audit-table-naming.ps1         # Dataverse table naming audit
│   └── user-data-erasure.ps1          # Right-to-erasure PowerShell script with OneNote cleanup
├── schemas/
│   ├── output-schema.json             # JSON Schema for agent output
│   ├── dataverse-table.json           # AssistantCards table definition
│   ├── briefing-output-schema.json    # Daily briefing output schema
│   ├── briefingschedule-table.json    # BriefingSchedule table definition
│   ├── episodicmemory-table.json      # Episodic Memory table definition (decision log)
│   ├── errorlog-table.json            # Error Log table definition (flow error monitoring)
│   ├── heartbeat-output-schema.json   # Heartbeat/Background Assessment output schema
│   ├── semanticknowledge-table.json   # Semantic Knowledge table definition (knowledge graph)
│   ├── senderprofile-table.json       # SenderProfile table definition
│   ├── skillregistry-table.json       # Skill Registry table definition (extensible agent skills)
│   ├── userpersona-table.json         # User Persona table definition (communication preferences)
│   └── workos/                        # Work OS JSON Schemas (8 files — agent-to-UI contract)

├── templates/
│   ├── onenote-meeting-prep.html      # OneNote meeting prep page template
│   ├── onenote-daily-briefing.html    # OneNote daily briefing page template
│   └── onenote-active-todos.html      # OneNote active to-dos page template
├── mock-api/                          # JSON API payload fixtures for offline Work OS development
└── src/                               # PCF React component + flow/topic definitions
    ├── models/                        # Work OS proposal view-model types + adapter layer
    │   ├── shared.ts                  # Common enums and base types
    │   ├── scenario.ts                # Scenario/card view-model
    │   ├── queue.ts                   # Queue and sorting types
    │   ├── messaging.ts               # Messaging/draft types
    │   ├── briefings.ts               # Briefing variant types
    │   ├── review.ts                  # Review and approval types
    │   ├── activity.ts                # Activity feed types
    │   ├── copilot.ts                 # Copilot interaction types
    │   ├── workOsViewModel.ts         # Top-level Work OS view-model
    │   ├── adapters.ts                # Legacy AssistantCard → Work OS adapters
    │   ├── index.ts                   # Barrel export
    │   └── __tests__/
    │       └── adapters.test.ts       # Adapter unit tests (32 tests)
    ├── mock-data/                     # Typed Work OS fixtures for development
    ├── AssistantDashboard/
    │   ├── ControlManifest.Input.xml  # PCF manifest (virtual, dataset)
    │   ├── index.ts                   # PCF lifecycle entry point
    │   ├── components/
    │   │   ├── App.tsx                # Root component (gallery/detail router)
    │   │   ├── CardGallery.tsx        # Focused 5-item queue with composite sort (urgency×confidence)
    │   │   ├── CardItem.tsx           # Collapsed card with urgency rationale and three-state confidence signal
    │   │   ├── CardDetail.tsx         # Expanded card view with draft ownership framing and learning feedback
    │   │   ├── BriefingCard.tsx       # Morning, end-of-day, and meeting prep briefing variants
    │   │   ├── CommandBar.tsx         # Context-aware prompts and agent activity feed
    │   │   ├── StatusBar.tsx          # Day metrics bar (decisions ready, focus status, drafts ready, next meeting)
    │   │   ├── ConfidenceCalibration.tsx # Low confidence warning badge with calibration indicator
    │   │   ├── DayGlance.tsx          # Compact today-at-a-glance calendar with meeting prep status
    │   │   ├── FilterBar.tsx          # Active filter status bar with quiet mode toggle for focus protection
    │   │   ├── ErrorBoundary.tsx      # React error boundary
    │   │   ├── types.ts              # TypeScript interfaces from schema
    │   │   └── constants.ts          # UI constants (colors, timings)
    │   ├── utils/
    │   │   ├── urlSanitizer.ts        # URL allowlist (https: and mailto: only)
    │   │   └── levenshtein.ts         # String distance for fuzzy matching
    │   ├── hooks/
    │   │   └── useCardData.ts         # Dataset API → typed AssistantCard[]
    │   ├── styles/
    │   │   └── AssistantDashboard.css
    │   └── strings/
    │       └── AssistantDashboard.1033.resx  # Localization strings
    ├── flow-1-email-trigger.json       # Flow 1: Email arrival → triage agent → Dataverse
    ├── flow-2-teams-trigger.json       # Flow 2: Teams mention → triage agent → Dataverse
    ├── flow-3-calendar-trigger.json    # Flow 3: Daily calendar scan → triage agent → Dataverse
    ├── flow-4-send-email.json          # Flow 4: Send email from Canvas app
    ├── flow-5-card-outcome-tracker.json # Flow 5: Card outcome → sender profile upsert
    ├── flow-6-daily-briefing.json      # Flow 6: Per-user daily briefing generation
    ├── flow-7-staleness-monitor.json   # Flow 7: Nudge overdue cards, expire abandoned
    ├── flow-8-command-execution.json   # Flow 8: Command bar → orchestrator agent
    ├── flow-9-sender-profile-analyzer.json # Flow 9: Weekly sender categorization
    ├── flow-10-reminder-firing.json    # Flow 10: Fire due SELF_REMINDER cards via Teams
    ├── tool-search-user-email.json     # Agent tool: Search Outlook inbox (Tier 1)
    ├── tool-search-sent-items.json     # Agent tool: Search sent items (Tier 1)
    ├── tool-search-teams-messages.json # Agent tool: Search Teams messages (Tier 1)
    ├── tool-search-sharepoint.json     # Agent tool: Search SharePoint (Tier 2)
    ├── tool-search-planner-tasks.json  # Agent tool: Search Planner tasks (Tier 3)
    ├── tool-query-cards.json           # Agent tool: Query assistant cards (Orchestrator)
    ├── tool-query-sender-profile.json  # Agent tool: Look up sender profile (Orchestrator)
    ├── tool-update-card.json           # Agent tool: Modify card properties (Orchestrator)
    ├── tool-create-card.json           # Agent tool: Create new card/reminder (Orchestrator)
    ├── tool-refine-draft.json          # Agent tool: Refine draft via Humanizer (Orchestrator)
    ├── triage-topic.yaml               # Copilot Studio topic: Main triage (5 inputs → JSON)
    ├── humanizer-topic.yaml            # Copilot Studio topic: Humanizer connected agent
    ├── briefing-topic.yaml             # Copilot Studio topic: Daily briefing generation
    ├── orchestrator-topic.yaml         # Copilot Studio topic: Command execution + tool actions
    ├── copilot-base-template.yaml      # Copilot Studio base agent template (system topics)
    ├── kickStartTemplate-1.0.0.json    # PAC CLI kickstart template for agent creation
    ├── Solutions/
    │   └── Solution.cdsproj           # Solution packaging project
    ├── AssistantDashboard.pcfproj     # PCF project file
    ├── package.json
    ├── tsconfig.json
    └── .eslintrc.json
```

## Quick Start

### Run the Dashboard Locally (5 minutes, no Power Platform needed)

```bash
cd code-app
npm install
npm run dev          # Opens http://localhost:3000 with 9 sample cards
npm run test         # 199 tests across 18 files
```

The Code App ships with mock data — no credentials, environment, or Dataverse required. See [`code-app/README.md`](code-app/README.md) for details.

### Deploy Full IWL Infrastructure (requires Power Platform)

Prerequisites: [PAC CLI](https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction), [Node.js 20+](https://nodejs.org), [PowerShell 7+](https://github.com/PowerShell/PowerShell), Power Platform environment with Copilot Studio capacity.

```bash
# 1. Provision environment and Dataverse tables
cd scripts
pwsh provision-environment.ps1 -TenantId "<tenant-id>" -AdminEmail "<admin@example.com>"
pwsh create-security-roles.ps1 -OrgUrl "https://<org>.crm.dynamics.com"

# 2. Configure Copilot Studio agent (see deployment-guide.md)

# 3. Deploy Code App to Power Platform
cd ../code-app
npm run build
pac code push

# 4. (Optional) Provision OneNote integration
cd ../scripts
pwsh provision-onenote.ps1 -OrgUrl "https://<org>.crm.dynamics.com" -GroupId "<m365-group-id>"
```

See [docs/deployment-guide.md](docs/deployment-guide.md) for the full step-by-step checklist.

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Code App as forward UI architecture** | Full React 18 ownership, Vite build, direct Dataverse SDK — replaces PCF + Canvas App (legacy) |
| `CardDataService` abstraction | Decouples UI from data source — `MockCardDataService` for offline dev, swap in Dataverse-backed implementation for production |
| Full JSON blob + discrete filter columns | Avoids schema drift; Canvas app uses `ParseJSON()` for detail rendering |
| Canvas app owns filter state | Passes to PCF via input props; reduces unnecessary API calls |
| Virtual PCF control type | Shares platform React tree — no duplicate React instances |
| Platform React 16.14.0 via `<platform-library>` | Don't bundle React; use the platform version |
| Humanizer as separate Connected Agent | Independent versioning, cleaner main prompt |
| Dataset-type PCF | Canvas app handles Dataverse connection; PCF receives pre-filtered records |
| SKIP items not persisted to Dataverse | Avoids null primary column conflict; reduces storage noise |
| SKIP returns minimal JSON | Consistent contract; easier flow error handling |
| Hybrid data: research_log as text, verified_sources as typed array | Simpler prompt for log; typed array enables clickable links in PCF |
| OneNote as optional write-only downstream (Phase 1) | Augments but never replaces Dataverse; works identically if OneNote unavailable |
| Group-scoped Graph app (not delegated `/me/`) | Least-privilege; doesn't break on connection owner changes |
| Feature flag + per-user opt-out for OneNote | Instant rollback; respects user preferences |
| `{{PLACEHOLDER}}` HTML templates for OneNote pages | Separates content from structure; Power Automate handles escaping |
| Draft persistence via `saveDraftAction` output | Debounced (2s) writes to Dataverse ensure edited drafts survive browser refresh |
| Dismiss retry with `pendingDismissals` map | Up to 3 automatic retries prevent silent failures on network issues |
| UX redesign grounded in cognitive research | Card intelligence (Cowan 4±1 queue cap, Zeigarnik draft ownership), attention protection (Gloria Mark 23-min recovery), three-state confidence (arXiv 2024 AI trust calibration), visual sustainability (PMC visual fatigue) |
| Escape key closes overlays and restores focus | Standard keyboard UX: Escape exits edit mode, confirmation, detail view (including BriefingCard), and command bar, then returns focus to the invoking control |

## Known Limitations

| Limitation | Mitigation |
|------------|------------|
| **POC Boundary — augments, does not replace** | This system augments Outlook and Teams — it does not replace them. Users continue to use their primary tools while IWL surfaces prepared intelligence in a companion dashboard. |
| **POC only — not production-hardened** |Full ARIA/screen reader audit, i18n, optimistic concurrency, DataSet paging (100+ cards), and capacity planning are out of scope. See `.planning/ROADMAP.md` for deferred items. |
| No automated data retention — AssistantCards table stores email subjects, sender PII, behavioral profiles, and communication drafts indefinitely with no cleanup flow | For organizations with data retention requirements, implement a scheduled Power Automate flow to delete/archive cards older than N days based on `cr_createdon`. See the Email Productivity Agent's Flow 5 for a 90-day cleanup reference pattern. |
| English-only UI and prompts — the PCF component ships with only English localization (`1033.resx`) and all agent prompts are written in English | Non-English email and Teams content is processed correctly, but UI labels remain in English. Add additional `.resx` files for other locales and localize prompts as needed. |
| OneNote Phase 2-3 not implemented — read-back, annotation promotion, and bi-directional sync are planned but not yet available | Phase 1 (write-only) is fully functional. See [`docs/onenote-integration.md`](docs/onenote-integration.md) for the roadmap. |
| SKIP items not auditable — items triaged as SKIP are not persisted to Dataverse (by design, to reduce storage) so there is no audit trail for why a signal was skipped | If audit requirements apply, extend the Email/Teams agent flows to log SKIP decisions to a separate lightweight Dataverse table or Application Insights before returning. |
