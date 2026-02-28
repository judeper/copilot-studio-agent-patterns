# AI Council Session 2 — Implementation Logic Review

**Date:** 2026-02-27
**Subject:** Second Brain Evolution — Revised Plan (post-Session 1 modifications)
**Focus:** Implementation-level design flaws, logic errors, integration gaps, and edge cases
**Methodology:** Each council member reviews the revised plan against the actual codebase, schemas, and flow documentation to find issues that would surface during build

---

## Council Members (same panel)

| Seat | Focus for This Session |
|------|----------------------|
| **Architect** | Data flow integrity, contract mismatches between components |
| **Product** | UX logic errors, state management gaps, user journey dead ends |
| **Security** | Specific implementation vulnerabilities in the new flows and UX |
| **Platform Engineer** | Connector behavior, expression correctness, runtime failures |
| **Pragmatist** | What will actually break when you build this, day 1 issues |

---

## Round 1 — Implementation-Level Findings

---

### 🔷 ARCHITECT

**Focus: Data contract consistency across the revised plan.**

**ISSUE 1 — The Send Email flow has no source email reference to reply to.**

The council approved one-click send in Sprint 1A. But the current data model doesn't store the original email's message ID or conversation ID needed to send a *reply* vs. a *new email*. The v1.0 agent output schema has no field for the original sender's email address or the message ID to reply to.

Look at the flow: when an email arrives, the PAYLOAD Compose captures `internetMessageId` and `conversationId`. These flow through the agent and come out in the JSON output — but they're embedded inside `cr_fulljson` (the full JSON blob), not in discrete columns. The Canvas app would need to `ParseJSON()` the blob to extract the original sender email and the message ID, then pass them to the Send flow.

**The problem:** The Send Email flow needs:
- `To` (recipient email address — the original sender)
- `Subject` (with "Re: " prefix for replies)
- `Body` (the humanized draft)
- `Internet Message ID` (to thread the reply correctly in Outlook)

None of these are discrete Dataverse columns. They're buried in `cr_fulljson`.

**Fix:** Sprint 1A must add two discrete columns:
- `cr_originalsenderemail` (Text, 320) — extracted from the trigger payload's `from` field
- `cr_originalsubject` (Text, 400) — extracted from the trigger payload's `subject` field

These get populated in the existing three flows alongside the other discrete columns. The Send Email flow then reads these directly without JSON parsing. The `internetMessageId` for proper reply threading can remain in `cr_fulljson` for now — if the Send flow can't thread the reply, it sends as a new email, which is acceptable for Sprint 1A. Proper reply threading is a Sprint 2 or 3 enhancement.

For TEAMS_MESSAGE cards, the Send flow needs:
- `Channel ID` and `Team ID` (to post a reply) or `Chat ID` (for 1:1)
- `Message ID` (to thread the reply)

These are even more complex. **Recommendation:** Sprint 1A ships Send for EMAIL cards only. TEAMS_MESSAGE send is deferred to Sprint 3 where the Orchestrator Agent can handle the more complex Teams reply logic.

**ISSUE 2 — The `cr_senderprofile` primary column design is wrong.**

The roadmap specifies `cr_senderemail` as the primary column (Text, 320). But in Dataverse, the primary column has specific behavior:
- It's the column shown in lookups and forms
- It must be populated on every row (it's implicitly required)
- It's used as the display value in relationship lookups

Using email address as the primary column works functionally, but consider: Dataverse primary columns cannot be set to "unique" via the standard schema — uniqueness enforcement requires a duplicate detection rule or an alternate key. Without this, the sender upsert logic in Sprint 1B could create duplicate rows if two flows process emails from the same sender simultaneously (race condition).

**Fix:** Create an alternate key on `cr_senderemail` in the provisioning script. The Dataverse upsert action (Platform Engineer recommended this in Session 1) naturally uses alternate keys for matching. This ensures no duplicate sender profiles.

**ISSUE 3 — The Card Outcome Tracker flow has a feedback loop risk.**

The plan says: "Trigger: When a row is modified in Dataverse (cr_assistantcard table), filtered to changes on `cr_cardoutcome` column." But the flow itself updates `cr_senderprofile` and potentially recalculates `cr_avgresponsehours`, which modifies a different table. That's fine.

However, what if a future sprint adds logic that updates the card row as part of outcome processing (e.g., setting `cr_drafteditdistance` in Sprint 4, or linking to an archive)? That update would re-trigger the Card Outcome Tracker flow. Power Automate's "When a row is modified" trigger fires on ANY column change unless you configure the filter attribute correctly.

**Fix:** The trigger must use the `filteringattributes` parameter set to exactly `cr_cardoutcome`. This is available in the Dataverse "When a row is added, modified or deleted" trigger (not the older "When a record is changed" trigger). Document this explicitly in the flow specification to prevent infinite trigger loops.

---

### 🟢 PRODUCT

**Focus: User journey completeness and state edge cases.**

**ISSUE 4 — The "Confirm and Send" dialog has no cancel recovery path.**

The current `CardDetail.tsx` has two actions: "Edit & Copy Draft" and "Dismiss Card". Sprint 1A adds a "Send" button with a confirmation dialog. But consider the user journey:

1. User opens card, reads draft
2. User clicks "Send"
3. Confirmation dialog shows recipient, subject, draft body
4. User realizes the draft needs a small edit
5. User clicks... what?

There's no "Edit before sending" flow. The confirmation dialog needs three buttons, not two:
- **Confirm and Send** → sends as-is, `cr_cardoutcome = SENT_AS_IS`
- **Edit First** → closes dialog, puts draft in editable mode (the existing Textarea becomes editable), user makes changes, then can Send again → `cr_cardoutcome = SENT_EDITED`
- **Cancel** → closes dialog, returns to read-only view, no outcome change

**The current Textarea is `readOnly`.** Sprint 1A must make it conditionally editable. When the user clicks "Edit First" (or enters edit mode), the Textarea becomes editable, and a new "Send Edited" button appears.

**Fix:** Update the `CardDetail.tsx` state machine:

```
ViewState: reading → editing → confirming → sent
                  ↗            ↘
            (edit first)    (cancel → reading)
```

The component needs local state:
```typescript
type DraftState =
    | { mode: "reading" }
    | { mode: "editing"; editedText: string }
    | { mode: "confirming"; finalText: string; isEdited: boolean }
    | { mode: "sent" };
```

This is more complex than "add a Send button" but it's the right UX for a system that tracks whether the user edited.

**ISSUE 5 — ACKNOWLEDGED outcome has no clear trigger point.**

The plan says: "When the user expands a LIGHT or CALENDAR card, Patch with `cr_cardoutcome = ACKNOWLEDGED`." But expanding a card is a navigation action — the user clicks the card in the gallery and the detail view renders. Should EVERY detail view open trigger ACKNOWLEDGED? What about:

- User opens a FULL card to read the research, doesn't take action, goes back → Should this be ACKNOWLEDGED?
- User opens a card, goes back, opens it again → Should it re-acknowledge?
- User opens a card via the command bar "jump to card" → ACKNOWLEDGED?

**The issue:** ACKNOWLEDGED is conflating "I saw this" with "I've processed this and it needs no further action." These are different things for analytics purposes.

**Fix:** Remove ACKNOWLEDGED from Sprint 1A entirely. It's a premature optimization on behavioral signal. The meaningful signals are:
- SENT_AS_IS / SENT_EDITED → user acted (strong signal)
- DISMISSED → user explicitly rejected (strong signal)
- PENDING → user hasn't acted (strong signal, especially combined with age)
- EXPIRED → system expired it (Sprint 2)

You can derive "user saw this" from a `cr_lastviewedtimestamp` column (simpler — just update the timestamp on card open, no complex state to manage). But even that can wait until Sprint 4 analytics.

**Revised CardOutcome Choice Values for Sprint 1A:**

| Label | Value |
|-------|-------|
| PENDING | 100000000 |
| SENT_AS_IS | 100000001 |
| SENT_EDITED | 100000002 |
| DISMISSED | 100000003 |
| EXPIRED | 100000004 |

Five values, not six. Cleaner.

**ISSUE 6 — The "Edit & Copy Draft" action in v1.0 conflicts with the Sprint 1A "Send" action.**

Currently, `onEditDraft` navigates to a separate screen (`scrEditDraft`) where the user edits in a TextInput and copies to clipboard. Sprint 1A introduces inline editing and sending in the CardDetail view. These two flows will confuse users:

- "Edit & Copy Draft" → navigate to edit screen → copy to clipboard → manually paste in Outlook
- "Send" → confirm → sends via flow → done

Why would a user ever use "Edit & Copy Draft" if "Send" exists?

**Fix:** Sprint 1A replaces "Edit & Copy Draft" with the new edit-and-send flow entirely. The old clipboard flow becomes a fallback for edge cases (Teams messages that can't be sent yet, calendar briefings that have no send action). Rename it to "Copy to Clipboard" and make it secondary/subtle. The primary action is "Send" for EMAIL FULL cards, "Copy to Clipboard" for everything else.

---

### 🔴 SECURITY

**Focus: Specific vulnerabilities in the Send Email flow and data exposure.**

**ISSUE 7 — The Send Email flow runs under the connection owner's identity, not the user's.**

This is the same pattern flagged in v1.0 for Dataverse writes — Power Automate flows use the connection owner's authentication. But for sending email, this means the email would be sent FROM the connection owner's mailbox, not the user's mailbox.

This is a critical flaw. If a shared service account owns the Office 365 Outlook connection, all emails sent through the assistant would come from that service account, not from the user.

**Fix options:**

**Option A — User-owned connections:** Each user must create their own Office 365 Outlook connection. The Canvas app calls a flow that runs under the user's own connection. This is the correct approach for delegated identity but requires connection setup per user.

**Option B — Use the "Send email from a shared mailbox" action:** The flow uses the user's delegated permissions via the connection reference. The "Send an email (V2)" action in the Office 365 Outlook connector has a "From" parameter for shared mailboxes, but this doesn't solve the delegated identity problem.

**Option C — Use Microsoft Graph HTTP action with delegated token:** The flow gets the user's identity from `Get my profile (V2)` and uses an HTTP action to call `/me/sendMail` with the user's delegated token. This sends FROM the user's mailbox regardless of the connection owner.

**Recommended approach: Option A for simplicity, with Option C documented as the enterprise-scale alternative.** The Send flow MUST use a connection authenticated as the current user. The flow's "Run only users" setting must be configured to "Provided by run-only user" for the Outlook connection, which prompts each user to provide their own connection when they first use the app. This is standard practice for Canvas app → Power Automate flows that need delegated identity.

**This must be explicitly documented in the deployment guide.** The existing flows (EMAIL trigger, TEAMS trigger) use the flow owner's connection because they're background flows. The Send flow is user-initiated and must use the user's connection.

**ISSUE 8 — The Send confirmation dialog must show the ACTUAL recipient, not a parsed assumption.**

The Architect (Issue 1) proposed adding `cr_originalsenderemail` as a discrete column. But email "From" addresses can be formatted in various ways:
- `"Sarah Chen" <sarah.chen@contoso.com>`
- `sarah.chen@contoso.com`
- `Sarah Chen <sarah.chen@contoso.com>;John Doe <john@contoso.com>` (multiple)

The flow's Compose step captures `triggerOutputs()?['body/from']` which returns the full display string including display name. The confirmation dialog must parse this to extract just the email address for the `To` field, and display the human-readable name for the user.

**Fix:** The existing EMAIL flow should store two separate values:
- `cr_originalsenderemail` — The actual email address only (parsed from the `from` field)
- `cr_originalsenderdisplay` — The display name (for UX purposes)

Use the Office 365 Outlook trigger's structured output: `triggerOutputs()?['body/from']` returns a JSON string. In some trigger versions it's a plain string, in others it's structured as `{"name": "Sarah Chen", "address": "sarah.chen@contoso.com"}`. The flow must handle both formats. Use an expression like:

```
if(
    contains(triggerOutputs()?['body/from'], '@'),
    if(
        contains(triggerOutputs()?['body/from'], '<'),
        last(split(first(split(triggerOutputs()?['body/from'], '>')), '<')),
        triggerOutputs()?['body/from']
    ),
    triggerOutputs()?['body/sender/emailAddress/address']
)
```

> This is fragile. Test with your specific Office 365 Outlook trigger version. The V3 trigger returns `sender.emailAddress.address` as a structured property which is more reliable.

**ISSUE 9 — Scope limitation enforcement for Send.**

Session 1's Security review said: "The send action should ONLY be available for drafts the agent generated." How is this enforced?

The Canvas app's "Send" button visibility should be conditional:
```
Visible: ThisItem.'Card Status' = 'Card Status'.READY
         && ThisItem.'Triage Tier' = 'Triage Tier'.FULL
         && ThisItem.'Trigger Type' = 'Trigger Type'.EMAIL
         && !IsBlank(ThisItem.'Humanized Draft')
```

But what prevents someone from calling the Send Email flow directly (bypassing the Canvas app) with arbitrary recipient and body parameters?

**Fix:** The Send Email flow must validate its inputs:
1. The `CardId` parameter must resolve to an actual Dataverse row owned by the current user
2. The `Recipient` parameter must match the card's `cr_originalsenderemail` value (no arbitrary recipients)
3. The `Body` parameter must not be empty

Add a condition step at the top of the flow that validates all three. If validation fails, terminate with an error.

---

### 🟡 PLATFORM ENGINEER

**Focus: Connector behavior, expression correctness, and runtime constraints.**

**ISSUE 10 — The Dataverse upsert for sender profiles doesn't exist as a standard action.**

Session 1's Platform Engineer recommended: "Use a Dataverse upsert action instead of get-then-conditionally-write." This needs correction. The standard Dataverse connector in Power Automate has:
- "Add a new row"
- "Update a row"
- "Delete a row"
- "List rows"
- "Get a row by ID"

There is NO "Upsert a row" action in the standard connector. Upsert is available via:
- The Dataverse Web API (HTTP action with `PATCH` to entity set URL)
- The premium Dataverse connector's "Perform an unbound action" (requires the alternate key configured)

**Fix:** For Sprint 1B, use the two-step pattern (List rows filtered by email → condition → Add or Update) unless you want to take a dependency on the HTTP action calling the Dataverse Web API directly. The HTTP approach is cleaner but requires:
1. An alternate key on `cr_senderemail` (Architect's Issue 2 already recommends this)
2. An access token for the Web API (available from the flow's Dataverse connection or via `workflow()?['tags']?['environmentName']` + managed identity)

**Recommendation:** Use the List → Condition → Add/Update pattern for Sprint 1B. It's 3 actions instead of 1 but it's standard connector behavior with no premium/HTTP dependencies. The volume is low (one upsert per signal, not hundreds) so performance isn't a concern.

**ISSUE 11 — The Send Email flow's "Run only users" connection sharing has a Canvas app limitation.**

Issue 7 correctly identifies that the Send flow needs the user's own Outlook connection. The "Run only users" feature prompts users for their connection when they first invoke the flow from the Canvas app. However:

Canvas apps using `PowerAutomate.Run()` (the preferred integration) handle "Run only users" connections differently than apps using the legacy Power Automate control. With `PowerAutomate.Run()`:
- The user is prompted ONCE to provide their connection when the app first calls the flow
- The connection is cached for subsequent calls
- BUT: if the user's access token expires (typically 1 hour), the next call may fail silently or prompt mid-action

**Testing required:** Verify that `PowerAutomate.Run()` correctly prompts for the Outlook connection and handles token refresh. This is documented behavior but it varies by platform version.

**ISSUE 12 — The Daily Briefing Agent's pre-summarized card array (Sprint 2) needs a maximum token budget, not just a card count.**

Session 1 agreed: "Maximum 50 cards in input. If > 50 PENDING cards exist, truncate to the 50 highest-priority." But the token consumption varies dramatically by card:
- A LIGHT card with a short summary: ~50 tokens
- A FULL card with a long summary + priority + cluster ID: ~150 tokens
- 50 condensed cards × 100 tokens average = ~5,000 tokens for the card array alone

Plus the system prompt (~2,000-4,000 tokens for a well-structured briefing prompt) and the output (briefing JSON could be 2,000-3,000 tokens), you're at ~10,000 tokens total. This is well within GPT-4.1's 128K context window.

**The actual constraint is the Copilot Studio connector's input parameter size.** The "Execute Agent and wait" action passes inputs as text variables. The combined size of all input variables has a practical limit of approximately 50,000 characters (platform-dependent, not officially documented, observed in production).

50 condensed cards × ~200 characters each = ~10,000 characters. This is safe. But if someone has 200+ pending cards (it happens with disengaged users), the flow must truncate BEFORE serializing, not after.

**Fix:** The Daily Briefing Flow should:
1. Query top 50 cards by priority, then by createdon desc
2. Serialize the condensed array
3. Check the string length: `if(length(outputs('Compose_Cards_Array')) > 40000, ...truncate...)`
4. Pass to agent

This is a safety valve, not expected in normal operation.

**ISSUE 13 — The `cr_conversationclusterid` for CALENDAR_SCAN items uses a "hash of subject + organizer" but there's no hash function in Power Automate.**

Power Automate expressions don't have a built-in hash function. The roadmap says "use a hash of `subject + organizer` (normalized, lowercased)" but doesn't specify how to compute the hash.

**Options:**
- Use a `concat()` + `toLower()` as a pseudo-hash: `toLower(concat(items('Apply_to_each')?['subject'], '|', items('Apply_to_each')?['organizer/emailAddress/name']))` — This isn't a hash, it's just a normalized concatenation, but it serves the same purpose (grouping).
- Use `base64()` of the concatenated string for shorter storage.
- Use the event's `seriesMasterId` for recurring events (this correctly clusters recurring meetings).

**Fix:** Don't hash. Use the normalized concatenation for non-recurring events and `seriesMasterId` for recurring events:

```
if(
    not(empty(items('Apply_to_each')?['seriesMasterId'])),
    items('Apply_to_each')?['seriesMasterId'],
    toLower(concat(
        replace(replace(items('Apply_to_each')?['subject'], ' ', ''), '-', ''),
        '|',
        items('Apply_to_each')?['organizer/emailAddress/address']
    ))
)
```

The `seriesMasterId` approach is much better for recurring meetings (like QBRs) because it groups all instances of the same recurring meeting regardless of subject line changes.

---

### ⚫ PRAGMATIST

**Focus: What breaks on day 1, what's unnecessarily complex, what's missing.**

**ISSUE 14 — The plan doesn't specify what happens AFTER the email is sent.**

Sprint 1A adds Send. The user clicks "Confirm and Send." The flow sends the email. Then what?

- Does the card status change? (Yes — `cr_cardoutcome = SENT_AS_IS`)
- Does the card disappear from the gallery? (It shouldn't — the user might want to reference it)
- Does the UI show a success message? (It must — otherwise the user doesn't know if it sent)
- Can the user send the same card again? (They shouldn't — one send per card)
- What if the send flow fails? (The user needs an error message, and the outcome should NOT change)

**Fix:** Define the post-send state machine explicitly:

1. User clicks "Confirm and Send"
2. Show loading state ("Sending...")
3. Call the Send Email flow via `PowerAutomate.Run()`
4. **On success:**
   - Patch card: `cr_cardoutcome = SENT_AS_IS` (or SENT_EDITED), `cr_outcometimestamp = Now()`, `cr_senttimestamp = Now()`
   - Show success toast/message: "Email sent to Sarah Chen"
   - Disable the Send button (change to "Sent ✓")
   - Stay on card detail view (don't auto-navigate away)
5. **On failure:**
   - Show error message: "Failed to send. Try again or copy to clipboard."
   - Do NOT update `cr_cardoutcome` (keep PENDING)
   - Keep Send button active for retry
   - Offer "Copy to Clipboard" as fallback

The PCF component needs to handle async state: sending → success → locked, or sending → error → retry-able.

**ISSUE 15 — The `cr_senderprofile` alternate key creation is not straightforward in PAC CLI.**

The Architect (Issue 2) and Platform Engineer (Issue 10) both reference an alternate key on `cr_senderemail`. But the current `provision-environment.ps1` script creates tables and columns via the Dataverse Web API. Alternate keys require a separate API call and, importantly, alternate key creation is an async operation in Dataverse — you call the API, it returns 202 Accepted, and the key is created in the background. The script needs to poll for completion before proceeding.

**Fix:** The provisioning script should:
1. Create the `cr_senderprofile` table and columns
2. Create the alternate key via `POST /EntityDefinitions([entity_id])/Keys` 
3. Poll `GET /EntityDefinitions([entity_id])/Keys([key_id])` until `EntityKeyMetadata.EntityKeyIndexStatus` = `Active`
4. Log success

Add a 30-second timeout on the poll. If the key isn't active after 30 seconds, warn the user to check manually. Alternate key indexing can take minutes for large tables but it's instant for new empty tables.

**ISSUE 16 — Sprint 1A and 1B are presented as independent but they share a provisioning script update.**

Both sprints modify `provision-environment.ps1`. Sprint 1A adds `cr_cardoutcome`, `cr_outcometimestamp`, `cr_originalsenderemail`, `cr_originalsubject`, `cr_senttimestamp`, `cr_sentrecipient`. Sprint 1B adds `cr_conversationclusterid`, `cr_sourcesignalid`, and the entire `cr_senderprofile` table.

If Sprint 1A's script changes are deployed and then Sprint 1B's script assumes a clean environment (like the current script does), it will fail or skip existing columns.

**Fix:** The provisioning script must be idempotent. Before creating each column, check if it already exists:

```powershell
# Pseudo-logic
$existingColumns = Get-DataverseTableColumns -TableName "cr_assistantcard"
if ($existingColumns -notcontains "cr_cardoutcome") {
    Add-DataverseColumn -TableName "cr_assistantcard" -Column $cardOutcomeDefinition
}
```

This is good practice regardless of sprint splits. The v1.0 script should already be idempotent — verify this.

**ISSUE 17 — The plan never addresses what "SENT_EDITED" means for TEAMS_MESSAGE cards.**

Sprint 1A ships Send for EMAIL only (per Architect Issue 1). But the `cr_cardoutcome` Choice column includes SENT_EDITED. When TEAMS_MESSAGE send is added later (Sprint 3), the "editing" concept is different:

- Email editing: User modifies draft text in a Textarea, then sends
- Teams editing: Teams messages are typically shorter. The "edit" might be a complete rewrite. Or the user might copy, paste into Teams, and edit there (outside the app entirely).

**Fix:** Don't overthink this now. SENT_EDITED means "user modified the draft before sending through this system." For Teams messages that are sent outside the system (copied to clipboard), we can't track the outcome at all — the card stays PENDING until dismissed or expired. This is a known gap that's acceptable. Just document it.

---

## Round 2 — Cross-Validation

---

**ARCHITECT → SECURITY (on Issue 7):** Option A (user-owned connections via "Run only users") is the right call. But it creates a first-run experience problem. The first time a user opens the Canvas app and clicks Send, they'll be prompted to create an Outlook connection. This needs an onboarding flow or documentation. Add a "Setup" section to the Canvas app that detects whether the Send flow connection exists and guides the user through creating it.

**SECURITY → ARCHITECT:** Agreed. And the setup detection should happen at app launch, not at first Send click. Discovering you need to authenticate mid-action is a terrible UX.

**PLATFORM ENGINEER → PRODUCT (on Issue 4):** The three-state edit flow (reading → editing → confirming) means the Textarea needs to toggle between `readOnly` and editable. In the current `CardDetail.tsx`, the Textarea uses `readOnly` as a prop. Switching this based on component state is straightforward in React. But the Canvas app's `OnChange` handler needs to know WHICH action was taken (Send As-Is, Send Edited, or Dismiss). Currently there's one output property per action (`editDraftAction`, `dismissCardAction`). Sprint 1A needs:

- `sendDraftAction` — outputs `{cardId}:{SENT_AS_IS|SENT_EDITED}:{finalText}` when user sends
- OR separate output properties: `sendAsIsAction`, `sendEditedAction` with the card ID and final text

**Recommendation:** Use a single `sendDraftAction` output property with a JSON-encoded value. The Canvas app parses it:

```
// In ControlManifest.Input.xml
<property name="sendDraftAction" display-name-key="sendDraftAction" of-type="SingleLine.Text" usage="output" />
```

```
// Output value (set by PCF on send)
'{"cardId":"abc-123","outcome":"SENT_EDITED","finalText":"Hi Sarah,\n\nUpdated text..."}'
```

The Canvas app's `OnChange` handler parses this and calls the Send Email flow + patches Dataverse.

**PRAGMATIST → ALL (on Issue 14):** The post-send state machine I described has 5 states. The current `CardDetail.tsx` has 0 state management beyond a `ViewState` type union at the `App.tsx` level. We're adding `DraftState` (Product, Issue 4) and now async send states. This is the most complex Sprint 1A component change.

**My concern:** This is supposed to be a "3-4 day" sprint. The CardDetail refactor alone (editable draft, confirmation dialog, send flow integration, success/error states, button disabling) is 2-3 days of PCF development including testing. Add schema changes, flow modifications, provisioning updates, and Canvas app formula changes, and Sprint 1A is more realistically 5-7 days.

**Recommendation:** Either:
- Accept 5-7 days for Sprint 1A (more honest)
- OR simplify the UX: Sprint 1A has NO inline editing. The user clicks "Send" → confirmation dialog → send as-is (SENT_AS_IS only). If they want to edit, they use the existing "Edit & Copy Draft" flow and manually send from Outlook. Sprint 1B adds inline editing + SENT_EDITED tracking. This cuts Sprint 1A's PCF complexity in half.

**PRODUCT → PRAGMATIST:** I hate losing the inline editing in Sprint 1A because it means we can't capture the SENT_EDITED signal early. But you're right about the timeline. Let's do it your way — Sprint 1A is send-as-is only. But rename your sprints:

- **Sprint 1A:** Outcome tracking + Send As-Is (no editing) — ~4-5 days
- **Sprint 1B:** Clustering + Sender Profiles — ~3-4 days
- **Sprint 1C:** Inline editing + Send Edited — ~2-3 days (can overlap with Sprint 2 start)

Three sub-sprints give us more honest checkpoints.

**ARCHITECT → PRODUCT:** Three sub-sprints for what was originally one sprint is getting granular. But I take the point — honest timelines matter. I'd keep it at 1A and 1B, and fold inline editing into Sprint 2 as a parallel workstream. Sprint 2 is "~1 week" and the briefing agent prompt is the bottleneck — PCF editing work can happen in parallel.

**ALL → CONSENSUS:** Sprint 1A = outcome tracking + send-as-is only. Inline editing moves to Sprint 2 (parallel with briefing agent development).

---

**SECURITY → PLATFORM ENGINEER (on Issue 11):** The token refresh issue for "Run only users" connections is a real concern for production use. In our FSI deployments, we've seen Canvas app → Power Automate flows fail silently when the cached connection token expires, especially if the user has the app open for an extended session. The Canvas app should wrap `PowerAutomate.Run()` in an error handler that catches connection failures and prompts re-authentication.

**PLATFORM ENGINEER → SECURITY:** Canvas app `PowerAutomate.Run()` error handling is limited. If the flow fails, `PowerAutomate.Run()` returns an error record you can check with `IsError()`. But there's no way to distinguish "connection expired" from "flow runtime error" from the Canvas app's perspective. The error message is generic.

**Recommendation:** The Send flow should include a validation step early (e.g., "Get my profile V2" using the user's Outlook connection). If this step fails, the flow terminates with a specific error message ("Connection expired — please re-authenticate") that the Canvas app can detect by string matching on the error output. It's not elegant, but it's the available mechanism.

---

## Round 3 — Consolidated Findings & Resolutions

---

### CRITICAL (Must fix before building)

| # | Issue | Resolution | Sprint |
|---|-------|------------|--------|
| 1 | Send flow needs original sender email and subject as discrete columns | Add `cr_originalsenderemail` (Text 320) and `cr_originalsubject` (Text 400) to `cr_assistantcard`. Populate in all 3 existing flows. Sprint 1A sends EMAIL only; TEAMS send deferred to Sprint 3. | 1A |
| 7 | Send flow runs under connection owner's identity, not user's | Use "Run only users" with user-provided Outlook connection. Add setup detection at Canvas app launch. Document in deployment guide. | 1A |
| 8 | Sender email extraction from trigger output varies by format | Store `cr_originalsenderemail` (parsed email) and `cr_originalsenderdisplay` (display name) separately. Use V3 trigger structured output where available. | 1A |
| 9 | Send flow accepts arbitrary parameters — no server-side validation | Add validation step: CardId resolves to user's row, Recipient matches `cr_originalsenderemail`, Body not empty. | 1A |
| 14 | No post-send state machine defined | Define: sending → success (lock) or error (retry). Success disables Send, shows confirmation. Error keeps button active, offers clipboard fallback. | 1A |

### HIGH (Must fix, can be addressed during build)

| # | Issue | Resolution | Sprint |
|---|-------|------------|--------|
| 2 | `cr_senderprofile` needs alternate key for safe upsert | Create alternate key on `cr_senderemail` in provisioning script. Poll for key activation. | 1B |
| 3 | Card Outcome Tracker trigger could loop on future column updates | Use `filteringattributes` parameter set to exactly `cr_cardoutcome`. Use the "When a row is added, modified or deleted" trigger (not the legacy trigger). | 1B |
| 4 | Send confirmation dialog needs edit-before-send path | Sprint 1A: Send-as-is only. Inline editing moves to Sprint 2 parallel workstream. SENT_EDITED tracking deferred to Sprint 2. | 1A → 2 |
| 10 | Dataverse upsert doesn't exist as standard action | Use List → Condition → Add/Update pattern for Sprint 1B. Alternate key (Issue 2) enables future HTTP upsert. | 1B |
| 13 | No hash function in Power Automate for calendar cluster IDs | Use `seriesMasterId` for recurring events, normalized `toLower(concat(subject, '|', organizer_email))` for non-recurring. | 1B |
| 16 | Provisioning script must be idempotent across sprint splits | Add column-existence checks before all create operations. | 1A, 1B |

### MEDIUM (Should fix, improve quality)

| # | Issue | Resolution | Sprint |
|---|-------|------------|--------|
| 5 | ACKNOWLEDGED outcome conflates "saw" with "processed" | Remove ACKNOWLEDGED from Sprint 1A. Five outcomes only (PENDING, SENT_AS_IS, SENT_EDITED, DISMISSED, EXPIRED). Add `cr_lastviewedtimestamp` if Sprint 4 analytics need "seen" data. | 1A |
| 6 | "Edit & Copy Draft" conflicts with Send action | Sprint 1A: Show "Send" for EMAIL FULL cards with humanized draft. Show "Copy to Clipboard" for everything else. Remove "Edit & Copy Draft" label. | 1A |
| 11 | "Run only users" token refresh is unreliable in long sessions | Add early validation step in Send flow. Canvas app checks for connection errors and shows re-auth prompt. | 1A |
| 12 | Daily Briefing input needs character length safety valve | Add string length check (40,000 char limit) in Daily Briefing Flow before agent invocation. Truncate if exceeded. | 2 |
| 15 | Alternate key creation is async; provisioning script must poll | Add poll-with-timeout (30s) for key activation in provisioning script. | 1B |

### LOW (Advisory, handle when encountered)

| # | Issue | Resolution | Sprint |
|---|-------|------------|--------|
| 17 | SENT_EDITED semantics unclear for future TEAMS_MESSAGE send | Document as known gap. For Teams sends (Sprint 3), same binary: modified before send = SENT_EDITED. Messages sent outside system = not trackable. | 3 |

---

## Revised Sprint 1A Deliverables (Post-Session 2)

Based on all findings, here is the corrected Sprint 1A specification:

### Schema Changes

**New columns on `cr_assistantcard`:**

| Column | Logical Name | Type | Notes |
|--------|-------------|------|-------|
| Card Outcome | `cr_cardoutcome` | Choice (5 values) | PENDING, SENT_AS_IS, SENT_EDITED, DISMISSED, EXPIRED |
| Outcome Timestamp | `cr_outcometimestamp` | DateTime | When user acted |
| Sent Timestamp | `cr_senttimestamp` | DateTime | When email was sent (audit) |
| Sent Recipient | `cr_sentrecipient` | Text (320) | Who it was sent to (audit) |
| Original Sender Email | `cr_originalsenderemail` | Text (320) | Parsed email address of original sender |
| Original Sender Display | `cr_originalsenderdisplay` | Text (200) | Display name of original sender |
| Original Subject | `cr_originalsubject` | Text (400) | Subject line of original signal |

**Removed from Sprint 1A (moved to Sprint 1B):**
- `cr_conversationclusterid`
- `cr_sourcesignalid`
- `cr_senderprofile` table
- `cr_drafteditdistance` (deferred to Sprint 4)

**Removed entirely:**
- ACKNOWLEDGED outcome (unnecessary complexity)

### New Flow: Send Email

- Trigger: Instant (Canvas app via `PowerAutomate.Run()`)
- Connection: "Run only users" — user provides own Outlook connection
- Inputs: CardId (text), FinalDraftText (text)
- Validation: CardId resolves to user's row, recipient matches `cr_originalsenderemail`, body not empty
- Action: Send email V2 to `cr_originalsenderemail`, subject = "Re: " + `cr_originalsubject`, body = FinalDraftText
- On success: Return success indicator
- On failure: Return error message

### Existing Flow Changes

All 3 flows (EMAIL, TEAMS, CALENDAR) updated to:
- Set `cr_cardoutcome = PENDING` (100000000) on new rows
- Populate `cr_originalsenderemail`, `cr_originalsenderdisplay`, `cr_originalsubject` from trigger payload
- (EMAIL flow: parse from structured trigger output; TEAMS: from message sender; CALENDAR: from organizer)

### PCF Changes

- `CardDetail.tsx`: Add "Send" button (EMAIL FULL cards with humanized draft only). Confirmation dialog with recipient, subject, body preview. Three buttons: Send, Copy to Clipboard, Cancel.
- Send-as-is only in Sprint 1A. No inline editing.
- Post-send state: sending → success (button locks to "Sent ✓") or error (retry + clipboard fallback)
- `AppProps`: Add `onSendDraft: (cardId: string, finalText: string) => Promise<{success: boolean; error?: string}>`
- Rename "Edit & Copy Draft" to "Copy to Clipboard" (secondary action)

### Canvas App Changes

- Add `PowerAutomate.Run()` call to Send Email flow
- OnChange handler: parse `sendDraftAction` output, call flow, Patch card outcome on success
- Add startup connection check: detect if user has Outlook connection for Send flow, show setup prompt if not

### Provisioning Script Changes

- Idempotent column creation (check before add)
- Add 7 new columns to `cr_assistantcard`

### Duration: ~5-6 days (revised from 3-4)

---

## Revised Sprint 1B Deliverables (Post-Session 2)

### Schema Changes

**New columns on `cr_assistantcard`:**
- `cr_conversationclusterid` (Text 200)
- `cr_sourcesignalid` (Text 500)

**New table: `cr_senderprofile`**
- All columns as originally specified
- Alternate key on `cr_senderemail` (with polling for activation)
- UserOwned with same RLS pattern

### Flow Changes
- All 3 flows: add cluster ID and source signal ID population
- Calendar flow: use `seriesMasterId` for recurring events, normalized concat for non-recurring
- All 3 flows: add sender upsert (List → Condition → Add/Update pattern)
- New flow: Card Outcome Tracker (Dataverse trigger on `cr_cardoutcome` change, `filteringattributes` = `cr_cardoutcome`)

### Duration: ~3-4 days

---

## Revised Overall Timeline

| Sprint | Duration | Changes from Session 1 |
|--------|----------|----------------------|
| **1A — Outcome + Send** | ~5-6 days | Expanded: added 4 new columns for send/audit, connection setup, send-as-is only |
| **1B — Clustering + Profiles** | ~3-4 days | Unchanged except alternate key and idempotent provisioning |
| **2 — Briefing + Inline Edit** | ~1.5 weeks | Expanded: inline editing moved here from 1A as parallel workstream |
| **3 — Command Bar** | ~1.5 weeks | Unchanged |
| **4 — Intelligence** | ~1.5 weeks | Unchanged |

**New total: ~6-7 weeks** (expanded from 5-6 weeks due to Sprint 1A scope correction and inline editing shift to Sprint 2)

---

## Council Conclusion

Session 2 identified **17 implementation-level issues**, of which **5 are critical** (would have caused build failures or security vulnerabilities) and **6 are high** (would have required rework during build). The most significant findings:

1. **The Send Email flow was underspecified** — missing discrete columns for recipient/subject, no identity delegation solution, no input validation, and no post-send state machine. This would have been discovered on day 2 of Sprint 1A and caused a multi-day redesign.

2. **The ACKNOWLEDGED outcome was unnecessary complexity** — removing it simplifies the data model and the UX with no loss of signal.

3. **Inline editing in Sprint 1A was scope-optimistic** — moving it to Sprint 2 makes Sprint 1A shippable in a realistic timeframe while still delivering the core Send capability.

4. **The calendar cluster ID had no implementation path** — "hash" isn't a Power Automate function. The `seriesMasterId` + normalized concat solution is concrete and correct.

5. **The provisioning script must be idempotent** — obvious in hindsight, but the sprint split makes it critical.

**The plan is now implementation-ready.** All critical and high issues have concrete resolutions. The council recommends proceeding to Sprint 1A with the revised specification above.

---

*Session 2 concluded: 2026-02-27*
*Next action: Begin Sprint 1A implementation with the revised spec*
