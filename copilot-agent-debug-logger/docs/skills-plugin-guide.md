# Copilot Agent Debug Logger — Skills for Copilot Studio Plugin Guide

> Alternative CLI import path. Use this instead of the Copilot Studio Web UI
> if you prefer terminal-based authoring, version-controlled topic YAMLs, or
> a repeatable scripted import workflow.

## What is the Skills plugin?

The Microsoft Skills for Copilot Studio plugin
(https://github.com/microsoft/skills-for-copilot-studio) is an open-source
CLI extension for authoring, validating, importing, and testing Copilot Studio
assets from a terminal.

It works with the same Copilot Studio Adaptive Dialog YAML format
(`.topic.mcs.yml`) used by this repo in `copilot-studio/topics/`.

## When to use it instead of the Web UI

Use the Skills CLI when you want to:

- Validate topic YAML before import.
- Import all 4 topic YAMLs without manually pasting each file.
- Keep topic edits in source control and review them in pull requests.
- Repeat the same import workflow across dev, test, and demo environments.
- Roundtrip-edit topics that already exist in a consumer agent.

Stay on the Web UI when:

- You prefer the visual designer.
- You are doing exploratory edits during a debugging session.
- You are a citizen-developer admin who does not regularly use a terminal.
- You need a one-off import and do not want to install extra tooling.

Both paths produce the same end state. Pick the path that fits your team.

## Prerequisites

- Skills plugin installed. See the upstream README for the current install
  command and distribution model:
  https://github.com/microsoft/skills-for-copilot-studio
- PAC CLI 1.32+ installed and authenticated to the target environment.
- PAC CLI environment selected:

```powershell
pac auth select --environment "<env-id>"
```

- A consumer Copilot Studio agent already created.
- The consumer agent's **Bot ID** available. In the Web UI, open:
  `https://copilotstudio.microsoft.com` → your agent → **Settings**
  (top right) → **General** → **Bot ID**.
- The 4 topic YAMLs ready:
  - `copilot-agent-debug-logger/copilot-studio/topics/log-chain-of-thoughts.topic.mcs.yml` (FULL)
  - `copilot-agent-debug-logger/copilot-studio/topics/log-chain-of-thoughts-blog-pure.topic.mcs.yml`
  - `copilot-agent-debug-logger/copilot-studio/topics/save-conversation-history.topic.mcs.yml` (FULL)
  - `copilot-agent-debug-logger/copilot-studio/topics/save-conversation-history-blog-pure.topic.mcs.yml`

If you import either FULL variant, run GUID substitution first. The FULL
variants call the logger tool flow and need the environment-specific flow ID.

## Workflow

### 1. Validate locally

Validate the source YAML before touching the agent. The exact subcommand name
may evolve; check the upstream README or your installed binary's `--help` for
current syntax. A typical workflow looks like this:

```powershell
skills validate copilot-agent-debug-logger/copilot-studio/topics/log-chain-of-thoughts.topic.mcs.yml
skills validate copilot-agent-debug-logger/copilot-studio/topics/log-chain-of-thoughts-blog-pure.topic.mcs.yml
skills validate copilot-agent-debug-logger/copilot-studio/topics/save-conversation-history.topic.mcs.yml
skills validate copilot-agent-debug-logger/copilot-studio/topics/save-conversation-history-blog-pure.topic.mcs.yml
```

Fix any YAML or schema errors before import.

### 2. Substitute flow GUIDs for FULL variants

Run the substitution script after the Debug Logger solution and tool flow have
been deployed to the target environment:

```powershell
pwsh copilot-agent-debug-logger/scripts/inject-flow-guid.ps1 -EnvironmentId "<env-id>"
```

The script writes substituted output to:

```text
copilot-agent-debug-logger/dist/topics/
```

Use the `dist/topics/` output for import when you include FULL variants.
Re-run this step any time you deploy to a new environment or recreate the tool
flow.

### 3. Import into the consumer agent

Use the consumer agent's Bot ID as `--agent-id`. The Bot ID is not the solution
unique name and not the environment ID.

```powershell
skills import-topics `
  --environment "<env-id>" `
  --agent-id "<consumer-agent-bot-id>" `
  --folder copilot-agent-debug-logger/dist/topics
```

If your installed Skills plugin uses different command names or option names,
use the equivalent import command from the upstream README. The important inputs
are the environment, the consumer agent Bot ID, and the folder containing the 4
ready-to-import topic YAMLs.

### 4. Verify in Copilot Studio

Open `https://copilotstudio.microsoft.com` → your consumer agent → **Topics**.

Confirm these topics appear:

- **Log Chain of Thoughts**
- **Log Chain of Thoughts (Blog-Pure)**
- **Save Conversation History**
- **Save Conversation History (Blog-Pure)**

Open each topic and confirm the imported YAML matches the source or substituted
file you expected. For FULL variants, confirm `flowId` no longer contains
`{{TOOL_LOG_AGENT_TRACE_FLOW_ID}}`.

Then run the smoke test from `docs/deployment-guide.md` Step 8.

## Updating an existing import

When you change the topic YAMLs, validate and import again:

```powershell
skills validate copilot-agent-debug-logger/copilot-studio/topics/log-chain-of-thoughts.topic.mcs.yml
skills validate copilot-agent-debug-logger/copilot-studio/topics/save-conversation-history.topic.mcs.yml

pwsh copilot-agent-debug-logger/scripts/inject-flow-guid.ps1 -EnvironmentId "<env-id>"

skills import-topics `
  --environment "<env-id>" `
  --agent-id "<consumer-agent-bot-id>" `
  --folder copilot-agent-debug-logger/dist/topics
```

Most teams overwrite by topic display name. If your plugin version exposes a
separate `update`, `push`, or `overwrite` flag, use the upstream README for the
current recommended syntax.

## Versioning and CI

Commit the source topic YAMLs in `copilot-studio/topics/`.

Keep `dist/topics/` out of source control because it contains per-environment
runtime output. Add a CI check that runs the Skills plugin validation command on
pull requests touching `*.topic.mcs.yml`.

A simple validation matrix is:

- Validate `log-chain-of-thoughts.topic.mcs.yml`.
- Validate `log-chain-of-thoughts-blog-pure.topic.mcs.yml`.
- Validate `save-conversation-history.topic.mcs.yml`.
- Validate `save-conversation-history-blog-pure.topic.mcs.yml`.

## Troubleshooting

### "Agent ID not found"

Use the consumer agent **Bot ID** as `--agent-id`. Find it at
`https://copilotstudio.microsoft.com` → your agent → **Settings** →
**General** → **Bot ID**.

### Import succeeds but the topic does not appear

Refresh the **Topics** page. The Web UI can cache topic lists for about
30 seconds. If it still does not appear, inspect the import response JSON for
per-topic errors.

### YAML validates locally but import fails

The hosted Copilot Studio schema can move ahead of the local CLI. Update the
Skills plugin by using the current upstream install/update instructions, then
run validation and import again.

### Tool flow GUID mismatch after redeploy

A fresh environment or recreated tool flow gets a new flow ID. Re-run:

```powershell
pwsh copilot-agent-debug-logger/scripts/inject-flow-guid.ps1 -EnvironmentId "<env-id>"
```

Then re-import from `copilot-agent-debug-logger/dist/topics/`.

## Cross-references

- Upstream plugin: https://github.com/microsoft/skills-for-copilot-studio
- Web UI alternative: `docs/deployment-guide.md` Step 7, GUID substitution.
- Topic authoring convention: `.github/copilot-instructions.md` §Topic definitions.
- Power CAT Custom Engine blog (Oct 2025): source pattern for the topic templates.
- Power CAT Copilot Studio Kit: complementary analytics and regression layer;
  it does not replace this Debug Logger or the Skills plugin import path.
