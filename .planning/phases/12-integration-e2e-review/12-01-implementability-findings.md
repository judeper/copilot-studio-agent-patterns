# Implementability Agent -- Integration/E2E Findings

## Summary

**19 issues found: 7 deploy-blocking, 12 non-blocking.**

End-to-end workflow tracing reveals 3 workflows with missing critical steps and 4 layer boundary error handling gaps that would cause user-visible failures. All 7 user workflows were traced from trigger to completion; 4 have complete data paths, 3 have gaps that block deployment.

## Methodology

1. **Workflow Tracing**: Each of the 7 user workflows was traced step-by-step from trigger event to user-visible completion, identifying every layer transition and checking for missing steps, undefined behavior, or silent failure points.
2. **Layer Boundary Error Audit**: Each of the 4 layer boundaries (Agent-to-Dataverse, Dataverse-to-PCF, PCF-to-Power Automate, Power Automate-to-Agent) was audited for error scenarios and handling status.
3. **Cross-Workflow Dependency Analysis**: Checked for ordering assumptions, shared resource contention, and workflow interdependencies.

Known Phase 10 (R-05 through R-08) and Phase 11 (F-02, F-03) issues are referenced where they have workflow completeness implications.

---

## Workflow Traces

### Workflow 1: Email Triage

| Step | Description | Layer Transition | Status | Evidence |
|------|------------|-----------------|--------|----------|
| 1 | New email arrives in Outlook | External -> Flow | PASS | Flow 1 trigger: "When a new email arrives (V3)" |
| 2 | Pre-filter low-value emails | Flow | PASS | Step 1a condition filters noreply/low-importance |
| 3 | Compose PAYLOAD with email metadata | Flow | PASS | Step 1 Compose with from/to/cc/subject/bodyPreview |
| 4 | Get user profile and compose USER_CONTEXT | Flow | PASS | Steps 2-3 |
| 5 | Invoke Copilot Studio main agent | Flow -> Agent | PASS | Step 4 with 4 input variables |
| 6 | Parse JSON response | Flow | PASS | Step 5 with simplified schema (no oneOf) |
| 7 | Check triage tier (skip SKIP) | Flow | PASS | Step 6 condition filters SKIP |
| 8 | Map Choice values and Add row to Dataverse | Flow -> Dataverse | PASS | Step 7 with Compose expressions for all 5 Choice columns |
| 9 | Check humanizer handoff condition | Flow | PASS | Step 8 condition: FULL + confidence >= 40 + not CALENDAR |
| 10 | Invoke Humanizer Agent | Flow -> Agent | PASS | Step 9 with string() serialization |
| 11 | Update row with humanized draft | Flow -> Dataverse | PASS | Step 10 updates cr_humanizeddraft |
| 12 | Upsert sender profile | Flow -> Dataverse | PASS | Step 11 with List-Condition-Add/Update pattern |
| 13 | PCF DataSet refresh detects new record | Dataverse -> PCF | PASS | updateView increments datasetVersion |
| 14 | useCardData parses cr_fulljson into AssistantCard | PCF | PASS | useCardData maps all fields |
| 15 | Card appears in gallery | PCF -> User | PASS | CardGallery renders cards |

**Workflow 1 Status: PASS** -- Complete end-to-end path from email arrival to card in dashboard. All 15 steps documented with implementation evidence.

### Workflow 2: Draft Editing

| Step | Description | Layer Transition | Status | Evidence |
|------|------------|-----------------|--------|----------|
| 1 | User clicks card with draft in dashboard | PCF (gallery -> detail) | PASS | App.tsx handleSelectCard sets viewState to detail |
| 2 | CardDetail displays humanized draft | PCF | PASS | CardDetail checks card.humanized_draft |
| 3 | User clicks "Edit draft" button | PCF | PASS | CardDetail handleEditClick sets isEditing=true |
| 4 | Textarea becomes editable | PCF | PASS | readOnly={!isEditing} on Textarea |
| 5 | User modifies draft text | PCF | PASS | onChange updates editedDraft state |
| 6 | "(modified)" indicator appears | PCF | PASS | draftIsModified computed from editedDraft !== humanized_draft |
| 7 | User clicks Send | PCF | PASS | handleSendClick sets confirming state |
| 8 | Confirm panel shows "(edited)" label | PCF | PASS | draftIsModified check in confirm panel |
| 9 | User confirms send | PCF -> Canvas App | PASS | handleConfirmSend calls onSendDraft with finalText=editedDraft |
| 10 | Canvas app calls Send Email flow | Canvas -> Flow | PASS | sendDraftAction JSON parsed, flow receives FinalDraftText |
| 11 | Flow sends email with edited text | Flow -> External | PASS | Flow step 7 uses FinalDraftText input |
| 12 | Flow updates Dataverse with outcome | Flow -> Dataverse | **PARTIAL** | Flow always sets SENT_AS_IS; should set SENT_EDITED when text differs |
| 13 | "Revert to original" restores draft | PCF | PASS | handleCancelEdit resets editedDraft |

**Workflow 2 Status: PARTIAL PASS** -- The edit-send path works end-to-end, but the outcome is always recorded as SENT_AS_IS regardless of edits (COR-I12). The edited draft is NOT persisted to Dataverse -- if the user edits but does not send, the edit is lost on page refresh.

### Workflow 3: Email Send (fire-and-forget)

| Step | Description | Layer Transition | Status | Evidence |
|------|------------|-----------------|--------|----------|
| 1 | User clicks "Send" in CardDetail | PCF | PASS | handleSendClick -> confirming state |
| 2 | Confirm panel shows recipient and subject | PCF | PASS | Shows original_sender_display and original_subject |
| 3 | User clicks "Confirm & Send" | PCF | PASS | handleConfirmSend fires |
| 4 | PCF sets sendDraftAction output property | PCF -> Canvas App | PASS | JSON.stringify({ cardId, finalText }) |
| 5 | Canvas App OnChange detects output | Canvas App | PASS | !IsBlank(AssistantDashboard1.sendDraftAction) |
| 6 | Canvas App calls SendEmailFlow.Run() | Canvas App -> Flow | PASS | Passes cardId and finalText |
| 7 | Flow validates ownership | Flow | PASS | Step 3 compares owner ID |
| 8 | Flow validates recipient exists | Flow | PASS | Step 4 checks cr_originalsenderemail |
| 9 | Flow sends email via Outlook connector | Flow -> External | PASS | Step 7 Send email (V2) |
| 10 | Flow writes audit columns to Dataverse | Flow -> Dataverse | PASS | Step 8 sets outcome, timestamps, recipient |
| 11 | Flow returns success to Canvas App | Flow -> Canvas App | PASS | Step 9 responds with success=true |
| 12 | Canvas App shows success notification | Canvas App | PASS | Notify() with recipient display name |
| 13 | Canvas App refreshes DataSet | Canvas App -> Dataverse | PASS | Refresh('Assistant Cards') |
| 14 | PCF updateView re-renders card with "Sent" badge | Dataverse -> PCF | PASS | effectiveSendState derived from card_outcome |
| 15 | PCF local state timeout (60s fallback) | PCF | PASS | setTimeout resets sending state |

**Workflow 3 Status: PASS** -- Complete round-trip from send through flow to confirmation. Error handling includes ownership validation, recipient check, draft empty check, and timeout fallback. Success/failure feedback reaches the user via Canvas App notification.

### Workflow 4: Outcome Tracking

| Step | Description | Layer Transition | Status | Evidence |
|------|------------|-----------------|--------|----------|
| 1a | User clicks Dismiss in CardDetail | PCF -> Canvas App | PASS | onDismissCard sets dismissCardAction output |
| 1b | Canvas App patches DISMISSED + timestamp | Canvas App -> Dataverse | PASS | Patch with Card Outcome = DISMISSED |
| 2 | Card Outcome Tracker flow triggers | Dataverse -> Flow | PASS | filteringattributes = cr_cardoutcome |
| 3a | Flow checks if SENT outcome | Flow | PASS | Condition: SENT_AS_IS or SENT_EDITED |
| 3b | For SENT: calculate response hours | Flow | PASS | ticks() subtraction with conversion |
| 3c | For SENT: update sender profile | Flow -> Dataverse | PASS | Increment response_count, recalculate avg |
| 3d | For DISMISSED: terminate (no profile update) | Flow | **FAIL** | Should increment cr_dismisscount but terminates |
| 4 | PCF DataSet refresh shows updated outcome | Dataverse -> PCF | PASS | useCardData reads cr_cardoutcome |
| 5 | ConfidenceCalibration aggregates outcomes | PCF | PASS | resolvedCards filter excludes PENDING |

**Workflow 4 Status: PARTIAL PASS** -- Send outcomes are fully tracked. Dismiss outcomes update the card but do NOT update sender profiles (dismiss_count not incremented). EXPIRED outcome has no triggering mechanism. Snooze is not implemented.

### Workflow 5: Daily Briefing

| Step | Description | Layer Transition | Status | Evidence |
|------|------------|-----------------|--------|----------|
| 1 | Scheduled trigger fires (weekday 7 AM) | External -> Flow | PASS | Flow 6 Recurrence trigger |
| 2 | Flow gathers open cards from Dataverse | Flow -> Dataverse | PASS | List open cards with PENDING filter |
| 3 | Flow gathers stale cards | Flow -> Dataverse | PASS | List cards older than 24h |
| 4 | Flow gets today's calendar events | Flow -> External | PASS | Get events V4 for today |
| 5 | Flow lists sender profiles | Flow -> Dataverse | PASS | Listed in spec |
| 6 | Token budget guard | Flow | PASS | Truncate to 30 cards if > 40K chars |
| 7 | Compose BRIEFING_INPUT JSON | Flow | **MISSING** | Flow spec ends at step 6 |
| 8 | Invoke Daily Briefing Agent | Flow -> Agent | **MISSING** | Not in flow spec |
| 9 | Parse briefing response | Flow | **MISSING** | Not in flow spec |
| 10 | Write briefing as DAILY_BRIEFING card | Flow -> Dataverse | **MISSING** | Not in flow spec |
| 11 | PCF DataSet refresh picks up briefing card | Dataverse -> PCF | PASS | App.tsx partitionCards separates DAILY_BRIEFING |
| 12 | BriefingCard renders at top of gallery | PCF -> User | **UNCERTAIN** | parseBriefing reads card.draft_payload; depends on how flow stores data |
| 13 | User clicks action item "Open card" link | PCF | PASS | onJumpToCard navigates to detail |

**Workflow 5 Status: FAIL** -- Steps 7-10 are missing from the flow specification. The frontend rendering depends on how the flow stores briefing data, which is undefined. BriefingCard.tsx parseBriefing() reads from card.draft_payload, but the briefing agent produces briefing-output-schema.json fields (not the standard output-schema.json). The flow must bridge this gap.

### Workflow 6: Command Execution

| Step | Description | Layer Transition | Status | Evidence |
|------|------------|-----------------|--------|----------|
| 1 | User types command in CommandBar | PCF | PASS | CommandBar input handling |
| 2 | User presses Enter or clicks Send | PCF | PASS | handleSubmit fires |
| 3 | PCF sets commandAction output property | PCF -> Canvas App | PASS | JSON.stringify({ command, currentCardId }) |
| 4 | Canvas App OnChange detects commandAction | Canvas App | PASS | !IsBlank(AssistantDashboard1.commandAction) |
| 5 | Canvas App calls CommandExecutionFlow.Run() | Canvas App -> Flow | PASS | Per canvas-app-setup.md Sprint 3 |
| 6 | Command Execution flow invokes Orchestrator Agent | Flow -> Agent | **MISSING** | No flow spec exists (R-06) |
| 7 | Orchestrator Agent uses tool actions | Agent | PASS (agent prompt complete) | Orchestrator prompt specifies 6 tools |
| 8 | Agent returns response JSON | Agent -> Flow | **MISSING** | No flow spec for response handling |
| 9 | Flow returns response to Canvas App | Flow -> Canvas App | **MISSING** | No flow spec |
| 10 | Canvas App passes response to PCF | Canvas App -> PCF | **FAIL** | No input property for response (F-02) |
| 11 | CommandBar displays response | PCF | **FAIL** | lastResponse={null} hardcoded |
| 12 | Card links in response navigate to cards | PCF | **FAIL** | Never receives card_links data |

**Workflow 6 Status: FAIL** -- The flow spec is completely missing (R-06). Even if the flow existed, the response has no path back to the PCF: there is no orchestratorResponse input property in the manifest, and App.tsx hardcodes lastResponse={null}. The command execution pipeline is one-way (user can send commands, but never receives responses).

### Workflow 7: Reminder Creation

| Step | Description | Layer Transition | Status | Evidence |
|------|------------|-----------------|--------|----------|
| 1 | User types "Remind me to..." in CommandBar | PCF | PASS | Captured by handleSubmit |
| 2 | Command reaches Orchestrator Agent | PCF -> Canvas -> Flow -> Agent | **MISSING** | Depends on Workflow 6 which is broken |
| 3 | Orchestrator calls CreateCard tool action | Agent -> Dataverse | PASS (in spec) | Orchestrator prompt CreateCard tool |
| 4 | SELF_REMINDER card created in Dataverse | Agent -> Dataverse | PASS (in spec) | Card with cr_triggertype=100000004 |
| 5 | Response with card link returned to user | Agent -> Flow -> Canvas -> PCF | **FAIL** | Blocked by Workflow 6 response path gap |
| 6 | Reminder card appears in dashboard | Dataverse -> PCF | PASS | useCardData would include SELF_REMINDER cards |
| 7 | Reminder firing mechanism | External -> User | **MISSING** | No reminder notification mechanism documented |

**Workflow 7 Status: FAIL** -- Depends entirely on Workflow 6 (Command Execution) which is broken. Even if commands worked, there is no reminder FIRING mechanism. The Orchestrator creates a card, but no flow monitors for reminder dates or sends notifications. The reminder would appear in the dashboard but the user would only see it if they happen to check.

---

## Layer Boundary Error Matrix

### Boundary A: Agent-to-Dataverse (via Power Automate)

| Error Scenario | Handling Status | Evidence |
|---------------|----------------|----------|
| Agent returns invalid JSON (malformed) | HANDLED | Parse JSON action will fail; caught by Scope error handler |
| Agent returns JSON missing required fields | PARTIAL | Parse JSON with simplified schema accepts missing fields (no "required" validation) |
| Agent returns wrong types (e.g., string for integer) | PARTIAL | Simplified schema uses loose types; Dataverse would reject type mismatches on Choice columns |
| Agent times out (Copilot Studio connector timeout) | HANDLED | Scope error handler catches timeout; error notification sent |
| Parse JSON fails (schema mismatch) | HANDLED | Error Scope logs failure |
| "Add a new row" fails (Dataverse unavailable) | HANDLED | Error Scope catches; no retry mechanism documented |
| "Add a new row" fails (permission denied) | HANDLED | Error Scope catches; error logged |
| "Add a new row" fails (duplicate key) | PARTIAL | No duplicate detection for cards; sender profile uses alternate key |
| No dead-letter mechanism | **MISSING** | Failed signals are logged in flow run history but not tracked in a persistent error table |

### Boundary B: Dataverse-to-PCF (via DataSet binding)

| Error Scenario | Handling Status | Evidence |
|---------------|----------------|----------|
| DataSet returns error instead of records | **MISSING** | useCardData checks for empty dataset but not error state |
| Column value is unexpected type | PARTIAL | try-catch in useCardData skips malformed records with console.warn |
| View filter excludes expected records | HANDLED | Canvas App formula filters by Owner; RLS provides secondary check |
| DataSet paging limit exceeded | **MISSING** | No paging implementation; limited to first page of results |
| DataSet.sortedRecordIds is undefined | HANDLED | useCardData checks `!dataset.sortedRecordIds` |

### Boundary C: PCF-to-Power Automate (via Canvas App)

| Error Scenario | Handling Status | Evidence |
|---------------|----------------|----------|
| PCF output property change not detected by Canvas App | PARTIAL | Relies on Canvas App OnChange event; no retry mechanism |
| Power Automate flow fails after fire-and-forget | HANDLED (Send), **MISSING** (others) | Send Email flow returns error to Canvas; Dismiss is Canvas-only Patch |
| Canvas App formula binding misconfigured | **MISSING** | No runtime validation; would silently fail |
| Multiple rapid output property changes | PARTIAL | PCF resets action outputs after getOutputs() to prevent stale re-fires |
| Canvas App Patch fails (Dismiss) | **MISSING** | No error handling on the Patch call for dismiss |

### Boundary D: Power Automate-to-Agent (via Copilot Studio connector)

| Error Scenario | Handling Status | Evidence |
|---------------|----------------|----------|
| Agent exceeds response size limits | PARTIAL | Output bounded by prompt constraints (item_summary maxLength 300); no explicit size check |
| Agent returns valid JSON but semantically wrong | **MISSING** | No validation beyond JSON parsing; "INVALID" triage_tier would pass Parse JSON |
| Concurrent flow runs invoke agent simultaneously | HANDLED | Each flow run gets its own agent session; Copilot Studio sessions are isolated |
| Agent returns partial response (network interruption) | HANDLED | Parse JSON would fail; caught by Scope error handler |

---

## Findings

### Deploy-Blocking Issues

**IMP-I01: Daily Briefing flow specification incomplete -- steps 7-10 missing (INTG-02)**

- **Workflow(s) affected:** Workflow 5 (Daily Briefing)
- **Missing steps:** Agent invocation, response parsing, Dataverse write as DAILY_BRIEFING card
- **Impact:** A developer cannot build the Daily Briefing flow. The frontend BriefingCard component exists but has no data source. Users would never see a daily briefing.
- **Suggested fix:** Complete Flow 6 specification: compose BRIEFING_INPUT from gathered data, invoke Daily Briefing Agent, parse response, create DAILY_BRIEFING card in Dataverse with appropriate field mapping.
- **Phase 10 cross-ref:** R-05

**IMP-I02: Command Execution flow specification missing entirely (INTG-02)**

- **Workflow(s) affected:** Workflow 6 (Command Execution), Workflow 7 (Reminder Creation)
- **Missing steps:** Entire flow from Canvas App trigger to Orchestrator Agent invocation to response return
- **Impact:** Users can type commands in the CommandBar but nothing happens. The entire orchestrator interaction path is non-functional.
- **Suggested fix:** Write Flow 7 (Command Execution) specification: instant trigger from Canvas App, pass command + user context + current card context to Orchestrator Agent, return response JSON.
- **Phase 10 cross-ref:** R-06

**IMP-I03: CommandBar response path broken -- hardcoded null (INTG-02, INTG-03)**

- **Workflow(s) affected:** Workflow 6 (Command Execution), Workflow 7 (Reminder Creation)
- **Missing step:** App.tsx passes `lastResponse={null}` and `isProcessing={false}` to CommandBar. No input property exists in the PCF manifest for the orchestrator response.
- **Impact:** Even if the Command Execution flow existed and worked, responses cannot reach the CommandBar. Users see their own messages but never get replies.
- **Suggested fix:** Add orchestratorResponse and isProcessing input properties to ControlManifest.Input.xml; wire through index.ts updateView to App.tsx to CommandBar.
- **Phase 11 cross-ref:** F-02

**IMP-I04: No error boundary -- single bad record crashes entire dashboard (INTG-03)**

- **Workflow(s) affected:** All workflows
- **Unhandled error:** A rendering error in any child component (CardDetail, BriefingCard, CardGallery, ConfidenceCalibration) propagates up the React tree and crashes the entire dashboard.
- **Impact:** One malformed card could crash the dashboard for all cards. No recovery path -- user must reload.
- **Evidence:** App.tsx has no `<ErrorBoundary>` wrapping the content area. useCardData's try-catch only protects data parsing, not rendering.
- **Suggested fix:** Add a React class component ErrorBoundary that catches render errors and displays a fallback UI with a "Return to gallery" action.
- **Phase 11 cross-ref:** F-03

**IMP-I05: Staleness Monitor flow specification missing -- no NUDGE or EXPIRED transitions (INTG-02)**

- **Workflow(s) affected:** Workflow 4 (Outcome Tracking), cross-workflow staleness management
- **Missing flow:** The Staleness Monitor is referenced in Sprint 2 verification checklist ("Creates nudge cards for High-priority items >24h PENDING", "Cards expire to EXPIRED after 7 days PENDING") but has no flow specification.
- **Impact:** Cards accumulate indefinitely as PENDING with no staleness indicators. No NUDGE cards appear. No automatic EXPIRED transition. The stale_alerts section of the Daily Briefing would identify stale cards but cannot trigger nudge creation.
- **Suggested fix:** Write Flow 8 (Staleness Monitor) specification: scheduled flow that queries PENDING cards, creates NUDGE cards for High items >24h, expires cards >7 days.
- **Phase 10 cross-ref:** R-07

**IMP-I06: Sender Profile Analyzer flow specification missing (INTG-02)**

- **Workflow(s) affected:** Cross-workflow -- affects sender-adaptive triage in all trigger workflows
- **Missing flow:** The Sender Profile Analyzer is referenced in Sprint 4 verification checklist but has no flow specification. It should compute cr_sendercategory (AUTO_HIGH/AUTO_MEDIUM/AUTO_LOW), cr_responserate, cr_dismissrate, and cr_avgeditdistance.
- **Impact:** All senders remain at AUTO_MEDIUM (the default set during creation). Sender-adaptive triage never activates. The Orchestrator's QuerySenderProfile returns incomplete profiles.
- **Suggested fix:** Write Flow 9 (Sender Profile Analyzer) specification: weekly scheduled flow that recalculates sender metrics and categories.
- **Phase 10 cross-ref:** R-08

**IMP-I07: BriefingCard data path depends on undefined flow behavior (INTG-02)**

- **Workflow(s) affected:** Workflow 5 (Daily Briefing)
- **Issue:** BriefingCard.tsx parseBriefing() expects briefing data in card.draft_payload. But the Daily Briefing Agent outputs briefing-output-schema.json fields (briefing_type, day_shape, action_items, etc.), NOT the standard output-schema.json fields. If the flow stores the raw briefing JSON in cr_fulljson, useCardData would parse briefing_type as undefined (it expects trigger_type), and draft_payload would be null (briefing schema has no draft_payload). BriefingCard would show "Unable to parse briefing data."
- **Impact:** Briefing cards would render with error message even if the flow and agent work correctly.
- **Suggested fix:** The Daily Briefing flow must wrap the briefing agent response in a standard output envelope: create a wrapper JSON with trigger_type="DAILY_BRIEFING", triage_tier="FULL", item_summary=day_shape, draft_payload=briefing JSON string, and other required fields.

### Non-Blocking Issues

**IMP-I08: No dead-letter mechanism for failed signal processing (INTG-03)**

- **Workflow(s) affected:** Workflows 1-3 (all trigger flows)
- **Issue:** When the error handling Scope catches a failure, it "sends notification / logs to error table" but no error table is defined. Failed signals exist only in flow run history (retained for 28 days by default).
- **Impact:** Failed signals cannot be replayed or investigated after flow run history expires.
- **Suggested fix:** Define an error logging table or use Dataverse for persisting failed signal metadata.

**IMP-I09: Parse JSON simplified schema accepts semantically invalid values (INTG-03)**

- **Workflow(s) affected:** Workflows 1-3
- **Issue:** The simplified Parse JSON schema types all string enums as just `"type": "string"` with no enum validation. An agent response with `triage_tier: "INVALID"` would pass Parse JSON. The Compose expressions for Choice mapping would fall through to defaults (e.g., CALENDAR_SCAN for trigger type, NO_OUTPUT for card status).
- **Impact:** Invalid agent responses would be silently stored with incorrect Choice values rather than being caught as errors.
- **Suggested fix:** Add enum validation to the simplified schema where possible, or add explicit validation conditions after Parse JSON.

**IMP-I10: Draft edits are not persisted to Dataverse (INTG-02)**

- **Workflow(s) affected:** Workflow 2 (Draft Editing)
- **Issue:** When a user edits a draft in CardDetail, the edit is held in React state (editedDraft). If the user navigates away without sending, the edit is lost. There is no mechanism to save draft edits to Dataverse independently of sending.
- **Impact:** Users who edit drafts over multiple sessions would lose their work.
- **Suggested fix:** Add a "Save draft" action that patches cr_humanizeddraft with the edited text, or auto-save on navigate-away.

**IMP-I11: Dismiss action has no error handling in Canvas App (INTG-03)**

- **Workflow(s) affected:** Workflow 4 (Outcome Tracking)
- **Issue:** The Canvas App Patch for DISMISSED has no error handling. If the Patch fails (e.g., Dataverse unavailable), the user sees no feedback. The PCF local state may show dismissed but Dataverse does not reflect it.
- **Evidence:** canvas-app-setup.md OnChange handler for dismissCardAction has bare Patch with no If/error check.
- **Impact:** Silent failure on dismiss. User thinks card is dismissed but it remains PENDING in Dataverse.
- **Suggested fix:** Wrap Patch in IfError() and show notification on failure.

**IMP-I12: Reminder creation has no firing/notification mechanism (INTG-02)**

- **Workflow(s) affected:** Workflow 7 (Reminder Creation)
- **Issue:** The Orchestrator Agent's CreateCard tool creates a SELF_REMINDER card in Dataverse with a future date context in the summary, but there is no scheduled flow or notification mechanism to alert the user when the reminder is due.
- **Impact:** Reminders exist as static cards. Users must manually check their dashboard. No push notification, email, or Teams message at the reminder time.
- **Suggested fix:** Create a Reminder Notification flow: scheduled flow that queries SELF_REMINDER PENDING cards whose date is today, sends a notification (email or Teams message), and optionally updates card status.

**IMP-I13: Canvas App delegation warning for Choice column filters (INTG-03)**

- **Workflow(s) affected:** All workflows (data retrieval)
- **Issue:** Canvas App formula `'Card Outcome' <> 'Card Outcome'.DISMISSED` is not delegable to Dataverse. Filtering happens client-side on the first 500 rows.
- **Evidence:** canvas-app-setup.md documents this limitation.
- **Impact:** Users with >500 active cards may not see all their data. The Staleness Monitor (if implemented) would keep counts manageable.
- **Suggested fix:** Documented and accepted. The staleness/expiration flow is the mitigation.

**IMP-I14: No loading state in PCF dashboard (INTG-03)**

- **Workflow(s) affected:** All workflows (data display)
- **Issue:** When the DataSet is loading or refreshing, the dashboard shows an empty gallery rather than a loading indicator. Users may think they have no cards when the data is still loading.
- **Evidence:** App.tsx has no loading state check; useCardData returns [] for empty datasets.
- **Impact:** Confusing UX during initial load and after Refresh() calls.
- **Suggested fix:** Check `dataset.loading` property and show a Spinner component.
- **Phase 11 cross-ref:** F-13

**IMP-I15: BriefingCard detail view has no Back button (INTG-02)**

- **Workflow(s) affected:** Workflow 5 (Daily Briefing)
- **Issue:** When a DAILY_BRIEFING card is selected and rendered in detail view (App.tsx line 189-194), BriefingCard renders without a Back button. The user is trapped in the briefing detail view.
- **Evidence:** App.tsx renders `<BriefingCard>` for DAILY_BRIEFING detail view but does not pass onBack. BriefingCard has no back navigation.
- **Impact:** User must dismiss the briefing to return to gallery.
- **Suggested fix:** Add onBack prop to BriefingCard; render a Back button in the component.
- **Phase 11 cross-ref:** F-14

**IMP-I16: Send Email flow SENT_EDITED distinction not implemented (INTG-02)**

- **Workflow(s) affected:** Workflow 2 (Draft Editing), Workflow 4 (Outcome Tracking)
- **Issue:** Flow 4 step 8 always sets cr_cardoutcome = SENT_AS_IS (100000001). The Sprint 2 spec says to compare final text against cr_humanizeddraft to determine SENT_EDITED, but this comparison is not in the flow specification.
- **Impact:** ConfidenceCalibration Draft Quality tab shows 100% "sent as-is" regardless of editing.
- **Suggested fix:** Add a condition in Flow 4 step 8: if FinalDraftText != cr_humanizeddraft from step 2, set 100000002 (SENT_EDITED).

**IMP-I17: Cross-workflow ordering dependency -- sender profile must exist before adaptive triage (INTG-02)**

- **Workflow(s) affected:** Cross-workflow (trigger flows + adaptive triage)
- **Issue:** Sender-adaptive triage requires a sender profile to exist. The trigger flow creates/upserts sender profiles (step 11) AFTER the agent invocation (step 4). This means the first email from a new sender cannot benefit from adaptive triage because the profile does not yet exist.
- **Impact:** First-time senders always get standard triage. This is likely acceptable behavior (you cannot have intelligence on an unknown sender), but the ordering assumption should be documented.
- **Suggested fix:** Document as expected behavior. For returning senders, the profile exists from previous signals, so step 11 happening after step 4 is fine -- the profile used by the agent is from PREVIOUS signals.

**IMP-I18: Concurrent sender profile upserts have race condition (INTG-03)**

- **Workflow(s) affected:** Cross-workflow (trigger flows)
- **Issue:** If two emails from the same sender arrive simultaneously, both flow runs execute the List-Condition-Add/Update pattern concurrently. Both may find 0 existing profiles and both try to Add, resulting in a duplicate or a conflict error. The alternate key on cr_senderemail (defined in senderprofile-table.json) would prevent duplicates but would cause one flow to error.
- **Evidence:** senderprofile-table.json defines alternate key, but the flow uses List-Condition-Add/Update instead of native upsert.
- **Impact:** One flow run would fail on the sender profile upsert. Since the upsert is in a Scope with error handling, the card creation still succeeds.
- **Suggested fix:** Use the Dataverse connector's native upsert capability (if available) with the alternate key, or accept the current behavior with error handling.
- **Phase 10 cross-ref:** R-19

**IMP-I19: Orchestrator tool actions not registered in deployment guide (INTG-02)**

- **Workflow(s) affected:** Workflow 6 (Command Execution)
- **Issue:** The Orchestrator Agent prompt specifies 6 tool actions (QueryCards, QuerySenderProfile, UpdateCard, CreateCard, RefineDraft, QueryCalendar), but the deployment guide Section 2.4 only covers the main agent's research tool actions. The Orchestrator's tools require separate registration.
- **Impact:** A developer following only the deployment guide would not register the Orchestrator's tools, causing all command execution to fail with "tool not found" errors.
- **Suggested fix:** Add Orchestrator tool registration section to the deployment guide.
- **Phase 10 cross-ref:** R-18

### Validated (No Issues)

1. **Email Triage end-to-end (Workflow 1)**: All 15 steps documented and implemented correctly. Every layer transition has a defined data path.
2. **Email Send end-to-end (Workflow 3)**: Complete round-trip with ownership validation, error handling, and user feedback. Fire-and-forget with feedback loop via Canvas App notification.
3. **Outcome Tracking for SENT outcomes (Workflow 4 partial)**: SENT_AS_IS and SENT_EDITED outcomes correctly flow through Card Outcome Tracker to update sender profiles.
4. **PCF output property reset pattern**: index.ts resets all action outputs after getOutputs() to prevent stale re-fires from Canvas App.
5. **Row ownership enforcement**: All "Add a new row" actions set Owner field to authenticated user ID. RLS on UserOwned tables provides defense-in-depth.
6. **Humanizer handoff gating**: Flow correctly checks FULL tier, confidence >= 40, and not CALENDAR_SCAN before invoking Humanizer.
7. **Error Scope pattern**: All 3 trigger flows use Scope-based error handling with parallel error Scope for logging.
8. **Sender profile upsert pattern**: List-Condition-Add/Update correctly handles new and existing senders with error tolerance.
