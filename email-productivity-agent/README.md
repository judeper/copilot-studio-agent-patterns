# Email Productivity Agent

A Copilot Studio pattern that brings Gmail-like email productivity features to Outlook — automatic follow-up nudges for unreplied emails and smart snooze that unsnoozes when someone replies. The current dry-run build keeps Flow 2 deterministic with a mocked agent payload and Flow 4 in POC bypass mode, while the Copilot prompt assets remain in the repo for later re-enablement.

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

### Current POC Runtime Mode
- **Flow 2** uses a mocked agent response so reply detection, Dataverse updates, and Teams card delivery can be regression-tested without a live Copilot dependency
- **Flow 4** bypasses the live Snooze Agent and always takes the deterministic UNSNOOZE path when a matching snoozed conversation is found
- **CLI harness flows (8-13)** provide HTTP-triggered coverage for Flow 2, 2b, 3, 4, 7, and 7b

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
│         Mark done   Mocked / optional Agent ──► Teams Card  │
│                     (current POC uses mocked output)        │
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

> In the currently validated dry-run build, Flow 2 uses mocked agent output and Flow 4 bypasses live Snooze Agent decisioning for stable CLI-driven regression tests.

## File Map

```
email-productivity-agent/
├── README.md                                    # This file
├── docs/
│   ├── deployment-guide.md                      # End-to-end deployment checklist
│   ├── follow-up-nudge-flows.md                 # Flow 1, 2, 2b, 5 step-by-step specs
│   ├── snooze-auto-removal-flows.md             # Flow 3, 4, 6 step-by-step specs
│   └── configuration-guide.md                   # User-facing settings documentation
├── prompts/
│   ├── nudge-agent-system-prompt.md             # Follow-up nudge agent instructions
│   └── snooze-agent-system-prompt.md            # Snooze auto-removal agent instructions
├── schemas/
│   ├── followup-tracking-table.json             # FollowUpTracking Dataverse table
│   ├── nudge-config-table.json                  # NudgeConfiguration Dataverse table
│   ├── snoozed-conversations-table.json         # SnoozedConversations Dataverse table
│   └── adaptive-card-nudge.json                 # Teams Adaptive Card template
├── scripts/
│   ├── provision-environment.ps1                # Environment + Dataverse table setup
│   ├── create-security-roles.ps1                # Ownership-based RLS
│   ├── assign-security-role.ps1                 # Assign role to users
│   ├── deploy-agent-flows.ps1                   # Deploy all Power Automate flows via API
│   ├── invoke-followup-test-harness.ps1         # Trigger Flow 8 by trackingId and wait for run status
│   └── invoke-http-flow-harness.ps1             # Trigger Flow 9-13 HTTP harnesses and wait for run status
├── src/
│   ├── nudge-topic.yaml                         # Copilot Studio topic YAML (paste into code editor)
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
```

## Quick Start

### Prerequisites

- [PAC CLI](https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction) (`dotnet tool install --global Microsoft.PowerApps.CLI.Tool`)
- [Azure CLI](https://aka.ms/installazurecli)
- [PowerShell 7+](https://github.com/PowerShell/PowerShell)
- Power Platform environment (Copilot Studio capacity is only required if you plan to re-enable live agent steps)
- Copilot Studio license is optional in the current POC build and only needed when re-enabling live agent decisioning

### Deploy

```powershell
# 1. Provision environment and Dataverse tables
cd email-productivity-agent/scripts
pwsh provision-environment.ps1 -TenantId "<tenant-id>"
pwsh create-security-roles.ps1 -OrgUrl "https://<org>.crm.dynamics.com"
pwsh assign-security-role.ps1 -OrgUrl "https://<org>.crm.dynamics.com"

# 2. (Optional) Configure Copilot Studio agent if you plan to re-enable live agent decisioning later

# 3. Deploy Phase 1 flows
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<org>.crm.dynamics.com" `
    -EnvironmentId "<env-id>" `
    -FlowsToCreate "Phase1"

# 4. (Phase 2) Deploy snooze flows
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<org>.crm.dynamics.com" `
    -EnvironmentId "<env-id>" `
    -FlowsToCreate "Phase2"

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
        -FlowsToCreate $flow
}

# 7. (Optional) Run regression harness examples
pwsh invoke-followup-test-harness.ps1 `
    -EnvironmentId "<env-id>" `
    -TrackingId "<cr_followuptrackingid-guid>" `
    -ForceNudge

pwsh invoke-http-flow-harness.ps1 `
    -EnvironmentId "<env-id>" `
    -FlowDisplayName "EPA - Flow 9: Card Action Test Harness" `
    -BodyJson '{"action":"dismiss_nudge","trackingId":"<cr_followuptrackingid-guid>","responderEmail":"<user@example.com>","responderUserPrincipalName":"<user@example.com>"}'
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
| Deterministic POC decisioning | The current dry-run keeps Flow 2 mocked and Flow 4 bypassed so automated validation stays stable while the Copilot prompt assets remain available for later re-enable |
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
| Flow 8: Follow-Up Test Harness (optional) | HTTP request | Run one Flow 2 candidate by `trackingId`; `-ForceNudge` replays the Teams card path with a mocked agent response |
| Flow 9: Card Action Test Harness (optional) | HTTP request | Exercise Flow 2b Draft / Dismiss / Snooze handling without waiting for a Teams card click |
| Flow 10: Settings Handler Test Harness (optional) | HTTP request | Exercise Flow 7b save / restore behavior from the CLI |
| Flow 11: Snooze Detection Test Harness (optional) | HTTP request | Run Flow 3 logic on demand, including folder recovery and snoozed-row upsert |
| Flow 12: Auto-Unsnooze Test Harness (optional) | HTTP request | Replay Flow 4 matching, Graph move, Dataverse update, and Teams notification from the CLI |
| Flow 13: Snooze Seed Test Harness (optional) | HTTP request | Send a test email to self and move it into `EPA-Snoozed` so Flow 11/12 can be tested end to end |

## Dry-Run Verification Status

- **Flow 1** verified against real sent mail and Dataverse row creation
- **Flow 2** verified through **Flow 8** with mocked agent output and forced Teams replay support
- **Flow 2b** verified through **Flow 9** for Draft / Dismiss / Snooze actions
- **Flow 7** verified through direct HTTP invocation
- **Flow 7b** verified through **Flow 10** for save and restore-defaults persistence
- **Flow 3** verified through **Flow 11**, including recovery of an existing `EPA-Snoozed` folder ID and owner-scoped snoozed-row persistence
- **Flow 4** verified through **Flow 12** after reseeding mail with **Flow 13**; the current deployed build uses the deterministic bypass path and no longer relies on a failing live Snooze Agent fallback

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
