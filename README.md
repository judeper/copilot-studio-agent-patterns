# Copilot Studio Agent Patterns

A collection of production-ready patterns for building autonomous agents on the Microsoft Copilot Studio + Power Platform stack. Each solution is a self-contained implementation with prompts, schemas, provisioning scripts, and UI components.

## Solutions

| Solution | Description | Components |
|----------|-------------|------------|
| [Enterprise Work Assistant](enterprise-work-assistant/) | Intelligent work layer that intercepts email, Teams, and calendar signals — triaging, researching, and preparing draft responses autonomously via a MARL pipeline with 17 agent prompts, learning from user behavior across 9 Dataverse tables, and rendering results on a PCF React dashboard with WCAG AA compliance. Design docs cover architecture, learning, and UX enhancements. | Copilot Studio agent (17 prompts), Power Automate flows, Dataverse (9 tables with learning system), PCF React dashboard, Canvas app, OneNote (optional) |
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
├── templates/     # HTML templates (e.g., OneNote page templates)
└── src/           # Code components, flow definitions, and topic YAMLs
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
