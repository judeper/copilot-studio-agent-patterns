# Work Routing — `copilot-studio-agent-patterns`

How to decide who handles what.

## Solutions in this repo

| Solution | Primary | Backup | Notes |
|---|---|---|---|
| **copilot-agent-debug-logger** (current build, v5 plan) | @danny (orchestration); domain artifacts per table below | @rusty | POC scope; 19 todos; council-validated |
| **intelligent-work-layer** (IWL) | @danny | @rusty | Reference patterns; do not modify without explicit task |
| **email-productivity-agent** (EPA) | @danny | @rusty | Reference patterns; do not modify without explicit task |
| **agent-cost-governance-paygo** | @danny | @rusty | Reference patterns; do not modify without explicit task |

## Routing Table (domains)

| Work Type | Primary | Backup | Examples |
|-----------|---------|--------|----------|
| **Triage / Planning / Cross-cutting** | @danny | @rusty | Decompose v5 todos; route work; coordinate councils |
| **Dataverse tables / schema** | @frank | @danny | `agenttrace-table.json`, env-var definitions, table relationships |
| **Solution scaffold / ALM packaging** | @frank | @basher | `Solution.cdsproj`, `Solution.xml`, `Customizations.xml`, MDA unpack |
| **Model-driven apps** | @frank | @saul | `Agent Debug Console` MDA (Phase-0 manual authoring + unpack) |
| **Power Automate flows (manual / scheduled triggers)** | @virgil | @basher | `flow-1-log-agent-trace.json` (child flow) |
| **Power Automate tool flows (PVA trigger)** | @virgil | @basher | `tool-log-agent-trace.json` (must mirror IWL `tool-search-sharepoint.json` error pattern verbatim) |
| **Copilot Studio topics** | @linus | @virgil | `*.topic.mcs.yml` × 4 (full + blog-pure variants per concern) |
| **PowerShell automation / scripts** | @basher | @frank | `provision-environment.ps1`, `deploy-solution.ps1`, `inject-flow-guid.ps1` |
| **PAC CLI / Web API workflows** | @basher | @frank | Solution import, env var management, flow GUID lookup |
| **Maker-facing docs (deployment, walk-throughs)** | @saul | @danny | `deployment-guide.md`, `maker-guide.md`, click-paths, sample input JSON |
| **README / architecture / cheatsheets** | @saul | @danny | `README.md`, `native-debugging-cheatsheet.md`, `skills-plugin-guide.md` |
| **Code review / quality gates** | @rusty | @danny | Every PR; PII scan; v5 plan adherence check |
| **Council critique coordination** | @danny | @rusty | Spawning multi-lens reviewers + consensus synthesis |
| **Session logging** | Scribe | — | Automatic, runs in background, never blocks |

## Issue Routing

| Label | Action | Who |
|-------|--------|-----|
| `squad` | Triage: analyze issue, assign `squad:<member>` label | @danny |
| `squad:lead` | Plan / triage / cross-cutting work | @danny |
| `squad:flow` | Power Automate flow JSON | @virgil |
| `squad:topic` | Copilot Studio topic YAML | @linus |
| `squad:schema` | Dataverse table or solution scaffolding | @frank |
| `squad:scripts` | PowerShell / PAC CLI / ALM | @basher |
| `squad:docs` | README / deployment / maker docs | @saul |
| `squad:review` | Code review / PR gate | @rusty |

### How Issue Assignment Works

1. When a GitHub issue gets the `squad` label, @danny triages it — analyzing content, assigning the right `squad:<member>` label, and commenting with triage notes.
2. When a `squad:<member>` label is applied, that member picks up the issue in their next round.
3. Members can reassign by removing their label and adding another member's label.
4. The `squad` label is the "inbox" — untriaged issues waiting for @danny.

## Human Review Gates

The label **`needs-human-review`** blocks any merge until Jude approves. Apply automatically when:

- 🔒 Dataverse schema changes (any new column, table, or relationship)
- 🔒 Environment variable changes (definition or default value)
- 🔒 PowerShell scripts that touch a real Power Platform environment
- 🔒 Anything that would call `pac solution import` against a live tenant
- 🔒 Public-facing maker documentation (final review before customer eyes)

@rusty applies this label as part of the reviewer gate. Squad CI fails on PRs with this label unmerged.

## ESS-Specific Coordination Patterns (debug logger POC)

| Scenario | Primary | Coordinates With |
|----------|---------|------------------|
| Tool flow + topic template must agree on response schema | @virgil | @linus |
| Topic template references flow GUID via `{{TOOL_LOG_AGENT_TRACE_FLOW_ID}}` placeholder | @linus | @basher (the script that substitutes it) |
| Table schema field added/changed → flow Create_AgentTrace_Row must update | @frank | @virgil |
| MDA references table columns → field rename ripples to MDA | @frank | @saul (docs) |
| Maker guide references exact click-paths → @saul must verify against actual UI | @saul | @danny (sign-off) |

## Rules

1. **Eager by default** — spawn all members who could usefully start work in parallel.
2. **Scribe always runs** in the background after substantial work.
3. **Quick facts → coordinator answers directly.** Don't spawn a member for "what's the PAC CLI version requirement?"
4. **"Team, ..." → fan-out** to all relevant members in parallel.
5. **Council critique** for any decision that would change v5 plan beyond a typo fix.
6. **Schema changes** always reviewed by @rusty AND human-gated.
7. **Anticipate downstream** — if @virgil builds the tool flow, spawn @linus simultaneously to author the topic template that calls it.

## Escalation Path

1. Member flags blocker by labeling the issue `go:blocked` and `@`-mentioning Jude
2. @danny coordinates if it's a cross-member dependency
3. For genuine ambiguities about the v5 plan, @danny may request a fresh council round before proceeding
