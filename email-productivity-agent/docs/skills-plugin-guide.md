# Skills for Copilot Studio — Plugin Guide (Email Productivity Agent)

This guide covers how to use the [Skills for Copilot Studio](https://github.com/microsoft/skills-for-copilot-studio) plugin with the Email Productivity Agent (EPA). The plugin lets you author, test, and troubleshoot Copilot Studio agents directly from GitHub Copilot CLI — without clicking through the portal.

> **What's already here:** `copilot-studio/` contains the live agent definition — `agent.mcs.yml`, `settings.mcs.yml`, and 15 topic YAML files (2 custom: `nudge`, `snooze`). Use the plugin to validate, improve, and test these files.

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

After installation, enable **auto-updates** in plugin settings.

Verify installation by typing `/` — you should see `copilot-studio:author`, `copilot-studio:test`, and `copilot-studio:troubleshoot` in the autocomplete menu.

---

## Step 2: Open the Agent Directory

```
cd email-productivity-agent
```

The agent definition is at:
```
copilot-studio/
├── agent.mcs.yml          # Agent metadata
├── settings.mcs.yml       # Auth, generative actions settings
├── topics/
│   ├── nudge.topic.mcs.yml      # Custom: follow-up nudge decisioning
│   ├── snooze.topic.mcs.yml     # Custom: snooze auto-removal evaluation
│   └── (13 system topics)
├── actions/
├── knowledge/
└── variables/
```

---

## Step 3: Validate the Nudge and Snooze Topics

```
/copilot-studio:troubleshoot Validate nudge.topic.mcs.yml and snooze.topic.mcs.yml in copilot-studio/topics/ for schema compliance and best-practice adherence. Check trigger phrases, variable scoping, condition groups, and action wiring.
```

Common issues to look for:
- **Trigger phrase overlap** between nudge and snooze (both relate to email follow-up — potential disambiguation)
- **Variable scoping** — confirm input variables from Power Automate flows are correctly declared
- **Condition groups** — verify the nudge decisioning logic uses `ConditionGroup` correctly rather than flat conditions

---

## Step 4: Improve Topics with Best Practices

The nudge and snooze topics interact with Power Automate flows via `ExecuteAgentAndWait`. Ask the plugin to review and improve the wiring:

```
/copilot-studio:author Review nudge.topic.mcs.yml. The topic receives these inputs from Power Automate: email subject, sender email, sent date, days since sent, and nudge config (days threshold, quiet hours, max nudges). Improve the topic to handle edge cases like emails sent to distribution lists, and add a condition branch for when the nudge config specifies quiet hours.
```

```
/copilot-studio:author Review snooze.topic.mcs.yml. The topic evaluates whether a snoozed email thread has received a reply and should be auto-unsnoozed. Improve the topic to better handle the case where the reply came from the user themselves (not an external reply).
```

---

## Step 5: Push Changes to Copilot Studio

1. Open VS Code in `email-productivity-agent/`
2. Locate the **Copilot Studio Extension** in the left sidebar
3. Select **Push** → choose your target environment and agent
4. Confirm the push → then **Publish** in the [Copilot Studio UI](https://copilotstudio.microsoft.com)

---

## Step 6: Test the Published Agent

### Setup: Azure App Registration (one-time)

- **Platform**: Public client / Native (Mobile and desktop applications)
- **Redirect URI**: `http://localhost` (HTTP, not HTTPS)
- **API permissions**: `CopilotStudio.Copilots.Invoke` — admin grant required

### Point-tests for nudge logic

```
/copilot-studio:test Send "I sent an email to john@example.com 5 days ago about the contract renewal and haven't heard back" to the published agent

/copilot-studio:test Send "Check if I need to follow up on any emails" to the published agent
```

### Point-tests for snooze logic

```
/copilot-studio:test Send "I snoozed an email thread with sarah@example.com — has she replied yet?" to the published agent

/copilot-studio:test Send "Remove the snooze on the project kickoff thread, there's been a new reply" to the published agent
```

### Verify negative cases (should not trigger nudge)

```
/copilot-studio:test Send "I sent an email to my team distribution list about the all-hands meeting" to the published agent
```

---

## Step 7: Troubleshoot Issues

```
# Wrong topic routing
/copilot-studio:troubleshoot The agent is routing snooze removal requests to the nudge topic instead of the snooze topic

# Power Automate integration issues
/copilot-studio:troubleshoot The nudge topic is not correctly receiving the sender email variable from the Power Automate flow — the variable appears empty in the topic execution

# Generative answer falling through
/copilot-studio:troubleshoot The agent is giving a generic response instead of executing the nudge decisioning logic
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

## Relationship to Power Automate Flows

The EPA Copilot Studio agent is invoked by Power Automate flows via `ExecuteAgentAndWait`. The plugin complements (but doesn't replace) the flow-based test harnesses in `src/`:

| Test Approach | Tool | When to Use |
|---|---|---|
| Point-test a topic | `/copilot-studio:test` | Quick validation of topic logic after YAML changes |
| Full flow regression | `scripts/invoke-followup-test-harness.ps1` | End-to-end validation including Dataverse reads/writes |
| Schema validation | `/copilot-studio:troubleshoot` | Before pushing YAML to catch errors early |
| Batch test suite | Power CAT Copilot Studio Kit | Systematic coverage across multiple test cases |

---

## Key Files

| File | Purpose |
|---|---|
| `copilot-studio/agent.mcs.yml` | Agent metadata |
| `copilot-studio/settings.mcs.yml` | Auth config |
| `copilot-studio/topics/nudge.topic.mcs.yml` | Follow-up nudge decisioning |
| `copilot-studio/topics/snooze.topic.mcs.yml` | Snooze auto-removal evaluation |
| `prompts/nudge-agent-system-prompt.md` | Source of truth for nudge agent behavior |
| `prompts/snooze-agent-system-prompt.md` | Source of truth for snooze agent behavior |

---

## Related Docs

- [Deployment Guide](deployment-guide.md)
- [Follow-up Nudge Flows](follow-up-nudge-flows.md)
- [Snooze Auto-Removal Flows](snooze-auto-removal-flows.md)
- [Skills for Copilot Studio GitHub Repo](https://github.com/microsoft/skills-for-copilot-studio)
- [VS Code Copilot Studio Extension](https://github.com/microsoft/vscode-copilotstudio)
