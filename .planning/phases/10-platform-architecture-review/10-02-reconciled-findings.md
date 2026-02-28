# Reconciled Platform Architecture Findings

## Summary

**Total unique issues: 33 (9 BLOCK, 14 WARN, 6 INFO, 4 FALSE)**

- Issues from three independent agents: 56 raw findings (19 Correctness + 14 Implementability + 23 Gaps)
- After deduplication: 33 unique issues (23 issues were unique, 10 groups of duplicates merged)
- Agents agreed on severity for 26 issues, disagreed on 7 issues
- 4 findings reclassified as FALSE (not actual issues or already handled)

## Reconciliation Methodology

1. **Extract**: Every issue from all three reports was catalogued with source agent, artifact, severity, and description.
2. **Deduplicate**: Issues describing the same underlying problem were merged. When multiple agents flagged the same issue, the most detailed description was preserved and all source agents noted. Multi-agent agreement strengthens the signal.
3. **Resolve disagreements**: For each severity disagreement, the specific artifact was re-read, cross-referenced with other files, and a final ruling made based on: (a) whether the issue actually prevents deployment, (b) whether a workaround exists, and (c) the principle "when genuinely ambiguous, classify as BLOCK."
4. **Classify**: Each reconciled issue assigned exactly one category: BLOCK, WARN, INFO, or FALSE.
5. **Map**: Each issue tagged with affected PLAT requirement(s).

---

## BLOCK -- Deploy-Blocking Issues

These must be fixed in Phase 13 before deployment.

| ID | Requirement | Artifact | Issue | Flagged By | Remediation |
|----|-------------|----------|-------|------------|-------------|
| R-01 | PLAT-01, PLAT-03 | output-schema.json, main-agent-system-prompt.md | N/A vs null mismatch (priority + temporal_horizon) | Correctness | Align schema enum to include "N/A" or change prompt to use null |
| R-02 | PLAT-03 | main-agent-system-prompt.md | USER_VIP orphaned reference | Correctness | Change to USER_OVERRIDE |
| R-03 | PLAT-04 | create-security-roles.ps1 | Privilege name casing (lowercase vs PascalCase) | Correctness | Use PascalCase schema names |
| R-04 | PLAT-02, PLAT-03 | agent-flows.md, senderprofile-table.json | Card Outcome Tracker DISMISSED contradiction | Correctness, Gaps | Add DISMISSED branch to Flow 5 |
| R-05 | PLAT-02 | agent-flows.md | Daily Briefing flow spec missing | Implementability, Gaps | Write Flow 6 spec |
| R-06 | PLAT-02 | agent-flows.md | Command Execution flow spec missing | Implementability, Gaps | Write Flow 7 spec |
| R-07 | PLAT-02 | agent-flows.md | Staleness Monitor flow spec missing | Implementability, Gaps | Write Flow 8 spec |
| R-08 | PLAT-02 | agent-flows.md | Sender Profile Analyzer flow spec missing | Implementability, Gaps | Write Flow 9 spec |
| R-09 | PLAT-04 | provision-environment.ps1 | Missing publisher creation step | Implementability, Correctness | Add publisher validation/creation before entity creation |

### R-01: N/A vs null mismatch in priority and temporal_horizon fields

**Source issues:** COR-01, COR-02, COR-13, COR-14

**Problem:** The output-schema.json defines `priority` with `enum: ["High", "Medium", "Low", null]` and `temporal_horizon` with `enum: ["TODAY", "THIS_WEEK", "NEXT_WEEK", "BEYOND", null]`. Both use `null` as the not-applicable value. However, the main agent prompt instructs the agent to output the string `"N/A"` for SKIP items (line 98: `priority = "N/A"`, `temporal_horizon = "N/A"`). The prompt's OUTPUT SCHEMA section and all few-shot examples reinforce this pattern. The deployment guide's JSON example also uses `"N/A"` strings.

**Evidence verified:** The Dataverse table has "N/A" Choice options (value 100000003 for priority, 100000004 for temporal_horizon), and the flow's Compose expression maps `"N/A"` to these integer values. So the runtime bridge works. But the canonical schema -- the authoritative contract -- says null, creating a formal contract violation.

**Final ruling: BLOCK.** The canonical schema is the single source of truth for the agent's output contract. While the runtime works today, this mismatch means: (1) any automated JSON Schema validation would reject agent output, (2) any future consumer trusting the schema would break, and (3) the discrepancy between four artifacts (schema, prompt, flow, deployment guide) creates confusion. Fix: add `"N/A"` to both enum arrays in output-schema.json to match reality, or change the prompt and all examples to use null.

**Remediation:** Add `"N/A"` to both enum definitions in output-schema.json. Update the schema description to document when `"N/A"` vs `null` is used. This is a one-file fix with no downstream impact since the flow already maps "N/A" correctly.

---

### R-02: USER_VIP orphaned reference in agent prompt

**Source issues:** COR-03

**Problem:** The sender-adaptive triage section of the main agent prompt references `sender_category = "USER_VIP"`. This value does not exist in the senderprofile-table.json Choice options. The defined options are: AUTO_HIGH (100000000), AUTO_MEDIUM (100000001), AUTO_LOW (100000002), USER_OVERRIDE (100000003).

**Evidence verified:** Confirmed in senderprofile-table.json lines 68-73. USER_OVERRIDE is the correct value for user-set sender overrides. "USER_VIP" is a naming error in the prompt.

**Final ruling: BLOCK.** The agent would reference a category that never appears in actual data, causing the sender-adaptive triage logic to silently fail for USER_OVERRIDE senders.

**Remediation:** Change `"USER_VIP"` to `"USER_OVERRIDE"` in the main agent prompt. Single-line fix.

---

### R-03: Privilege name casing in security roles script

**Source issues:** COR-06

**Problem:** The create-security-roles.ps1 script constructs Dataverse privilege names from lowercase logical names (e.g., `prvCreatecr_assistantcard`). Dataverse privilege names use the schema name (PascalCase): `prvCreatecr_AssistantCard`.

**Evidence verified:** Dataverse Web API privilege lookup uses the schema name format. The script's `$filter=name eq '$privName'` query would return no results with lowercase names, causing the role configuration to fail silently (no privileges added to the security role).

**Final ruling: BLOCK.** Without correct privileges, the security role would be empty and users would have no access to the custom tables.

**Remediation:** Change entity name variables to use PascalCase schema names: `cr_AssistantCard` and `cr_SenderProfile`.

---

### R-04: Card Outcome Tracker does not handle DISMISSED outcomes despite Sprint 4 requiring it

**Source issues:** COR-07, GAP-09

**Problem:** Flow 5 (Card Outcome Tracker) explicitly excludes DISMISSED and EXPIRED outcomes. But senderprofile-table.json describes `cr_dismisscount` as "Updated by the Card Outcome Tracker flow" and the Sprint 4 verification checklist requires "Card Outcome Tracker increments cr_dismisscount on DISMISSED outcomes."

**Evidence verified:** agent-flows.md Flow 5 step 2 says "Only update sender profile for SENT_AS_IS or SENT_EDITED outcomes (not DISMISSED or EXPIRED)." This directly contradicts Sprint 4's dismiss count requirement. Additionally, GAP-09 notes that `cr_avgeditdistance` (for SENT_EDITED outcomes) is also not computed by the flow.

**Final ruling: BLOCK.** The Sprint 4 sender intelligence features depend on dismiss count and edit distance data. Without this data, the Sender Profile Analyzer (R-08) cannot compute dismiss_rate and the adaptive triage thresholds are incomplete.

**Remediation:** Add Sprint 4 addendum to Flow 5: (1) DISMISSED branch that increments cr_dismisscount, (2) edit distance computation on SENT_EDITED that updates cr_avgeditdistance. The existing SENT_AS_IS/SENT_EDITED branch handles response count and avg hours unchanged.

---

### R-05: Daily Briefing flow specification missing

**Source issues:** IMP-04, GAP-01

**Problem:** The Daily Briefing Agent has a fully specified prompt (daily-briefing-agent-prompt.md) and output schema (briefing-output-schema.json), but no flow build specification exists in agent-flows.md. A developer cannot build this flow without knowing how to: query open cards, filter stale cards, get calendar events, query sender profiles, compose the BRIEFING_INPUT JSON, invoke the agent, parse the response, and write the briefing card to Dataverse.

**Evidence verified:** agent-flows.md covers Flows 1-5 only. Both Implementability and Gaps agents flagged this identically. Both classified it as deploy-blocking. Agreed.

**Final ruling: BLOCK.** Without the flow spec, a core Sprint 2 feature (daily briefing) cannot be built.

**Remediation:** Add "Flow 6 -- Daily Briefing" to agent-flows.md with step-by-step build instructions covering: (1) Recurrence trigger (weekdays 7 AM), (2) Query open cards from Dataverse, (3) Filter stale cards, (4) Get today's calendar, (5) Query sender profiles, (6) Compose BRIEFING_INPUT, (7) Invoke agent, (8) Parse output, (9) Write briefing card.

---

### R-06: Command Execution flow specification missing

**Source issues:** IMP-05, GAP-02

**Problem:** The Canvas App calls `CommandExecutionFlow.Run()` and the Orchestrator Agent prompt describes 6 tool actions, but no flow build specification exists. A developer would not know how to wire the Canvas App trigger to the Orchestrator Agent or how to handle the 120-second timeout.

**Evidence verified:** Both agents flagged identically, both deploy-blocking. Agreed.

**Final ruling: BLOCK.** Sprint 3 command bar feature cannot be built without this spec.

**Remediation:** Add "Flow 7 -- Command Execution" to agent-flows.md.

---

### R-07: Staleness Monitor flow specification missing

**Source issues:** IMP-13, GAP-03

**Problem:** The Sprint 2 verification checklist references Staleness Monitor behavior (nudge cards, expiration) but no flow specification exists. The Implementability agent classified this as non-blocking; the Gaps agent classified it as deploy-blocking.

**Disagreement resolution:** The deployment guide's Sprint 2 verification explicitly requires: "Staleness Monitor creates nudge cards for High-priority items >24h PENDING" and "Cards expire to EXPIRED after 7 days PENDING." These are Sprint 2 acceptance criteria. Without the specification, a developer cannot build the flow and Sprint 2 verification would fail. The Implementability agent's "non-blocking" classification appears to have weighted the flow's background nature (it doesn't block other flows from running), but the issue is that it cannot be *built* at all without a spec.

**Final ruling: BLOCK.** The specification is required for Sprint 2 acceptance. Reclassifying from IMP-13's "non-blocking" to BLOCK.

**Remediation:** Add "Flow 8 -- Staleness Monitor" to agent-flows.md.

---

### R-08: Sender Profile Analyzer flow specification missing

**Source issues:** IMP-14, GAP-04

**Problem:** Sprint 4 verification requires "Sender Profile Analyzer flow runs weekly and categorizes senders correctly." No flow specification exists. Same disagreement pattern as R-07.

**Disagreement resolution:** Same reasoning as R-07. The categorization thresholds are documented in the deployment guide verification checklist but the flow that implements them is not specified. A developer cannot build what is not specified. Sprint 4 verification requires this flow.

**Final ruling: BLOCK.** Reclassifying from IMP-14's "non-blocking" to BLOCK.

**Remediation:** Add "Flow 9 -- Sender Profile Analyzer" to agent-flows.md.

---

### R-09: Missing publisher creation in provisioning script

**Source issues:** IMP-01, COR-04 (partial)

**Problem:** The provisioning script defaults `$PublisherPrefix` to "cr" and creates entities with schema names like `cr_assistantcard`. But it does not validate or create a publisher with that prefix. In a fresh environment, the default publisher prefix may be "new_" (Microsoft changed defaults in some regions), causing entity creation to fail.

**Evidence verified:** COR-04 flagged `pac admin create --async` and `pac admin list --json` version dependency (a separate but related script issue). IMP-01 flagged the publisher prefix problem specifically. The publisher issue is the more critical one -- without a matching publisher, ALL entity creation fails.

**Final ruling: BLOCK.** Entity creation will fail in environments without a "cr" publisher. This is the first step in provisioning -- if it fails, nothing else works.

**Remediation:** Add publisher creation/validation step before entity creation. Either create a custom publisher with the "cr" prefix via Web API, or validate an existing publisher's prefix and use it.

---

## WARN -- Non-Blocking Issues

These should be fixed but deployment can proceed without them.

| ID | Requirement | Artifact | Issue | Flagged By | Remediation |
|----|-------------|----------|-------|------------|-------------|
| R-10 | PLAT-04 | provision-environment.ps1 | Missing Sprint 4 SenderProfile columns | Correctness | Add 4 column creation calls |
| R-11 | PLAT-04 | provision-environment.ps1 | Missing alternate key creation | Correctness, Implementability, Gaps | Add key creation after publish |
| R-12 | PLAT-04 | provision-environment.ps1 | Missing Publish Customizations step | Gaps, Implementability | Add PublishAllXml API call |
| R-13 | PLAT-04 | provision-environment.ps1 | Duplicate `pac auth create` call | Correctness | Replace with auth validation check |
| R-14 | PLAT-04 | provision-environment.ps1 | PAC CLI `--json` flag version dependency | Correctness | Document minimum version or add fallback |
| R-15 | PLAT-02 | agent-flows.md | Trigger Type Compose maps only 3 of 6 values | Correctness | Add note that expression is Flow 1-3 specific |
| R-16 | PLAT-03 | deployment-guide.md | Missing SENDER_PROFILE input variable docs | Correctness, Gaps | Add 5th variable to input table |
| R-17 | PLAT-02 | agent-flows.md | SENDER_PROFILE not passed to agent in flows | Gaps | Add Sprint 4 addendum to Flows 1-3 |
| R-18 | PLAT-03 | deployment-guide.md | Orchestrator Agent tool action registration not documented | Gaps | Add Phase 2.6 Orchestrator setup steps |
| R-19 | PLAT-02 | agent-flows.md | Sender profile upsert race condition | Implementability | Use Dataverse Upsert action with alternate key |
| R-20 | PLAT-04 | deploy-solution.ps1 | NuGet package restore not validated | Implementability | Add explicit dotnet restore step |
| R-21 | PLAT-04 | Solution.cdsproj | Unmanaged solution type for production | Implementability | Add -Managed parameter or document change |
| R-22 | PLAT-03 | deployment-guide.md | Humanizer not registered as Connected Agent for Orchestrator | Implementability | Add inter-agent configuration step |
| R-23 | PLAT-03 | deployment-guide.md | Knowledge source configurations not documented | Gaps | Add SharePoint/Graph/Bing setup details |

### R-10: Missing Sprint 4 SenderProfile columns in provisioning script

**Source:** COR-16

The provisioning script creates 8 SenderProfile columns but misses 4 Sprint 4 columns: cr_dismisscount, cr_avgeditdistance, cr_responserate, cr_dismissrate. Base deployment (Sprints 1-3) works without them. Sprint 4 features would fail on first write to these columns.

**WARN** because base deployment works; Sprint 4 columns can be added incrementally.

### R-11: Missing alternate key creation on SenderProfile table

**Sources:** COR-17, IMP-06, GAP-12 (partial)

Three agents flagged related aspects: COR-17 (key not created), IMP-06 (key requires publish first), GAP-12 (indexes not defined). The alternate key on cr_senderemail enables atomic upserts preventing duplicate sender profiles. Without it, the List-Condition-Add/Update pattern still works but has a race condition (see R-19).

**WARN** because the flow functions without the key; data integrity degradation is the risk, not failure.

### R-12: Missing Publish Customizations step in provisioning script

**Sources:** GAP-06, IMP-06

The script creates entities and columns but never publishes customizations. Dataverse requires publishing before new tables/columns appear in flow designer or Canvas App data sources. IMP-06 also notes that alternate key creation requires a prior publish step.

**WARN** because a developer following the deployment guide would likely discover this gap during flow creation and run a manual publish. But the script should be self-contained.

### R-13: Duplicate `pac auth create` call in provisioning script

**Source:** COR-05

The deployment guide instructs users to run `pac auth create` before the script, then the script runs it again. The second call prompts for interactive browser login, breaking automated execution.

**WARN** because it creates confusion and breaks automation but can be worked around by removing the script line or skipping the manual step.

### R-14: PAC CLI `--json` flag version dependency

**Source:** COR-04

The script's polling loop uses `pac admin list --json`, which requires PAC CLI 1.29+. Older versions would cause the polling loop to fail.

**WARN** because documenting the minimum version resolves the issue.

### R-15: Trigger Type Compose expression maps only 3 of 6 values

**Source:** COR-11

The Compose expression for Trigger Type in Flows 1-3 only maps EMAIL, TEAMS_MESSAGE, and CALENDAR_SCAN. The other 3 trigger types (DAILY_BRIEFING, SELF_REMINDER, COMMAND_RESULT) would default to CALENDAR_SCAN (100000002) if this expression were reused.

**WARN** because Flows 1-3 hardcode their own trigger types and don't use the fallback. The expression is correct for its scope but should document its limitation.

### R-16: Missing SENDER_PROFILE in deployment guide input variable table

**Sources:** COR-15, GAP-11 (related)

The deployment guide lists 4 input variables but the main agent prompt defines 5 (including SENDER_PROFILE for Sprint 4). A developer following the guide would not create this variable.

**WARN** because Sprint 4 features would not receive sender data, but Sprints 1-3 work without it.

### R-17: SENDER_PROFILE not passed to agent in flow specifications

**Source:** GAP-11

Flows 1-3 pass 4 variables to the agent but not SENDER_PROFILE. The Sprint 1B sender upsert step queries/creates sender profiles but doesn't pass the data to the agent.

**WARN** because Sprint 4's sender-adaptive triage degrades gracefully (treats as unknown sender) without this data.

### R-18: Orchestrator Agent tool action registration not documented

**Source:** GAP-05

The Orchestrator Agent has 6 tool actions (QueryCards, QuerySenderProfile, UpdateCard, CreateCard, RefineDraft, QueryCalendar) that must be registered as Copilot Studio actions. No registration steps exist in the deployment guide.

**WARN** because the Orchestrator Agent was introduced in Sprint 3 and the deployment guide covers Sprint 3 at a verification level but not at a build-step level. A developer would need to figure out the action registration independently.

### R-19: Sender profile upsert race condition

**Source:** IMP-07

The List-Condition-Add/Update pattern for sender profiles is not atomic. Concurrent flow runs for the same sender could create duplicates. The alternate key (R-11) would prevent this.

**WARN** because the probability is low (two emails from the same sender arriving within milliseconds) and duplicates are inconvenient but not system-breaking.

### R-20: NuGet package restore not validated in deploy-solution.ps1

**Source:** IMP-10

The script runs `dotnet build` without verifying NuGet package availability. In air-gapped or proxy environments, NuGet restore would fail without a clear error.

**WARN** because standard environments with internet access work fine.

### R-21: Unmanaged solution type for production

**Source:** IMP-11

The Solution.cdsproj uses `SolutionPackageType = Unmanaged`. Production environments should use Managed solutions for governance.

**WARN** because the development deployment works and the deployment guide already notes this.

### R-22: Humanizer not registered as Connected Agent for Orchestrator

**Source:** IMP-12

The Orchestrator Agent's RefineDraft tool action invokes the Humanizer Agent, but the inter-agent connection is not documented.

**WARN** because the Orchestrator functions without RefineDraft (it is one of 6 tools), and the connection can be configured post-deployment.

### R-23: Knowledge source configurations not documented

**Source:** GAP-10

The deployment guide lists research tool actions but doesn't specify which SharePoint sites, Graph API permissions, or Bing Search resource to configure.

**WARN** because these are environment-specific and vary by organization. The guide should provide a template but specific values cannot be predetermined.

---

## INFO -- Known Constraints

These are platform limitations with documented workarounds or accepted risks. No fix needed.

| ID | Requirement | Constraint | Accepted Risk | Documented? |
|----|-------------|-----------|---------------|-------------|
| R-24 | PLAT-05 | Parse JSON does not support oneOf/anyOf | Simplified schema with `{}` for polymorphic fields | Yes |
| R-25 | PLAT-05 | Canvas App delegation limits (500/2000 rows) | 7-day expiration keeps active rows manageable | Yes |
| R-26 | PLAT-05 | PCF virtual controls have limited event support | Output properties used as event surrogates (standard pattern) | Yes |
| R-27 | PLAT-05 | Power Automate ticks() Int64 theoretical overflow | No practical impact; response times are hours/days, not centuries | Yes |
| R-28 | PLAT-05 | Copilot Studio connector response size limit (~100KB) | Agent output bounded by prompt constraints; largest field is draft_payload | Yes |
| R-29 | PLAT-05 | Copilot Studio system prompt length limits | Prompt is at high end of range; few-shot examples at risk of truncation | Partially |

### R-24: Parse JSON does not support oneOf/anyOf (GAP-18, COR-19)

**Constraint:** Power Automate's Parse JSON action cannot validate JSON Schema composition keywords.

**Workaround:** Already implemented. The simplified schema in agent-flows.md uses `{}` (empty schema) for polymorphic fields. COR-19 confirmed the `["type", "null"]` type arrays ARE supported (distinct from oneOf/anyOf).

**Accepted risk:** Malformed draft_payload passes Parse JSON silently but would fail on downstream Dataverse write or Humanizer invocation.

### R-25: Canvas App delegation limits (IMP-08, GAP-19)

**Constraint:** Choice column filters are not delegable to Dataverse. Client-side filtering limited to 500 rows (default) or 2000 rows (if increased).

**Workaround:** The 7-day staleness expiration policy keeps active card counts manageable. Both agents agreed this is non-blocking.

**Accepted risk:** Power users with >2000 active non-expired cards could see incomplete data. Unlikely given expiration policy.

### R-26: PCF virtual controls have limited event support (GAP-21)

**Constraint:** No direct event callback mechanism between PCF and Canvas App.

**Workaround:** Output properties (`sendDraftAction`, `dismissCardAction`, etc.) serve as event surrogates. This is the standard PCF-Canvas communication pattern.

**Accepted risk:** None -- this is how PCF controls are designed to work.

### R-27: Power Automate ticks() Int64 overflow (GAP-22)

**Constraint:** The `ticks()` function returns Int64 values that could theoretically overflow for time differences greater than ~292 years.

**Accepted risk:** Zero practical impact. Card response times are measured in hours to days.

### R-28: Copilot Studio connector response size limit (GAP-23)

**Constraint:** "Execute Agent and wait" action has a ~100KB response size limit.

**Accepted risk:** Agent output is bounded by prompt design (item_summary max 300 chars, research_log is concise, key_findings is bulleted). The largest component is draft_payload, which is bounded by reasonable email/message length. Unlikely to approach 100KB.

### R-29: Copilot Studio system prompt length limits (IMP-03, GAP-20)

**Constraint:** Copilot Studio has a system prompt character limit (historically 10,000-16,000 characters). The main agent prompt is approximately 12,000 characters.

**Disagreement resolution:** IMP classified this as deploy-blocking; GAP classified it as a known constraint. Research: The prompt MAY fit within limits but is at the high end. Testing in a real environment would confirm. However, the prompt works today in its current form -- the risk is that it is NEAR the limit, not that it exceeds it. If truncated, few-shot examples at the bottom would be lost first, degrading format consistency but not breaking the agent.

**Final ruling: INFO** (reclassified from IMP-03's deploy-blocking). This is a real platform constraint that requires monitoring during deployment. It can be mitigated by moving few-shot examples to a Knowledge Source if needed. It is not something that can be "fixed" in the artifacts -- it requires runtime testing.

**Mitigation:** Measure exact character count during deployment. If near limit, move few-shot examples to a Knowledge Source document.

---

## FALSE -- False Positives

These were flagged by agents but are not actual issues upon closer inspection.

| ID | Source | Artifact | Why False |
|----|--------|----------|-----------|
| F-01 | COR-08 | dataverse-table.json | "WholeNumber" is a valid Dataverse display name; script uses correct API type |
| F-02 | COR-09 | dataverse-table.json | "MultilineText" is the Maker UI label; script uses correct "MemoAttributeMetadata" |
| F-03 | COR-18 | create-security-roles.ps1 | Privilege depth "Basic" is the correct Web API string enum value |
| F-04 | COR-12 | briefing-output-schema.json | Optional fyi_items/stale_alerts arrays are correctly handled -- prompt says "omit if none qualify" |

### F-01: dataverse-table.json uses "WholeNumber" type name (COR-08)

The Correctness agent noted that "WholeNumber" is not the API type name (which is "Integer" / IntegerAttributeMetadata). However, the JSON file is documentation, not an API contract. The provisioning script correctly uses `IntegerAttributeMetadata`. Both naming conventions (Maker UI vs. API) are well-understood. Not an issue.

### F-02: dataverse-table.json uses "MultilineText" type name (COR-09)

Same pattern as F-01. "MultilineText" is the Maker portal label for `MemoAttributeMetadata`. The provisioning script uses the correct API type. Not an issue.

### F-03: Security roles privilege depth uses string "Basic" (COR-18)

The Correctness agent noted that the plan references numeric depths (1=User, 2=BU, etc.) but the script uses `Depth = "Basic"`. The script is correct -- the Web API uses string enum values (Basic, Local, Deep, Global), not integers. The plan's numeric reference is from older documentation. Not an issue.

### F-04: briefing-output-schema.json optional arrays (COR-12)

The Correctness agent noted that `fyi_items` and `stale_alerts` are not in the `required` array. This is intentional -- the prompt says "Omit the array if none qualify." The schema correctly marks them as optional. The Parse JSON action in the Daily Briefing flow should handle their absence, which is standard behavior. Not an issue.

---

## Undocumented Assumptions (from Gaps Agent)

These are not bugs or missing features, but documentation gaps that should be addressed.

| ID | Requirement | Topic | Suggested Action |
|----|-------------|-------|------------------|
| R-30 | PLAT-02 | Agent timeout behavior not documented | Document expected response times and timeout config |
| R-31 | PLAT-02 | Copilot Studio API rate limits for calendar scan loop | Document rate limits and validate 50 invocations in 5 min |
| R-32 | PLAT-05 | Assumed data volume not documented | Add capacity planning section to deployment guide |
| R-33 | PLAT-04 | License and admin role requirements not fully documented | Add license requirements and per-step role requirements |

These are classified as WARN-level documentation improvements. They do not block deployment but should be addressed for production readiness.

- **R-30** (GAP-13): Document expected agent response times and "Execute Agent and wait" timeout configuration.
- **R-31** (GAP-14): Document Copilot Studio API rate limits. The calendar scan loop (30-50 sequential invocations with 5-second delays) may approach limits.
- **R-32** (GAP-15): Add capacity planning assumptions (20-50 cards/user/day, 100-300 sender profiles/user, 7-day expiration ceiling).
- **R-33** (GAP-16, GAP-17): Document Power Platform license requirements and per-deployment-step admin role requirements.

---

## Additional Non-Blocking Items (not merged with other agents)

| ID | Requirement | Source | Issue | Category |
|----|-------------|--------|-------|----------|
| R-34 | PLAT-01 | COR-10 | maxLength not enforced by Parse JSON; Dataverse write could fail on long summaries | WARN |
| R-35 | PLAT-02 | GAP-07 | No Dataverse table for briefing schedule preferences (stored in component state) | WARN |
| R-36 | PLAT-02 | GAP-08 | No Teams message send flow (by design -- documented limitation) | INFO |
| R-37 | PLAT-02 | IMP-02 | Agent publish verification step missing between Phase 2 and Phase 3 | WARN |
| R-38 | PLAT-02 | IMP-09 | Canvas App OnChange uses If() blocks instead of Switch() | INFO |

- **R-34** (COR-10): Consider adding truncation expression in flow: `@{take(body('Parse_JSON')?['item_summary'], 300)}`.
- **R-35** (GAP-07): Known tech debt #13. Accept or add a user preferences table.
- **R-36** (GAP-08): Intentional limitation. TEAMS_MESSAGE cards show "Send" button hidden.
- **R-37** (IMP-02): Add verification step: confirm agent appears in connector dropdown before building flows.
- **R-38** (IMP-09): Functional as designed. PCF changes one output property per event.

---

## Disagreement Log

| Issue | Agent A Said | Agent B Said | Resolution | Reasoning |
|-------|-------------|-------------|------------|-----------|
| R-07: Staleness Monitor missing | IMP: Non-blocking | GAP: Deploy-blocking | **BLOCK** | Sprint 2 acceptance criteria require this flow. Cannot be built without spec. "Non-blocking for other flows" is irrelevant; it is blocking for Sprint 2 verification. |
| R-08: Sender Profile Analyzer missing | IMP: Non-blocking | GAP: Deploy-blocking | **BLOCK** | Sprint 4 acceptance criteria require this flow. Same reasoning as R-07. |
| R-29: Prompt length limit | IMP: Deploy-blocking | GAP: Known constraint | **INFO** | Prompt MAY fit within limits. Cannot be "fixed" in artifacts -- requires runtime testing. Mitigation exists (move examples to Knowledge Source). Classified as known constraint with monitoring requirement. |
| R-10: Sprint 4 columns missing | COR: Non-blocking | (no other agent) | **WARN** | Agreed with COR. Base deployment works without Sprint 4 columns. |
| R-12: Missing Publish step | GAP: Deploy-blocking | IMP: Non-blocking (implicit) | **WARN** | A developer would discover this gap quickly during flow creation. The fix is a single API call. Important but not deploy-blocking because manual publish via the Maker portal is trivially discovered. |
| R-18: Orchestrator tool actions | GAP: Deploy-blocking | (no other agent) | **WARN** | Reclassified. The tool actions require registration but the Orchestrator is a Sprint 3 feature that enhances the command bar. Core functionality (Sprints 1-2) works without it. The deployment guide Sprint 3 section mentions verification but a skilled developer can infer the registration pattern from the Main Agent's tool action setup. |
| R-33: License/role docs | GAP: Non-blocking | (no other agent) | **WARN** | Agreed. Documentation improvement, not a code fix. |

---

## PLAT Requirement Coverage

| Requirement | BLOCK | WARN | INFO | FALSE | Assessment |
|-------------|-------|------|------|-------|------------|
| PLAT-01 (Dataverse validity) | 1 (R-01) | 1 (R-34) | 0 | 2 (F-01, F-02) | Conditional -- N/A vs null is the only schema contract issue |
| PLAT-02 (Flow buildability) | 5 (R-04, R-05, R-06, R-07, R-08) | 6 (R-15, R-17, R-19, R-35, R-37, R-38 partial) | 1 (R-36) | 0 | FAIL -- 4 missing flow specs + 1 contradiction |
| PLAT-03 (Copilot Studio completeness) | 1 (R-02) | 4 (R-16, R-18, R-22, R-23) | 1 (R-29) | 1 (F-04) | Conditional -- USER_VIP is the only blocking issue |
| PLAT-04 (Deployment scripts) | 1 (R-09) | 6 (R-10, R-11, R-12, R-13, R-14, R-20, R-21) | 0 | 1 (F-03) | Conditional -- publisher prefix is the only blocker |
| PLAT-05 (Platform limitations) | 0 | 2 (R-30, R-31) | 5 (R-24, R-25, R-26, R-27, R-28) | 0 | PASS -- all limitations documented with workarounds |
