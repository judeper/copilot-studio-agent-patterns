# Correctness Agent -- Integration/E2E Findings

## Summary

**22 issues found: 8 deploy-blocking, 14 non-blocking.**

Cross-layer contract tracing across all 5 layers (prompt -> schema -> Dataverse -> flow -> TypeScript) reveals 8 field/enum mismatches that would cause runtime data loss or incorrect behavior, plus 14 inconsistencies that degrade correctness but would not cause immediate failures.

## Methodology

Systematic cross-layer contract tracing for every field and every enum value across all 5 integration layers:

1. **Schema-to-Prompt Contract**: Verified every field in output-schema.json and briefing-output-schema.json against agent prompt instructions.
2. **Schema-to-Dataverse Contract**: Verified type compatibility between JSON schema types and Dataverse column types for every field.
3. **Dataverse-to-Flow Contract**: Verified flow expressions reference correct column names and use correct Choice integer values.
4. **Dataverse-to-Frontend Contract**: Verified TypeScript interfaces, useCardData mapping, and constants match Dataverse structure.
5. **End-to-End Enum Consistency**: Built tracing tables for every enum type across all layers.

Known Phase 10 issues (R-01, R-02) and Phase 11 issues (F-01) are referenced where they have cross-layer integration implications.

---

## Cross-Layer Tracing Tables

### Enum: trigger_type

| Value | Prompt | output-schema.json | dataverse-table.json | Flow Compose | types.ts | UI Display |
|-------|--------|-------------------|---------------------|-------------|----------|-----------|
| EMAIL | Yes (TRIGGER_TYPE input) | Yes | Yes (100000000) | Yes (100000000) | Yes | Yes (badge) |
| TEAMS_MESSAGE | Yes | Yes | Yes (100000001) | Yes (100000001) | Yes | Yes |
| CALENDAR_SCAN | Yes | Yes | Yes (100000002) | Yes (100000002) | Yes | Yes |
| DAILY_BRIEFING | Not in main prompt (separate agent) | Yes | Yes (100000003) | Not in main flows (separate flow) | Yes | Yes (partitioned) |
| SELF_REMINDER | Not in any prompt (created by Orchestrator tool) | Yes | Yes (100000004) | Not in documented flows | Yes | Yes |
| COMMAND_RESULT | Not in any prompt (created by Orchestrator tool) | Yes | Yes (100000005) | Not in documented flows | Yes | Yes |

**Status: PASS** -- All 6 values consistent across layers that use them. DAILY_BRIEFING, SELF_REMINDER, and COMMAND_RESULT are correctly absent from the main agent prompt (they are handled by separate agents/tools).

### Enum: triage_tier

| Value | Prompt | output-schema.json | dataverse-table.json | Flow Compose | types.ts |
|-------|--------|-------------------|---------------------|-------------|----------|
| SKIP | Yes | Yes | Yes (100000000) | Filtered out before write | Yes |
| LIGHT | Yes | Yes | Yes (100000001) | Yes (100000001) | Yes |
| FULL | Yes | Yes | Yes (100000002) | Yes (100000002) | Yes |

**Status: PASS** -- All 3 values consistent. SKIP correctly excluded from Dataverse write per design.

### Enum: priority

| Value | Prompt | output-schema.json | dataverse-table.json | Flow Compose | types.ts | constants.ts |
|-------|--------|-------------------|---------------------|-------------|----------|-------------|
| High | Yes | Yes | Yes (100000000) | Yes (100000000) | Yes | Yes (red color) |
| Medium | Yes | Yes | Yes (100000001) | Yes (100000001) | Yes | Yes (amber color) |
| Low | Yes | Yes | Yes (100000002) | Yes (100000002) | Yes | Yes (green color) |
| null | Yes (for SKIP) | Yes (nullable) | N/A | N/A | Yes (null) | N/A (hidden) |
| "N/A" | Yes (prompt says `priority = "N/A"` for SKIP) | **NO -- not in enum** | Yes (100000003) | Yes (100000003) | **NO -- not in type** | No |

**Status: ISSUE COR-I01** -- The prompt instructs `priority = "N/A"` for SKIP items, but output-schema.json enum is `["High", "Medium", "Low", null]` -- "N/A" is not a valid value. Dataverse has N/A (100000003) and the flow maps it. The TypeScript type is `Priority | null` where `Priority = "High" | "Medium" | "Low"` -- "N/A" excluded. useCardData converts "N/A" to null at the ingestion boundary. **This is Phase 10 issue R-01 confirmed at integration level.**

### Enum: temporal_horizon

| Value | Prompt | output-schema.json | dataverse-table.json | Flow Compose | types.ts |
|-------|--------|-------------------|---------------------|-------------|----------|
| TODAY | Yes | Yes | Yes (100000000) | Yes (100000000) | Yes |
| THIS_WEEK | Yes | Yes | Yes (100000001) | Yes (100000001) | Yes |
| NEXT_WEEK | Yes | Yes | Yes (100000002) | Yes (100000002) | Yes |
| BEYOND | Yes | Yes | Yes (100000003) | Yes (100000003) | Yes |
| null | Yes (for non-calendar) | Yes (nullable) | Not required | N/A | Yes (null) |
| "N/A" | Yes (prompt says `temporal_horizon = "N/A"` for EMAIL/TEAMS) | **NO -- not in enum** | Yes (100000004) | Yes (100000004) | **NO -- not in type** |

**Status: ISSUE COR-I02** -- Same pattern as priority. Prompt says "N/A", schema enum does not include it, Dataverse has it (100000004), flow maps it, but TypeScript type excludes it. useCardData converts "N/A" to null. **This is Phase 10 issue R-01 confirmed -- the N/A vs null mismatch spans prompt-schema-frontend layers.**

### Enum: card_status

| Value | Prompt | output-schema.json | dataverse-table.json | Flow Compose | types.ts | useCardData source |
|-------|--------|-------------------|---------------------|-------------|----------|-------------------|
| READY | Yes | Yes | Yes (100000000) | Yes (100000000) | Yes | cr_fulljson |
| LOW_CONFIDENCE | Yes | Yes | Yes (100000001) | Yes (100000001) | Yes | cr_fulljson |
| SUMMARY_ONLY | Yes | Yes | Yes (100000002) | Yes (100000002) | Yes | cr_fulljson |
| NO_OUTPUT | Yes | Yes | Yes (100000003) | Yes (100000003) | Yes | cr_fulljson |
| NUDGE | **Not in any prompt** | **Not in schema** | Yes (100000004) | In mapping table but no flow sets it | Yes | cr_fulljson |

**Status: ISSUE COR-I03** -- NUDGE exists in Dataverse (100000004) and TypeScript but is NOT in output-schema.json, NOT in any agent prompt, and NO documented flow sets it. The Staleness Monitor flow (which Phase 10 flagged as missing spec, R-07) is the intended source. useCardData reads card_status from cr_fulljson, but NUDGE would be set by a flow updating the discrete cr_cardstatus column, NOT by the agent JSON output. **This means NUDGE cards would have the wrong card_status in the PCF -- Phase 11 issue F-01 confirmed with cross-layer root cause: NUDGE bypasses the cr_fulljson data path entirely.**

### Enum: card_outcome

| Value | Prompt | Schema | dataverse-table.json | Flow | types.ts | useCardData source |
|-------|--------|--------|---------------------|------|----------|-------------------|
| PENDING | N/A | N/A | Yes (100000000) | Yes (default on create) | Yes | cr_cardoutcome (discrete column) |
| SENT_AS_IS | N/A | N/A | Yes (100000001) | Yes (Send Email flow) | Yes | cr_cardoutcome |
| SENT_EDITED | N/A | N/A | Yes (100000002) | Referenced but not yet impl | Yes | cr_cardoutcome |
| DISMISSED | N/A | N/A | Yes (100000003) | Canvas app Patch | Yes | cr_cardoutcome |
| EXPIRED | N/A | N/A | Yes (100000004) | No flow sets this | Yes | cr_cardoutcome |

**Status: ISSUE COR-I04** -- EXPIRED (100000004) exists in Dataverse and TypeScript but no documented flow or Canvas app action sets it. The Staleness Monitor (missing spec, R-07) would presumably expire cards after 7 days PENDING. This means EXPIRED cards cannot occur in the current implementation, making the CardOutcome type wider than what can actually happen.

### Enum: draft_type (nested in draft_payload)

| Value | Prompt | output-schema.json | Humanizer prompt | types.ts |
|-------|--------|-------------------|-----------------|----------|
| EMAIL | Yes | Yes | Yes | Yes |
| TEAMS_MESSAGE | Yes | Yes | Yes | Yes |

**Status: PASS** -- Both values consistent across all layers.

### Enum: recipient_relationship (nested in draft_payload)

| Value | Prompt | output-schema.json | Humanizer prompt | types.ts |
|-------|--------|-------------------|-----------------|----------|
| Internal colleague | Yes | Yes | Yes | Yes |
| External client | Yes | Yes | Yes | Yes |
| Leadership | Yes | Yes | Yes | Yes |
| Unknown | Yes | Yes | Yes (defaults to semi-formal) | Yes |

**Status: PASS** -- All 4 values consistent.

### Enum: inferred_tone (nested in draft_payload)

| Value | Prompt | output-schema.json | Humanizer prompt | types.ts |
|-------|--------|-------------------|-----------------|----------|
| formal | Yes | Yes | Yes | Yes |
| semi-formal | Yes | Yes | Yes | Yes |
| direct | Yes | Yes | Yes | Yes |
| collaborative | Yes | Yes | Yes | Yes |

**Status: PASS** -- All 4 values consistent.

### Enum: sender_category (SenderProfile)

| Value | Main prompt | senderprofile-table.json | Flow (sender upsert) | Orchestrator |
|-------|-------------|------------------------|---------------------|-------------|
| AUTO_HIGH | Yes (sender_category = "AUTO_HIGH") | Yes (100000000) | Not set by trigger flow | QuerySenderProfile |
| AUTO_MEDIUM | Not referenced | Yes (100000001) | Yes (default for new senders) | QuerySenderProfile |
| AUTO_LOW | Yes (sender_category = "AUTO_LOW") | Yes (100000002) | Not set by trigger flow | QuerySenderProfile |
| USER_OVERRIDE | Yes (sender_category = "USER_OVERRIDE") | Yes (100000003) | Not set by trigger flow | UpdateCard? |
| USER_VIP | Yes (prompt says "USER_VIP") | **NOT in schema** | N/A | N/A |

**Status: ISSUE COR-I05** -- The main agent prompt references `sender_category = "USER_VIP"` in the sender-adaptive triage section, but this value does NOT exist in senderprofile-table.json. The schema has USER_OVERRIDE (100000003). **This is Phase 10 issue R-02 confirmed at integration level.** If the agent receives a sender profile with category "USER_OVERRIDE", the prompt's "USER_VIP" check would never match, causing the agent to treat USER_OVERRIDE senders as standard senders instead of VIP.

### Enum: briefing fyi_items.category

| Value | Briefing prompt | briefing-output-schema.json | types.ts |
|-------|----------------|---------------------------|----------|
| MEETING_PREP | Yes | Yes | Yes |
| INFO_UPDATE | Yes | Yes | Yes |
| LOW_PRIORITY | Yes | Yes | Yes |

**Status: PASS** -- All 3 values consistent.

### Enum: stale_alerts.recommended_action (briefing)

| Value | Briefing prompt | briefing-output-schema.json | types.ts |
|-------|----------------|---------------------------|----------|
| RESPOND | Yes | Yes | Yes |
| DELEGATE | Yes | Yes | Yes |
| DISMISS | Yes | Yes | Yes |

**Status: PASS** -- All 3 values consistent.

---

## Field-Level Cross-Layer Tracing

### output-schema.json fields -> All layers

| Field | Schema Type | Schema Required | Prompt | Dataverse Column | Dataverse Type | Flow Maps | TS Interface | useCardData Source |
|-------|-------------|----------------|--------|-----------------|---------------|-----------|-------------|-------------------|
| trigger_type | string enum | Yes | Yes (input) | cr_triggertype | Choice | Yes (Compose) | trigger_type: TriggerType | cr_fulljson |
| triage_tier | string enum | Yes | Yes | cr_triagetier | Choice | Yes (Compose) | triage_tier: TriageTier | cr_fulljson |
| item_summary | string | Yes | Yes | cr_itemsummary (Primary) | Text(300) | Yes (direct) | item_summary: string | cr_fulljson |
| priority | string/null enum | Yes | Yes | cr_priority | Choice | Yes (Compose) | priority: Priority/null | cr_fulljson (N/A->null) |
| temporal_horizon | string/null enum | Yes | Yes | cr_temporalhorizon | Choice | Yes (Compose) | temporal_horizon: TemporalHorizon/null | cr_fulljson (N/A->null) |
| research_log | string/null | Yes | Yes | **None (cr_fulljson only)** | N/A | N/A | research_log: string/null | cr_fulljson |
| key_findings | string/null | Yes | Yes | **None (cr_fulljson only)** | N/A | N/A | key_findings: string/null | cr_fulljson |
| verified_sources | array/null | Yes | Yes | **None (cr_fulljson only)** | N/A | N/A | verified_sources: VerifiedSource[]/null | cr_fulljson |
| confidence_score | integer/null | Yes | Yes | cr_confidencescore | WholeNumber | Yes (direct) | confidence_score: number/null | cr_fulljson |
| card_status | string enum | Yes | Yes | cr_cardstatus | Choice | Yes (Compose) | card_status: CardStatus | cr_fulljson |
| draft_payload | oneOf(null/string/object) | Yes | Yes | **None (cr_fulljson only)** | N/A | Yes (string() for humanizer) | draft_payload: DraftPayload/string/null | cr_fulljson |
| low_confidence_note | string/null | Yes | Yes | **None (cr_fulljson only)** | N/A | N/A | low_confidence_note: string/null | cr_fulljson |

### Non-schema fields (Dataverse only, not in agent output)

| Dataverse Column | Type | Written By | Read By | TS Field |
|-----------------|------|-----------|---------|----------|
| cr_fulljson | MultilineText | Flow (raw agent response) | useCardData (JSON.parse) | (all parsed fields) |
| cr_humanizeddraft | MultilineText | Flow (humanizer response) | useCardData (discrete read) | humanized_draft |
| cr_cardoutcome | Choice | Flow/Canvas app | useCardData (discrete read) | card_outcome |
| cr_outcometimestamp | DateTime | Flow/Canvas app | Not read by PCF | N/A |
| cr_senttimestamp | DateTime | Send Email flow | Not read by PCF | N/A |
| cr_sentrecipient | Text | Send Email flow | Not read by PCF | N/A |
| cr_originalsenderemail | Text | Trigger flows | useCardData (discrete read) | original_sender_email |
| cr_originalsenderdisplay | Text | Trigger flows | useCardData (discrete read) | original_sender_display |
| cr_originalsubject | Text | Trigger flows | useCardData (discrete read) | original_subject |
| cr_conversationclusterid | Text | Trigger flows | useCardData (discrete read) | conversation_cluster_id |
| cr_sourcesignalid | Text | Trigger flows | useCardData (discrete read) | source_signal_id |

---

## Findings

### Deploy-Blocking Issues

**COR-I01: Priority "N/A" not in output-schema.json enum (Prompt <-> Schema <-> Frontend)**

- **Layers affected:** Prompt, Schema, Frontend
- **Fields:** priority
- **Issue:** Main agent prompt instructs `priority = "N/A"` for SKIP items, but output-schema.json enum is `["High", "Medium", "Low", null]`. The agent will produce "N/A" which fails JSON Schema validation. Dataverse has N/A (100000003) and flows map it, so data reaches Dataverse correctly, but the schema contract is broken. useCardData compensates by converting "N/A" to null.
- **Evidence:** output-schema.json line 38 enum vs main-agent-system-prompt.md line 98 (`priority = "N/A"`)
- **Impact:** Schema validation tools would reject valid agent output. Any consumer strictly validating against the schema would fail.
- **Suggested fix:** Add `"N/A"` to the priority enum in output-schema.json: `["High", "Medium", "Low", "N/A", null]`
- **Phase 10 cross-ref:** R-01

**COR-I02: Temporal horizon "N/A" not in output-schema.json enum (Prompt <-> Schema <-> Frontend)**

- **Layers affected:** Prompt, Schema, Frontend
- **Fields:** temporal_horizon
- **Issue:** Same pattern as COR-I01. Prompt instructs `temporal_horizon = "N/A"` for EMAIL/TEAMS_MESSAGE, but output-schema.json enum is `["TODAY", "THIS_WEEK", "NEXT_WEEK", "BEYOND", null]`.
- **Evidence:** output-schema.json line 44 enum vs main-agent-system-prompt.md line 227-234
- **Impact:** Same as COR-I01 -- schema validation failure.
- **Suggested fix:** Add `"N/A"` to temporal_horizon enum: `["TODAY", "THIS_WEEK", "NEXT_WEEK", "BEYOND", "N/A", null]`
- **Phase 10 cross-ref:** R-01

**COR-I03: NUDGE card_status unreachable via cr_fulljson ingestion path (Dataverse <-> Frontend)**

- **Layers affected:** Dataverse, Flow, Frontend
- **Fields:** card_status (NUDGE value)
- **Issue:** NUDGE (100000004) exists in dataverse-table.json and types.ts CardStatus, but NO agent produces it (it is not in any prompt or schema). The Staleness Monitor flow (unspecified, R-07) would set it by updating the discrete cr_cardstatus column. However, useCardData reads card_status from the parsed cr_fulljson blob, NOT from the discrete cr_cardstatus column. Since the agent JSON will never contain "NUDGE", the PCF will never see NUDGE status even if the flow sets it.
- **Evidence:** useCardData.ts line 71 (`parsed.card_status`) vs dataverse-table.json line 68 (NUDGE: 100000004). No code reads `record.getFormattedValue("cr_cardstatus")`.
- **Impact:** Nudge cards will display with whatever card_status was in the original agent JSON (likely READY or SUMMARY_ONLY), not NUDGE. Users will not see staleness indicators.
- **Suggested fix:** In useCardData, read card_status from the discrete Dataverse column (`record.getFormattedValue("cr_cardstatus")`) instead of cr_fulljson. Add NUDGE to output-schema.json for completeness.
- **Phase 11 cross-ref:** F-01; **Phase 10 cross-ref:** R-07

**COR-I04: EXPIRED card_outcome has no writer (Dataverse <-> Flow)**

- **Layers affected:** Dataverse, Flow
- **Fields:** card_outcome (EXPIRED value)
- **Issue:** EXPIRED (100000004) exists in dataverse-table.json and types.ts but no flow or Canvas app action ever sets a card to EXPIRED. The Staleness Monitor flow spec is missing (R-07). The deployment guide Sprint 2 checklist mentions "Cards expire to EXPIRED after 7 days PENDING" but no flow implements this.
- **Evidence:** No flow Compose expression maps to 100000004 (EXPIRED). Card Outcome Tracker (Flow 5) only handles SENT_AS_IS, SENT_EDITED, DISMISSED. Canvas app OnChange only patches DISMISSED.
- **Impact:** Cards will accumulate indefinitely as PENDING, with no automated cleanup. The ConfidenceCalibration dashboard's resolvedCards filter would never include EXPIRED cards.
- **Suggested fix:** Include EXPIRED transition logic in the Staleness Monitor flow specification (R-07).
- **Phase 10 cross-ref:** R-07

**COR-I05: USER_VIP referenced in prompt but not in schema (Prompt <-> Dataverse)**

- **Layers affected:** Prompt, Dataverse (SenderProfile)
- **Fields:** sender_category
- **Issue:** Main agent prompt line 78 checks for `sender_category = "USER_VIP"`, but senderprofile-table.json defines USER_OVERRIDE (100000003), not USER_VIP. The SENDER_PROFILE JSON passed to the agent would contain "USER_OVERRIDE" from Dataverse, which would never match "USER_VIP" in the prompt.
- **Evidence:** main-agent-system-prompt.md line 78 vs senderprofile-table.json line 73
- **Impact:** Users who manually override sender categories would not get VIP treatment. The adaptive triage logic would silently fall through to the default path.
- **Suggested fix:** Change "USER_VIP" to "USER_OVERRIDE" in the main agent prompt (line 78 and line 90).
- **Phase 10 cross-ref:** R-02

**COR-I06: Card Outcome Tracker ignores DISMISSED -- missing dismiss_count increment (Flow <-> Dataverse)**

- **Layers affected:** Flow, Dataverse (SenderProfile)
- **Fields:** cr_dismisscount, cr_cardoutcome
- **Issue:** The Card Outcome Tracker flow (Flow 5) explicitly terminates on DISMISSED outcomes ("If No: Terminate -- no sender profile update needed"). However, senderprofile-table.json defines cr_dismisscount (Sprint 4) which should be incremented on DISMISSED outcomes. The Sender Profile Analyzer flow needs accurate dismiss counts to calculate cr_dismissrate and categorize senders.
- **Evidence:** agent-flows.md Flow 5 step 2 condition excludes DISMISSED. senderprofile-table.json line 87-89 describes cr_dismisscount "Updated by the Card Outcome Tracker flow."
- **Impact:** cr_dismisscount will always be 0. cr_dismissrate (computed by Sender Profile Analyzer) will always be 0. AUTO_LOW categorization based on dismiss_rate >= 0.6 will never trigger. Sender-adaptive triage downgrade logic will be broken.
- **Suggested fix:** Add a DISMISSED branch to Flow 5 that increments cr_dismisscount on the sender profile.
- **Phase 10 cross-ref:** R-04

**COR-I07: Trigger Type Compose expression missing 3 values (Flow <-> Dataverse)**

- **Layers affected:** Flow, Dataverse
- **Fields:** trigger_type
- **Issue:** The Trigger Type Compose expression in Flow 1 step 7 only handles EMAIL, TEAMS_MESSAGE, and CALENDAR_SCAN. The if-chain defaults to 100000002 (CALENDAR_SCAN) for any unmatched value. If a flow attempted to write DAILY_BRIEFING (100000003), SELF_REMINDER (100000004), or COMMAND_RESULT (100000005), they would be incorrectly stored as CALENDAR_SCAN.
- **Evidence:** agent-flows.md Flow 1 step 7 Trigger Type Compose: `if(equals(...,'EMAIL'),100000000,if(equals(...,'TEAMS_MESSAGE'),100000001,100000002))`
- **Impact:** The current 3 trigger flows only produce their own types, so this doesn't fail today. But the Daily Briefing flow (unspecified, R-05) and Command Execution flow (unspecified, R-06) would need their own Compose expressions or an extended if-chain. The existing expression is misleadingly incomplete.
- **Suggested fix:** The existing flows are scoped correctly (each hardcodes its own trigger type). The missing flow specs should include their own Compose expressions. Document this limitation in agent-flows.md.

**COR-I08: Privilege name casing in create-security-roles.ps1 (Script <-> Dataverse)**

- **Layers affected:** Script, Dataverse
- **Fields:** Privilege names
- **Issue:** create-security-roles.ps1 constructs privilege names using lowercase logical names: `prvCreate${entityName}` where `$entityName = "cr_assistantcard"`. Dataverse privilege names use PascalCase schema names (e.g., `prvCreatecr_AssistantCard`). The lowercase lookup would fail to find privileges, and the role would have no permissions.
- **Evidence:** create-security-roles.ps1 lines 106-113 vs Dataverse privilege naming convention
- **Impact:** The security role would be created but with no table permissions. Users assigned the role would have no access to AssistantCards or SenderProfiles.
- **Suggested fix:** Use PascalCase entity schema names or query EntityDefinitions for the SchemaName to construct privilege names dynamically.
- **Phase 10 cross-ref:** R-03

### Non-Blocking Issues

**COR-I09: confidence_score dual read path (Schema <-> Frontend)**

- **Layers affected:** Schema, Dataverse, Frontend
- **Fields:** confidence_score
- **Issue:** confidence_score exists both as a discrete Dataverse column (cr_confidencescore, WholeNumber) and inside cr_fulljson. useCardData reads it from cr_fulljson (`parsed.confidence_score`), not from the discrete column. This works but creates a redundant data path where the two values could theoretically diverge if a flow updates the discrete column independently.
- **Evidence:** useCardData.ts line 70 vs dataverse-table.json line 88
- **Impact:** Low -- the agent sets both values from the same source. No flow updates confidence_score independently today.
- **Suggested fix:** Consider reading from discrete column for consistency with how card_outcome is read.

**COR-I10: verified_sources type mismatch in Parse JSON simplified schema (Flow <-> Schema)**

- **Layers affected:** Flow, Schema
- **Fields:** verified_sources
- **Issue:** The simplified Parse JSON schema in agent-flows.md uses `{}` (empty schema) for verified_sources. The canonical schema specifies an array of objects with required title/url/tier fields. The empty schema means Power Automate will not validate the structure, allowing malformed sources to pass through to cr_fulljson.
- **Evidence:** agent-flows.md Parse JSON schema vs output-schema.json lines 55-77
- **Impact:** Low -- the flow does not process individual sources; they are stored as-is in cr_fulljson and parsed by the PCF. useCardData checks `Array.isArray(parsed.verified_sources)` which provides minimal validation.
- **Suggested fix:** Acceptable as-is per the documented rationale (Power Automate cannot validate complex array schemas). No fix needed.

**COR-I11: draft_payload type mismatch in Parse JSON simplified schema (Flow <-> Schema)**

- **Layers affected:** Flow, Schema
- **Fields:** draft_payload
- **Issue:** Same as COR-I10. The simplified schema uses `{}` for draft_payload while the canonical schema uses `oneOf` (null, string, object). This is a documented design decision: Power Automate does not support `oneOf`.
- **Evidence:** agent-flows.md Parse JSON Schema section documents this explicitly.
- **Impact:** None -- this is an accepted platform limitation (PLAT-05).
- **Suggested fix:** None needed. Documented as a known constraint.

**COR-I12: SENT_EDITED outcome not yet set by Send Email flow (Flow)**

- **Layers affected:** Flow
- **Fields:** cr_cardoutcome
- **Issue:** The Send Email flow (Flow 4) always sets `cr_cardoutcome = 100000001` (SENT_AS_IS). The Sprint 2 note says the flow "should be updated to compare the final text against the stored cr_humanizeddraft column value" but the flow spec does not include this comparison logic.
- **Evidence:** agent-flows.md Flow 4 step 8 always sets 100000001. Sprint 2 note in canvas-app-setup.md mentions SENT_EDITED tracking.
- **Impact:** Draft quality metrics in ConfidenceCalibration will report all sends as "as-is" even when users edit before sending. The draftStats.edited count will always be 0.
- **Suggested fix:** Add a condition to Flow 4 step 8 that compares FinalDraftText to cr_humanizeddraft and sets 100000002 (SENT_EDITED) if they differ.

**COR-I13: SenderProfile cr_avgeditdistance and cr_responserate have no writer (Dataverse)**

- **Layers affected:** Dataverse, Flow
- **Fields:** cr_avgeditdistance, cr_responserate, cr_dismissrate
- **Issue:** These Sprint 4 SenderProfile columns are defined in senderprofile-table.json but the Sender Profile Analyzer flow (which would compute and write them) has no specification (R-08).
- **Evidence:** senderprofile-table.json lines 93-111 vs absence of Flow 9 spec in agent-flows.md
- **Impact:** These columns will always be null/0. Sender-adaptive confidence adjustments in the main agent prompt that reference avg_edit_distance will always evaluate to the default path.
- **Suggested fix:** Write the Sender Profile Analyzer flow specification.
- **Phase 10 cross-ref:** R-08

**COR-I14: SENDER_PROFILE not passed to agent in trigger flows (Flow <-> Prompt)**

- **Layers affected:** Flow, Prompt
- **Fields:** SENDER_PROFILE input variable
- **Issue:** The main agent prompt references `{{SENDER_PROFILE}}` as a runtime input, but none of the 3 trigger flows (EMAIL, TEAMS_MESSAGE, CALENDAR_SCAN) include a SENDER_PROFILE input variable in their "Invoke agent" step. The prompt says "If {{SENDER_PROFILE}} is provided (non-null), adjust the tier."
- **Evidence:** agent-flows.md Flow 1 step 4 input variables table has only TRIGGER_TYPE, PAYLOAD, USER_CONTEXT, CURRENT_DATETIME. No SENDER_PROFILE.
- **Impact:** Sender-adaptive triage (Sprint 4) will never activate. The agent will always use standard signal-based triage.
- **Suggested fix:** Add SENDER_PROFILE input variable to each trigger flow's invoke step, populated from the sender profile lookup.
- **Phase 10 cross-ref:** R-17

**COR-I15: Daily Briefing flow spec incomplete -- truncated after step 6 (Flow)**

- **Layers affected:** Flow
- **Fields:** Daily Briefing flow
- **Issue:** The Daily Briefing flow specification (Flow 6) in agent-flows.md is incomplete. It specifies steps 1-6 but does not include the agent invocation, Parse JSON, or Dataverse write steps. The flow spec is cut off at "List sender profiles."
- **Evidence:** agent-flows.md Flow 6 ends at step 6 without agent invocation or Dataverse write
- **Impact:** A developer cannot build the complete flow from the spec.
- **Suggested fix:** Complete the Daily Briefing flow specification.
- **Phase 10 cross-ref:** R-05

**COR-I16: Briefing-to-frontend data path relies on cr_fulljson overloading (Schema <-> Frontend)**

- **Layers affected:** Schema, Dataverse, Frontend
- **Fields:** Daily Briefing fields (briefing_type, day_shape, action_items, etc.)
- **Issue:** The Daily Briefing Agent output follows briefing-output-schema.json, not output-schema.json. It is stored as raw JSON in cr_fulljson. BriefingCard.tsx parses the briefing from card.draft_payload (which useCardData extracts from cr_fulljson). The briefing-specific fields (action_items, fyi_items, stale_alerts, day_shape) have no discrete Dataverse columns -- they exist only in the JSON blob.
- **Evidence:** briefing-output-schema.json has no corresponding Dataverse columns. BriefingCard.tsx parseBriefing() reads from card.draft_payload.
- **Impact:** Low -- this is a valid architectural choice (store full JSON, parse client-side). However, the briefing card's useCardData mapping sets trigger_type, triage_tier, item_summary etc. from the cr_fulljson, which won't match the briefing schema structure well. The briefing JSON has `briefing_type`, `briefing_date`, `day_shape` but NOT `trigger_type`, `triage_tier`, etc.
- **Suggested fix:** Document that the Daily Briefing flow must wrap the briefing JSON in a standard agent output structure (with trigger_type=DAILY_BRIEFING, draft_payload=briefing JSON string) for useCardData to parse correctly.

**COR-I17: Humanizer input/output mismatch with flow wiring (Prompt <-> Flow)**

- **Layers affected:** Prompt, Flow
- **Fields:** Humanizer Agent input
- **Issue:** The Humanizer Agent prompt says "You receive exactly one JSON object" matching the DraftPayload structure. Flow step 9 passes `string(body('Parse_JSON')?['draft_payload'])` which serializes the entire draft_payload object. This is correct for the object case. However, if draft_payload is a string (CALENDAR_SCAN briefing), the flow would serialize a string, not a JSON object. The humanizer condition (step 8) correctly excludes CALENDAR_SCAN, so this path should never trigger.
- **Evidence:** agent-flows.md step 8 condition excludes CALENDAR_SCAN. Humanizer prompt says "If you receive a calendar briefing by mistake, return it unchanged."
- **Impact:** None in normal operation. The defensive handling in the humanizer prompt is a good safety net.
- **Suggested fix:** None needed. Correctly guarded.

**COR-I18: Orchestrator response format not wired back to PCF (Flow <-> Frontend)**

- **Layers affected:** Flow, Frontend
- **Fields:** OrchestratorResponse (response_text, card_links, side_effects)
- **Issue:** The Orchestrator Agent returns a JSON response with response_text, card_links, and side_effects. The Canvas app OnChange handler calls the Command Execution flow and receives the response. However, the PCF CommandBar receives `lastResponse={null}` and `isProcessing={false}` hardcoded in App.tsx. There is no input property in the PCF manifest to pass the orchestrator response back from Canvas app to PCF.
- **Evidence:** App.tsx line 210-211 (`lastResponse={null}`, `isProcessing={false}`). CommandBar.tsx useEffect watches lastResponse but it never changes.
- **Impact:** Users can send commands but never see responses. The CommandBar conversation history shows user messages but no assistant replies.
- **Suggested fix:** Add `orchestratorResponse` and `isProcessing` input properties to the PCF manifest; wire them through index.ts and App.tsx.
- **Phase 11 cross-ref:** F-02

**COR-I19: provision-environment.ps1 missing Sprint 4 SenderProfile columns (Script <-> Schema)**

- **Layers affected:** Script, Dataverse
- **Fields:** cr_dismisscount, cr_avgeditdistance, cr_responserate, cr_dismissrate
- **Issue:** The provisioning script does not create 4 Sprint 4 SenderProfile columns: cr_dismisscount, cr_avgeditdistance, cr_responserate, cr_dismissrate. These are defined in senderprofile-table.json but not in the provisioning script.
- **Evidence:** senderprofile-table.json columns vs provision-environment.ps1 SenderProfile section
- **Impact:** The table would be created without these columns. Sprint 4 flows (Sender Profile Analyzer, Card Outcome Tracker DISMISSED branch) would fail when trying to write to non-existent columns.
- **Suggested fix:** Add Sprint 4 column creation to provision-environment.ps1.
- **Phase 10 cross-ref:** R-10

**COR-I20: Publisher prefix hardcoded as "cr" with no validation (Script)**

- **Layers affected:** Script
- **Fields:** PublisherPrefix parameter
- **Issue:** provision-environment.ps1 defaults PublisherPrefix to "cr" and uses it to construct entity names, but does not verify that a publisher with prefix "cr" exists in the target environment. Fresh environments may not have this publisher.
- **Evidence:** provision-environment.ps1 line 44 ($PublisherPrefix = "cr")
- **Impact:** All entity creation API calls would fail in a fresh environment without the "cr" publisher.
- **Suggested fix:** Add publisher creation/validation step before entity creation.
- **Phase 10 cross-ref:** R-09

**COR-I21: BriefingCard parses draft_payload for briefing data -- fragile coupling (Frontend)**

- **Layers affected:** Frontend
- **Fields:** DailyBriefing data
- **Issue:** BriefingCard.tsx parseBriefing() extracts briefing data from `card.draft_payload`. For this to work, the Daily Briefing flow must store the briefing JSON in a way that useCardData maps it to the draft_payload field. If the flow stores the raw briefing agent response in cr_fulljson, useCardData would parse the briefing fields (briefing_type, day_shape, etc.) as the card's top-level fields, and draft_payload would be undefined/null (since briefing-output-schema.json has no draft_payload field).
- **Evidence:** BriefingCard.tsx parseBriefing() vs briefing-output-schema.json (no draft_payload field)
- **Impact:** BriefingCard would show "Unable to parse briefing data" error. The data is in the cr_fulljson blob but parseBriefing() looks in the wrong place.
- **Suggested fix:** Either (a) the Daily Briefing flow wraps the briefing JSON in a standard output envelope with draft_payload containing the briefing string, or (b) BriefingCard reads directly from a different path (e.g., parse the full JSON from the card context rather than draft_payload).

**COR-I22: Card Status flow Compose expression missing NUDGE mapping (Flow <-> Dataverse)**

- **Layers affected:** Flow, Dataverse
- **Fields:** card_status (NUDGE)
- **Issue:** The Card Status Compose expression in flow step 7 maps READY/LOW_CONFIDENCE/SUMMARY_ONLY/NO_OUTPUT but not NUDGE. The default falls through to NO_OUTPUT (100000003). If a flow tried to write card_status = "NUDGE" via this expression, it would be stored as NO_OUTPUT.
- **Evidence:** agent-flows.md step 7 Card Status Compose expression defaults to 100000003. NUDGE (100000004) not in the if-chain.
- **Impact:** The trigger flows never produce NUDGE (it is set by the Staleness Monitor updating the discrete column). But the Compose expression is misleadingly incomplete.
- **Suggested fix:** Add NUDGE mapping to the Card Status Compose expression for completeness, or document that NUDGE is set via discrete column update only.

### Validated (No Issues)

The following cross-layer contracts passed all consistency checks:

1. **trigger_type enum**: All 6 values consistent across all layers that reference them.
2. **triage_tier enum**: All 3 values consistent (SKIP correctly excluded from Dataverse writes).
3. **draft_type enum**: EMAIL and TEAMS_MESSAGE consistent across prompt, schema, humanizer, and TypeScript.
4. **recipient_relationship enum**: All 4 values consistent.
5. **inferred_tone enum**: All 4 values consistent.
6. **briefing fyi_items.category enum**: All 3 values consistent.
7. **stale_alerts.recommended_action enum**: All 3 values consistent.
8. **DraftPayload object structure**: All 7 fields (draft_type, raw_draft, research_summary, recipient_relationship, inferred_tone, confidence_score, user_context) consistent between output-schema.json, humanizer prompt INPUT CONTRACT, and types.ts DraftPayload interface.
9. **DailyBriefing structure**: All fields in briefing-output-schema.json match the DailyBriefing TypeScript interface in types.ts.
10. **SenderProfile columns**: cr_senderemail, cr_senderdisplayname, cr_signalcount, cr_responsecount, cr_avgresponsehours, cr_lastsignaldate, cr_sendercategory, cr_isinternal all consistent between schema and trigger flow upsert logic.
11. **Dataverse Choice integer values**: All Choice columns use the 100000000+ convention consistently across dataverse-table.json, flow Compose expressions, and the provisioning script.
12. **PCF output properties**: selectedCardId, sendDraftAction, copyDraftAction, dismissCardAction, jumpToCardAction, commandAction all correctly wired from index.ts through getOutputs() to Canvas app OnChange handlers.
13. **Fire-and-forget pattern**: Send Email flow returns success/failure to Canvas app; Canvas app refreshes DataSet; PCF re-renders via updateView. Pattern is correctly implemented.
14. **N/A-to-null ingestion boundary**: useCardData correctly converts "N/A" strings to null for priority and temporal_horizon, aligning the prompt's "N/A" output with the TypeScript null type.
15. **Humanizer handoff condition**: Flow step 8 correctly gates on FULL tier, confidence >= 40, and not CALENDAR_SCAN, matching the prompt's instructions.
