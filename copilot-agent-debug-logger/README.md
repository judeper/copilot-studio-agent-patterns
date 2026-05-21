# Copilot Agent Debug Logger (POC)

A maker-focused POC that fills three practical gaps in the native Copilot Studio + Power Automate debugging stack: exact Power Automate request/response payload capture, shared correlation ID stitching between Copilot Studio and Power Automate records, and drop-in Chain-of-Thought + Conversation History topic templates from the Power CAT Custom Engine blog (Oct 2025).

> **POC scope, not production.** This is a debugging workbench for demos, labs, and maker iteration. Customers must extend it with PII redaction, retention, per-user toggles, sampling, custom roles, and production telemetry before UAT or production use.

## What It Does

- **Captures Power Automate payloads** before and after `ExecuteAgentAndWait`, including the exact request envelope and response body the maker wants to inspect.
- **Captures tool-flow payloads** at tool entry and exit so agent-invoked actions can be reviewed next to agent-side topic events.
- **Stitches related rows** through `cr_correlationid`; `System.Conversation.Id` is the default Copilot Studio key, and makers can override it by packing `correlation_id` into existing serialized JSON inputs.
- **Ships four topic templates**: full + blog-pure variants for `/Log Chain of Thoughts`, and full + blog-pure variants for `/Save Conversation History` per D6.
- **Surfaces traces in a minimal model-driven app** named **Agent Debug Console** with three views: **Recent Traces**, **Timeline by Correlation ID**, and **Errors Only**.
- **Toggles cleanly** through one Boolean environment variable, `cr_DebugLoggerEnabled`, which defaults to `false` and lives inside the flows per D1.
- **Fails open** when Dataverse, connection references, or the env-var read fail; debugging should never brick the maker's main flow or agent turn.
- **Keeps native tooling first** by documenting Save Snapshot, App Insights, `ConversationTranscript`, Developer Mode, Activity Map, and Power CAT Kit before this POC.

## Architecture

```
+----------------------------------------------------------------------+
|                    CONSUMER AGENT (Copilot Studio)                   |
|                                                                      |
|  /Log Chain of Thoughts                                              |
|  /Save Conversation History                                          |
|             |                                                        |
|             v                                                        |
|  +--------------------------------------------------------------+    |
|  | tool-log-agent-trace (PVA-trigger tool flow)                 |    |
|  | - Added as an Action on each consumer agent                  |    |
|  | - Reads cr_DebugLoggerEnabled inside the flow (D1)           |    |
|  | - Writes one COPILOT_TOPIC row when enabled                  |    |
|  | - Responds before graceful terminate on error (D3)           |    |
|  +---------------------------+----------------------------------+    |
+------------------------------|---------------------------------------+
                               |
+------------------------------|---------------------------------------+
|                  CALLER POWER AUTOMATE FLOW                          |
|                                                                      |
|  Maker wraps ExecuteAgentAndWait or a tool flow with child calls:     |
|                                                                      |
|  +--------------------------------------------------------------+    |
|  | flow-1-log-agent-trace (child flow)                          |    |
|  | - REQUEST row before ExecuteAgentAndWait                     |    |
|  | - RESPONSE row after ExecuteAgentAndWait                     |    |
|  | - TOOL_FLOW rows at tool entry / exit when used that way     |    |
|  | - Scope_Write fails open, then terminates Succeeded (D4)     |    |
|  +---------------------------+----------------------------------+    |
+------------------------------|---------------------------------------+
                               |
                               v
                 +------------------------------+
                 | Dataverse: cr_agenttrace     |
                 | - 13 custom columns          |
                 | - UserOwned table            |
                 | - Primary: cr_tracelabel     |
                 | - Stitch: cr_correlationid   |
                 | - Payload raw, 900 KB cap    |
                 +--------------+---------------+
                                |
                                v
                 +------------------------------+
                 | Agent Debug Console (MDA)    |
                 | - Recent Traces              |
                 | - Timeline by Correlation ID |
                 | - Errors Only                |
                 | - Plain multiline payload    |
                 +------------------------------+
```

The solution intentionally stays small. The table and environment variable are script-provisioned, the model-driven app is a documented Phase-0 Maker portal step, and the topic YAMLs are imported into whichever consumer agents need the debugging patterns. The result is a per-conversation workbench that complements, rather than replaces, Microsoft's native observability tools.

## File Map

```
copilot-agent-debug-logger/
|-- README.md                                      <- this file
|-- docs/
|   |-- native-debugging-cheatsheet.md             <- Microsoft tooling to use FIRST
|   |-- phase-0-mda-authoring.md                   <- Maker portal click-paths for the MDA (D7)
|   |-- deployment-guide.md                        <- end-to-end deploy walkthrough
|   |-- maker-guide.md                             <- Quick Start + Patterns A-E
|   `-- skills-plugin-guide.md                     <- optional CLI topic import workflow
|-- schemas/
|   |-- agenttrace-table.json                      <- 13-column UserOwned Dataverse table
|   `-- debugloggerenabled-envvar.json             <- Boolean env var and single kill switch
|-- copilot-studio/
|   `-- topics/
|       |-- log-chain-of-thoughts.topic.mcs.yml
|       |   `-- FULL: visible italic trace + Dataverse persistence
|       |-- log-chain-of-thoughts-blog-pure.topic.mcs.yml
|       |   `-- BLOG-PURE: visible italic trace only (D6)
|       |-- save-conversation-history.topic.mcs.yml
|       |   `-- FULL: silent transcript capture + Dataverse persistence
|       `-- save-conversation-history-blog-pure.topic.mcs.yml
|           `-- BLOG-PURE: capture-only variable, zero dependencies (D6)
|-- scripts/
|   |-- provision-environment.ps1                  <- creates solution, table, env var
|   |-- deploy-solution.ps1                        <- builds unmanaged solution + runs GUID inject
|   `-- inject-flow-guid.ps1                       <- replaces {{TOOL_LOG_AGENT_TRACE_FLOW_ID}}
`-- src/
    |-- flow-1-log-agent-trace.json                <- child flow reference definition
    |-- tool-log-agent-trace.json                  <- PVA-trigger tool flow reference definition
    `-- Solutions/                                 <- unmanaged solution scaffold (D8)
        |-- Solution.cdsproj                       <- SolutionPackageType=Unmanaged
        |-- other/
        |   |-- Solution.xml                       <- solution manifest placeholder until unpack
        |   `-- Customizations.xml                 <- solution components placeholder until unpack
        `-- CanvasApps/
            `-- .gitkeep                           <- AgentDebugConsole_* lands here after Phase-0
```

## Quick Start

Full walkthrough: **[`docs/maker-guide.md` Quick Start](docs/maker-guide.md#quick-start-hello-world)**.

Expected time per D9:

- **≈20 minutes for first-time setup** because you still need PAC auth, Phase-0 MDA verification, tool-flow registration, GUID substitution, and a smoke test.
- **<5 minutes once tools are installed** and the solution has already been imported to the environment.

TL;DR path:

1. Read the native-tooling baseline first: [`docs/native-debugging-cheatsheet.md`](docs/native-debugging-cheatsheet.md).
2. Provision the Dataverse table and environment variable:

   ```powershell
   pwsh copilot-agent-debug-logger\scripts\provision-environment.ps1 -EnvironmentId "<env-guid>"
   ```

3. Complete the one-time model-driven app step in [`docs/phase-0-mda-authoring.md`](docs/phase-0-mda-authoring.md).
4. First deploy, intentionally skipping GUID substitution until the tool flow is attached:

   ```powershell
   pwsh copilot-agent-debug-logger\scripts\deploy-solution.ps1 -EnvironmentId "<env-guid>" -SkipInjectFlowGuid
   ```

5. In Copilot Studio, open each consumer agent that will use the full topics and add **tool-log-agent-trace** as an Action.
6. Rerun deploy or run GUID injection so full topic YAMLs get the real flow ID:

   ```powershell
   pwsh copilot-agent-debug-logger\scripts\deploy-solution.ps1 -EnvironmentId "<env-guid>"
   ```

7. Import the substituted topics from `dist/topics/` through the Skills plugin or the Copilot Studio Web UI. See [`docs/skills-plugin-guide.md`](docs/skills-plugin-guide.md) for the CLI path.
8. Enable logging only for the active debugging window:

   `https://make.powerapps.com -> Solutions -> Copilot Agent Debug Logger -> Environment variables -> cr_DebugLoggerEnabled -> Edit current value -> true -> Save -> Publish all customizations`

9. Smoke test with [`docs/deployment-guide.md` Step 8](docs/deployment-guide.md#step-8--smoke-test).
10. Turn `cr_DebugLoggerEnabled` back to `false` when active debugging ends.

### Emergency kill switch (A14)

If a consumer agent starts looping through `/Log Chain of Thoughts`, recover in this order:

1. **Disable writes globally**: Power Apps maker -> Solutions -> Copilot Agent Debug Logger -> Environment variables -> `cr_DebugLoggerEnabled` -> Edit current value -> `false` -> Save -> Publish all customizations.
2. **Disable the topic**: Copilot Studio -> consumer agent -> Topics -> **Log Chain of Thoughts** -> toggle **Active** off -> Save.
3. **Remove the instruction trigger**: consumer agent -> Instructions -> delete the line telling the agent to call `/Log Chain of Thoughts` after every step -> Save -> Publish.

After recovery, test with the blog-pure variant first. Re-enable the full variant only during an active debugging window.

## Pattern Chooser

| Need | Start here | Notes |
|---|---|---|
| Prove the table, env var, and MDA work | [`docs/maker-guide.md` Quick Start](docs/maker-guide.md#quick-start-hello-world) | Manual child-flow smoke test writes one row. |
| Capture a Power Automate -> Agent call | Maker Guide Pattern A | Wrap `ExecuteAgentAndWait` with REQUEST and RESPONSE child-flow calls. |
| Capture a custom tool flow | Maker Guide Pattern B | Add child-flow calls at tool entry and just before Respond to agent. |
| Show and optionally persist intermediate reasoning notes | Maker Guide Pattern C | Choose full or blog-pure topic variant per D6. |
| Capture the conversation transcript at a selected point | Maker Guide Pattern D | Choose full or blog-pure topic variant per D6. |
| Stitch Power Automate and Copilot Studio rows together | Maker Guide Pattern E | Pack `correlation_id` into the existing serialized JSON input. |

## How the Pieces Work Together

### 1. Provisioning creates the shared contract

`scripts/provision-environment.ps1` is the first source-controlled setup step. It creates or reuses:

- unmanaged solution `CopilotAgentDebugLogger`;
- publisher prefix `cr`;
- table `cr_agenttrace` / entity set `cr_agenttraces`;
- environment variable `cr_DebugLoggerEnabled` with default and current value `false`.

The script is idempotent. Rerun it when recovering from a partial setup or after the env var is accidentally deleted.

### 2. The child flow captures Power Automate-side evidence

`src/flow-1-log-agent-trace.json` is the reusable child flow for makers who already have a Power Automate flow.

Typical rows:

- `REQUEST` immediately before `ExecuteAgentAndWait`.
- `RESPONSE` immediately after `ExecuteAgentAndWait`.
- `REQUEST` / `RESPONSE` around custom tool-flow internals when the maker uses Pattern B.
- `ERROR` rows from a caller-owned failure branch.

The child flow composes a trace label, truncates `payload` with `left(string(...), 900000)`, resolves `correlation_id`, and writes to `cr_agenttrace` only when the env var is true. If the write fails, `Scope_Write` routes to a succeeded terminate so the caller keeps running.

### 3. The tool flow captures Copilot Studio-side topic events

`src/tool-log-agent-trace.json` uses the `PowerVirtualAgents` trigger kind and must be added as an Action on each consumer agent that imports full topic variants.

It is used by:

- `log-chain-of-thoughts.topic.mcs.yml` for `CoT` events;
- `save-conversation-history.topic.mcs.yml` for `ConversationHistory` events.

The tool flow follows the IWL respond-before-terminate error pattern. On Dataverse write failure it still returns `{ "logged": false }` to the agent before terminating gracefully, which avoids hanging the topic call.

### 4. Topic variants keep the maker choice explicit (D6)

| Topic need | Full variant | Blog-pure variant |
|---|---|---|
| Chain-of-thought-style visible trace | `log-chain-of-thoughts.topic.mcs.yml` | `log-chain-of-thoughts-blog-pure.topic.mcs.yml` |
| Conversation-history capture | `save-conversation-history.topic.mcs.yml` | `save-conversation-history-blog-pure.topic.mcs.yml` |

Use full variants when you want searchable Dataverse rows. Use blog-pure variants when you want the Power CAT Custom Engine blog behavior without registering a tool flow, enabling the env var, or importing the solution.

### 5. The console is deliberately simple

The **Agent Debug Console** model-driven app is the inspection surface, not a dashboard product. It gives makers enough to answer three questions quickly:

- **What just happened?** Use **Recent Traces**.
- **What happened in this conversation or run?** Use **Timeline by Correlation ID**.
- **What failed?** Use **Errors Only**.

For richer dashboards, add Power BI or App Insights mirroring as extension work.

## Data Contract

`cr_agenttrace` is the only custom table in v1. It is `UserOwned`, uses `cr_tracelabel` as the primary name column, and relies on Dataverse system columns such as `createdon` and `OwnerId` rather than custom timestamp or user columns.

Key columns:

| Column | Purpose |
|---|---|
| `cr_correlationid` | Stitching key across topic, child-flow, and tool-flow rows. |
| `cr_agentname` | Friendly name of the calling agent. |
| `cr_source` | `POWER_AUTOMATE_FLOW`, `TOOL_FLOW`, or `COPILOT_TOPIC`. |
| `cr_sourcename` | Flow or topic that emitted the row. |
| `cr_stepname` | Step under inspection, such as `ExecuteAgentAndWait`, `CoT`, or `ConversationHistory`. |
| `cr_direction` | `REQUEST`, `RESPONSE`, or `EVENT`. |
| `cr_sequence` | Per-caller tie-breaker only; not a global counter. |
| `cr_payload` | Raw JSON/text payload, truncated to 900,000 characters before write. |
| `cr_durationms` | Optional step duration in milliseconds. |
| `cr_status` | `OK` or `ERROR`. |
| `cr_errormessage` | Optional details for error rows. |

Security note: `cr_payload` is raw. Truncation protects the Dataverse field limit; it is not PII redaction.

## Key Design Decisions

| Decision | Choice | Why |
|---|---|---|
| **D1** | Env-var gate lives inside the flows, not in topics | Topics preserve the Power CAT blog UX and always invoke; flows decide whether to write. |
| **D2** | `System.Conversation.Id` is the default correlation key | Built-in, zero retrofit, and maker-overridable through a packed `correlation_id`. |
| **D3** | Tool flow follows the IWL error response pattern | Responding to PVA before graceful termination prevents a stuck agent turn. |
| **D4** | Child flow fails open | Logger failures must never brick the caller's main business flow. |
| **D5** | GUID lifecycle uses placeholder + `inject-flow-guid.ps1` | Matches IWL `{{FLOW_GUID_*}}` precedent and survives environment moves. |
| **D6** | Each topic ships in two variants: full + blog-pure | Makers can choose searchable Dataverse persistence or the zero-dependency blog pattern. |
| **D7** | MDA is Phase-0 manual authoring, then PAC unpack | Microsoft does not provide a supported code-first MDA authoring path. |
| **D8** | Solution is unmanaged-only for v1 | POC scope; managed ALM is a customer or v0.2 extension. |
| **D9** | Quick Start time is ≈20 min first-time / <5 min installed | Honest maker UX beats a false 10-minute promise. |
| **D15** | PII discipline uses placeholders and `example.com` samples only | No real customer, partner, tenant, UPN, org URL, runtime config, logs, or dumps. |

See [`.squad/decisions.md`](../.squad/decisions.md) for the full D1-D15 register.

## Extension Points

This POC is intentionally lean. Treat each item below as a customer hardening project before UAT or production.

1. **PII auto-redaction** - `cr_payload` is currently raw and truncated to 900 KB. Add a redaction pass before writing or before sharing traces.
2. **Retention policy** - no purge flow ships. Add a scheduled flow that deletes, archives, or exports rows older than the customer-approved window.
3. **Per-user / per-agent toggles** - one global `cr_DebugLoggerEnabled` switch only. Add a user, agent, or SkillRegistry-style switch table for finer control.
4. **Sampling / rate limiting** - every call is captured when enabled. Add modulo, random sampling, or severity-only capture for high-throughput agents.
5. **Custom roles** - v1 assumes built-in maker/admin access. Add environment-specific security roles and row-level ownership rules for production.
6. **Power BI dashboard** - v1 uses the model-driven app only. Connect `cr_agenttrace` to Power BI for trend, latency, and error analysis.
7. **App Insights mirror** - v1 writes to Dataverse only. Mirror selected rows to Application Insights for KQL, longer retention, and dependency correlation.
8. **Wrapper flow** - current child flow logs one row per call. Add a parent wrapper to apply shared redaction, sampling, and business-specific labels.
9. **Split env vars** - replace the single switch with separate flags such as `cr_DebugLoggerEnabled`, `cr_CoTLoggingEnabled`, and `cr_ConvHistoryLoggingEnabled`.
10. **PCF JSON viewer** - the MDA uses a plain multiline `cr_payload` field. Add a PCF control for JSON formatting, folding, and search.
11. **Direct Line / Teams / webchat side capture** - Pattern A covers Power Automate -> Agent calls only. Add capture at Direct Line, Teams, or Bot Framework boundaries for channel-side telemetry.
12. **AAD-OID column on traces** - v1 relies on system `OwnerId`. Add explicit user or AAD object ID fields if cross-tenant reporting requires them.
13. **Downstream ConvHistory targets** - Pattern D documents ticket creation, escalation notification, and MCP/Outlook delivery. Pick the target and ship the connector flow.

## What This Is NOT (D6 explicit scope discipline)

- **NOT a production logger.** It has no built-in PII redaction, retention, sampling, quota handling, or production support model.
- **NOT an App Insights substitute.** Application Insights gives keyed errors, latency, dependency telemetry, KQL, and platform telemetry integration. Use it first; see [`docs/native-debugging-cheatsheet.md`](docs/native-debugging-cheatsheet.md).
- **NOT a substitute for Copilot Studio's `ConversationTranscript` table.** Native transcripts give the full message history and orchestration data after platform write delay. This POC complements that with Power Automate-side payload capture.
- **NOT a substitute for the Power CAT Copilot Studio Kit.** The kit provides Agent Insights Hub dashboards, governance views, and batch regression testing. This POC is a maker's per-conversation debugging workbench.
- **No PII redaction.** Payloads are captured raw and capped for size only.
- **No retention policy.** Rows accumulate until the customer deletes or archives them.
- **No per-user roles.** v1 relies on standard Dataverse ownership and built-in maker/admin roles.
- **No per-agent roles.** Any consumer agent configured with the tool flow can write when the global switch is on.
- **No managed-solution ALM.** `Solution.cdsproj` builds an unmanaged package only.
- **No code-first MDA.** The Agent Debug Console must be authored once in Maker portal and unpacked per [`docs/phase-0-mda-authoring.md`](docs/phase-0-mda-authoring.md).

## Native Debugging Stack to Exhaust First

Microsoft already ships the supported baseline. Use these before reaching for this POC:

- **Test pane -> Save Snapshot** for `dialog.json`, routing, tools, orchestration plan, and per-step timing.
- **Application Insights + `/debug conversationid`** for production errors, latency, dependencies, custom events, and KQL.
- **`ConversationTranscript` Dataverse table** for full transcript history and orchestration evidence after platform write delay.
- **Developer Mode** for globals, node state, routing decisions, and live test-pane inspection.
- **Activity Map & Transcripts page** for a visual node map and transcript review.
- **Power CAT Copilot Studio Kit - Agent Insights Hub** for dashboards, governance, and batch regression testing across an agent fleet.

Full cheat sheet: [`docs/native-debugging-cheatsheet.md`](docs/native-debugging-cheatsheet.md).

## Cross-References

- **Maker Quick Start and Patterns A-E:** [`docs/maker-guide.md`](docs/maker-guide.md).
- **Deployment and troubleshooting:** [`docs/deployment-guide.md`](docs/deployment-guide.md).
- **Phase-0 model-driven app authoring:** [`docs/phase-0-mda-authoring.md`](docs/phase-0-mda-authoring.md).
- **Skills CLI topic import:** [`docs/skills-plugin-guide.md`](docs/skills-plugin-guide.md).
- **Native Microsoft debugging surfaces:** [`docs/native-debugging-cheatsheet.md`](docs/native-debugging-cheatsheet.md).
- **Power CAT Custom Engine blog (Oct 2025):** source pattern for the Chain-of-Thought and Conversation History topic templates.
- **Power CAT Copilot Studio Kit:** <https://github.com/microsoft/Power-CAT-Copilot-Studio-Kit> - complementary analytics and regression layer.
- **Skills for Copilot Studio plugin:** <https://github.com/microsoft/skills-for-copilot-studio> - terminal-first topic authoring and import.
- **Intelligent Work Layer:** [`../intelligent-work-layer/`](../intelligent-work-layer/) - sibling solution whose README tone, solution scaffold, GUID placeholder pattern, and fail-open tool-flow patterns informed this POC.

## Status and License

This is a demonstration POC in the `copilot-studio-agent-patterns` repository. Use at your own risk, keep `cr_DebugLoggerEnabled` off outside active debugging, and extend the hardening points above before any production path. PRs are welcome through the umbrella issue and the draft PR review flow.
