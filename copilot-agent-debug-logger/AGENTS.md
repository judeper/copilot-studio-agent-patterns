# AGENTS.md — Copilot Agent Debug Logger

> Optimized for AI coding agents. Human contributors should start with [`README.md`](README.md) and [`docs/maker-guide.md`](docs/maker-guide.md).

## Mission

Maker-focused POC that fills 3 specific gaps Microsoft's native Copilot Studio + Power Automate debugging stack leaves open:

1. Power Automate request/response payload capture
2. Shared correlation ID stitching across CS-side topic events and PA-side flow events
3. Drop-in Chain-of-Thought + Conversation History topic templates from the Power CAT Custom Engine blog (Oct 2025) in **full** + **blog-pure** variants per decision D6

Scope discipline (POC, not production) — see [`README.md`](README.md) "What This Is NOT" and [`docs/native-debugging-cheatsheet.md`](docs/native-debugging-cheatsheet.md) for the native stack to exhaust first.

## Stack

| Layer | Technology |
|---|---|
| Schema | JSON definitions in [`schemas/`](schemas/) consumed by PowerShell provisioner via Dataverse Web API |
| Flows | Power Automate cloud flows — JSON definitions in [`src/`](src/) (child flow + PVA tool flow) |
| Topics | Copilot Studio Adaptive Dialog YAML (`*.topic.mcs.yml`) in [`copilot-studio/topics/`](copilot-studio/topics/) |
| MDA | Model-driven app — Phase-0 manual authoring per D7; XML unpacked into [`src/Solutions/src/AppModules/`](src/Solutions/src/) |
| Solution | Unmanaged Dataverse solution — `CopilotAgentDebugLogger` — packed via `Microsoft.PowerApps.MSBuild.Solution` MSBuild SDK |
| Scripts | PowerShell 7+ — provision (Web API), deploy (MSBuild + `pac solution import`), inject-flow-guid (Flow Mgmt API + placeholder substitution) |
| Auth | PAC CLI for tenant ops, `az account get-access-token` for Dataverse Web API + Flow Mgmt API bearer tokens |

## Commands

```powershell
# Provision (create table + env var; idempotent — safe to re-run)
pwsh scripts\provision-environment.ps1 -EnvironmentId "<env-guid>"

# Deploy (build cdsproj → import solution → optional GUID inject)
pwsh scripts\deploy-solution.ps1 -EnvironmentId "<env-guid>" -SkipInjectFlowGuid    # first deploy
pwsh scripts\deploy-solution.ps1 -EnvironmentId "<env-guid>"                          # subsequent deploys (after tool-flow Action add)

# Substitute {{TOOL_LOG_AGENT_TRACE_FLOW_ID}} placeholder in topic YAMLs
pwsh scripts\inject-flow-guid.ps1 -EnvironmentId "<env-guid>"

# Local build of the solution package (sanity check, no env required)
cd src\Solutions
dotnet restore .\CopilotAgentDebugLogger.cdsproj --verbosity minimal
dotnet build .\CopilotAgentDebugLogger.cdsproj --configuration Debug --nologo --verbosity minimal
# → produces bin\Debug\CopilotAgentDebugLogger.zip
```

There are no automated tests — validation is operator-driven via the smoke test in [`docs/maker-guide.md`](docs/maker-guide.md#quick-start-hello-world) and the validation checklist in [`docs/deployment-guide.md`](docs/deployment-guide.md#validation-checklist).

## File map

```
copilot-agent-debug-logger/
├── AGENTS.md                                    ← this file (AI-context companion)
├── README.md                                    ← human-facing POC framing
├── schemas/
│   ├── agenttrace-table.json                    ← 13-column Dataverse table definition
│   └── debugloggerenabled-envvar.json           ← Boolean env var (single kill switch)
├── copilot-studio/topics/
│   ├── log-chain-of-thoughts.topic.mcs.yml             ← FULL (Message + InvokeFlowAction)
│   ├── log-chain-of-thoughts-blog-pure.topic.mcs.yml   ← BLOG-PURE (Message only, zero deps)
│   ├── save-conversation-history.topic.mcs.yml         ← FULL (silent capture + InvokeFlowAction)
│   └── save-conversation-history-blog-pure.topic.mcs.yml  ← BLOG-PURE (capture only)
├── scripts/
│   ├── provision-environment.ps1                ← table + env var via Web API; idempotent
│   ├── deploy-solution.ps1                      ← MSBuild + pac solution import + GUID inject
│   └── inject-flow-guid.ps1                     ← {{TOOL_LOG_AGENT_TRACE_FLOW_ID}} substitution
├── docs/
│   ├── native-debugging-cheatsheet.md           ← use Microsoft's native stack FIRST
│   ├── phase-0-mda-authoring.md                 ← Maker-portal click-paths for the MDA (D7)
│   ├── deployment-guide.md                      ← end-to-end maker walkthrough
│   ├── maker-guide.md                           ← Quick Start + Patterns A–E
│   └── skills-plugin-guide.md                   ← CLI alternative for topic import
└── src/
    ├── flow-1-log-agent-trace.json              ← child flow (Request/Button trigger; reference)
    ├── tool-log-agent-trace.json                ← PVA tool flow (reference; manual Action add required)
    └── Solutions/                               ← Microsoft-canonical unmanaged solution layout
        ├── CopilotAgentDebugLogger.cdsproj      ← produced by `pac solution clone`
        ├── .gitignore                           ← pac defaults
        └── src/
            ├── Other/{Solution.xml, Customizations.xml, Relationships*/}
            ├── Entities/cr_agenttrace/{Entity.xml, FormXml/, SavedQueries/, RibbonDiff.xml}
            ├── AppModules/cr_AgentDebugConsole/{AppModule.xml, ...}
            ├── AppModuleSiteMaps/cr_AgentDebugConsole/{AppModuleSiteMap.xml, ...}
            └── environmentvariabledefinitions/cr_DebugLoggerEnabled/{...}
```

## Critical constraints (must not violate)

These are council-approved decisions (see [`.squad/decisions.md`](../.squad/decisions.md) for the full register) plus the Section A no-debate fixes from the v5 plan. If a change conflicts with any of these, the change is invalid — open a council round before proceeding.

- **A1** — `cr_tracelabel` is plain `Text(200)`, required, primary column. **NO `formulaDefinition`.** Flow populates it via Compose `concat(triggerBody()?['source'], '/', triggerBody()?['step_name'], ' @ ', utcNow())`.
- **A2 / D3** — Tool flow `Scope_Handle_Errors` mirrors `intelligent-work-layer/src/tool-search-sharepoint.json` lines 117-207 **verbatim**: `Compose_ErrorDetails` → `Respond_with_error` (`PowerVirtualAgentsResponseV2`, `statusCode 200`, body `{"logged": false}`) → `Terminate_Graceful(Failed)`. **Respond-before-terminate is non-negotiable** — otherwise the calling topic hangs.
- **A3 / D4** — Child flow `Scope_Write` has `Configure run after → Failed/TimedOut → Terminate(Succeeded)`. A logger failure never propagates to the caller.
- **A4** — Env-var read is fail-open. `Get_DebugLoggerEnabled` → `Compose_EnabledFlag` with `runAfter` covering `Succeeded, Failed, TimedOut, Skipped` → deleted/failed var = enabled=false.
- **A9** — Tool flow response schema is exactly `{"type":"object","properties":{"logged":{"type":"boolean"}}}`.
- **A15** — Payload truncation: `substring(string(triggerBody()?['payload']), 0, min(900000, length(string(triggerBody()?['payload']))))`. **Do not use `left()`** — that's Power Apps Canvas, not WDL.
- **D1** — Env-var gate lives INSIDE the flows, not in topics. Topics always run their message/capture; the flow no-ops when the env var is false.
- **D2 / A5 / A6** — Correlation key is `=System.Conversation.Id` (PascalCase, no `Global.`). Caller may override by packing `correlation_id` into the serialized JSON input.
- **D5 / B1** — Topic GUID lifecycle uses `{{TOOL_LOG_AGENT_TRACE_FLOW_ID}}` placeholder. `scripts/inject-flow-guid.ps1` substitutes after import into `dist/topics/` (gitignored).
- **D6** — Each topic ships TWO variants (full + blog-pure). Modify both together when changing the contract.
- **D7** — MDA is Phase-0 manual: Maker portal authoring → `pac solution clone` → commit unpacked XML. Never code-first.
- **D8** — Unmanaged-only v1. No managed-build artifacts.
- **D15** — PII discipline: `example.com` only in samples; no real tenants, UPNs, org URLs, domains, or logs in commits. Repo guardrail at `.github/workflows/prevent-pii-domains.yml`.

## Schema-prompt-code contract

The data flow is JSON-schema-driven end to end. When you change a column, update **all** of:

1. [`schemas/agenttrace-table.json`](schemas/agenttrace-table.json) — the source of truth
2. [`src/flow-1-log-agent-trace.json`](src/flow-1-log-agent-trace.json) trigger inputs + Create_AgentTrace_Row parameters
3. [`src/tool-log-agent-trace.json`](src/tool-log-agent-trace.json) trigger inputs + Create_AgentTrace_Row parameters
4. Topic InvokeFlowAction args in all four `*.topic.mcs.yml`
5. [`docs/maker-guide.md`](docs/maker-guide.md) sample JSON + column tables
6. [`docs/deployment-guide.md`](docs/deployment-guide.md) smoke-test expectations
7. This file's data contract section

The schema → flow column mapping is implicit: every `cr_*` column gets an `item/cr_*` parameter on `CreateRecord`. Provision is fully schema-driven (loops over `columns[]`).

## Known issues (deploy-time discoveries, first verified on Jude Dev 2026-05-21)

See [`README.md` Known Issues](README.md#known-issues-deploy-time-discoveries) for the full list with backlog todos. Summary for AI agents working in this folder:

| Issue | Behavior | Workaround | Follow-up |
|---|---|---|---|
| `cr_sourcename` schema collision | Dataverse Picklist `cr_source` auto-generates Virtual `cr_sourcename`; blocks the documented Text(200) column | Provision skips; flows omit `item/cr_sourcename`; trace label encodes source/step | Rename to `cr_originname` (backlog: `rename-cr-sourcename`) |
| Maker portal Boolean env vars store as `"yes"` | `Compose_EnabledFlag` only matches `'true'` | PATCH `/environmentvariablevalues(<id>)` body `{"value":"true"}` via Web API | Make Compose tolerant of yes/true/1 (backlog: `boolean-envvar-tolerance`) |
| PVA tool flow can't be created via Flow Mgmt API | `inject-flow-guid.ps1` exits non-zero | Add `tool-log-agent-trace` as Action on a consumer agent in Copilot Studio first | None — Microsoft platform constraint |
| Custom UniqueIdentifier columns rejected by Web API | `0x80040203` | Provision script skips type=UniqueIdentifier columns; platform auto-creates `<tablename>id` | None — documented behavior |
| PAC CLI 2.x dropped `pac admin list-environments` | Returns "Not a valid command" with exit 0 | Provision script sniffs for JSON shape (`[` / `{`) before parsing | None — implemented |
| Child flow CAN be created via Flow Mgmt API | Despite repo convention saying main flows need manual authoring | Use `intelligent-work-layer/scripts/deploy-agent-flows.ps1` as the template | Productionize as `scripts/deploy-flows.ps1` (backlog: `productionize-deploy-flows-script`) |

## Operational sequence (first-time deploy)

The Phase-0 MDA + tool-flow Action add are the only manual steps:

1. `pwsh scripts/provision-environment.ps1 -EnvironmentId "<env-guid>"` — table + env var
2. Maker portal Phase-0 MDA per [`docs/phase-0-mda-authoring.md`](docs/phase-0-mda-authoring.md): create app, add table, build form + 3 views, **publish all customizations**
3. `pac solution clone --name CopilotAgentDebugLogger --environment "<env-guid>"` from `src/Solutions/` — extracts MDA XML into source
4. (Restructure if first time — move clone contents up to `src/Solutions/` per PR #42; subsequent clones can overwrite-in-place)
5. `pwsh scripts/deploy-solution.ps1 -EnvironmentId "<env-guid>" -SkipInjectFlowGuid` — first deploy (no tool flow yet)
6. Copilot Studio → consumer agent → Tools → Add tool → Flow → `tool-log-agent-trace` → Add
7. PATCH env var value to `"true"` via Web API (workaround for the `"yes"` storage issue)
8. `pwsh scripts/deploy-solution.ps1 -EnvironmentId "<env-guid>"` — substitutes GUIDs into `dist/topics/`
9. Smoke test per [`docs/maker-guide.md`](docs/maker-guide.md#quick-start-hello-world)

Reference precedent that the same end-to-end sequence has been validated on a live tenant: PR #42.

## Reference precedents (IWL is the canonical sibling)

When in doubt about tone, layout, or error-handling, mirror the Intelligent Work Layer:

- [`../intelligent-work-layer/scripts/provision-environment.ps1`](../intelligent-work-layer/scripts/provision-environment.ps1) — Web API table-creation pattern, idempotency, section dividers
- [`../intelligent-work-layer/scripts/deploy-solution.ps1`](../intelligent-work-layer/scripts/deploy-solution.ps1) — prereq validation, MSBuild dispatch, transcript logging
- [`../intelligent-work-layer/scripts/deploy-agent-flows.ps1`](../intelligent-work-layer/scripts/deploy-agent-flows.ps1) — Flow Management API pattern with connection-reference handling (template for productionizing `scripts/deploy-flows.ps1`)
- [`../intelligent-work-layer/src/tool-search-sharepoint.json`](../intelligent-work-layer/src/tool-search-sharepoint.json) lines 117-207 — verbatim A2/D3 tool-flow error pattern
- [`../intelligent-work-layer/copilot-studio/topics/orchestrator.topic.mcs.yml`](../intelligent-work-layer/copilot-studio/topics/orchestrator.topic.mcs.yml) — `{{FLOW_GUID_*}}` placeholder + InvokeFlowAction shape

## Don't

- ❌ Add `formulaDefinition` to `cr_tracelabel` (A1).
- ❌ Hardcode the tool-flow GUID in topic YAMLs (D5).
- ❌ Use `left()` or other Power Apps Canvas-formula functions in flow expressions (A15).
- ❌ Recreate the legacy `src/Solutions/CanvasApps/AgentDebugConsole_*` path (PR #42 moved to canonical layout).
- ❌ Drop the blog-pure variant of any topic (D6).
- ❌ Add managed-build artifacts (D8).
- ❌ Commit real org URLs, tenant IDs, UPNs, or domains other than `example.com` (D15).
- ❌ Try to create the PVA tool flow via Flow Management API — it's a Microsoft platform constraint, not a script bug.
- ❌ Modify topic descriptions for AutomaticTaskInput — they are verbatim from the Power CAT blog and constitute the orchestrator contract.

## Where to look first when something breaks

| Symptom | Most likely cause | Diagnostic file |
|---|---|---|
| `pac admin list-environments` not recognized | PAC CLI 2.x — already handled in provision script | [`scripts/provision-environment.ps1`](scripts/provision-environment.ps1) section 1 |
| `0x80040203` from provision | Trying to create UniqueIdentifier column — already skipped | [`scripts/provision-environment.ps1`](scripts/provision-environment.ps1) section 7 column loop |
| Phase-0 precheck fails | `src/Solutions/src/AppModules/cr_AgentDebugConsole/` missing | Run `pac solution clone` per [`docs/phase-0-mda-authoring.md`](docs/phase-0-mda-authoring.md) |
| `inject-flow-guid.ps1` exits non-zero | Tool flow not yet attached as Action on any consumer agent | Backlog `add-tool-flow-action-cs` |
| Flow Mgmt API rejects child flow create | Check operationId is `ListRecords` not fabricated; check `substring()` not `left()` | [`src/flow-1-log-agent-trace.json`](src/flow-1-log-agent-trace.json) |
| Flow runs Succeeded but no row in `cr_agenttrace` | Env var stored as `"yes"` instead of `"true"` — PATCH via Web API | Backlog `boolean-envvar-tolerance` |
| Connector schema rejects `item/cr_<name>` | Likely a Picklist auto-generated Virtual collision (like `cr_sourcename`) | Cross-check against actual `cr_*` Attributes via `EntityDefinitions(LogicalName='cr_agenttrace')/Attributes` |

## Cross-references

- [`README.md`](README.md) — human-facing POC framing, architecture, design decisions, extension points
- [`docs/maker-guide.md`](docs/maker-guide.md) — Quick Start, Patterns A–E
- [`docs/deployment-guide.md`](docs/deployment-guide.md) — end-to-end deploy walkthrough + troubleshooting
- [`docs/phase-0-mda-authoring.md`](docs/phase-0-mda-authoring.md) — the one manual Maker-portal step
- [`docs/skills-plugin-guide.md`](docs/skills-plugin-guide.md) — CLI alternative for topic import
- [`docs/native-debugging-cheatsheet.md`](docs/native-debugging-cheatsheet.md) — use Microsoft's native stack first
- [`../.github/copilot-instructions.md`](../.github/copilot-instructions.md) — repo-wide AI context including the POC Constraints section
- [`../.squad/decisions.md`](../.squad/decisions.md) — D1–D15 council decision register
