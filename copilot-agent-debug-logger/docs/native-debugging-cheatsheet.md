# Native Debugging Cheatsheet — What This POC Does NOT Rebuild

Microsoft already ships rich debugging surfaces for Copilot Studio and Power Automate. Use these first: they are native, supported, and usually enough for day-to-day maker triage. The Debug Logger POC fills the specific gaps that remain after those native tools have been exhausted.

---

## Native capabilities table

| Native capability | What it gives you | When to use |
|---|---|---|
| Test pane → Save Snapshot | `dialog.json` with `IntentRecognition` (TopicName + Score), `DialogRedirect` activities, tool/MCP invocation events, generative orchestration plan, `SearchAndSummarizeContent` for knowledge sources, per-step timing, `SessionInfo` outcome | Single-conversation forensic deep dive |
| App Insights + `/debug conversationid` | Errors, latency, dependency failures keyed by conversation GUID; KQL over `customEvents` | Production telemetry |
| `ConversationTranscript` Dataverse table | Full message history, intent confidence, full orchestration plan, knowledge chunks (~30 min write delay) | Production triage |
| Developer Mode in test pane | All globals, node info, routing decisions throughout session | Verbose live debugging |
| Activity Map & Transcripts page | Visual node map of inputs/decisions/reactions | Visual flow understanding |
| Power CAT Copilot Studio Kit — Agent Insights Hub | Pre-built dashboards + batch regression testing | Cross-agent fleet view |

---

## Test pane → Save Snapshot

**Use this first for a single broken conversation.** A saved snapshot is the fastest native way to inspect the exact design-time turn that failed.

**Click-path**

1. Open the agent in Copilot Studio.
2. Select **Test** to open the **Test your agent** pane.
3. Select the **⋯** menu at the top of the test pane.
4. Select **Save snapshot**.
5. Select **Save** when Copilot Studio warns that the snapshot might contain sensitive information.
6. Download the snapshot archive and inspect `dialog.json`.

**What to look for in `dialog.json`**

- `IntentRecognition` with `TopicName` and confidence `Score`.
- `DialogRedirect` activities showing topic routing.
- Tool, flow, action, or MCP invocation events.
- Generative orchestration plan details.
- `SearchAndSummarizeContent` for knowledge-source grounding.
- Per-step timing for slow nodes or slow actions.
- `SessionInfo` outcome for the overall turn.

**Good fit**

Use it when one test conversation behaved incorrectly and you need a forensic bundle for that exact run.

**Source**

Microsoft Learn documents **Save snapshot** in the Copilot Studio **Test your agent** pane: <https://learn.microsoft.com/en-us/microsoft-copilot-studio/authoring-test-bot>. The v5 plan also cites the Power CAT Custom Engine blog (Oct 2025) for the deeper native-debugging landscape.

---

## App Insights + `/debug conversationid`

**Use this first for production telemetry.** Application Insights is the native place to inspect errors, latency, dependency failures, and custom events for conversations that have already happened.

**Click-path**

1. In Copilot Studio, open the agent.
2. Go to **Settings** → **Advanced**.
3. In **Application Insights**, enter the Application Insights **Connection string**.
4. Enable the logging options your environment allows.
5. Reproduce or collect the affected conversation.
6. Use `/debug conversationid` where supported to capture the conversation identifier.
7. In the Azure portal, open the Application Insights resource → **Logs**.
8. Query `customEvents` by conversation identifier.

**Small KQL starter**

```kusto
let conversationId = "<paste-conversation-id>";
customEvents
| where timestamp > ago(24h)
| where tostring(customDimensions["conversationId"]) == conversationId
   or tostring(customDimensions["conversationId"]) contains conversationId
| project timestamp, name, operation_Id, customDimensions
| order by timestamp asc
```

**Good fit**

Use it when the issue is in a published channel, involves latency or dependency failures, or needs trend analysis beyond a single test-pane run.

**Source**

Microsoft Learn documents Application Insights telemetry and `customEvents` queries for Copilot Studio: <https://learn.microsoft.com/en-us/microsoft-copilot-studio/advanced-bot-framework-composer-capture-telemetry>. For the conversation ID command, the v5 plan cites the Power CAT Custom Engine blog (Oct 2025); if you need the original post, search Microsoft Tech Community or The Custom Engine for **Custom Engine in Copilot Studio** and **conversation ID**.

---

## ConversationTranscript Dataverse table

**Use this first for production triage where the full transcript matters.** The `ConversationTranscript` table is the native Dataverse source for transcript export and reporting.

**Click-path**

1. Open <https://make.powerapps.com/>.
2. Select the target environment.
3. Go to **Solutions** → **Default solution**.
4. Open **Tables**.
5. Search for `ConversationTranscript`.
6. Open the table and export or inspect the rows your role can access.

**What it gives you**

- Full message history for stored conversations.
- Intent confidence and orchestration details.
- Knowledge chunks used in responses when available.
- Dataverse-native export paths for reporting and review.

**Important delay**

Plan for an approximate **30-minute write delay**. Microsoft Learn describes transcript records being saved after inactivity, so this table is useful for production triage but not for instant live debugging.

**Good fit**

Use it when a maker, admin, or support owner needs transcript-level evidence after the conversation has completed.

**Source**

Microsoft Learn documents viewing and exporting the `ConversationTranscript` table: <https://learn.microsoft.com/en-us/microsoft-copilot-studio/analytics-sessions-transcripts>.

---

## Developer Mode in test pane

**Use this first for verbose live debugging.** Developer Mode helps a maker watch routing, variables, and node-level state while the test conversation is still running.

**Click-path**

1. Open the agent in Copilot Studio.
2. Open the **Test** pane.
3. Open test pane settings.
4. Set **Developer mode** to **On**.
5. Run the test conversation again.

**What to inspect**

- Global, system, and topic variables.
- Node information for the active turn.
- Routing decisions throughout the session.
- Any debug cards or trace details surfaced by the current Copilot Studio experience.

**Good fit**

Use it when you need live visibility while iterating on a topic, action, prompt, or orchestration path.

**Source**

The v5 plan cites the Power CAT Custom Engine blog (Oct 2025) for this native debugging surface. Microsoft Learn also documents developer-mode debugging concepts for Microsoft 365 Copilot agents: <https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/debugging-agents-copilot-studio>.

---

## Activity Map & Transcripts page

**Use this first when the problem is easier to understand visually.** Activity Map shows how the agent moved through inputs, decisions, actions, and responses.

**Click-path**

1. Open the maker portal.
2. Open the agent.
3. Go to **Analytics** → **Activity Map / Transcripts**.
4. Select the affected activity.
5. Use the map to inspect inputs, decisions, reactions, timing, and errors.

**What to look for**

- Which node or action the agent selected.
- Missing or invalid input and output parameters.
- Slow steps.
- Unexpected routing or decision points.
- Transcript context next to the visual map.

**Good fit**

Use it when a screenshot-level view of the agent path will explain the issue faster than raw JSON.

**Source**

Microsoft Learn documents real-time and historical activity maps, transcript-plus-map view, and node details: <https://learn.microsoft.com/en-us/microsoft-copilot-studio/authoring-review-activity>.

---

## Power CAT Copilot Studio Kit — Agent Insights Hub

**Use this first for fleet-level analytics and regression testing.** The Power CAT Kit is not a low-level payload logger; it is a broader toolkit for governing, testing, and improving agents at scale.

**Click-path**

1. Open the Power CAT Copilot Studio Kit repository.
2. Follow the kit setup guide for your environment.
3. Use **Agent Insights Hub** for dashboard views.
4. Use the kit testing features for batch regression coverage across prompts and agents.

**What it gives you**

- Pre-built dashboards.
- Batch regression testing.
- Cross-agent reporting.
- Governance and quality views for makers and admins.

**Good fit**

Use it when the question is about agent quality, trends, or regression status across more than one agent.

**Source**

Power CAT Copilot Studio Kit: <https://github.com/microsoft/Power-CAT-Copilot-Studio-Kit>. Microsoft Learn overview: <https://learn.microsoft.com/en-us/microsoft-copilot-studio/guidance/kit-overview>.

---

## Gaps this POC covers

After exhausting the native stack, three practical gap categories remain: exact Power Automate payload capture, correlation across Copilot Studio and Power Automate records, and drop-in topic templates for maker debugging. The v5 plan breaks those down as follows.

| Gap | This POC |
|---|---|
| Exact request envelope sent from PA to `ExecuteAgentAndWait` | `flow-1-log-agent-trace` child flow wraps the call |
| Exact inputs/outputs of each tool flow the agent invokes | Same child flow at tool-flow trigger and pre-respond |
| Shared correlation ID stitching CS-side and PA-side records | `System.Conversation.Id` default (no agent changes); optional override via `correlation_id` packed into existing serialized JSON input |
| Drop-in CoT and ConvHistory topic templates | Ship as `.topic.mcs.yml` in `copilot-studio/topics/` (full + blog-pure variants) |
| Optional persistence of CoT/ConvHistory to a queryable table | Full topic variant always emits chat output (blog fidelity); always invokes tool flow; flow no-ops when env var off |

---

## Positioning vs Power CAT Kit

The Debug Logger POC is complementary to the Power CAT Copilot Studio Kit, not a substitute. Use the Power CAT Kit for analytics, dashboards, governance, and batch regression testing across agents. Use this POC when a maker needs request/response payload capture at the debugging workbench, especially around Power Automate `ExecuteAgentAndWait` calls and agent-invoked tool flows.

---

## External references

- **Power CAT Custom Engine blog (Oct 2025)** — cited by the v5 plan for the native debugging landscape. If you need the original source, search Microsoft Tech Community or The Custom Engine for **Custom Engine in Copilot Studio**.
- **Microsoft Learn: Copilot Studio — Test your agent and Save snapshot**: <https://learn.microsoft.com/en-us/microsoft-copilot-studio/authoring-test-bot>
- **Microsoft Learn: Copilot Studio — Application Insights telemetry and `customEvents`**: <https://learn.microsoft.com/en-us/microsoft-copilot-studio/advanced-bot-framework-composer-capture-telemetry>
- **Power CAT / The Custom Engine: Conversation ID command** — search for **How to Get Your Conversation ID When Chatting With Agents** if you need the `/debug conversationid` walkthrough.
- **Microsoft Learn: Copilot Studio — Conversation transcripts and `ConversationTranscript`**: <https://learn.microsoft.com/en-us/microsoft-copilot-studio/analytics-sessions-transcripts>
- **Microsoft Learn: Copilot Studio — Activity map and transcripts**: <https://learn.microsoft.com/en-us/microsoft-copilot-studio/authoring-review-activity>
- **Microsoft Learn: Developer-mode debugging for Microsoft 365 Copilot agents**: <https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/debugging-agents-copilot-studio>
- **Power CAT Copilot Studio Kit GitHub repo**: <https://github.com/microsoft/Power-CAT-Copilot-Studio-Kit>
