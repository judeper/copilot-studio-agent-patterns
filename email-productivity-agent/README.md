# Email Productivity Agent

A Copilot Studio pattern that brings Gmail-like email productivity features to Outlook — automatic follow-up nudges for unreplied emails and smart snooze that unsnoozes when someone replies. Flow 2 and Flow 4 invoke the Copilot Studio agent via `ExecuteAgentAndWait` for live AI-powered nudge decisioning and smart unsnooze evaluation.

## What It Does

### Follow-Up Nudges (Phase 1)
- **Tracks** every email you send, monitoring for replies per recipient
- **Detects** when a configurable number of business days pass without a response
- **Nudges** you via a Teams Adaptive Card with thread summary, suggested follow-up draft, and one-click actions (Draft / Snooze / Dismiss)
- **Configurable** per-user timeframes: Internal (3 days), External (5 days), Priority (1 day), General (7 days)

### Snooze Auto-Removal (Phase 2)
- **Monitors** a managed `EPA-Snoozed` folder for snoozed email threads
- **Detects** when a new reply arrives on a snoozed conversation
- **Auto-unsnoozes** by moving the email back to Inbox immediately
- **Notifies** you via Teams with context about who replied and what they said

### Agent-Powered Decisioning
- **Flow 2** invokes the Follow-Up Nudge topic in Copilot Studio to evaluate thread context and return a NUDGE or SKIP decision with a thread summary, suggested follow-up draft, priority, and confidence score
- **Flow 4** invokes the Snooze Auto-Removal topic to decide UNSNOOZE or SUPPRESS based on reply content, sender, working hours, and auto-reply detection
- **CLI harness flows (8-13)** provide HTTP-triggered coverage for Flow 2, 2b, 3, 4, 7, and 7b — harness flows 8 and 12 also use live agent invocation

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 FOLLOW-UP NUDGES (Phase 1)                  │
│                                                             │
│  Sent Items ──► Flow 1: Sent Items Tracker                  │
│                   │                                         │
│                   ▼                                         │
│               Dataverse: FollowUpTracking                   │
│               (one row per recipient per email)             │
│                   │                                         │
│                   ▼                                         │
│  Daily 9 AM ──► Flow 2: Response Detection                  │
│                   │                                         │
│          ┌───────┴────────┐                                │
│          │ Reply found?   │                                │
│          └───┬────────┬───┘                                │
│          Yes │        │ No                                  │
│              ▼        ▼                                     │
│         Mark done   Copilot Studio Agent ──► Teams Card    │
│                     (live nudge decisioning via agent)       │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                SNOOZE AUTO-REMOVAL (Phase 2)                │
│                                                             │
│  Every 15 min ──► Flow 3: Snooze Detection                  │
│                     │                                       │
│                     ▼                                       │
│                 Dataverse: SnoozedConversations              │
│                     │                                       │
│  New Inbox Mail ──► Flow 4: Auto-Unsnooze                   │
│                     │                                       │
│          ┌──────────┴──────────┐                           │
│          │ Matches snoozed     │                           │
│          │ conversation?       │                           │
│          └───┬─────────┬──────┘                            │
│          Yes │         │ No                                 │
│              ▼         ▼                                    │
│         Move to      Exit                                   │
│         Inbox + Notify                                      │
└─────────────────────────────────────────────────────────────┘
```

> Flow 2 invokes the Follow-Up Nudge agent topic and Flow 4 invokes the Snooze Auto-Removal agent topic, both via the Copilot Studio connector.

## File Map

```
email-productivity-agent/
├── README.md                                    # This file
├── docs/
│   ├── deployment-guide.md                      # End-to-end deployment checklist
│   ├── demo-walkthrough.md                      # Step-by-step demo guide
│   ├── follow-up-nudge-flows.md                 # Flow 1, 2, 2b, 5 step-by-step specs
│   ├── snooze-auto-removal-flows.md             # Flow 3, 4, 6 step-by-step specs
│   ├── canvas-app-setup.md                      # Settings Canvas App build guide
│   └── configuration-guide.md                   # User-facing settings documentation
├── prompts/
│   ├── nudge-agent-system-prompt.md             # Follow-up nudge agent instructions
│   └── snooze-agent-system-prompt.md            # Snooze auto-removal agent instructions
├── schemas/
│   ├── followup-tracking-table.json             # FollowUpTracking Dataverse table
│   ├── nudge-config-table.json                  # NudgeConfiguration Dataverse table
│   ├── snoozed-conversations-table.json         # SnoozedConversations Dataverse table
│   ├── adaptive-card-nudge.json                 # Teams nudge card template
│   └── adaptive-card-settings.json              # Teams settings card template
├── scripts/
│   ├── provision-environment.ps1                # Environment + Dataverse table setup
│   ├── create-security-roles.ps1                # Ownership-based RLS
│   ├── assign-security-role.ps1                 # Assign role to users
│   ├── deploy-agent-flows.ps1                   # Deploy all Power Automate flows via API
│   ├── provision-copilot.ps1                    # Create + publish Copilot Studio agent
│   ├── check-test-readiness.ps1                 # Validate environment readiness (12 checks)
│   ├── complete-test-setup.ps1                  # Orchestrate full test environment setup
│   ├── invoke-followup-test-harness.ps1         # Trigger Flow 8 by trackingId
│   ├── invoke-http-flow-harness.ps1             # Trigger Flow 9-13 HTTP harnesses
│   └── sync-settings-canvas-app-source.ps1      # Sync canvas app source to repo
├── src/
│   ├── copilot-base-template.yaml               # Copilot Studio base bot template
│   ├── kickStartTemplate-1.0.0.json             # Copilot Studio template metadata
│   ├── nudge-topic.yaml                         # Follow-Up Nudge topic definition
│   ├── snooze-topic.yaml                        # Snooze Auto-Removal topic definition
│   ├── flow-1-sent-items-tracker.json           # Flow 1: event-driven sent email tracker
│   ├── flow-2-response-detection.json           # Flow 2: daily reply check + Teams nudge
│   ├── flow-2b-card-action-handler.json         # Flow 2b: adaptive card button handler
│   ├── flow-3-snooze-detection.json             # Flow 3: scheduled EPA-Snoozed folder scanner
│   ├── flow-4-auto-unsnooze.json                # Flow 4: event-driven auto-unsnooze on reply
│   ├── flow-5-data-retention.json               # Flow 5: weekly 90-day cleanup
│   ├── flow-6-snooze-cleanup.json               # Flow 6: weekly 30-day snooze cleanup
│   ├── flow-7-settings-card.json                # Flow 7: send settings card to Teams
│   ├── flow-7b-settings-handler.json            # Flow 7b: handle settings card submissions
│   ├── flow-8-followup-test-harness.json        # Flow 8: HTTP-triggered Flow 2 test harness
│   ├── flow-9-card-action-test-harness.json     # Flow 9: HTTP-triggered Flow 2b action harness
│   ├── flow-10-settings-handler-test-harness.json # Flow 10: HTTP-triggered Flow 7b harness
│   ├── flow-11-snooze-detection-test-harness.json # Flow 11: HTTP-triggered Flow 3 harness
│   ├── flow-12-auto-unsnooze-test-harness.json  # Flow 12: HTTP-triggered Flow 4 harness
│   └── flow-13-snooze-seed-test-harness.json    # Flow 13: seed a real snoozed message for Flow 11/12 testing
├── tools/
│   └── lab-wizard/                              # Python CLI deployment wizard
│       ├── wizard.py                            # Main entry point (menu-driven)
│       ├── auth.py                              # MSAL + Azure CLI token management
│       ├── config.py                            # Interactive config collection
│       ├── requirements.txt                     # Python dependencies (rich, requests, msal)
│       └── phases/                              # Deployment phase modules (8 files, 9 wizard steps)
```

## Quick Start

### Prerequisites

- [PAC CLI](https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction) (`dotnet tool install --global Microsoft.PowerApps.CLI.Tool`)
- [Azure CLI](https://aka.ms/installazurecli)
- [PowerShell 7+](https://github.com/PowerShell/PowerShell)
- [Python 3.9+](https://www.python.org/) (for the lab wizard)
- Power Platform environment with Copilot Studio capacity for live agent decisioning
- Copilot Studio license is **required** for live agent decisioning in Flow 2, Flow 4, Flow 8, and Flow 12

### Deploy (Lab Wizard — Recommended)

The lab wizard automates all deployment phases interactively:

```powershell
cd email-productivity-agent/tools/lab-wizard
pip install -r requirements.txt
python wizard.py
```

The wizard handles: environment creation, Dataverse tables, security roles, Copilot agent provisioning, connections, flow deployment, user role assignment, validation, and demo email staging. See [docs/demo-walkthrough.md](docs/demo-walkthrough.md) for the step-by-step demo guide.

### Deploy (Manual Scripts)

```powershell
# 1. Provision environment and Dataverse tables
cd email-productivity-agent/scripts
pwsh provision-environment.ps1 -TenantId "<tenant-id>"
pwsh create-security-roles.ps1 -OrgUrl "https://<org>.crm.dynamics.com"
pwsh assign-security-role.ps1 -OrgUrl "https://<org>.crm.dynamics.com"

# 2. Provision Copilot Studio agent (captures Bot ID for flow deployment)
pwsh provision-copilot.ps1 -EnvironmentId "<env-id>"
# Note the Bot ID from the output (e.g., "a1b2c3d4-e5f6-...")

# 3. Deploy Phase 1 flows (pass -CopilotBotId for live agent invocation)
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<org>.crm.dynamics.com" `
    -EnvironmentId "<env-id>" `
    -FlowsToCreate "Phase1" `
    -CopilotBotId "<bot-id>"

# 4. (Phase 2) Deploy snooze flows
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<org>.crm.dynamics.com" `
    -EnvironmentId "<env-id>" `
    -FlowsToCreate "Phase2" `
    -CopilotBotId "<bot-id>"

# 5. (Phase 3) Deploy settings flows
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<org>.crm.dynamics.com" `
    -EnvironmentId "<env-id>" `
    -FlowsToCreate "Phase3"

# 6. (Optional) Deploy regression harness flows — each must be deployed individually
#    Valid values: Flow8, Flow9, Flow10, Flow11, Flow12, Flow13
foreach ($flow in @("Flow8","Flow9","Flow10","Flow11","Flow12","Flow13")) {
    pwsh deploy-agent-flows.ps1 `
        -OrgUrl "https://<org>.crm.dynamics.com" `
        -EnvironmentId "<env-id>" `
        -FlowsToCreate $flow `
        -CopilotBotId "<bot-id>"
}

# 7. (Optional) Run regression harness examples
pwsh invoke-followup-test-harness.ps1 `
    -EnvironmentId "<env-id>" `
    -TrackingId "<cr_followuptrackingid-guid>" `
    -ForceNudge

pwsh invoke-http-flow-harness.ps1 `
    -EnvironmentId "<env-id>" `
    -FlowDisplayName "EPA - Flow 9: Card Action Test Harness" `
    -BodyJson '{"action":"dismiss_nudge","trackingId":"<cr_followuptrackingid-guid>","responderEmail":"<user@domain.com>","responderUserPrincipalName":"<user@domain.com>"}'
```

See [docs/deployment-guide.md](docs/deployment-guide.md) for the full step-by-step checklist, including Flow 10-13 deployment and invocation examples.

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Polling-only for Phase 1-2 (no Graph webhooks) | Graph webhooks require an Azure Function for validation handshake — breaks the low-code constraint |
| Managed `EPA-Snoozed` folder | Outlook's native snoozed folder is not a Graph well-known folder; its display name varies by locale |
| One row per To-line recipient | Multi-recipient emails need per-recipient reply tracking; CC recipients excluded |
| Single-row NudgeConfiguration per user | 4 integer columns (one per recipient type) — simpler than 4 separate rows |
| Auto-GUID PKs + alternate keys | Dataverse requires GUID primary keys; alternate keys remain in the schema, but the validated flow implementations now use `ListRecords` + `UpdateRecord`/`CreateRecord` in places where connector-level alternate-key writes proved unreliable |
| Daily scheduled sweep for nudges | Simple, reliable, low API usage — avoids webhook complexity |
| Event-driven for snooze unsnooze | Must be near-real-time to match Gmail's behavior |
| Live agent decisioning | Flow 2 and Flow 4 invoke the Copilot Studio agent via `ExecuteAgentAndWait` for real-time AI-powered nudge and snooze decisions |
| Flow-generated draft (not Copilot deeplink) | Adaptive Card buttons cannot open Copilot; draft content is generated server-side and posted back |
| Teams Adaptive Card for nudge delivery | Interactive buttons, delivered where users already work |
| Canvas App for configuration | Only viable low-code option for end-user settings management |
| Scope + parallel error branch in all flows | Consistent error handling; individual failures don't crash the entire flow |
| 90-day data retention | Prevents unbounded table growth; weekly cleanup flow purges resolved records |

## Flows Summary

| Flow | Trigger | Purpose |
|------|---------|---------|
| Flow 1: Sent Items Tracker | When a new email is sent | Log to FollowUpTracking (one row per To-line recipient) |
| Flow 2: Response Detection | Daily at 9 AM | Check Graph for replies, deliver nudge Adaptive Cards |
| Flow 2b: Card Action Handler | When someone responds to an adaptive card | Handle Draft / Snooze / Dismiss button clicks |
| Flow 3: Snooze Detection | Every 15 minutes | Scan EPA-Snoozed folder, upsert to SnoozedConversations |
| Flow 4: Auto-Unsnooze | When a new email arrives (Inbox) | Match against snoozed conversations, move back to Inbox |
| Flow 5: Data Retention Cleanup | Weekly (Sunday 2 AM) | Delete resolved FollowUpTracking rows older than 90 days |
| Flow 6: Snooze Cleanup | Weekly (Sunday 2:30 AM) | Delete resolved SnoozedConversation rows older than 30 days |
| Flow 7: Settings Card | Manual/request | Post a Teams settings card so users can review their nudge configuration |
| Flow 7b: Settings Card Handler | Adaptive card response | Persist settings card updates back to Dataverse |
| Flow 8: Follow-Up Test Harness (optional) | HTTP request | Run one Flow 2 candidate by `trackingId`; `-ForceNudge` replays the Teams card path with live agent invocation |
| Flow 9: Card Action Test Harness (optional) | HTTP request | Exercise Flow 2b Draft / Dismiss / Snooze handling without waiting for a Teams card click |
| Flow 10: Settings Handler Test Harness (optional) | HTTP request | Exercise Flow 7b save / restore behavior from the CLI |
| Flow 11: Snooze Detection Test Harness (optional) | HTTP request | Run Flow 3 logic on demand, including folder recovery and snoozed-row upsert |
| Flow 12: Auto-Unsnooze Test Harness (optional) | HTTP request | Replay Flow 4 matching, Graph move, Dataverse update, and Teams notification from the CLI |
| Flow 13: Snooze Seed Test Harness (optional) | HTTP request | Send a test email to self and move it into `EPA-Snoozed` so Flow 11/12 can be tested end to end |

## Lab Verification Status

- **Flow 1** verified against real sent mail and Dataverse row creation
- **Flow 2** verified through **Flow 8** with live agent invocation and forced Teams replay support
- **Flow 2b** verified through **Flow 9** for Draft / Dismiss / Snooze actions
- **Flow 7** verified through direct HTTP invocation
- **Flow 7b** verified through **Flow 10** for save and restore-defaults persistence
- **Flow 3** verified through **Flow 11**, including recovery of an existing `EPA-Snoozed` folder ID and owner-scoped snoozed-row persistence
- **Flow 4** verified through **Flow 12** after reseeding mail with **Flow 13**; the Snooze Agent evaluates reply context and returns UNSNOOZE or SUPPRESS decisions

## CLI Regression Harnesses

| Harness | Validates | Invocation helper |
|---------|-----------|-------------------|
| Flow 8 | Flow 2 follow-up detection and nudge delivery | `invoke-followup-test-harness.ps1` |
| Flow 9 | Flow 2b adaptive-card action handling | `invoke-http-flow-harness.ps1` |
| Flow 10 | Flow 7b settings persistence | `invoke-http-flow-harness.ps1` |
| Flow 11 | Flow 3 snooze detection and Dataverse upsert | `invoke-http-flow-harness.ps1` |
| Flow 12 | Flow 4 auto-unsnooze and Teams notification | `invoke-http-flow-harness.ps1` |
| Flow 13 | Seed a real snoozed message for Phase 2 regression | `invoke-http-flow-harness.ps1` |

The generic `invoke-http-flow-harness.ps1` helper resolves the Flow callback URL, handles the `x-ms-client-scope` requirement, accepts either `-BodyJson` or `-BodyFilePath`, and waits for the run to reach a terminal state.

## Dataverse Tables

| Table | Purpose | Rows Per User |
|-------|---------|---------------|
| `cr_followuptracking` | Tracks sent emails awaiting follow-up | ~50/week (one per recipient per sent email) |
| `cr_nudgeconfiguration` | Per-user nudge settings | 1 |
| `cr_snoozedconversation` | Tracks snoozed email threads | Low volume |
