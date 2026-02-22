# Enterprise Work Assistant Agent — Implementation Design

This document provides the high-level steps required to implement the Enterprise Work Assistant Agent as described in the system prompt specification. Each section maps to the platform components within Microsoft Copilot Studio, Power Automate, Dataverse, and Power Apps (Canvas).

***

## 1. Foundation: Environment & Identity Setup

Before building anything, establish the Power Platform environment and security posture.

### Steps

1. **Provision a dedicated Power Platform environment** (or use an existing governed one) with Copilot Studio capacity allocated. All agent flows, the Copilot Studio agent, Dataverse tables, and the Canvas app must live in the same environment.[^1][^2]
2. **Configure Microsoft Entra ID authentication** for the Copilot Studio agent. Set it to "Authenticate users → Require authentication → Microsoft Entra ID" so every invocation operates under a delegated user identity. This satisfies Constraint #1 (Delegated Identity) — the agent inherits the authenticated user's Microsoft 365 permissions and can only access their mailbox, calendar, Teams, SharePoint sites, etc.[^3][^4]
3. **Register API connections** (connection references) in Power Automate for all connectors the agent flows will use:
   - Office 365 Outlook (email read/send)
   - Microsoft Teams
   - Office 365 Users (user profile lookup)
   - Microsoft Graph (calendar, people, search)
   - SharePoint (internal knowledge)
   - Planner / Jira (project tools)
   - HTTP with Azure AD (for external API calls if needed)
4. **Create a Dataverse custom table** called `AssistantCards` (or similar) to persist the JSON output objects. Key columns: `trigger_type`, `triage_tier`, `item_summary`, `priority`, `temporal_horizon`, `confidence_score`, `card_status`, `draft_payload`, `full_json` (multi-line text storing the complete JSON output), `created_on`, `owner` (lookup to systemuser). This table serves as the bridge between the agent layer and the Canvas app dashboard.[^5][^6]
5. **Apply Dataverse row-level security (RLS)** via an ownership-based security role so each user can only read/write their own `AssistantCards` rows. This enforces Constraint #4 (No Cross-User Access) at the data layer.

***

## 2. Event Trigger Layer — Three Power Automate Agent Flows

Build three separate agent flows (or Power Automate cloud flows converted to Copilot Studio plan) — one per trigger type. These are the "interceptors" that capture incoming signals and invoke the Copilot Studio agent.[^7][^8][^1]

### Flow 1: EMAIL Trigger

1. **Trigger**: "When a new email arrives (V3)" — Office 365 Outlook connector. Enable the **Split On** setting so each email gets its own flow run.[^7]
2. **Filter conditions** (optional pre-filter): Exclude emails from known no-reply addresses or distribution lists at the flow level to reduce agent invocations and credit consumption.
3. **Compose the PAYLOAD**: Use a Compose action to build a JSON object containing:
   - `from`, `to`, `cc`, `subject`, `body` (plain text + HTML), `receivedDateTime`, `importance`, `hasAttachments`, `conversationId`, `internetMessageId`
4. **Compose USER_CONTEXT**: Call the Office 365 Users connector "Get my profile" to retrieve `displayName`, `jobTitle`, `department`.
5. **Invoke the Copilot Studio Agent**: Use the "Run a flow from Copilot" / HTTP request action to call the agent, passing `TRIGGER_TYPE = "EMAIL"`, `PAYLOAD`, `USER_CONTEXT`, and `CURRENT_DATETIME` (utcNow()).[^8]
6. **Receive the agent's JSON response** via the "Respond to Copilot" action (100-second window).[^8]
7. **Parse JSON** the response and write a new row to the `AssistantCards` Dataverse table if `triage_tier ≠ SKIP`.[^9]

### Flow 2: TEAMS_MESSAGE Trigger

1. **Trigger**: "When a new channel message is added" or "When someone is mentioned" — Microsoft Teams connector. Scope to channels/chats relevant to the user.
2. Build and pass `PAYLOAD` (message body, sender, channel/chat context, mentions, timestamp).
3. Same invocation pattern as Flow 1 — call the agent, receive JSON, write to Dataverse.

### Flow 3: CALENDAR_SCAN Trigger

1. **Trigger**: Scheduled recurrence — run daily (e.g., 7:00 AM user's local time) or every few hours.
2. **Action**: Use the Office 365 Outlook "Get events (V4)" action to retrieve calendar events for the next 10 business days (the temporal horizon window).
3. **Loop**: For each event, compose a `PAYLOAD` with event subject, body/notes, attendees (names + emails), location, start/end times, organizer, whether it's recurring, online meeting link.
4. Invoke the agent for each event (or batch — see optimization note below). Write resulting cards to Dataverse.

> **Optimization note**: To avoid excessive agent invocations, consider a lightweight pre-triage in the flow itself — skip events with subjects matching known low-value patterns (e.g., "Focus Time", "Lunch", "Public Holiday") before invoking the agent.

***

## 3. Copilot Studio Agent — Core Configuration

This is the "brain" — a single Copilot Studio agent with generative orchestration enabled.[^2][^6]

### Steps

1. **Create a new Agent** in Copilot Studio within the provisioned environment. Name it "Enterprise Work Assistant."
2. **Enable Generative Orchestration** so the agent can autonomously select and chain actions (tools) based on the system prompt instructions.[^2]
3. **Paste the full system prompt** (from the specification) into the agent's system message / instructions field. This instructs the LLM on triage logic, research hierarchy, confidence scoring, and output schema.[^10][^11]
4. **Enforce JSON output**: In the agent's prompt configuration, specify structured output using a JSON schema that matches the OUTPUT SCHEMA from the specification. Copilot Studio supports JSON output mode where you provide the schema and the model returns conforming JSON.[^12][^11][^10]
5. **Set up input parameters**: Define the four runtime inputs as agent input variables — `TRIGGER_TYPE` (choice), `PAYLOAD` (multi-line text / JSON), `USER_CONTEXT` (text), `CURRENT_DATETIME` (text).[^13]

***

## 4. Research Hierarchy — Agent Tools (Actions)

The agent needs access to tools (actions) corresponding to each research tier. Register these as agent actions (agent flows or connectors) so generative orchestration can invoke them as needed.[^14][^15][^1]

### Tier 1 — Internal Personal Context

| Tool | Implementation |
|------|---------------|
| Search user's email threads | Agent flow using Office 365 Outlook "Search emails" action, scoped to the authenticated user's mailbox[^7] |
| Search user's sent items | Same connector, folder = SentItems |
| Search Teams conversations | Agent flow using Microsoft Graph API `GET /me/chats/messages` with `$search` parameter |
| Search meeting notes | Agent flow querying OneNote API or Loop pages via Graph |

### Tier 2 — Internal Organizational Knowledge

| Tool | Implementation |
|------|---------------|
| Search SharePoint sites | Agent flow using SharePoint "Search" action or Microsoft Graph Search API (`/search/query` with entity type `driveItem`, `listItem`)[^16] |
| Search internal wikis | If using SharePoint pages as wiki, same as above. If using a Graph Connector for internal content, query via Microsoft Search API[^17] |

### Tier 3 — Project & Task Tools

| Tool | Implementation |
|------|---------------|
| Query Planner tasks | Agent flow using Microsoft Graph Planner API (`/me/planner/tasks`) |
| Query Jira (if applicable) | Agent flow using HTTP connector calling Jira REST API with stored credentials, or a custom connector |

### Tier 4 — External Public Sources

| Tool | Implementation |
|------|---------------|
| Web search for companies/people/topics | Use a Bing Search MCP server or a custom HTTP action calling Bing Web Search API. Alternatively, connect an MCP server for web search — Copilot Studio supports MCP natively[^18][^15][^19] |
| Public filings / news | Same web search tool, or a dedicated news API connector |

### Tier 5 — Official Documentation

| Tool | Implementation |
|------|---------------|
| Microsoft Learn / product docs | Connect the Microsoft Learn MCP server (if available) or use a web search scoped to `site:learn.microsoft.com`[^18][^15] |

### Tool Registration

For each tool above, create it as either:
- **An Agent Flow** with the "Run a flow from Copilot" trigger and "Respond to Copilot" response action, OR[^1][^14]
- **An MCP connection** pointing to an MCP server that exposes the capability[^15][^19]

Give each tool a clear **name and description** so generative orchestration knows when to invoke it. For example: *"SearchUserEmail — Searches the authenticated user's mailbox for emails matching a query string. Use this for Tier 1 research to find prior conversations about a topic, sender, or project."*

***

## 5. Triage Logic Implementation

The triage classification (SKIP / LIGHT / FULL) is handled entirely by the LLM within the system prompt. However, you can reinforce it:

1. **System prompt already defines the rules** — the agent classifies based on sender type, CC vs. TO, urgency signals, etc.
2. **Add a Knowledge source** containing a curated list of known no-reply addresses, newsletter domains, and internal distribution list patterns. The agent can reference this to improve SKIP accuracy.
3. **For CALENDAR_SCAN**, the temporal horizon reasoning (TODAY / THIS_WEEK / NEXT_WEEK / BEYOND) is also prompt-driven. The agent uses `CURRENT_DATETIME` and the event's start time to calculate the horizon and determine preparation urgency.

***

## 6. Confidence Scoring & Low-Confidence Handling

The confidence score is computed by the LLM based on the rules in Step 4 of the specification. To make this reliable:

1. **Include scoring examples in the system prompt** (or a connected Knowledge source) so the model has calibration anchors.
2. **In the output schema**, `confidence_score` is a required integer. The JSON schema enforcement ensures it's always present.[^12]
3. **When `confidence_score` is 0–39**, the system prompt instructs the agent to:
   - Set `card_status = "LOW_CONFIDENCE"`
   - Populate `low_confidence_note` with what was checked and what the user should verify
   - Set `draft_payload = null` (no draft generated)

***

## 7. Humanizer Agent — Downstream Handoff

For EMAIL and TEAMS_MESSAGE items classified as FULL with confidence ≥ 40, the main agent produces a `draft_payload` object intended for a separate Humanizer Agent.

### Implementation Options

**Option A: Second Copilot Studio Agent (Recommended)**

1. Create a second agent called "Humanizer Agent" in the same environment.
2. Its system prompt instructs it to rewrite a raw draft into natural, human-sounding language calibrated to the `recipient_relationship` and `inferred_tone` fields.
3. The Humanizer Agent is invoked as a **Connected Agent** (child agent) from the main agent's orchestration, or called via a follow-up Agent Flow after the main agent returns its output.[^19]
4. The Humanizer Agent receives the `draft_payload` JSON object and returns a polished `humanized_draft` string.
5. The calling flow updates the Dataverse `AssistantCards` row with the humanized draft.

**Option B: Inline Prompt Action**

1. Instead of a separate agent, add an AI Prompt action within the same topic/flow that takes the `draft_payload` and rewrites it.
2. Simpler but less modular — harder to independently test, version, or swap the humanizer model.

### Key Design Decision

The specification explicitly states *"Do not attempt to humanize the draft yourself"* — meaning the main agent's system prompt must not rewrite the draft. It produces a raw, research-grounded draft, and the humanizer is a separate processing step.

***

## 8. Canvas Power App — Single-Pane-of-Glass Dashboard

The Canvas app is the user-facing surface. It reads from the `AssistantCards` Dataverse table and renders cards.

### Steps

1. **Create a Canvas Power App** in the same environment.[^4]
2. **Connect to the `AssistantCards` Dataverse table** as the primary data source.
3. **Build the main screen** as a scrollable gallery (vertical gallery control) filtered to the current user's cards, sorted by `created_on` descending.
4. **Card template (collapsed view)**: Each gallery item renders a minimal card showing:
   - **Priority indicator** (color-coded: High = red, Medium = amber, Low = green)
   - **Trigger type icon** (envelope for EMAIL, chat bubble for TEAMS_MESSAGE, calendar for CALENDAR_SCAN)
   - **`item_summary`** (1-2 sentence text)
   - **`card_status`** badge (READY, LOW_CONFIDENCE, SUMMARY_ONLY)
   - **`temporal_horizon`** tag (if CALENDAR_SCAN)
5. **Expand behavior**: On card tap, navigate to a detail screen that parses and displays the full JSON:
   - **Research log** (`research_log` field) — displayed in a scrollable text area
   - **Key findings** (`key_findings` field) — bulleted list
   - **Verified sources** (`verified_sources` array) — rendered as tappable links
   - **Draft** (from `draft_payload`) — displayed in an editable text box so the user can review, tweak, and then manually send
   - **Low-confidence note** (if applicable) — displayed in a warning banner
6. **Filtering and sorting controls**: Add dropdowns/toggles at the top to filter by trigger type, priority, card status, or temporal horizon.
7. **(Optional) Embed the Copilot Studio agent** directly in the Canvas app using the App Copilot preview feature, allowing the user to ask follow-up questions about any card.[^3][^4]

### JSON Handling in the Canvas App

- Use the `ParseJSON()` function (available in Canvas apps) to deserialize the `full_json` column into a typed record.
- For the `verified_sources` array, use `ForAll(Table(ParseJSON(...).verified_sources), ...)` to render each source as a hyperlink.[^20]
- For Adaptive Card rendering (optional enhancement), use a custom component or the HTML text control to render an Adaptive Card JSON template populated with the card data.

***

## 9. End-to-End Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                     INCOMING SIGNALS                                │
│  ┌──────────┐    ┌──────────────┐    ┌────────────────────┐        │
│  │  Email    │    │ Teams Msg    │    │ Calendar (Schedule)│        │
│  └────┬─────┘    └──────┬───────┘    └─────────┬──────────┘        │
│       │                 │                      │                    │
│       ▼                 ▼                      ▼                    │
│  ┌──────────────────────────────────────────────────────┐          │
│  │         POWER AUTOMATE AGENT FLOWS (3 flows)         │          │
│  │  • Extract payload + user context                    │          │
│  │  • Invoke Copilot Studio Agent                       │          │
│  │  • Receive JSON response                             │          │
│  │  • Write to Dataverse (AssistantCards table)          │          │
│  └──────────────────────┬───────────────────────────────┘          │
│                         │                                           │
│                         ▼                                           │
│  ┌──────────────────────────────────────────────────────┐          │
│  │           COPILOT STUDIO AGENT (Main)                │          │
│  │  • System prompt: Triage → Research → Score → Output │          │
│  │  • Generative orchestration selects tools/actions     │          │
│  │  • Tools: Email Search, SharePoint Search, Graph,     │          │
│  │    Planner, Web Search, MS Learn (MCP)               │          │
│  │  • Returns strict JSON per OUTPUT SCHEMA              │          │
│  └──────────────────────┬───────────────────────────────┘          │
│                         │                                           │
│              ┌──────────┴──────────┐                                │
│              │  FULL + conf ≥ 40?  │                                │
│              └──────────┬──────────┘                                │
│                    Yes  │  No → store as-is                         │
│                         ▼                                           │
│  ┌──────────────────────────────────────────────────────┐          │
│  │          HUMANIZER AGENT (Connected Agent)           │          │
│  │  • Receives draft_payload                            │          │
│  │  • Rewrites draft in natural tone                    │          │
│  │  • Returns humanized_draft                           │          │
│  └──────────────────────┬───────────────────────────────┘          │
│                         │                                           │
│                         ▼                                           │
│  ┌──────────────────────────────────────────────────────┐          │
│  │              DATAVERSE (AssistantCards)               │          │
│  │  • Row-level security: user sees only their cards    │          │
│  │  • Stores full JSON output + humanized draft          │          │
│  └──────────────────────┬───────────────────────────────┘          │
│                         │                                           │
│                         ▼                                           │
│  ┌──────────────────────────────────────────────────────┐          │
│  │         CANVAS POWER APP (Dashboard)                 │          │
│  │  • Gallery of minimal cards (collapsed view)         │          │
│  │  • Expand to see full research + draft               │          │
│  │  • Filter by type, priority, status, horizon         │          │
│  │  • User reviews, edits, and manually sends           │          │
│  └──────────────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────────┘
```

***

## 10. Security & Governance Checklist

| Concern | Mitigation |
|---------|-----------|
| **Delegated identity** | Entra ID authentication on the agent; all connector actions run as the signed-in user[^3] |
| **No fabrication** | System prompt rule + JSON schema enforcement; agent must cite only retrieved sources[^12][^10] |
| **PII handling** | System prompt prohibits echoing sensitive data; Dataverse column-level security on `full_json` if needed |
| **No cross-user access** | Dataverse ownership-based RLS; Canvas app filters to `Owner = User()` |
| **DLP compliance** | Power Platform DLP policies applied to the environment — restrict which connectors can be used together[^2] |
| **Audit trail** | Enable Purview/Sentinel auditing for Copilot Studio agent activities; Power Automate flow run history provides execution logs[^2] |
| **Responsible AI** | Copilot Studio's built-in Responsible AI content filtering applies to all agent outputs[^21] |

***

## 11. Licensing & Capacity Considerations

- **Copilot Studio capacity**: Each agent invocation consumes capacity (Classic Answers or Autonomous Actions depending on orchestration mode). The CALENDAR_SCAN trigger, running daily across potentially dozens of events, will be the highest-volume consumer — pre-filter aggressively.[^1]
- **Agent flows converted to Copilot Studio plan** consume Copilot Studio capacity instead of Power Automate per-flow licensing.[^22][^1]
- **Dataverse storage**: Each `AssistantCards` row is small (a few KB of JSON text), but implement a retention policy (e.g., auto-delete cards older than 30 days) to manage storage.
- **Power Apps per-user or per-app licensing**: The Canvas app requires appropriate Power Apps licensing for each user.

***

## 12. Implementation Phases

### Phase 1 — MVP (Weeks 1–3)
- Environment setup, Dataverse table, security roles
- EMAIL trigger agent flow (single trigger type)
- Copilot Studio agent with system prompt, JSON output, and Tier 1 + Tier 4 tools only
- Basic Canvas app with gallery and detail view
- Manual testing with real emails

### Phase 2 — Full Triggers (Weeks 4–5)
- Add TEAMS_MESSAGE trigger flow
- Add CALENDAR_SCAN trigger flow with temporal horizon logic
- Add Tier 2 (SharePoint) and Tier 3 (Planner) tools
- Refine triage accuracy based on Phase 1 testing

### Phase 3 — Humanizer & Polish (Weeks 6–7)
- Build and integrate the Humanizer Agent
- Add confidence scoring calibration (test with diverse email samples, adjust prompt)
- Canvas app UX improvements: priority color coding, filtering, temporal horizon badges
- Add Tier 5 (Microsoft Learn) tool for technical items

### Phase 4 — Governance & Scale (Week 8+)
- DLP policy validation
- Purview/Sentinel audit integration
- Load testing (simulate high email volume)
- User acceptance testing with pilot group
- Dataverse retention policy
- Documentation and handoff

***

## 13. Key Technical Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| **100-second timeout** on "Respond to Copilot" action | Multi-tier research may exceed the time limit[^8] | Implement parallel tool calls where possible; set aggressive timeouts per research tier; fall back to partial results |
| **LLM non-determinism** in triage classification | Same email type may get classified differently across runs | Add few-shot examples in the system prompt; use a Knowledge source with classification examples; log and review edge cases |
| **JSON schema drift** | Agent occasionally returns malformed JSON | Use Copilot Studio's native JSON output mode with schema enforcement[^12]; add a Parse JSON step in the flow with error handling |
| **Calendar scan volume** | A user with 40+ events in 10 business days triggers 40 agent calls daily | Pre-filter in the flow: skip recurring 1:1s with no agenda changes, focus time blocks, holidays; batch similar events |
| **Connector throttling** | Microsoft Graph / Outlook / Teams APIs have rate limits | Implement retry logic with exponential backoff in agent flows; spread calendar scans across time windows |

***

## 14. Testing Strategy

1. **Unit test each agent flow** independently by manually providing sample payloads and verifying Dataverse writes.
2. **Test the Copilot Studio agent** using the built-in test chat — provide various `TRIGGER_TYPE` + `PAYLOAD` combinations and validate JSON output conformance.
3. **Integration test** the full loop: send a real email → verify the agent flow fires → verify the agent processes it → verify the card appears in the Canvas app.
4. **Edge case testing**:
   - Newsletter email (should SKIP)
   - CC-only email (should SKIP)
   - Urgent email from an external client (should FULL with High priority)
   - Calendar event with external attendees next week (should FULL with NEXT_WEEK horizon)
   - Email where no research sources return results (should LOW_CONFIDENCE)
5. **Humanizer A/B test**: Compare raw drafts vs. humanized drafts with real users to calibrate tone accuracy.

***

This design gives you a complete, buildable architecture using native Microsoft Power Platform components. The system prompt you've written is effectively the agent's "operating system" — the implementation steps above create the infrastructure that feeds it signals, gives it tools, persists its output, and surfaces results to the user.

---

## References

1. [Agent flows overview - Microsoft Copilot Studio](https://learn.microsoft.com/en-us/microsoft-copilot-studio/flows-overview) - Agent flows are a powerful way to automate repetitive tasks and integrate your apps and services. Ag...

2. [Power Automate and Copilot Studio Autonomous Agents](https://holgerimbery.blog/powerautomate-autonomousagents) - Copilot Studio agents: Generative orchestration—the agent selects and chains actions (including flow...

3. [Integrate Your Custom Copilot into Your Canvas App in Power ...](https://www.inogic.com/blog/2024/10/integrate-your-custom-copilot-into-your-canvas-app-in-power-apps/) - In a few simple steps, you can implement your custom Copilot across every screen of your Canvas App ...

4. [Add a custom Copilot to a canvas app (preview)](https://learn.microsoft.com/en-us/power-apps/maker/canvas-apps/add-custom-copilot) - This feature lets you add a custom Copilot created in Microsoft Copilot Studio to a canvas app. It d...

5. [Return a list of results - Microsoft Copilot Studio](https://learn.microsoft.com/en-us/microsoft-copilot-studio/advanced-flow-list-of-results) - This example uses the Dataverse connector in Power Automate to search for accounts. The connector re...

6. [Use Agent to Update Dataverse Table Content - ISE Developer Blog](https://devblogs.microsoft.com/ise/use-agent-to-update-dataverse-table/) - This article explores how to build an agent in Microsoft Copilot Studio to update information in a D...

7. [Mission 04: Add Event Triggers to act autonomously](https://microsoft.github.io/agent-academy/operative/04-automate-triggers/) - By default, the When a new email arrives trigger in Power Automate may process multiple emails toget...

8. [Autonomous Agents with Microsoft Copilot Studio](https://adoption.microsoft.com/files/copilot-studio/Autonomous-agents-with-Microsoft-Copilot-Studio.pdf) - Send an email notification with the report attached. Your agent can then trigger this flow whenever ...

9. [Using 'Code Interpreter' to Process Excel Files in Copilot Studio ...](https://rajeevpentyala.com/2025/11/18/using-code-interpreter-to-process-excel-files-in-copilot-studio-agents/) - Create an 'Agent Flow' to parse JSON and create Dataverse records: In the Topic after the Prompt act...

10. [How to make Copilot output consistent with JSON schema - LinkedIn](https://www.linkedin.com/posts/danielando_do-your-copilot-agents-give-you-different-activity-7348345600926498817-SViH) - Define your output structure upfront using JSON schema. Tell your Copilot agent exactly how you want...

11. [How do I get my agent to respond in a structured format like JSON?](https://techcommunity.microsoft.com/blog/azuredevcommunityblog/how-do-i-get-my-agent-to-respond-in-a-structured-format-like-json/4433108) - You can provide a JSON schema alongside your prompt, and the agent will automatically aim to match t...

12. [JSON output - Microsoft Copilot Studio](https://learn.microsoft.com/en-us/microsoft-copilot-studio/process-responses-json-output) - The JSON output lets you generate a JSON structure for your prompt response instead of text. JSON ma...

13. [Work with variables - Microsoft Copilot Studio](https://learn.microsoft.com/en-us/microsoft-copilot-studio/authoring-variables) - Select Get Schema from Sample JSON, enter the desired JSON example in the editor that opens, and sel...

14. [Use agent flows with your agent - Microsoft Copilot Studio](https://learn.microsoft.com/en-us/microsoft-copilot-studio/advanced-flow) - Extend the capabilities of your agent with agent flows that you build in Copilot Studio using low-co...

15. [Extend your agent with Model Context Protocol - Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-copilot-studio/agent-extend-action-mcp) - Model Context Protocol (MCP) allows users to connect with existing knowledge servers and data source...

16. [SharePoint Server Microsoft 365 Copilot connector (preview)](https://learn.microsoft.com/en-us/microsoftsearch/sharepoint-server-connector) - One Graph Connector Agent can be used to source content from multiple connections of SharePoint On-p...

17. [Lab E7 - Add Copilot Connector - Microsoft Open Source](https://microsoft.github.io/copilot-camp/pages/extend-m365-copilot/07-add-graphconnector/) - In this lab you will learn to: deploy a Microsoft Copilot Connector of your own data into Microsoft ...

18. [Building MCP Agents in Microsoft Copilot Studio | atal upadhyay](https://atalupadhyay.wordpress.com/2025/08/05/building-mcp-agents-in-microsoft-copilot-studio/) - MCP standardizes AI-to-service connections; Uses client-server architecture; Provides pre-built tool...

19. [Copilot Studio Multi‑Agent Orchestration - Holger Imbery](https://holgerimbery.blog/multi-agent-orchestration) - Explore how Microsoft Copilot Studio's multi-agent orchestration enables specialized agents to colla...

20. [Power Platform – Pass json collection from Canvas App to ...](https://rajeevpentyala.com/2020/02/09/power-platform-pass-json-collection-from-canvas-app-to-power-automate-flow/) - Open the Canvas app created in above sections. · Add a new button 'Share Collection To Flow' · Selec...

21. [Orchestrate the copilot to send email after receiving a new ...](https://learn.microsoft.com/en-sg/answers/questions/5597610/orchestrate-the-copilot-to-send-email-after-receiv) - After the trigger “When a new email arrives (V3)” runs, you need to pass the agent's response as dyn...

22. [Agent Flows in Copilot Studio | Complete Tutorial - YouTube](https://www.youtube.com/watch?v=bCQGte09-Ko) - ... Agent flows Vs Power Automate cloud flows 19:14 - Agents + Agent flows = Better together 22:10 -...

