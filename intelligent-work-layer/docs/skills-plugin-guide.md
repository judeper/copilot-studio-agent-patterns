# Skills for Copilot Studio — Plugin Guide (Intelligent Work Layer)

This guide covers how to use the [Skills for Copilot Studio](https://github.com/microsoft/skills-for-copilot-studio) plugin with the Intelligent Work Layer (IWL) agent. The plugin lets you author, test, and troubleshoot Copilot Studio agents directly from GitHub Copilot CLI — without clicking through the portal.

> **What's already here:** `copilot-studio/` contains the live agent definition — `agent.mcs.yml`, `settings.mcs.yml`, and 17 topic YAML files. Use the plugin to extend, validate, and test these files.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| GitHub Copilot CLI (latest) | `gh copilot --version` |
| VS Code + [Copilot Studio Extension](https://github.com/microsoft/vscode-copilotstudio) | Used to push/pull YAML to your environment |
| PAC CLI | `pac --version` — already required by the main deployment guide |
| Power Platform environment with Copilot Studio capacity | Required for publishing and testing |
| Azure App Registration | Required for `/copilot-studio:test` — see setup below |

---

## Step 1: Install the Plugin

```
/plugin marketplace add microsoft/skills-for-copilot-studio
/plugin install copilot-studio@skills-for-copilot-studio
```

After installation, enable **auto-updates** in plugin settings. The Copilot Studio YAML schema evolves — auto-updates ensure the plugin always reflects the latest patterns and schema definitions.

Verify installation by typing `/` — you should see `copilot-studio:author`, `copilot-studio:test`, and `copilot-studio:troubleshoot` in the autocomplete menu.

---

## Step 2: Open the Agent Directory

Open this solution folder in GitHub Copilot CLI. The plugin works against the files in `intelligent-work-layer/copilot-studio/`:

```
cd intelligent-work-layer
```

The agent definition is at:
```
copilot-studio/
├── agent.mcs.yml          # Agent metadata, conversation starters, model hints
├── settings.mcs.yml       # Auth, generative actions settings
├── topics/                # 17 topic YAML files
│   ├── triage.topic.mcs.yml
│   ├── humanizer.topic.mcs.yml
│   ├── daily-briefing.topic.mcs.yml
│   ├── orchestrator.topic.mcs.yml
│   └── (13 system topics)
├── actions/               # Connector actions (agent tool flows)
├── knowledge/             # Knowledge sources
└── variables/             # Global variables
```

---

## Step 3: Validate Existing Topics

Before making changes, validate the current state:

```
/copilot-studio:troubleshoot Validate all topics in copilot-studio/topics/ and report any schema errors, disambiguation risks, or routing anti-patterns
```

With 17 topics (4 custom + 13 system), routing conflicts are the most common issue. Pay particular attention to how `triage.topic.mcs.yml` and `orchestrator.topic.mcs.yml` handle trigger phrases vs. the system `fallback` and `multiple-topics-matched` topics.

---

## Step 4: Author Missing v3.0 Topics

The IWL v3.0 architecture introduced 7 new specialized agents whose system prompts live in `prompts/` but do not yet have corresponding topic YAML files in `copilot-studio/topics/`:

| Prompt File | Missing Topic | Purpose |
|---|---|---|
| `prompts/router-agent-prompt.md` | `router.topic.mcs.yml` | Signal routing decisions |
| `prompts/calendar-agent-prompt.md` | `calendar.topic.mcs.yml` | Calendar event processing |
| `prompts/task-agent-prompt.md` | `task.topic.mcs.yml` | Task extraction from signals |
| `prompts/email-compose-agent-prompt.md` | `email-compose.topic.mcs.yml` | Email composition |
| `prompts/search-agent-prompt.md` | `search.topic.mcs.yml` | Search orchestration |
| `prompts/validation-agent-prompt.md` | `validation.topic.mcs.yml` | Output validation |
| `prompts/delegation-agent-prompt.md` | `delegation.topic.mcs.yml` | Task delegation |

Use `/copilot-studio:author` to generate these topics. Provide the prompt content as context:

```
/copilot-studio:author I am building the Intelligent Work Layer agent. Read prompts/router-agent-prompt.md and create a new topic called "router" in copilot-studio/topics/ that implements this agent as a Copilot Studio topic. Wire it as a child agent invocation from the triage topic.
```

Repeat for each missing topic, or batch them:

```
/copilot-studio:author Read the following prompt files and create corresponding topics in copilot-studio/topics/ for each: prompts/calendar-agent-prompt.md, prompts/task-agent-prompt.md, prompts/email-compose-agent-prompt.md, prompts/search-agent-prompt.md, prompts/validation-agent-prompt.md, prompts/delegation-agent-prompt.md. Each topic should follow the same pattern as the existing triage.topic.mcs.yml — topic trigger phrases, input variables, generative answer nodes, and output variable assignments.
```

---

## Step 5: Wire Agent Tool Flows as Actions

The IWL agent uses 10 tool flows as callable Actions. After generating new topics, ensure they reference the correct action definitions in `copilot-studio/actions/`:

```
/copilot-studio:author Review the new topics in copilot-studio/topics/ and verify each one correctly references its tool flow actions from copilot-studio/actions/. The tool flows are: SearchUserEmail, SearchSentItems, SearchTeamsMessages, SearchSharePoint, SearchPlannerTasks, QueryCards, QuerySenderProfile, UpdateCard, CreateCard, RefineDraft.
```

---

## Step 6: Push Changes to Copilot Studio

1. Open VS Code in `intelligent-work-layer/`
2. Locate the **Copilot Studio Extension** in the left sidebar
3. Select **Push** → choose your target environment and agent
4. Confirm the push — this creates a **draft** in Copilot Studio

> Pushing creates a draft. You must also click **Publish** in the Copilot Studio UI at [copilotstudio.microsoft.com](https://copilotstudio.microsoft.com) to make changes testable.

---

## Step 7: Test the Published Agent

### Setup: Azure App Registration

Create an App Registration for the test agent (one-time):
- **Platform**: Public client / Native (Mobile and desktop applications)
- **Redirect URI**: `http://localhost` (HTTP, not HTTPS)
- **API permissions**: `CopilotStudio.Copilots.Invoke` — must be granted by an admin

### Point-tests

Send individual utterances to the published agent and verify routing:

```
# Test email triage
/copilot-studio:test Send "I just received an urgent email from the CFO about Q3 budget approval" to the published agent

# Test Teams triage
/copilot-studio:test Send "Someone mentioned me in a Teams channel asking about the project timeline" to the published agent

# Test calendar triage
/copilot-studio:test Send "I have a meeting with the engineering team in 30 minutes about the product roadmap" to the published agent

# Test daily briefing
/copilot-studio:test Send "Give me my morning briefing" to the published agent

# Test orchestrator command
/copilot-studio:test Send "Send the draft for the CFO email" to the published agent
```

### Batch test suite

If you have the [Power CAT Copilot Studio Kit](https://github.com/microsoft/Power-CAT-Copilot-Studio-Kit) installed:

```
/copilot-studio:test Run my test suite
```

### Evaluation analysis

Export evaluation results from the Copilot Studio UI as CSV, then:

```
/copilot-studio:test Analyze my evaluation results from <path-to-csv> and propose fixes for any failed test cases
```

---

## Step 8: Troubleshoot Issues

```
# Routing wrong topic
/copilot-studio:troubleshoot The agent is routing calendar signals to the email triage topic instead of the calendar topic

# Disambiguation errors
/copilot-studio:troubleshoot The agent shows disambiguation when it receives Teams mention signals — it's not routing cleanly to the triage topic

# Generative answer issues
/copilot-studio:troubleshoot The humanizer topic is not applying tone calibration — it seems to be falling through to the default generative answer
```

---

## Dev Loop Summary

```
Clone agent (VS Code Extension)
     ↓
Author / edit topics (Copilot CLI: /copilot-studio:author)
     ↓
Validate (Copilot CLI: /copilot-studio:troubleshoot)
     ↓
Push (VS Code Extension) → Publish (Copilot Studio UI)
     ↓
Test (Copilot CLI: /copilot-studio:test)
     ↓
Troubleshoot & iterate (/copilot-studio:troubleshoot → :author → push → :test)
```

---

## Key Files

| File | Purpose |
|---|---|
| `copilot-studio/agent.mcs.yml` | Agent metadata, model hints, conversation starters |
| `copilot-studio/settings.mcs.yml` | Auth config, generative actions toggle |
| `copilot-studio/topics/triage.topic.mcs.yml` | Main signal triage — entry point for email/Teams/calendar |
| `copilot-studio/topics/orchestrator.topic.mcs.yml` | Command bar execution |
| `copilot-studio/topics/humanizer.topic.mcs.yml` | Tone calibration for draft output |
| `copilot-studio/topics/daily-briefing.topic.mcs.yml` | Morning/EOD/meeting briefing |
| `prompts/` | 22 system prompt `.md` files — source of truth for agent behavior |

---

## Related Docs

- [Architecture Overview](architecture-overview.md)
- [Agent Flows](agent-flows.md)
- [Deployment Guide](deployment-guide.md)
- [Skills for Copilot Studio GitHub Repo](https://github.com/microsoft/skills-for-copilot-studio)
- [VS Code Copilot Studio Extension](https://github.com/microsoft/vscode-copilotstudio)
