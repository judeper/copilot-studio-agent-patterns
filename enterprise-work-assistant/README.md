# Enterprise Work Assistant

An AI-powered assistant that triages incoming emails, Teams messages, and calendar events — conducting automated research and preparing briefings and draft responses before the user ever has to ask.

## What It Does

- **Triages** every incoming signal into SKIP / LIGHT / FULL tiers based on sender importance, urgency, and action requirements
- **Researches** across 5 tiers: personal email/Teams history, SharePoint/internal wikis, project tools, public web, official documentation
- **Scores confidence** (0-100) based on evidence strength and source reliability
- **Prepares drafts** for emails and Teams replies, calibrated to recipient relationship and tone
- **Surfaces everything** on a single-pane-of-glass Canvas app dashboard with a Power Apps Component Framework (PCF) React component
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
enterprise-work-assistant/
├── docs/
│   ├── agent-flows.md            # Step-by-step flow building guide
│   ├── canvas-app-setup.md       # Canvas app + PCF configuration
│   ├── deployment-guide.md       # End-to-end deployment checklist
│   └── onenote-integration.md    # OneNote integration design (Phase 1-3)
├── prompts/
│   ├── main-agent-system-prompt.md    # Main agent operating instructions
│   ├── humanizer-agent-prompt.md      # Tone calibration prompt
│   ├── daily-briefing-agent-prompt.md # Daily briefing agent instructions
│   └── orchestrator-agent-prompt.md   # Orchestrator agent instructions
├── scripts/
│   ├── provision-environment.ps1      # Environment + Dataverse setup
│   ├── create-security-roles.ps1      # Ownership-based RLS
│   ├── deploy-solution.ps1            # PCF build + solution import
│   ├── provision-onenote.ps1          # OneNote notebook + section provisioning
│   ├── validate-onenote-integration.ps1 # Verify OneNote integration health
│   └── audit-table-naming.ps1         # Dataverse table naming audit
├── schemas/
│   ├── output-schema.json             # JSON Schema for agent output
│   ├── dataverse-table.json           # AssistantCards table definition
│   ├── briefing-output-schema.json    # Daily briefing output schema
│   ├── briefingschedule-table.json    # BriefingSchedule table definition
│   └── senderprofile-table.json       # SenderProfile table definition
├── templates/
│   ├── onenote-meeting-prep.html      # OneNote meeting prep page template
│   ├── onenote-daily-briefing.html    # OneNote daily briefing page template
│   └── onenote-active-todos.html      # OneNote active to-dos page template
└── src/                               # PCF React component
    ├── AssistantDashboard/
    │   ├── ControlManifest.Input.xml  # PCF manifest (virtual, dataset)
    │   ├── index.ts                   # PCF lifecycle entry point
    │   ├── components/
    │   │   ├── App.tsx                # Root component (gallery/detail router)
    │   │   ├── CardGallery.tsx        # Scrollable card list
    │   │   ├── CardItem.tsx           # Collapsed card (priority, icon, summary)
    │   │   ├── CardDetail.tsx         # Expanded card view (research, draft, sources)
    │   │   ├── FilterBar.tsx          # Active filter status bar
    │   │   └── types.ts              # TypeScript interfaces from schema
    │   ├── hooks/
    │   │   └── useCardData.ts         # Dataset API → typed AssistantCard[]
    │   ├── styles/
    │   │   └── AssistantDashboard.css
    │   └── strings/
    │       └── AssistantDashboard.1033.resx  # Localization strings
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
- [Node.js 18+](https://nodejs.org)
- [PowerShell 7+](https://github.com/PowerShell/PowerShell)
- Power Platform environment with Copilot Studio capacity

### Deploy

```bash
# 1. Provision environment and Dataverse table
cd scripts
pwsh provision-environment.ps1 -TenantId "<tenant-id>" -AdminEmail "<admin@example.com>"
pwsh create-security-roles.ps1 -OrgUrl "https://<org>.crm.dynamics.com"

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
