# Intelligent Work Layer

An intelligent work layer for Microsoft 365 that triages incoming emails, Teams messages, and calendar events — conducting automated research and preparing briefings and draft responses before the user ever has to ask.

## What It Does

- **Triages** every incoming signal into SKIP / LIGHT / FULL tiers based on sender importance, urgency, and action requirements
- **Researches** across 5 tiers: personal email/Teams history, SharePoint/internal wikis, project tools, public web, official documentation
- **Scores confidence** (0-100) based on evidence strength and source reliability
- **Prepares drafts** for emails and Teams replies, calibrated to recipient relationship and tone
- **Surfaces everything** on a single-pane-of-glass Canvas app dashboard with a Power Apps Component Framework (PCF) React component
- **Conversation threading** groups related signals by conversationId so users see context, not isolated messages
- **Snooze/defer** lets users defer cards to a future time; Focus Shield suppresses non-urgent items during deep work
- **Batch actions** enable multi-select dismiss, snooze, and archive with undo support
- **Keyboard shortcuts** provide power-user navigation (j/k to move, ? for help overlay, Esc to close)
- **Graduated autonomy** adapts agent behavior based on user trust — new users get confirmations, experienced users get auto-actions
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
├── docs/
│   ├── agent-flows.md            # Step-by-step flow building guide
│   ├── architecture-enhancements.md # v3.0 MARL pipeline architecture design
│   ├── architecture-overview.md  # System architecture and "Intelligent Work Layer" positioning
│   ├── canvas-app-setup.md       # Canvas app + PCF configuration
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
│   ├── provision-env-variables.ps1    # Create Dataverse environment variables for flows
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
│   ├── orchestrator-output-schema.json # Orchestrator agent response format (command bar)
│   └── router-output-schema.json      # Router agent routing decision format (Phase 5)
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
    │   │   ├── BatchActionBar.tsx      # Multi-select batch operations (dismiss, snooze, archive)
    │   │   ├── KeyboardHelpOverlay.tsx # Keyboard shortcut reference overlay (? key)
    │   │   ├── OnboardingWizard.tsx   # First-run setup wizard for new users
    │   │   ├── UndoToast.tsx          # Timed undo notification for destructive actions
    │   │   ├── ErrorBoundary.tsx      # React error boundary
    │   │   ├── types.ts              # TypeScript interfaces from schema
    │   │   └── constants.ts          # UI constants (colors, timings)
    │   ├── utils/
    │   │   ├── urlSanitizer.ts        # URL allowlist (https: and mailto: only)
    │   │   └── levenshtein.ts         # String distance for fuzzy matching
    │   ├── hooks/
    │   │   ├── useCardData.ts         # Dataset API → typed AssistantCard[]
    │   │   ├── useConversationClusters.ts # Group cards by conversationId into threaded clusters
    │   │   └── useKeyboardNavigation.ts # Global keyboard shortcut bindings (j/k nav, ? help, Esc close)
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
    ├── flow-11-external-action-scanner.json # Flow 11: Detect external replies → auto-resolve cards
    ├── flow-12-light-auto-archive.json # Flow 12: Expire stale LIGHT cards after 48h
    ├── flow-13-data-retention.json     # Flow 13: GDPR cleanup — delete resolved cards/memory >90 days
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
    ├── tool-query-onenote.json         # Agent tool: Search OneNote notebook pages (Orchestrator)
    ├── tool-update-onenote.json        # Agent tool: Create/append OneNote pages (Orchestrator)
    ├── tool-query-skills.json          # Agent tool: Look up available skills (Orchestrator)
    ├── tool-execute-skill.json         # Agent tool: Run a registered skill (Orchestrator)
    ├── tool-assign-task.json           # Agent tool: Delegate task via Planner/To Do (Delegation)
    ├── tool-track-completion.json      # Agent tool: Monitor delegated task status (Delegation)
    ├── tool-promote-knowledge.json     # Agent tool: Promote episodic → semantic knowledge (Learning)
    ├── tool-analyze-sent-patterns.json # Agent tool: Analyze sent email tone/frequency (Analytics)
    ├── triage-topic.yaml               # Copilot Studio topic: Main triage (5 inputs → JSON)
    ├── humanizer-topic.yaml            # Copilot Studio topic: Humanizer connected agent
    ├── briefing-topic.yaml             # Copilot Studio topic: Daily briefing generation
    ├── orchestrator-topic.yaml         # Copilot Studio topic: Command execution + tool actions
    ├── draft-refiner-topic.yaml        # Copilot Studio topic: Iterative draft refinement
    ├── delegation-topic.yaml           # Copilot Studio topic: Task delegation routing
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

### Prerequisites

- [PAC CLI](https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction) (`dotnet tool install --global Microsoft.PowerApps.CLI.Tool`)
- [Bun 1.x+](https://bun.sh) — JavaScript runtime used by the build scripts
- [Node.js 20+](https://nodejs.org) — Required for PCF tooling
- [PowerShell 7+](https://github.com/PowerShell/PowerShell)
- Power Platform environment with Copilot Studio capacity

### Deploy

```bash
# 1. Provision environment and Dataverse table
cd scripts
pwsh provision-environment.ps1 -TenantId "<tenant-id>" -AdminEmail "<admin@domain.com>"
pwsh create-security-roles.ps1 -OrgUrl "https://<org>.crm.dynamics.com"
pwsh provision-env-variables.ps1 -OrgUrl "https://<org>.crm.dynamics.com" -AdminNotificationEmail "<admin@domain.com>"

# 2. Configure Copilot Studio agent (see deployment-guide.md)

# 3. Build and deploy PCF component
pwsh deploy-solution.ps1 -EnvironmentId "<env-id>"

# 4. Create Canvas app (see canvas-app-setup.md)

# 5. (Optional) Provision OneNote integration
pwsh provision-onenote.ps1 -OrgUrl "https://<org>.crm.dynamics.com" -GroupId "<m365-group-id>"
pwsh validate-onenote-integration.ps1 -OrgUrl "https://<org>.crm.dynamics.com"
```

See [docs/deployment-guide.md](docs/deployment-guide.md) for the full step-by-step checklist.

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
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
| Data retention requires Flow 13 — AssistantCards table stores email subjects, sender PII, behavioral profiles, and communication drafts. Flow 13 (Data Retention) runs weekly to delete resolved cards and episodic memory older than 90 days. | Deploy Flow 13 for automated GDPR-compliant cleanup. Adjust the 90-day retention window in the flow's filter expression to match your organization's data retention policy. |
| English-only UI and prompts — the PCF component ships with only English localization (`1033.resx`) and all agent prompts are written in English | Non-English email and Teams content is processed correctly, but UI labels remain in English. Add additional `.resx` files for other locales and localize prompts as needed. |
| OneNote Phase 2-3 not implemented — read-back, annotation promotion, and bi-directional sync are planned but not yet available | Phase 1 (write-only) is fully functional. See [`docs/onenote-integration.md`](docs/onenote-integration.md) for the roadmap. |
| SKIP items not auditable — items triaged as SKIP are not persisted to Dataverse (by design, to reduce storage) so there is no audit trail for why a signal was skipped | If audit requirements apply, extend the Email/Teams agent flows to log SKIP decisions to a separate lightweight Dataverse table or Application Insights before returning. |
