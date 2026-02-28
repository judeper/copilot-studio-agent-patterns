# Gaps Agent -- Platform Architecture Findings

## Summary

**23 gaps found: 6 deploy-blocking, 11 non-blocking, 6 known constraints**

This report identifies what is MISSING, what is ASSUMED but not documented, and what PLATFORM LIMITATIONS contradict the design. Each gap is classified by severity: deploy-blocking (must be filled before deployment), non-blocking (should be filled but deployment can proceed), or known constraint (platform limitation with no workaround).

## Methodology

Analyzed all platform-layer files for:
- Tables, columns, views, or indexes referenced but not defined
- Flows referenced in docs/prompts but not specified in agent-flows.md
- Copilot Studio configurations described conceptually but lacking step-by-step instructions
- Assumptions that require specific licenses, admin roles, or connector permissions
- Platform limitations that conflict with the design's assumptions
- Missing error handling, retry logic, or fallback behavior

## Findings

### Deploy-Blocking Gaps

**GAP-01: Daily Briefing flow specification is missing**
- **Category:** Missing Flow Definition
- **Artifact:** Referenced in `docs/deployment-guide.md` (Sprint 2), `prompts/daily-briefing-agent-prompt.md`, `schemas/briefing-output-schema.json`
- **Issue:** The Daily Briefing Agent prompt describes a rich input contract (`BRIEFING_INPUT` containing open_cards, stale_cards, today_calendar, sender_profiles). The briefing output schema is fully specified. But no flow build guide exists to tell a developer how to:
  1. Query Dataverse for open cards (filter: cr_cardoutcome eq 100000000, top 50, ordered by createdon desc)
  2. Filter stale cards from the result set (>24h pending, non-null priority)
  3. Query the user's calendar via the Outlook connector (Get events V4)
  4. Query sender profiles for all senders appearing in the open cards
  5. Compose the BRIEFING_INPUT JSON object
  6. Invoke the Daily Briefing Agent via "Execute Agent and wait"
  7. Parse the briefing output JSON
  8. Write the briefing card to Dataverse with trigger_type = DAILY_BRIEFING
- **Evidence:** agent-flows.md covers Flows 1-5 only. The daily briefing prompt (lines 17-23) describes the input contract but the flow that assembles it does not exist.
- **Suggested Fix:** Add "Flow 6 -- Daily Briefing" to agent-flows.md with complete step-by-step build instructions.

**GAP-02: Command Execution flow specification is missing**
- **Category:** Missing Flow Definition
- **Artifact:** Referenced in `docs/canvas-app-setup.md` (Sprint 3), `docs/deployment-guide.md` (Sprint 3), `prompts/orchestrator-agent-prompt.md`
- **Issue:** The Canvas App setup guide references `CommandExecutionFlow.Run(command, userEntraObjectId, currentCardId)`. The Orchestrator Agent prompt describes 6 tool actions (QueryCards, QuerySenderProfile, UpdateCard, CreateCard, RefineDraft, QueryCalendar). But no flow specification exists describing:
  1. The instant trigger (Canvas app trigger) with input parameters
  2. How to optionally retrieve the current card context
  3. How to retrieve the most recent briefing (for context)
  4. How to invoke the Orchestrator Agent
  5. How to parse the response (response_text, card_links, side_effects)
  6. How to return the response to the Canvas app
  7. The 120-second timeout handling
- **Evidence:** canvas-app-setup.md Sprint 3 notes reference the flow. orchestrator-agent-prompt.md describes the agent's capabilities.
- **Suggested Fix:** Add "Flow 7 -- Command Execution" to agent-flows.md.

**GAP-03: Staleness Monitor flow specification is missing**
- **Category:** Missing Flow Definition
- **Artifact:** Referenced in `docs/deployment-guide.md` (Sprint 2 verification)
- **Issue:** The Sprint 2 verification checklist references: "Staleness Monitor creates nudge cards for High-priority items >24h PENDING", "No duplicate nudge cards created for the same source", and "Cards expire to EXPIRED after 7 days PENDING." No flow specification exists for this background process.
- **Required specification:**
  1. Recurrence trigger (suggested: every 6 hours during business hours)
  2. Query cards: cr_cardoutcome eq 100000000 (PENDING) and createdon < 24h ago and cr_priority in (High, Medium)
  3. Duplicate check: for each stale card, query for existing NUDGE card with matching cr_sourcesignalid
  4. Create NUDGE card if no duplicate found
  5. Expiration: query cards with cr_cardoutcome eq 100000000 and createdon < 7 days ago, update cr_cardoutcome to EXPIRED
- **Suggested Fix:** Add "Flow 8 -- Staleness Monitor" to agent-flows.md.

**GAP-04: Sender Profile Analyzer flow specification is missing**
- **Category:** Missing Flow Definition
- **Artifact:** Referenced in `docs/deployment-guide.md` (Sprint 4 verification)
- **Issue:** Sprint 4 verification references: "Sender Profile Analyzer flow runs weekly and categorizes senders correctly." The categorization thresholds are documented in the deployment guide verification checklist but no flow specification exists.
- **Required specification:**
  1. Weekly recurrence trigger
  2. List all sender profiles with cr_signalcount >= 3
  3. For each: compute response_rate = cr_responsecount / cr_signalcount
  4. Classify: AUTO_HIGH if response_rate >= 0.8 AND cr_avgresponsehours < 8; AUTO_LOW if response_rate < 0.4 OR cr_dismissrate >= 0.6; else AUTO_MEDIUM
  5. Skip profiles with cr_sendercategory = USER_OVERRIDE
  6. Update cr_sendercategory if classification changed
- **Suggested Fix:** Add "Flow 9 -- Sender Profile Analyzer" to agent-flows.md.

**GAP-05: Orchestrator Agent tool actions are not documented as Copilot Studio action registrations**
- **Category:** Missing Copilot Studio Configuration
- **Artifact:** `prompts/orchestrator-agent-prompt.md` (lines 38-104)
- **Issue:** The Orchestrator Agent describes 6 tool actions (QueryCards, QuerySenderProfile, UpdateCard, CreateCard, RefineDraft, QueryCalendar). For Copilot Studio to make these available to the agent, they must be registered as Actions. The deployment guide (Phase 2, Step 2.4) documents research tool actions for the Main Agent but does not document the Orchestrator's tool action registration.
- **Required details:**
  - Are these implemented as Power Automate flows (instant triggers) invoked via Copilot Studio flow actions?
  - Are they Dataverse connector actions registered directly in Copilot Studio?
  - Are they custom connectors or plugins?
  - What are the exact parameter schemas for each action?
- **Evidence:** deployment-guide.md Sprint 3 verification says "Orchestrator Agent published in Copilot Studio with 6 tool actions registered" but no registration steps are documented.
- **Suggested Fix:** Add a "Phase 2.6 -- Orchestrator Agent Setup" section to the deployment guide with step-by-step action registration for all 6 tool actions.

**GAP-06: No `Publish All Customizations` step in provisioning script after creating tables and columns**
- **Category:** Missing Deployment Step
- **Artifact:** `scripts/provision-environment.ps1`
- **Issue:** The provisioning script creates entities and columns via the Dataverse Web API but never publishes the customizations. Dataverse requires customizations to be published before they are available to other tools (Canvas Apps, Power Automate flows, model-driven apps). Without publishing, the tables and columns will exist in metadata but may not be accessible in the flow designer's dynamic content picker or the Canvas App's data source browser.
- **Evidence:** The script ends after creating columns. No `POST /api/data/v9.2/PublishAllXml` call or `pac solution publish` command.
- **Suggested Fix:** Add a `PublishAllXml` API call at the end of the script: `Invoke-RestMethod -Uri "$apiBase/PublishAllXml" -Method Post -Headers $headers -Body '{"ParameterXml": "<importexportxml><entities><entity>cr_assistantcard</entity><entity>cr_senderprofile</entity></entities></importexportxml>"}'`

### Non-Blocking Gaps

**GAP-07: No Dataverse table for storing Daily Briefing schedules**
- **Category:** Missing Dataverse Definition
- **Issue:** PROJECT.md (tech debt #13) notes: "Daily briefing schedule stored in component state (lost on refresh)." The current design stores the briefing schedule (time, days) in React component state, which resets when the Canvas App refreshes. No Dataverse table exists to persist briefing schedule preferences.
- **Impact:** Users lose their schedule configuration on every app refresh. The scheduled flow itself runs on a fixed recurrence (weekday 7 AM per the prompt's design), but the user's DISPLAY preference for the schedule is ephemeral.
- **Suggested Fix:** Either: (1) add a `cr_userpreferences` Dataverse table with a JSON column for storing per-user preferences, or (2) accept that the briefing schedule is fixed (weekday 7 AM) and remove the configurable schedule UI.

**GAP-08: No email send flow specification for TEAMS_MESSAGE drafts**
- **Category:** Missing Flow Definition
- **Issue:** The Send Email flow (Flow 4) sends emails for EMAIL-type cards. But the main agent also produces humanized drafts for TEAMS_MESSAGE FULL-tier items. There is no flow to send a Teams message reply on behalf of the user.
- **Impact:** Users can view and copy TEAMS_MESSAGE drafts but cannot send them directly from the dashboard (unlike email drafts). The canvas-app-setup.md notes "Send button hidden for TEAMS_MESSAGE cards" (Sprint 1A testing T4), confirming this is by design for now.
- **Suggested Fix:** Document this as an intentional limitation. Consider adding a "Flow 10 -- Send Teams Message" in a future iteration.

**GAP-09: No flow specification for updating sender profiles with Sprint 4 columns (edit distance, dismiss count)**
- **Category:** Missing Flow Definition
- **Issue:** The Card Outcome Tracker (Flow 5) updates response count and average response hours but does not update Sprint 4 columns: cr_dismisscount (increment on DISMISSED), cr_avgeditdistance (compute on SENT_EDITED). The deployment guide Sprint 4 verification references these updates but no flow spec covers them.
- **Evidence:** senderprofile-table.json defines cr_dismisscount ("Updated by the Card Outcome Tracker flow") and cr_avgeditdistance ("Updated by the Sender Profile Analyzer"). But neither flow spec includes these operations.
- **Suggested Fix:** Add Sprint 4 addendum to Flow 5 (Card Outcome Tracker): add a DISMISSED branch that increments cr_dismisscount. Add edit distance computation on SENT_EDITED outcomes (compare final text length vs. humanized draft length as a proxy for edit distance).

**GAP-10: Copilot Studio knowledge source configurations are not documented**
- **Category:** Missing Copilot Studio Configuration
- **Issue:** The main agent prompt's research hierarchy references SharePoint search, Teams messages search, Planner tasks, and other data sources. The deployment guide (Step 2.4) lists research tool actions with connectors and operations. However, the following is not documented:
  - Which SharePoint sites to connect (deployment guide says "Search SharePoint" but not which sites)
  - What Microsoft Graph API permissions/scopes are needed (beyond what the connector provides)
  - Whether the Microsoft Search API requires specific admin configuration
  - How to configure the Bing Search connector (requires a Bing Search resource in Azure)
- **Impact:** A developer would know WHAT tools to register but not HOW to configure the underlying data sources.
- **Suggested Fix:** Add a "Knowledge Source Configuration" section to the deployment guide specifying SharePoint site URLs (or how to select them), Graph API permissions, and Bing Search resource setup.

**GAP-11: SENDER_PROFILE variable not passed to agent in flow specifications**
- **Category:** Missing Flow Update
- **Issue:** The main agent prompt defines `{{SENDER_PROFILE}}` as a runtime input (Sprint 4). The flow specifications in agent-flows.md (Flows 1-3) pass TRIGGER_TYPE, PAYLOAD, USER_CONTEXT, and CURRENT_DATETIME to the agent. They do not pass SENDER_PROFILE. The Sprint 1B sender upsert step queries/creates sender profiles, but the profile data is not packaged and sent to the agent.
- **Evidence:** agent-flows.md Flow 1 step 4 passes 4 variables. main-agent-system-prompt.md defines 5 runtime inputs including SENDER_PROFILE.
- **Suggested Fix:** Add a Sprint 4 addendum to Flows 1-3: after the sender upsert step, if the profile exists, compose a SENDER_PROFILE JSON object from the profile columns and pass it as a 5th input variable to the agent.

**GAP-12: Dataverse indexes and views are not defined**
- **Category:** Missing Dataverse Definition
- **Issue:** Neither dataverse-table.json nor the provisioning script define any indexes or Dataverse views. The following queries would benefit from indexes:
  - Filter by cr_cardoutcome (used by Canvas App, briefing flow, staleness monitor)
  - Filter by cr_originalsenderemail + ownerid (used by Card Outcome Tracker)
  - Filter by cr_conversationclusterid (used by briefing agent for thread grouping)
  - Filter by cr_senderemail + ownerid on SenderProfile table (used by all sender upserts)
- **Impact:** Non-blocking for small-scale usage. Performance will degrade as data volume grows. Dataverse does automatically index primary key columns.
- **Suggested Fix:** Add system views and index recommendations to the table definitions or provisioning script. Note: Dataverse automatically indexes alternate keys, so creating the cr_senderemail alternate key (GAP-06 / COR-17) would address that index need.

**GAP-13: What happens if the Copilot Studio agent times out?**
- **Category:** Undocumented Assumption
- **Issue:** The "Execute Agent and wait" action has a timeout (default varies). If the agent takes too long (complex research across 5 tiers), the action may time out. The error handling pattern in agent-flows.md wraps the invocation in a Scope with failure handling, but the timeout behavior is not documented: Does the action retry? Does it return a partial response? What status does the flow receive?
- **Impact:** Non-blocking if agent responses are typically fast. Could cause silent failures for complex FULL-tier items with extensive research.
- **Suggested Fix:** Document the expected agent response time (e.g., <30 seconds for SKIP/LIGHT, <120 seconds for FULL with 5-tier research). Add a timeout configuration recommendation for the "Execute Agent and wait" action.

**GAP-14: API rate limits for Copilot Studio connector not documented**
- **Category:** Undocumented Assumption
- **Issue:** The Copilot Studio connector's "Execute Agent and wait" action is subject to Power Platform API rate limits. The CALENDAR_SCAN flow invokes the agent inside a loop (Apply to each) with a 5-second delay between iterations. For a 14-day calendar scan with 30-50 events, this means 30-50 sequential agent invocations. The Copilot Studio connector has usage limits per tenant/environment.
- **Evidence:** agent-flows.md Flow 3 step 4e adds a 5-second delay. Performance note mentions 3-5 minutes total.
- **Suggested Fix:** Document the Copilot Studio API rate limits and calculate whether 50 invocations in 5 minutes is within limits. Reference: Microsoft Copilot Studio usage limits documentation.

**GAP-15: Assumed data volume is not documented**
- **Category:** Undocumented Assumption
- **Issue:** No document states the expected data volume: cards per user per day, sender profiles per user, maximum concurrent users. Design decisions (500-row delegation limit, staleness monitor expiration, 50-card briefing input limit) imply assumptions about volume that should be explicit.
- **Suggested Fix:** Add a "Capacity Planning" section to the deployment guide with assumptions: estimated 20-50 cards/user/day for active email users, 100-300 sender profiles per user, 7-day expiration keeping active rows under 350, and the 500-row delegation limit as the design ceiling.

**GAP-16: License requirements not fully documented**
- **Category:** Undocumented Assumption
- **Issue:** The deployment guide lists tools (PAC CLI, Azure CLI, Bun) but does not enumerate required Power Platform licenses:
  - **Copilot Studio**: Required for agent creation and the "Execute Agent and wait" connector action
  - **Power Automate Premium** (or per-flow plan): Required for the Copilot Studio connector, which is a premium connector
  - **Dataverse capacity**: Required for table storage
  - **Microsoft 365 licenses**: Required for the Office 365 Outlook, Teams, and Users connectors
  - **Bing Search API**: Requires an Azure Cognitive Services or Bing Search resource (paid)
- **Suggested Fix:** Add a "License Requirements" section to the deployment guide.

**GAP-17: Admin role requirements not documented per deployment step**
- **Category:** Undocumented Assumption
- **Issue:** Different deployment steps require different admin roles:
  - `pac admin create` (environment creation): Power Platform Admin or Global Admin
  - `pac solution import`: Environment Maker or System Customizer in the target environment
  - `create-security-roles.ps1`: Security Role Administrator or System Administrator
  - Copilot Studio agent creation: Copilot Studio Maker or Environment Maker
  - DLP policy changes: Power Platform Admin
- **Suggested Fix:** Add a "Required Roles" column to each deployment phase in the deployment guide.

### Known Constraints

**GAP-18: Power Automate Parse JSON does not support oneOf/anyOf**
- **Category:** Platform Limitation
- **Workaround:** Already implemented. The simplified schema in agent-flows.md uses `{}` (empty schema) for polymorphic fields (`draft_payload`, `verified_sources`). This accepts any value without validation.
- **Accepted Risk:** The flow cannot validate the structure of draft_payload at the Parse JSON step. Malformed draft_payload objects would pass through and cause errors in downstream steps (humanizer invocation, Dataverse write).

**GAP-19: Canvas App delegation limits for Dataverse queries**
- **Category:** Platform Limitation
- **Workaround:** Documented in canvas-app-setup.md. The staleness monitor expires old cards (7 days) to keep active card counts manageable. The delegation limit can be increased from 500 to 2000 in app settings.
- **Accepted Risk:** Users with >500 (or >2000) active, non-expired cards would see incomplete data in the Canvas App. This is unlikely given the 7-day expiration policy.

**GAP-20: Copilot Studio system prompt length limits**
- **Category:** Platform Limitation
- **Workaround:** Not yet implemented. The main agent prompt is at the high end of the character limit range. If truncated, few-shot examples would be lost first (they're at the bottom of the prompt).
- **Accepted Risk:** Loss of few-shot examples may degrade output format consistency. The output schema section (before the examples) would still be preserved.
- **Suggested Mitigation:** Measure exact character count. If over limit, move examples to a Knowledge Source document.

**GAP-21: PCF virtual controls in Canvas Apps have limited event support**
- **Category:** Platform Limitation
- **Description:** PCF virtual controls communicate with Canvas Apps via input/output properties. There is no direct event callback mechanism (like DOM events). The Canvas App detects changes via the `OnChange` event on the control, which fires when any output property changes.
- **Accepted Risk:** The current design uses output properties (`sendDraftAction`, `dismissCardAction`, `commandAction`, `jumpToCardAction`, `copyDraftAction`) as event surrogates. This is the standard pattern for PCF-Canvas communication and works reliably.

**GAP-22: Power Automate `ticks()` function returns Int64 which may overflow in `div()` for large time differences**
- **Category:** Platform Limitation
- **Description:** The Card Outcome Tracker flow's response time calculation uses `ticks()` to compute the difference between outcome timestamp and card creation time. For time differences greater than approximately 292 years, the Int64 tick value would overflow. This is a theoretical concern -- not a practical risk since response times will always be hours to days.
- **Accepted Risk:** No practical impact. The calculation is safe for any realistic response time.

**GAP-23: Copilot Studio connector response size limit**
- **Category:** Platform Limitation
- **Description:** The "Execute Agent and wait" action has a response size limit (typically 100KB for text output). The main agent's output includes the full JSON object with research logs, key findings, verified sources, and draft payload. For complex FULL-tier items with extensive research and long drafts, the response could approach this limit.
- **Accepted Risk:** Unlikely to be hit in practice. The agent prompt constrains output verbosity (item_summary max 300 chars, research_log is a concise log, key_findings is a bulleted list). The largest component is draft_payload, which is bounded by reasonable email/message length.
- **Suggested Mitigation:** Monitor flow run output sizes during testing. If approaching limits, truncate research_log or verified_sources.

### Validated (No Issues)

1. **Tables referenced in flows exist in table definitions**: cr_assistantcard and cr_senderprofile are both defined with complete column sets.
2. **All Dataverse columns referenced in flows exist in table definitions**: Every column written by Flows 1-5 has a corresponding definition in dataverse-table.json or senderprofile-table.json.
3. **All trigger types in prompts match Dataverse Choice options**: EMAIL, TEAMS_MESSAGE, CALENDAR_SCAN, DAILY_BRIEFING, SELF_REMINDER, COMMAND_RESULT all exist in both the prompt and the Dataverse table.
4. **Agent prompt output format matches schema fields**: The OUTPUT SCHEMA section in the main agent prompt lists all 12 fields that exist in output-schema.json.
5. **Briefing agent output format matches briefing schema**: The briefing prompt's output structure matches briefing-output-schema.json fields.
6. **Humanizer agent input contract matches main agent's draft_payload**: The humanizer prompt's INPUT CONTRACT matches the draft_payload object structure in output-schema.json.
7. **Canvas App setup uses correct Dataverse display names**: The Canvas App formulas reference 'Assistant Cards' (display name) which maps to the cr_assistantcard entity.
