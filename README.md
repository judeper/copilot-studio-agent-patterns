# Copilot Studio Agent Patterns

A collection of production-ready patterns for building autonomous agents on the Microsoft Copilot Studio + Power Platform stack. Each solution is a self-contained implementation with prompts, schemas, provisioning scripts, and UI components.

## Solutions

| Solution | Description | Components |
|----------|-------------|------------|
| [Enterprise Work Assistant](enterprise-work-assistant/) | AI assistant that triages emails, Teams messages, and calendar events — conducting research, preparing briefings and drafts, and optionally syncing to OneNote for offline access | Copilot Studio agent, Power Automate flows, Dataverse, Power Apps Component Framework (PCF) React dashboard, Canvas app, OneNote (optional) |
| [Email Productivity Agent](email-productivity-agent/) | Gmail-like follow-up nudges and smart snooze for Outlook — automatically reminds you to follow up on unreplied emails and unsnoozes threads when new replies arrive | Copilot Studio agent, Power Automate flows, Dataverse, Teams Adaptive Cards |
| [Agent Cost Governance — PAYGO](agent-cost-governance-paygo/) | Leadership-quality PAYGO cost visibility for Copilot Studio agents — budget dashboards, alerts, and FSI regulatory alignment using Azure Cost Management + Power BI | Azure Cost Management, Power BI, PowerShell provisioning, ARM templates, FSI governance artifacts |

## Prerequisites

- [PAC CLI](https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction) — Power Platform CLI for provisioning and deployment
- [Node.js 18+](https://nodejs.org) — Required for Power Apps Component Framework (PCF) component builds
- [PowerShell 7+](https://github.com/PowerShell/PowerShell) — Required for provisioning scripts
- Power Platform environment with Copilot Studio capacity

## Repository Structure

Each solution lives in its own top-level folder with a consistent structure:

```
<solution-name>/
├── docs/          # Setup guides and flow documentation
├── prompts/       # Agent system prompts
├── scripts/       # Provisioning and deployment PowerShell scripts
├── schemas/       # JSON schemas and table definitions
└── src/           # Code components (PCF, custom connectors, etc.)
```

## Getting Started

1. Pick a solution from the table above
2. Read its `README.md` for architecture overview
3. Follow `docs/deployment-guide.md` for step-by-step setup

## Contributing

Each solution should include:
- System prompts with clear input/output contracts
- JSON schemas for structured data
- Provisioning scripts for repeatable environment setup
- Documentation sufficient for a Power Platform maker to implement the flows
