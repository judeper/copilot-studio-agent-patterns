# Email Productivity Agent

A Copilot Studio autonomous agent that brings Gmail-like email productivity features to Outlook — automatic follow-up nudges for unreplied emails and smart snooze that unsnoozes when someone replies.

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
│         Mark done   Copilot Agent ──► Teams Adaptive Card   │
│                     (assess, summarize, draft)              │
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

## File Map

```
email-productivity-agent/
├── README.md                                    # This file
├── docs/
│   ├── deployment-guide.md                      # End-to-end deployment checklist
│   ├── follow-up-nudge-flows.md                 # Flow 1, 2, 5 step-by-step specs
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
│   └── deploy-agent-flows.ps1                   # Deploy all Power Automate flows via API
├── src/
│   ├── nudge-topic.yaml                         # Copilot Studio topic YAML (paste into code editor)
│   ├── flow-1-sent-items-tracker.json           # Flow 1: event-driven sent email tracker
│   ├── flow-2-response-detection.json           # Flow 2: daily reply check + Teams nudge
│   ├── flow-2b-card-action-handler.json         # Flow 2b: adaptive card button handler
│   └── flow-5-data-retention.json               # Flow 5: weekly 90-day cleanup
```

## Quick Start

### Prerequisites

- [PAC CLI](https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction) (`dotnet tool install --global Microsoft.PowerApps.CLI.Tool`)
- [Azure CLI](https://aka.ms/installazurecli)
- [PowerShell 7+](https://github.com/PowerShell/PowerShell)
- Power Platform environment with Copilot Studio capacity
- Copilot Studio license (Agent Flows cover premium connectors — no Power Automate Premium needed)

### Deploy

```powershell
# 1. Provision environment and Dataverse tables
cd email-productivity-agent/scripts
pwsh provision-environment.ps1 -TenantId "<tenant-id>" -AdminEmail "<admin@domain.com>"
pwsh create-security-roles.ps1 -OrgUrl "https://<org>.crm.dynamics.com"
pwsh assign-security-role.ps1 -OrgUrl "https://<org>.crm.dynamics.com"

# 2. Configure Copilot Studio agent (see docs/deployment-guide.md Step 3)

# 3. Deploy all Power Automate flows
pwsh deploy-agent-flows.ps1 -EnvironmentId "<env-id>" -OrgUrl "https://<org>.crm.dynamics.com"

# 4. (Phase 2) Build snooze flows (see docs/snooze-auto-removal-flows.md)
```

See [docs/deployment-guide.md](docs/deployment-guide.md) for the full step-by-step checklist.

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Polling-only for Phase 1-2 (no Graph webhooks) | Graph webhooks require an Azure Function for validation handshake — breaks the low-code constraint |
| Managed `EPA-Snoozed` folder | Outlook's native snoozed folder is not a Graph well-known folder; its display name varies by locale |
| One row per To-line recipient | Multi-recipient emails need per-recipient reply tracking; CC recipients excluded |
| Single-row NudgeConfiguration per user | 4 integer columns (one per recipient type) — simpler than 4 separate rows |
| Auto-GUID PKs + alternate keys | Dataverse requires GUID primary keys; text-based alternate keys enable safe Upsert |
| Daily scheduled sweep for nudges | Simple, reliable, low API usage — avoids webhook complexity |
| Event-driven for snooze unsnooze | Must be near-real-time to match Gmail's behavior |
| Flow-generated draft (not Copilot deeplink) | Adaptive Card buttons cannot open Copilot; draft is generated server-side and posted back |
| Teams Adaptive Card for nudge delivery | Interactive buttons, delivered where users already work |
| Canvas App for configuration | Only viable low-code option for end-user settings management |
| Scope + parallel error branch in all flows | Consistent error handling; individual failures don't crash the entire flow |
| 90-day data retention | Prevents unbounded table growth; weekly cleanup flow purges resolved records |

## Flows Summary

| Flow | Trigger | Purpose |
|------|---------|---------|
| Flow 1: Sent Items Tracker | When a new email is sent | Log to FollowUpTracking (one row per To-line recipient) |
| Flow 2: Response Detection | Daily at 9 AM | Check Graph for replies, deliver nudge Adaptive Cards |
| Flow 3: Snooze Detection | Every 15 minutes | Scan EPA-Snoozed folder, upsert to SnoozedConversations |
| Flow 4: Auto-Unsnooze | When a new email arrives (Inbox) | Match against snoozed conversations, move back to Inbox |
| Flow 5: Nudge Cleanup | Weekly (Sunday 2 AM) | Delete resolved FollowUpTracking rows older than 90 days |
| Flow 6: Snooze Cleanup | Weekly (Sunday 2:30 AM) | Delete resolved SnoozedConversation rows older than 30 days |

## Dataverse Tables

| Table | Purpose | Rows Per User |
|-------|---------|---------------|
| `cr_followuptracking` | Tracks sent emails awaiting follow-up | ~50/week (one per recipient per sent email) |
| `cr_nudgeconfiguration` | Per-user nudge settings | 1 |
| `cr_snoozedconversation` | Tracks snoozed email threads | Low volume |
