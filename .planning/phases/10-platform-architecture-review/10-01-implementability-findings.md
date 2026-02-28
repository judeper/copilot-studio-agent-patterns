# Implementability Agent -- Platform Architecture Findings

## Summary

**14 issues found: 5 deploy-blocking, 9 non-blocking**

This report evaluates whether every specification in the platform-layer artifacts can be physically built and deployed on a real Power Platform environment using current tooling and connectors. The focus is "can this actually be built?" rather than "is the syntax correct?"

## Methodology

Traced the implementation path for every artifact from specification to deployment:
- Walked through each API call in provisioning scripts step by step
- Verified connector action input/output schemas against real connector capabilities
- Evaluated Copilot Studio agent configuration against current UI and limits
- Traced the end-to-end deployment sequence for gaps and missing steps
- Assessed Canvas App control compatibility with Dataverse column types

## Findings

### Deploy-Blocking Issues

**IMP-01: provision-environment.ps1 creates table with only the primary name column in the initial EntityDefinitions POST, then adds columns individually -- but the entity creation itself may fail without proper publisher configuration**
- **Artifact:** `scripts/provision-environment.ps1` (lines 126-189)
- **Issue:** The script creates the entity definition via `POST /api/data/v9.2/EntityDefinitions` with the primary name attribute embedded in the Attributes array. This approach works for the initial entity creation. However, the script uses `SchemaName = "${PublisherPrefix}_assistantcard"` where `$PublisherPrefix` defaults to "cr". In Dataverse, the publisher prefix must match an existing publisher registered in the environment. A fresh environment created by `pac admin create` does NOT have a publisher with prefix "cr" -- the default publisher has prefix "cr" only if you specifically create one.
- **Impact:** If the environment's default publisher has a different prefix (e.g., "new_"), the table creation will fail because the schema name prefix doesn't match any registered publisher. The `pac admin create` command creates a Dataverse database with the CDS Default Publisher (prefix "cr" historically, but Microsoft changed the default to "new_" in some regions).
- **Evidence:** provision-environment.ps1 line 44: `[string]$PublisherPrefix = "cr"`. Line 128: `SchemaName = "${PublisherPrefix}_assistantcard"`. No publisher creation step exists in the script.
- **Suggested Fix:** Add a publisher creation step before the entity creation: create a custom publisher with the "cr" prefix via the Web API, or validate that a publisher with the specified prefix exists before proceeding.

**IMP-02: The "Execute Agent and wait" action requires the agent to be published AND available in the same environment as the flow -- but the agent and flow creation are not linked**
- **Artifact:** `docs/agent-flows.md` (step 4) and `docs/deployment-guide.md` (Phase 2-3)
- **Issue:** The deployment guide creates the Copilot Studio agent in Phase 2 and the Power Automate flows in Phase 3. The "Execute Agent and wait" action in the Microsoft Copilot Studio connector requires selecting a published agent from a dropdown. If the agent is not published, it won't appear. If the agent is in a different environment than the flow, it won't appear. The deployment guide does mention "Publish the Agent" (Step 2.5), but there is no explicit step verifying the agent appears in the flow designer's connector dropdown before proceeding to flow creation.
- **Impact:** Users may create the agent, publish it, but then not find it in the flow designer if there is an environment mismatch or propagation delay.
- **Suggested Fix:** Add a verification step between Phase 2 and Phase 3: "Before creating flows, verify the agent appears in the Microsoft Copilot Studio connector by adding a temporary 'Execute Agent and wait' action in a new test flow."

**IMP-03: Copilot Studio system prompt length may exceed limits for the main agent prompt**
- **Artifact:** `prompts/main-agent-system-prompt.md`
- **Issue:** The main agent system prompt is approximately 12,000 characters including all sections (identity, triage, research, confidence, output schema, few-shot examples, Sprint 4 additions). Copilot Studio has a system message character limit that varies by configuration but historically has been around 10,000-16,000 characters for the system prompt in Generative Orchestration mode. The prompt is at the high end of this range. With the Sprint 4 sender-adaptive triage and confidence adjustments adding approximately 2,000 characters, the total may approach or exceed the limit depending on the Copilot Studio version.
- **Impact:** If the prompt exceeds the character limit, Copilot Studio will truncate it silently or reject the save. The few-shot examples at the end of the prompt would be the first content lost.
- **Evidence:** The main-agent-system-prompt.md file is approximately 356 lines with significant content density.
- **Suggested Fix:** Measure the exact character count. If near the limit, move the few-shot examples to a Knowledge Source (Copilot Studio supports file-based knowledge). Alternatively, move Sprint 4 additions to a separate knowledge source document.

**IMP-04: Daily Briefing flow is not fully specified in agent-flows.md**
- **Artifact:** `docs/agent-flows.md` -- missing Flow specification
- **Issue:** The agent-flows.md document specifies 5 flows: EMAIL (Flow 1), TEAMS_MESSAGE (Flow 2), CALENDAR_SCAN (Flow 3), Send Email (Flow 4), and Card Outcome Tracker (Flow 5). The Daily Briefing flow is referenced in the deployment guide (Sprint 2 verification), the daily-briefing-agent-prompt.md, and the briefing-output-schema.json, but its step-by-step build specification is NOT in agent-flows.md. The deployment guide says flows follow agent-flows.md, but the briefing flow spec is missing.
- **Impact:** A developer following the build guide would not know how to build the Daily Briefing flow: what input data to assemble (open_cards, stale_cards, today_calendar, sender_profiles), how to query Dataverse for these, how to serialize them into the BRIEFING_INPUT variable, and how to write the briefing card to Dataverse.
- **Evidence:** agent-flows.md covers Flows 1-5 only. daily-briefing-agent-prompt.md describes the input contract (BRIEFING_INPUT JSON with open_cards, stale_cards, today_calendar, sender_profiles) but not the flow that assembles it.
- **Suggested Fix:** Add a "Flow 6 -- Daily Briefing" section to agent-flows.md specifying: (1) Recurrence trigger (weekdays 7 AM), (2) Query open cards from Dataverse, (3) Filter stale cards (>24h pending, non-null priority), (4) Get today's calendar events, (5) Query sender profiles for senders in open cards, (6) Compose BRIEFING_INPUT JSON, (7) Invoke Daily Briefing Agent, (8) Parse JSON briefing output, (9) Write briefing card to Dataverse with trigger_type = DAILY_BRIEFING.

**IMP-05: Command Execution flow is not specified in agent-flows.md**
- **Artifact:** `docs/agent-flows.md` -- missing Flow specification
- **Issue:** The Command Execution flow (referenced in canvas-app-setup.md Sprint 3 notes and deployment guide Sprint 3 verification) is not specified in agent-flows.md. The canvas-app-setup.md mentions `CommandExecutionFlow.Run(command, userEntraObjectId, currentCardId)` and a 120-second timeout, but the full flow specification (trigger type, input handling, Orchestrator Agent invocation, tool action routing, response formatting) is not documented.
- **Impact:** A developer would not know how to build this flow. The Orchestrator Agent prompt describes 6 tool actions (QueryCards, QuerySenderProfile, UpdateCard, CreateCard, RefineDraft, QueryCalendar), but how these are registered as Copilot Studio actions and how the flow passes parameters is not specified.
- **Evidence:** canvas-app-setup.md Sprint 3 notes reference "Command Execution Flow." Orchestrator prompt describes tool actions. No flow spec exists.
- **Suggested Fix:** Add a "Flow 7 -- Command Execution" section to agent-flows.md specifying: (1) Instant trigger from Canvas app with command, userId, currentCardId inputs, (2) Optionally get current card if currentCardId is non-null, (3) Get recent briefing if available, (4) Invoke Orchestrator Agent with composed inputs, (5) Parse response JSON, (6) Return response to Canvas app.

### Non-Blocking Issues

**IMP-06: SenderProfile alternate key creation requires table to be published first**
- **Artifact:** `schemas/senderprofile-table.json` (lines 8-14) vs. `scripts/provision-environment.ps1`
- **Issue:** Even if the provisioning script were updated to create the alternate key (per COR-17), alternate keys on Dataverse tables can only be created AFTER the table and its columns are published (customizations published). The provisioning script does not include a "publish customizations" step between creating columns and creating the key.
- **Impact:** The key creation API call would fail silently or return an error.
- **Suggested Fix:** Add `pac solution publish` or a Web API publish request after column creation and before alternate key creation.

**IMP-07: Flow-based upsert for sender profiles is not atomic -- race conditions possible**
- **Artifact:** `docs/agent-flows.md` (Flow 1, step 11)
- **Issue:** The sender profile upsert uses a List-Condition-Add/Update pattern. If two emails from the same sender arrive simultaneously, both flows could List (finding 0 rows), then both Add (creating duplicates). The alternate key (COR-17) would prevent this IF it were created, but currently neither the key nor a native upsert is used.
- **Impact:** Duplicate sender profile rows for the same sender/user combination. Not deploy-blocking because the flows will still function, but data integrity is degraded.
- **Suggested Fix:** After creating the alternate key, use the Dataverse "Upsert a row" action (available in the Dataverse connector) with the alternate key as the lookup criteria. This provides atomic upsert semantics.

**IMP-08: Canvas App delegation warning for Choice column filters**
- **Artifact:** `docs/canvas-app-setup.md` (line 109)
- **Issue:** The document correctly notes that Choice column comparisons (e.g., `'Card Outcome' <> 'Card Outcome'.DISMISSED`) are not delegable to Dataverse. This means the filter runs client-side on only the first 500 rows (default) or 2000 rows (if increased in app settings). The doc mentions the staleness monitor keeps counts manageable.
- **Impact:** Non-blocking for most users. Could become an issue for power users with high email volume who accumulate >500 active cards.
- **Suggested Fix:** Document how to increase the delegation limit to 2000 in Canvas App advanced settings. Consider adding a Dataverse View that pre-filters dismissed/expired cards server-side.

**IMP-09: Canvas App OnChange handler uses multiple If() blocks instead of Switch() -- functional but fragile**
- **Artifact:** `docs/canvas-app-setup.md` (lines 127-182)
- **Issue:** The OnChange handler uses sequential `If(!IsBlank(...))` checks for each output property. If two output properties change simultaneously (edge case), only the first matching block executes because Power Apps processes the OnChange handler once per change event. This is unlikely in practice since the PCF control changes one output property at a time.
- **Impact:** Functional in current design. Could become an issue if the PCF changes multiple outputs in a single event cycle.
- **Suggested Fix:** Document the assumption that the PCF control changes one output property per event. No code change needed.

**IMP-10: deploy-solution.ps1 uses `dotnet build` for solution packing but does not verify the Solution.cdsproj SDK is installed**
- **Artifact:** `scripts/deploy-solution.ps1` (line 173)
- **Issue:** The script runs `dotnet build` in the Solutions directory, which requires the `Microsoft.PowerApps.MSBuild.Solution` NuGet package (referenced in Solution.cdsproj). The .NET SDK is validated but not the NuGet package availability. On first run, `dotnet build` will attempt to restore NuGet packages, which requires internet access and a NuGet source that includes the PowerApps MSBuild SDK.
- **Impact:** If NuGet restore fails (corporate proxy, air-gapped environment), the build will fail without a clear error about the missing SDK.
- **Suggested Fix:** Add a note about NuGet connectivity requirements, or add `dotnet restore` as an explicit step before `dotnet build` with error handling.

**IMP-11: PCF component deployed as Unmanaged solution -- appropriate for dev but not production**
- **Artifact:** `enterprise-work-assistant/src/Solutions/Solution.cdsproj` (line 3) and `docs/deployment-guide.md` (line 253)
- **Issue:** The Solution.cdsproj specifies `SolutionPackageType = Unmanaged`. The deployment guide mentions this is for development and suggests changing to Managed for production. An unmanaged solution in a production environment allows users to modify or delete components, which is a governance concern.
- **Impact:** Non-blocking for development/testing. Needs to be changed for production deployment.
- **Suggested Fix:** Add a deploy-solution.ps1 parameter `-Managed` that switches the SolutionPackageType before building, or document the manual change needed.

**IMP-12: Multiple Copilot Studio agents can coexist in one environment -- but inter-agent calls require Connected Agent configuration**
- **Artifact:** `docs/deployment-guide.md` (Phase 4) and `prompts/orchestrator-agent-prompt.md` (RefineDraft action)
- **Issue:** The deployment guide creates Main Agent, Humanizer Agent, Daily Briefing Agent, and Orchestrator Agent in the same Copilot Studio environment. This is supported. However, the Orchestrator Agent's `RefineDraft` tool action is described as passing drafts through the Humanizer Agent. This requires the Humanizer to be registered as a Connected Agent or as a Copilot Studio action available to the Orchestrator. The deployment guide does not document this inter-agent connection for the Orchestrator.
- **Impact:** The Orchestrator's RefineDraft capability would not work without configuring the Humanizer as a connected agent or action within the Orchestrator.
- **Suggested Fix:** Add a step in the deployment guide for configuring the Humanizer as a Connected Agent within the Orchestrator, or as a Copilot Studio action that the Orchestrator can invoke.

**IMP-13: Staleness Monitor flow is referenced but not specified**
- **Artifact:** `docs/deployment-guide.md` (Sprint 2 verification) references "Staleness Monitor" creating nudge cards
- **Issue:** The deployment guide Sprint 2 verification checklist mentions "Staleness Monitor creates nudge cards for High-priority items >24h PENDING" and "No duplicate nudge cards created for the same source." However, no flow specification exists for this in agent-flows.md. The Staleness Monitor likely runs as a scheduled flow that queries Dataverse for stale cards and creates NUDGE-status cards, but the implementation details are not documented.
- **Impact:** A developer cannot build the Staleness Monitor without a specification.
- **Suggested Fix:** Add a flow specification for the Staleness Monitor: (1) Recurrence trigger (e.g., every 6 hours), (2) Query cards with cr_cardoutcome = PENDING and createdon > 24h and cr_priority = High, (3) For each, check if a NUDGE card already exists with the same source signal, (4) If not, create a NUDGE card. Also specify the 7-day EXPIRED threshold logic.

**IMP-14: Sender Profile Analyzer flow is referenced but not specified**
- **Artifact:** `docs/deployment-guide.md` (Sprint 4 verification) references "Sender Profile Analyzer flow runs weekly"
- **Issue:** The Sprint 4 verification checklist references a "Sender Profile Analyzer" flow that runs weekly to categorize senders (AUTO_HIGH, AUTO_MEDIUM, AUTO_LOW). No flow specification exists. The categorization logic is described (response_rate >= 0.8 AND avg_response_hours < 8 = AUTO_HIGH, etc.) but the flow steps are not documented.
- **Impact:** A developer cannot build the Sender Profile Analyzer without a specification.
- **Suggested Fix:** Add a flow specification for the Sender Profile Analyzer: (1) Weekly recurrence trigger, (2) List all sender profiles with signal_count >= 3, (3) For each, compute category based on thresholds, (4) Skip USER_OVERRIDE senders, (5) Update category if changed.

### Validated (No Issues)

1. **AssistantCards table creation via Web API**: The provisioning script's API sequence (create entity, add attributes individually) is a valid approach for Dataverse table creation via the Web API.
2. **Column types are buildable**: All specified column types (Text/StringAttributeMetadata, Choice/PicklistAttributeMetadata, WholeNumber/IntegerAttributeMetadata, Memo/MemoAttributeMetadata, DateTime/DateTimeAttributeMetadata, Boolean/BooleanAttributeMetadata, Decimal/DecimalAttributeMetadata) are supported and correctly specified in the provisioning script.
3. **Canvas App Gallery/Form compatibility**: All Dataverse column types used are compatible with Canvas App controls -- Choice columns work with Dropdown, Text with TextInput, DateTime with DatePicker, etc.
4. **Parse JSON action handles simplified schema**: The simplified schema using `{}` for polymorphic fields and `["type", "null"]` for nullable fields is a proven pattern that works in Power Automate.
5. **Power Automate expression functions exist**: All expression functions referenced in flow specs are real and available in the current Power Automate environment.
6. **"Add a new row" action handles all column types**: The Dataverse connector's "Add a new row" action correctly handles Choice (integer), DateTime (ISO string), Memo (string), Text (string), WholeNumber (integer), and Boolean (boolean) inputs.
7. **Row ownership via Azure AD Object ID**: Setting the Owner field to `outputs('Get_my_profile_(V2)')?['body/id']` (which returns the AAD Object ID) is the correct approach for setting row ownership in Dataverse.
8. **PAC CLI pack/import sequence**: The `dotnet build` (which runs MSBuild solution packaging) followed by `pac solution import` is the standard PCF deployment pipeline.
9. **Security roles via Web API**: The create-security-roles.ps1 approach (create role, look up privileges, add via AddPrivilegesRole action) is a valid Dataverse Web API pattern.
10. **Copilot Studio JSON output mode**: Copilot Studio supports JSON output mode configuration through the Prompt Builder UI as described in the deployment guide.
11. **Research tool registration**: Copilot Studio supports registering connector-based actions (Office 365 Outlook, SharePoint, Microsoft Graph) as tool actions for agents.
12. **deploy-solution.ps1 end-to-end flow**: The prerequisite check, bun install, bun run build, dotnet build, pac solution import sequence is correct and will produce a deployable solution.
