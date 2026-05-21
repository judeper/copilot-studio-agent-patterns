# Copilot Agent Debug Logger — Deployment Guide

End-to-end deployment checklist for the Copilot Agent Debug Logger POC.

> **TL;DR for first-time deploy:** plan on **≈20 minutes for first-time setup; <5 minutes once tools are installed**. Do not promise a shorter path: first-time makers still need PAC auth, Azure CLI auth, Phase-0 MDA verification, environment-variable enablement, per-agent tool registration, GUID substitution, and a smoke test.

---

## Quick-start sequence

Run the steps in this order.

| # | Step | Command / action |
|---|---|---|
| 1 | Authenticate | `pac auth create --url https://<your-env>.crm.dynamics.com` |
| 2 | Confirm Phase-0 MDA | Follow `docs\phase-0-mda-authoring.md` before importing |
| 3 | Provision table + env var | `pwsh copilot-agent-debug-logger\scripts\provision-environment.ps1 -EnvironmentId "<env-guid>"` |
| 4 | Build + import | First deploy: `pwsh copilot-agent-debug-logger\scripts\deploy-solution.ps1 -EnvironmentId "<env-guid>" -SkipInjectFlowGuid` |
| 5 | Enable logging | Maker portal → solution → environment variable → `true` |
| 6 | Register tool flow | Copilot Studio → consumer agent → Tools → add `tool-log-agent-trace` |
| 7 | Substitute GUIDs | `pwsh copilot-agent-debug-logger\scripts\inject-flow-guid.ps1 -EnvironmentId "<env-guid>"` |
| 8 | Smoke test | Manual child-flow run + consumer-agent test turn |

The solution is unmanaged-only for v1. It is a maker debugging POC, not a production telemetry platform.

---

## Prerequisites

### Platform access

- [ ] Power Platform environment with Dataverse enabled.
- [ ] Sandbox or Developer environment recommended for first deployment.
- [ ] **System Customizer** or **System Administrator** role in the target environment.
- [ ] Access to Power Apps Maker portal at `https://make.powerapps.com`.
- [ ] Access to Copilot Studio at `https://copilotstudio.microsoft.com`.
- [ ] Access to Power Automate at `https://make.powerautomate.com`.

### Local tools

- [ ] PowerShell 7+ (`pwsh`).
- [ ] .NET SDK, required by PAC CLI packaging.
- [ ] PAC CLI 1.32+.
- [ ] Azure CLI (`az`), used to acquire the Dataverse Web API bearer token.

Install or update PAC CLI:

```powershell
dotnet tool install --global Microsoft.PowerApps.CLI.Tool
# or, if already installed:
dotnet tool update --global Microsoft.PowerApps.CLI.Tool
pac --version
```

Install Azure CLI on Windows if needed:

```powershell
winget install Microsoft.AzureCLI
az version
```

### PII discipline before you start

This repository must not contain real customer, partner, or tenant emails, domains, UPNs, org URLs, runtime configs, logs, dumps, or generated backups.

Use placeholders only:

- Environment URL: `https://<your-env>.crm.dynamics.com`
- Environment ID: `<env-guid>`
- Sample domains: `example.com`
- Sample email, if needed: `maker@example.com`

Do not paste a real org URL into commits, PR descriptions, screenshots, sample JSON, or docs.

---

## Step 1 — Authenticate

Run from the repository root.

```powershell
pac auth create --url https://<your-env>.crm.dynamics.com
az login
pac auth list
```

Then select the target environment by GUID:

```powershell
pac auth select --environment "<env-guid>"
pac org who
```

Expected result:

- PAC CLI has an active auth profile.
- `pac org who` points at the same Dataverse environment URL you used in `pac auth create`.
- Azure CLI can issue a Dataverse token for the provisioning and GUID-injection scripts.

If `az login` opens a browser, finish that sign-in before continuing.

---

## Step 2 — Phase-0 MDA authoring (first deploy only)

The **Agent Debug Console** model-driven app is a one-time manual Maker portal step.

Read and complete:

- [`docs\phase-0-mda-authoring.md`](phase-0-mda-authoring.md)

Why this comes first:

1. Microsoft model-driven apps are not safely authored code-first from scratch.
2. The app must be created once in the Maker portal.
3. The unmanaged solution must then be cloned and unpacked into `copilot-agent-debug-logger\src\Solutions\`.
4. `deploy-solution.ps1` checks for the unpacked `AgentDebugConsole_*` artifacts before import.

If Phase-0 is not complete, deployment fails loudly with exit code `2` and points back to `docs\phase-0-mda-authoring.md`.

Expected source state after Phase-0:

```powershell
Get-ChildItem copilot-agent-debug-logger\src\Solutions\CanvasApps\AgentDebugConsole_* -Directory
```

Do not treat `.gitkeep` as evidence that the MDA exists.

---

## Step 3 — Provision Dataverse table + environment variable

Run the provisioner after PAC and Azure CLI are authenticated.

```powershell
pwsh copilot-agent-debug-logger\scripts\provision-environment.ps1 -EnvironmentId "<env-guid>"
```

The script creates or reuses:

- unmanaged solution `CopilotAgentDebugLogger`;
- user-owned Dataverse table `cr_agenttrace` (`cr_agenttraces` entity set);
- Boolean environment variable `cr_DebugLoggerEnabled` with default/current value `false`.

The script is idempotent. It uses GET-or-CREATE checks and is safe to rerun when recovering from a partial setup.

Important behavior:

- `cr_DebugLoggerEnabled = false` means both logger flows no-op.
- If the env var cannot be read, both flows fail open and skip writes.
- Topics do not read the env var directly; the gate lives inside the flows.

---

## Step 4 — Build + import the solution

### First-ever deploy

On the first import, the PVA-trigger tool flow has not yet been attached to any consumer agent. Skip GUID substitution for this one run.

```powershell
pwsh copilot-agent-debug-logger\scripts\deploy-solution.ps1 -EnvironmentId "<env-guid>" -SkipInjectFlowGuid
```

Expected result:

- prerequisites pass;
- Phase-0 MDA precheck passes;
- solution package builds from `copilot-agent-debug-logger\src\Solutions\Solution.cdsproj`;
- unmanaged solution imports to the environment;
- GUID substitution is skipped intentionally.

### Normal rerun after tool registration

After Step 6 registers `tool-log-agent-trace` as an Action on at least one consumer agent, rerun without the skip flag.

```powershell
pwsh copilot-agent-debug-logger\scripts\deploy-solution.ps1 -EnvironmentId "<env-guid>"
```

This normal run imports the solution and then calls:

```powershell
pwsh copilot-agent-debug-logger\scripts\inject-flow-guid.ps1 -EnvironmentId "<env-guid>"
```

The substituted topic YAML files are written to:

```text
copilot-agent-debug-logger\dist\topics\
```

### Deploy-script exit codes

| Code | Meaning | Fix |
|---|---|---|
| 0 | Success | Continue to the next step |
| 1 | Prerequisite/auth failure | Install missing tools or rerun `pac auth create` / `az login` |
| 2 | Phase-0 MDA precheck failed | Complete `docs\phase-0-mda-authoring.md` |
| 3 | Solution build failed | Check .NET SDK and solution-packager output |
| 4 | Solution import failed | Check connection references and PAC environment selection |
| 5 | GUID substitution failed | Complete Step 6, then rerun without `-SkipInjectFlowGuid` |

---

## Step 5 — Enable the environment variable

Logging is disabled by default. Enable it only in the environment you are actively testing.

Exact click-path:

1. Open `https://make.powerapps.com`.
2. Top bar → environment selector → choose the target environment.
3. Left nav → **Solutions**.
4. Open **Copilot Agent Debug Logger**.
5. Left rail inside the solution → **Environment variables**.
6. Select **cr_DebugLoggerEnabled**.
7. Right pane → **Current value** section.
8. If no current value exists, select **+ New environment variable value**.
9. If a current value exists, select **Edit current value**.
10. Set the value to `true`.
11. Select **Save**.
12. Top command bar → **Publish all customizations**.

Expected result: a current value exists and the value is `true`.

Keep this value at `false` in shared environments unless every consumer agent owner knows traces are being written.

---

## Step 6 — Per-agent tool flow registration

`tool-log-agent-trace` uses the `PowerVirtualAgents` trigger kind. PVA-trigger flows cannot be auto-attached to every consumer agent by the deploy script.

Repeat this section for each consumer agent that will import the full topic templates.

### Registration checklist

1. Open `https://copilotstudio.microsoft.com`.
2. Top bar → environment selector → choose the target environment.
3. Open the consumer agent.
4. Left nav → **Tools**.
5. Select **+ Add a tool**.
6. Select **Flow**.
7. Search for `tool-log-agent-trace`.
8. Choose **tool-log-agent-trace**.
9. Select **Add**.
10. Save the agent if Copilot Studio prompts you to save.
11. Repeat for every consumer agent that uses `Log Chain of Thoughts` or `Save Conversation History` full variants.

Expected result: the tool appears in the agent's Tools list.

This first Action attach is also what materializes the workflow row that `inject-flow-guid.ps1` queries.

### Choose the topic variant before import (D6)

Each topic ships in two variants.

| Scenario | File | Requires tool flow? | Writes `cr_agenttrace`? |
|---|---|---:|---:|
| Persistent chain-of-thought logging | `log-chain-of-thoughts.topic.mcs.yml` | Yes | Yes |
| Blog-pure visible italic trace | `log-chain-of-thoughts-blog-pure.topic.mcs.yml` | No | No |
| Persistent conversation-history capture | `save-conversation-history.topic.mcs.yml` | Yes | Yes |
| Blog-pure capture-only topic variable | `save-conversation-history-blog-pure.topic.mcs.yml` | No | No |

Use the full variant when you want rows in `cr_agenttrace`. Use the blog-pure variant when you only want the Power CAT blog UX without Dataverse persistence.

---

## Step 7 — GUID substitution (B1)

The full topic YAML files ship with this placeholder:

```text
{{TOOL_LOG_AGENT_TRACE_FLOW_ID}}
```

Copilot Studio needs the actual flow GUID in each `InvokeFlowAction`. Use this four-step process.

### B1.1 Import / materialize the tool flow

Confirm Steps 4 and 6 are complete:

```powershell
pwsh copilot-agent-debug-logger\scripts\deploy-solution.ps1 -EnvironmentId "<env-guid>" -SkipInjectFlowGuid
```

Then add `tool-log-agent-trace` as an Action on at least one consumer agent through Copilot Studio → consumer agent → **Tools** → **+ Add a tool** → **Flow**.

### B1.2 Copy or record the actual flow GUID

Preferred: let the script query it and copy the GUID from the script output.

Manual verification path:

1. Open `https://make.powerautomate.com`.
2. Top bar → environment selector → choose the target environment.
3. Left nav → **Solutions**.
4. Open **Copilot Agent Debug Logger**.
5. Select **Cloud flows**.
6. Open **tool-log-agent-trace**.
7. Copy the workflow GUID from the browser URL or from the flow details pane.

Keep the GUID in your deployment notes. Do not commit environment-specific GUIDs into source files.

### B1.3 Run `inject-flow-guid.ps1`

Run the script directly:

```powershell
pwsh copilot-agent-debug-logger\scripts\inject-flow-guid.ps1 -EnvironmentId "<env-guid>"
```

Or rerun the solution deploy without the first-time skip flag:

```powershell
pwsh copilot-agent-debug-logger\scripts\deploy-solution.ps1 -EnvironmentId "<env-guid>"
```

Expected output includes:

```text
Tool flow GUID: <tool-flow-guid>
Substituted topics written to: ...\copilot-agent-debug-logger\dist\topics
Import via Skills CLI: skills import-topics --folder ...\dist\topics
```

### B1.4 Import substituted topics

Choose one import path.

#### Option A — Skills CLI

Use this when you use the Skills for Copilot Studio plugin.

```powershell
skills import-topics --folder copilot-agent-debug-logger\dist\topics
```

Then open the consumer agent in Copilot Studio and confirm the imported topics appear under **Topics**.

#### Option B — Copilot Studio Web UI hand-build

Use this when the Skills CLI is not available.

1. Open `copilot-agent-debug-logger\dist\topics\log-chain-of-thoughts.topic.mcs.yml`.
2. Open `https://copilotstudio.microsoft.com`.
3. Top bar → environment selector → choose the target environment.
4. Open the consumer agent.
5. Left nav → **Topics**.
6. Select **+ Add a topic**.
7. Select **From blank**.
8. Select the topic menu or YAML/code view option.
9. Paste the substituted YAML content.
10. Save the topic.
11. Repeat for `save-conversation-history.topic.mcs.yml` if you need conversation-history capture.
12. Publish the agent.

If the Web UI does not expose YAML import in your tenant, use the substituted YAML as the build reference and recreate the nodes manually: AutomaticTaskInput → SendActivity if present → InvokeFlowAction with the substituted flow GUID.

### Add the Pattern C instruction snippet

For the full `Log Chain of Thoughts` topic, add this to the consumer agent instructions only after the topic imports successfully:

```text
After every tool, topic, or step you take (except when you are already calling
/Log Chain of Thoughts or other debug/logging topics), log your intermediate
reasoning by calling /Log Chain of Thoughts.
```

Exact click-path:

1. Open `https://copilotstudio.microsoft.com`.
2. Top bar → environment selector → choose the target environment.
3. Open the consumer agent.
4. Left nav → **Overview**.
5. Open **Instructions**.
6. Paste the snippet at the end of the existing instructions.
7. Select **Save**.
8. Select **Publish**.

Before adding this snippet, read the infinite-loop kill switch in Troubleshooting.

---

## Step 8 — Smoke test

Run one Power Automate child-flow test and one consumer-agent test turn.

### 8.1 Manual child-flow write

Exact click-path:

1. Open `https://make.powerautomate.com`.
2. Top bar → environment selector → choose the target environment.
3. Left nav → **Solutions**.
4. Open **Copilot Agent Debug Logger**.
5. Select **Cloud flows**.
6. Open **flow-1-log-agent-trace**.
7. Command bar → **Test**.
8. Select **Manually**.
9. Select **Test**.
10. Fill all 11 inputs.
11. Select **Run flow**.
12. Wait for the run to complete.

Use these sample values:

| Input | Value |
|---|---|
| `correlation_id` | `smoke-test-correlation-001` |
| `agent_name` | `Debug Logger Smoke Agent` |
| `source` | `POWER_AUTOMATE_FLOW` |
| `source_name` | `flow-1-log-agent-trace` |
| `step_name` | `ManualSmokeTest` |
| `direction` | `EVENT` |
| `sequence` | `1` |
| `payload` | `{"message":"smoke test","sampleDomain":"example.com"}` |
| `duration_ms` | `0` |
| `status` | `OK` |
| `error_message` | leave blank |

Expected result: the run succeeds even if Dataverse write fails; the logger is fail-open by design.

### 8.2 Confirm the row in Agent Debug Console

Exact click-path:

1. Open `https://make.powerapps.com`.
2. Top bar → environment selector → choose the target environment.
3. Left nav → **Apps**.
4. Open **Agent Debug Console**.
5. Left nav inside the app → **Traces** → **Inspection** → **Agent Trace**.
6. View selector → **Recent Traces**.
7. Confirm one new row.

Expected row values:

- `cr_status = OK`
- `cr_source = POWER_AUTOMATE_FLOW`
- `cr_stepname = ManualSmokeTest`
- `cr_correlationid = smoke-test-correlation-001`

### 8.3 Consumer-agent topic write

Exact click-path:

1. Open `https://copilotstudio.microsoft.com`.
2. Top bar → environment selector → choose the target environment.
3. Open the consumer agent.
4. Bottom-left or side pane → **Test** / **Test your agent**.
5. Start a new test conversation.
6. Ask a harmless prompt, for example: `Say hello and then summarize what you did.`
7. If you imported `Log Chain of Thoughts`, confirm the italic trace appears.
8. Return to **Agent Debug Console** → **Recent Traces**.
9. Confirm a second row arrives.

Expected topic row values:

- `cr_source = COPILOT_TOPIC`
- `cr_stepname = CoT` or `ConversationHistory`
- `cr_sourcename = log-chain-of-thoughts` or `save-conversation-history`

If the row does not appear, check the env var first, then the tool-flow GUID.

---

## Connection References

The solution uses the Dataverse connector reference `shared_commondataserviceforapps`.

The deploy script does **not** inject connection references through a PAC `--settings-file` in this POC. Future v0.2 work may add that automation.

Manual binding path after first solution import:

1. Open `https://make.powerapps.com`.
2. Top bar → environment selector → choose the target environment.
3. Left nav → **Solutions**.
4. Open **Copilot Agent Debug Logger**.
5. Left rail inside the solution → **Connection references**.
6. For each reference shown as **Unset**, select the reference row.
7. Right pane → **Connection**.
8. Select an existing Dataverse connection, or select **+ New connection**.
9. Complete sign-in for Microsoft Dataverse if prompted.
10. Select **Save**.
11. Top command bar → **Publish all customizations**.

Expected result: no Dataverse connection reference remains **Unset**.

If a cloud flow still fails with a connection error, open the flow details page, select **Edit**, confirm the Dataverse actions are bound to the selected connection, then save the flow.

---

## Troubleshooting

### Cross-solution picker / tool flow appears under a different solution

**Symptom:** When configuring an `InvokeFlowAction` in Copilot Studio Web UI, the cross-solution picker shows `tool-log-agent-trace` under a different solution name than expected, or does not show it at all.

**Cause:** A cloud flow's solution attribution can reflect the first solution that created or imported it. If a maker previously created the flow by hand in another solution, the picker may surface that older solution relationship.

**Fix:** Use the actual GUID from `inject-flow-guid.ps1` output instead of relying on the picker label.

Exact recovery:

1. Run `pwsh copilot-agent-debug-logger\scripts\inject-flow-guid.ps1 -EnvironmentId "<env-guid>"`.
2. Copy the `Tool flow GUID` value from the output.
3. Re-import from `copilot-agent-debug-logger\dist\topics\` or manually set the `InvokeFlowAction.flowId` to that GUID.
4. Save and publish the consumer agent.

### Topic `ActionFailed` at runtime

**Symptom:** The consumer agent invokes `/Log Chain of Thoughts` or `/Save Conversation History`, then the topic returns `ActionFailed`.

**Most common cause:** The topic YAML still contains `{{TOOL_LOG_AGENT_TRACE_FLOW_ID}}`, or it points at a flow GUID from another environment.

**Fix:** Regenerate and re-import the substituted topics.

```powershell
pwsh copilot-agent-debug-logger\scripts\inject-flow-guid.ps1 -EnvironmentId "<env-guid>"
skills import-topics --folder copilot-agent-debug-logger\dist\topics
```

If you use the Web UI path, paste the regenerated YAML from `copilot-agent-debug-logger\dist\topics\` and publish again.

### Topic name collision

**Symptom:** Importing `log-chain-of-thoughts.topic.mcs.yml` fails because a topic named **Log Chain of Thoughts** already exists.

**Cause:** The consumer agent already has a topic from the Power CAT Custom Engine blog, a prior POC version, or a previous import attempt.

**Fix:** Delete or rename the existing topic before importing.

Exact click-path:

1. Open `https://copilotstudio.microsoft.com`.
2. Top bar → environment selector → choose the target environment.
3. Open the consumer agent.
4. Left nav → **Topics**.
5. Search for **Log Chain of Thoughts**.
6. Open the existing topic.
7. Topic menu → **Delete** or **Rename**.
8. Save the agent.
9. Re-import the substituted topic.
10. Publish the agent.

Use the same process for **Save Conversation History** collisions.

### Env-var-read failure (A4 fail-open)

**Symptom:** `cr_DebugLoggerEnabled` was deleted, renamed, or its current value cannot be read. Logger writes stop, but calling flows and topics continue.

**Expected behavior:** fail-open. Both flows treat unreadable env var as disabled and skip writes gracefully.

Verify in a flow run:

1. Open `https://make.powerautomate.com`.
2. Top bar → environment selector → choose the target environment.
3. Left nav → **Solutions**.
4. Open **Copilot Agent Debug Logger**.
5. Open **flow-1-log-agent-trace**.
6. Open the failed or skipped run.
7. Expand **Get_DebugLoggerEnabled**.
8. Confirm it failed, timed out, or was skipped.
9. Expand **Compose_EnabledFlag**.
10. Confirm it still ran because **Configure run after** includes Failed/TimedOut/Skipped.

Recovery:

```powershell
pwsh copilot-agent-debug-logger\scripts\provision-environment.ps1 -EnvironmentId "<env-guid>"
```

Then repeat Step 5 to set `cr_DebugLoggerEnabled` to `true`.

### Infinite-loop kill switch (A14)

**Symptom:** A consumer agent is in a tight loop calling `/Log Chain of Thoughts` on every turn, each CoT call invokes the tool flow, and downstream automation creates more agent turns.

This is unlikely in the normal setup, but Pattern C can loop in pathological systems if the logging topic itself becomes part of the work being logged.

Use this three-step kill switch in order:

1. **Disable writes globally.**
   - Open `https://make.powerapps.com`.
   - Top bar → environment selector → choose the target environment.
   - Left nav → **Solutions**.
   - Open **Copilot Agent Debug Logger**.
   - Left rail → **Environment variables**.
   - Open **cr_DebugLoggerEnabled**.
   - Right pane → **Current value** → **Edit current value**.
   - Set value to `false`.
   - Select **Save**.
   - Top command bar → **Publish all customizations**.
2. **Disable the topic.**
   - Open `https://copilotstudio.microsoft.com`.
   - Top bar → environment selector → choose the target environment.
   - Open the consumer agent.
   - Left nav → **Topics**.
   - Open **Log Chain of Thoughts**.
   - Toggle **Active** off.
   - Select **Save**.
3. **Remove the instruction trigger.**
   - In the same consumer agent, left nav → **Overview**.
   - Open **Instructions**.
   - Remove the line that tells the agent to call `/Log Chain of Thoughts` after every tool, topic, or step.
   - Select **Save**.
   - Select **Publish**.

After the loop stops, inspect recent rows by `cr_correlationid` in **Agent Debug Console** before re-enabling the env var.

### Managed-agent caveat (A16)

**Symptom:** You cannot edit the consumer agent instructions to add the Pattern C CoT snippet. The instructions area is locked or changes are blocked on publish.

**Cause:** The consumer agent ships in a managed solution. Managed layers can block direct edits to instructions and topics.

**Fix:** Create an unmanaged overlay solution in the same environment, add the consumer agent as an existing component, then edit the agent through that unmanaged layer.

Exact Maker portal path:

1. Open `https://make.powerapps.com`.
2. Top bar → environment selector → choose the target environment.
3. Left nav → **Solutions**.
4. Select **+ New solution**.
5. Display name: `Debug Logger Agent Overlay`.
6. Name: `DebugLoggerAgentOverlay`.
7. Publisher: choose an unmanaged publisher for your tenant.
8. Select **Create**.
9. Open **Debug Logger Agent Overlay**.
10. Command bar → **Add existing**.
11. Choose the component type for Copilot Studio agents in your tenant, typically **Agent** or **Copilot**.
12. Select the consumer agent.
13. Select **Add**.
14. Open the consumer agent from Copilot Studio.
15. Edit **Overview** → **Instructions**.
16. Save and publish.

The instruction edit lives in the unmanaged overlay. Do not modify the managed base solution.

### `Tool flow not found` from `inject-flow-guid.ps1`

**Symptom:** `inject-flow-guid.ps1` exits with a message like `Tool flow 'tool-log-agent-trace' not found`.

**Cause:** The PVA-trigger flow has not been materialized in the workflows table yet. Importing the solution alone is not enough for the GUID query in every tenant.

**Fix:** Complete Step 6 first.

Exact recovery:

1. Open `https://copilotstudio.microsoft.com`.
2. Open at least one consumer agent.
3. Left nav → **Tools** → **+ Add a tool** → **Flow**.
4. Add **tool-log-agent-trace**.
5. Rerun:

```powershell
pwsh copilot-agent-debug-logger\scripts\inject-flow-guid.ps1 -EnvironmentId "<env-guid>"
```

### Connection reference remains unset

**Symptom:** The solution imports, but `flow-1-log-agent-trace` or `tool-log-agent-trace` fails on a Dataverse action.

**Cause:** The `shared_commondataserviceforapps` connection reference is not bound in the target environment.

**Fix:** Use the [Connection References](#connection-references) section above, then turn the flows off/on if Power Automate asks for a refresh.

---

## Validation checklist

Before handing the environment to another maker, verify each item.

- [ ] `pac org who` points at the target environment.
- [ ] Phase-0 MDA artifacts exist under `copilot-agent-debug-logger\src\Solutions\CanvasApps\AgentDebugConsole_*`.
- [ ] `provision-environment.ps1` completed without errors.
- [ ] `deploy-solution.ps1 -SkipInjectFlowGuid` completed on first import.
- [ ] `cr_DebugLoggerEnabled` current value is `true` only in the test environment.
- [ ] `tool-log-agent-trace` is registered as an Action on each consumer agent that imports full topics.
- [ ] `inject-flow-guid.ps1` wrote substituted YAML to `copilot-agent-debug-logger\dist\topics\`.
- [ ] Full topics no longer contain `{{TOOL_LOG_AGENT_TRACE_FLOW_ID}}` after substitution.
- [ ] Manual child-flow smoke test writes one `POWER_AUTOMATE_FLOW` row.
- [ ] Consumer-agent test writes one `COPILOT_TOPIC` row.
- [ ] No sample data contains real tenant URLs, real domains, real UPNs, logs, or dumps.

Quick placeholder check:

```powershell
Select-String -Path copilot-agent-debug-logger\dist\topics\*.yml -Pattern "\{\{TOOL_LOG_AGENT_TRACE_FLOW_ID\}\}"
```

Expected result: no matches in `dist\topics` for full topic imports.

---

## Cross-references

- Power CAT Custom Engine blog (Oct 2025) — source pattern for the chain-of-thought and conversation-history topic templates.
- Power CAT Copilot Studio Kit — complementary analytics and dashboards; this POC does not replace it.
- Skills for Copilot Studio plugin — CLI topic import path; see `docs\skills-plugin-guide.md` when available.
- Phase-0 MDA authoring — [`docs\phase-0-mda-authoring.md`](phase-0-mda-authoring.md).
- Native debugging stack to exhaust first — [`docs\native-debugging-cheatsheet.md`](native-debugging-cheatsheet.md).
- Maker patterns A-E — `docs\maker-guide.md` when available.

---

## What this deployment does not cover

This POC intentionally does not provide:

- production PII redaction;
- retention policies;
- per-user or per-agent toggles;
- custom security roles;
- App Insights mirroring;
- Power BI dashboards;
- managed-solution ALM;
- automated MDA authoring;
- automated connection-reference settings files.

The payload field is raw, no redaction, and capped at 900,000 characters before write. Add redaction, retention, and role design before UAT or production use.
