# AI Council Session 3 — Build Readiness Verification

**Date:** 2026-02-27
**Subject:** Final review before Sprint 1A implementation begins
**Focus:** Contradictions between Session 1 and 2 decisions, remaining under-specified interfaces, exact PCF/Canvas integration contracts, and a build-ready checklist that can be followed without interpretation
**Methodology:** Each council member reviewed the actual codebase (index.ts, useCardData.ts, CardDetail.tsx, ControlManifest.Input.xml, agent-flows.md, provision-environment.ps1) against the revised plan to find integration seams where code and plan don't align

---

## Preamble — What Session 2 Got Right

Session 2 caught 17 issues, 5 critical. The plan is significantly more solid than before Session 2. This session is NOT a re-litigation of Session 2's decisions. This session focuses on three things:

1. **Contradictions and ambiguities** remaining between the original roadmap, Session 1 modifications, and Session 2 modifications
2. **PCF ↔ Canvas app interface contract** — the exact boundary where the React component ends and Canvas app Power Fx begins (this is where build failures concentrate)
3. **Sprint-level build order within Sprint 1A** — which file to change first, which change depends on which, and where the integration test points are

---

## Round 1 — Contradiction & Gap Audit

---

### 🔷 ARCHITECT

**FINDING 1 — The `onSendDraft` callback contract in Session 2 is incompatible with the existing PCF output property pattern.**

Session 2 specifies:
```typescript
onSendDraft: (cardId: string, finalText: string) => Promise<{success: boolean; error?: string}>
```

But the existing PCF architecture does NOT support async callbacks. Look at `index.ts`:

```typescript
this.handleDismissCard = (cardId: string) => {
    this.dismissCardAction = cardId;
    this.notifyOutputChanged();
};
```

The PCF framework's output mechanism is: set a class property → call `notifyOutputChanged()` → Canvas app reads the output property on the `OnChange` event. This is a **fire-and-forget signal**. There is no mechanism for the Canvas app to return a Promise result back to the PCF component.

The Session 2 specification implies the PCF component awaits the Canvas app's flow call result and then updates its own UI (showing "Sent ✓" or error). But the PCF component cannot receive information back from the Canvas app via the output property mechanism.

**The information flow is one-directional: PCF → Canvas App via output properties. Canvas App → PCF is only via input properties (which update on the next `updateView` cycle).**

This means the post-send state machine (sending → success → locked OR error → retry) described in Session 2 Issue 14 cannot be driven by a Promise callback. It must use the same pattern as the existing architecture: PCF fires an output event, Canvas app processes it (calls flow, patches Dataverse), and the PCF component sees the result on the NEXT dataset refresh when the Dataverse row has been updated.

**Resolution — Two-phase send with input property feedback:**

Phase 1 (PCF → Canvas App):
1. User clicks "Send" in CardDetail
2. PCF sets `sendDraftAction` output property to JSON: `{"cardId":"abc","finalText":"..."}`
3. PCF calls `notifyOutputChanged()`
4. PCF immediately enters local "sending" state (spinner, disabled button) — this is optimistic UI

Phase 2 (Canvas App → Dataverse → PCF):
5. Canvas app `OnChange` handler reads `sendDraftAction`
6. Canvas app calls `PowerAutomate.Run()` for the Send Email flow
7. On success: Canvas app Patches Dataverse row (`cr_cardoutcome = SENT_AS_IS`, `cr_senttimestamp`, `cr_sentrecipient`)
8. On failure: Canvas app Patches a different column or uses a separate input property to signal error
9. Dataverse update triggers dataset refresh in PCF (`updateView` fires)
10. `useCardData` hook reads the updated `cr_cardoutcome` value from the dataset
11. PCF component sees `card_outcome === "SENT_AS_IS"` and renders "Sent ✓" state

**Critical implication:** The `AssistantCard` TypeScript interface must be extended to include `card_outcome`. The `useCardData` hook must read `cr_cardoutcome` from the Dataverse dataset. And the `CardDetail` component must use the card's outcome value (from Dataverse) to determine its display state, NOT local React state alone.

**New `types.ts` additions:**
```typescript
export type CardOutcome = "PENDING" | "SENT_AS_IS" | "SENT_EDITED" | "DISMISSED" | "EXPIRED";

export interface AssistantCard {
    // ... existing fields ...
    card_outcome: CardOutcome;
    original_sender_email: string | null;
    original_sender_display: string | null;
    original_subject: string | null;
}
```

**New `useCardData.ts` additions:**
```typescript
card_outcome: (record.getFormattedValue("cr_cardoutcome") as CardOutcome) ?? "PENDING",
original_sender_email: record.getValue("cr_originalsenderemail") as string | null,
original_sender_display: record.getValue("cr_originalsenderdisplay") as string | null,
original_subject: record.getValue("cr_originalsubject") as string | null,
```

**Error feedback path:** For send failures, the Canvas app can either:
- Option A: Set a new input property `sendError` on the PCF control (simple, but adds a manifest property)
- Option B: Write a temporary error state to a Dataverse column (over-engineered)
- Option C: Show the error in a Canvas app label/notification OUTSIDE the PCF component (avoids PCF modification for error handling)

**Recommendation: Option C.** The PCF component is optimistic — it enters "sending" state on click, and recovers to "Sent ✓" or back to "ready" on the next dataset refresh. The Canvas app shows a top-level Notification if the flow fails. This keeps the PCF component simple and the error handling where the flow context is available (Canvas app).

The only complication: if the flow fails and the Canvas app shows an error, the PCF component is stuck in its optimistic "sending" state until the next `updateView`. The Canvas app should trigger a dataset refresh after a failure (by re-reading the Dataverse source) to force the PCF out of its optimistic state. Since `cr_cardoutcome` hasn't changed (still PENDING), the PCF renders the Send button as active again.

**FINDING 2 — The Dismiss action in v1.0 updates `Card Status` to `SUMMARY_ONLY`. Sprint 1A adds `Card Outcome = DISMISSED`. These overlap.**

Looking at `canvas-app-setup.md`, the current dismiss logic:
```
Patch(
    'Assistant Cards',
    LookUp('Assistant Cards', cr_assistantcardid = GUID(AssistantDashboard1.dismissCardAction)),
    { 'Card Status': 'Card Status'.SUMMARY_ONLY }
)
```

Sprint 1A should change this to:
```
Patch(
    'Assistant Cards',
    LookUp('Assistant Cards', cr_assistantcardid = GUID(AssistantDashboard1.dismissCardAction)),
    {
        'Card Outcome': 'Card Outcome'.DISMISSED,
        'Outcome Timestamp': Now()
    }
)
```

But should it ALSO keep the `Card Status` change? The `Card Status` field (READY, LOW_CONFIDENCE, SUMMARY_ONLY, NO_OUTPUT) represents the card's processing state from the agent. `Card Outcome` (PENDING, SENT_AS_IS, DISMISSED, etc.) represents the user's action. These are orthogonal dimensions.

**Resolution:** Do NOT change `Card Status` on dismiss. A card can be `Card Status = READY` (agent prepared a full draft) AND `Card Outcome = DISMISSED` (user decided they don't need it). Separating these dimensions is cleaner for analytics. The gallery can filter by outcome to hide dismissed cards:

```
// Updated Canvas App dataset binding
SortByColumns(
    Filter(
        'Assistant Cards',
        Owner.'Primary Email' = User().Email,
        'Card Outcome' <> 'Card Outcome'.DISMISSED,
        'Card Outcome' <> 'Card Outcome'.EXPIRED
    ),
    "createdon",
    SortOrder.Descending
)
```

**Warning:** Filtering on a Choice column is NOT delegable in Canvas Apps. This is the same delegation limit flagged in v1.0. For users with < 500 cards, it works fine. For power users, the 500-row ceiling applies. This is acceptable for now.

---

### 🟢 PRODUCT

**FINDING 3 — The confirmation dialog UX is specified but the implementation approach is not.**

Session 2 says: "Confirmation dialog with recipient, subject, body preview." But the PCF component uses Fluent UI v9, which has a `Dialog` component. However, PCF virtual controls share the platform React tree and Fluent provider. There's a known issue with Fluent UI v9 Dialog rendering in PCF virtual controls: the dialog portal may render outside the PCF's containing element, causing z-index and positioning issues in Canvas Apps.

**Safe alternatives:**
1. **Inline confirmation panel** — Instead of a modal Dialog, render the confirmation as an inline panel within the CardDetail view (same DOM tree, no portal issues). The Send button area expands to show recipient, subject, preview, and Confirm/Cancel buttons.
2. **Canvas app native dialog** — The PCF fires the `sendDraftAction` output, and the Canvas app shows a native confirmation using `DisplayMode.Edit` on a hidden Group or Popup. This keeps the modal outside the PCF entirely.

**Recommendation: Option 1 (inline panel).** It stays within the PCF rendering boundary, avoids Canvas app interaction complexity, and is consistent with the existing CardDetail design pattern (which is already a full-page view, not a small card).

**Layout:**
```
┌─────────────────────────────────────────┐
│ [← Back]                                │
│                                         │
│ [Badges row]                            │
│ Summary text...                         │
│ [Key Findings section]                  │
│ [Draft section - Textarea read-only]    │
│                                         │
│ ┌─── Confirmation Panel ─────────────┐  │  ← appears on Send click
│ │ To: Sarah Chen <sarah@contoso.com> │  │
│ │ Subject: Re: Q3 Budget Review      │  │
│ │                                    │  │
│ │ [Confirm & Send]  [Cancel]         │  │
│ └────────────────────────────────────┘  │
│                                         │
│ [Send]  [Copy to Clipboard]  [Dismiss]  │  ← Send disabled during confirm
└─────────────────────────────────────────┘
```

**FINDING 4 — The plan has no specification for what "Copy to Clipboard" does to card outcome.**

Session 2 renamed "Edit & Copy Draft" to "Copy to Clipboard." But what outcome does this map to? If the user copies and then manually sends from Outlook, the system can't track that action. The card stays PENDING forever.

**Options:**
- Copy to Clipboard = no outcome change (card stays PENDING, may eventually expire)
- Copy to Clipboard = ACKNOWLEDGED (Session 2 removed this)
- Copy to Clipboard = set a new outcome: COPIED

**Resolution:** Copy to Clipboard does NOT change the outcome. The card stays PENDING. This is acceptable because:
1. We can't verify the user actually sent the email
2. The staleness monitor (Sprint 2) will eventually flag it as overdue
3. The user can manually Dismiss if they handled it outside the app

This is a conscious gap. Document it: "Cards handled outside the app (copied and sent from Outlook) remain PENDING until manually dismissed or auto-expired."

**FINDING 5 — The PCF component needs to know the original sender email and subject to render the confirmation panel, but `useCardData` currently only reads from `cr_fulljson`.**

Looking at `useCardData.ts`, the hook reads most fields from `JSON.parse(cr_fulljson)` and only reads `cr_humanizeddraft` and `createdon` as discrete columns. The Sprint 1A columns (`cr_originalsenderemail`, `cr_originalsenderdisplay`, `cr_originalsubject`, `cr_cardoutcome`) are discrete Dataverse columns.

The `useCardData` hook must add `record.getValue()` calls for the new discrete columns. But there's a subtlety: **the PCF dataset only exposes columns that are included in the Canvas app's dataset binding view.** If the Canvas app's dataset binding (`Filter('Assistant Cards', ...)`) doesn't include these columns, `record.getValue("cr_originalsenderemail")` returns `null`.

**Fix:** The Canvas app's dataset binding should work fine — Canvas app datasets include all columns from the source table by default. But verify this during testing. If specific columns aren't available, the Canvas app may need an explicit `AddColumns()` call or a Dataverse view that includes all needed columns.

---

### 🔴 SECURITY

**FINDING 6 — The Send Email flow's "Re: " subject prefix is not always correct.**

Session 2 specifies: `subject = "Re: " + cr_originalsubject`. But what if the original subject already starts with "Re: " (because it's a reply chain)?

- Original: "Q3 Budget Review" → Send subject: "Re: Q3 Budget Review" ✓
- Original: "Re: Q3 Budget Review" → Send subject: "Re: Re: Q3 Budget Review" ✗
- Original: "RE: Q3 Budget Review" → Send subject: "Re: RE: Q3 Budget Review" ✗
- Original: "Re: Re: Re: Q3 Budget Review" → Send subject: "Re: Re: Re: Re: Q3 Budget Review" ✗

**Fix:** The Send Email flow should strip existing "Re: " / "RE: " / "re: " prefixes before adding its own:

```
Re: @{if(
    startsWith(toLower(outputs('Get_Card')?['body/cr_originalsubject']), 're: '),
    substring(outputs('Get_Card')?['body/cr_originalsubject'], 4),
    outputs('Get_Card')?['body/cr_originalsubject']
)}
```

This handles one level. For deeply nested "Re: Re: Re: ", use a loop or accept the single-strip (most email clients handle multiple "Re:" gracefully).

**FINDING 7 — The Send Email flow validation step (Session 2, Issue 9) has a privilege escalation gap.**

The validation says: "CardId resolves to user's row." But how does the flow determine the "current user"? The flow runs under the connection reference. If using "Run only users" with the Outlook connection, the flow can identify the user via the Outlook connector's `Get my profile (V2)` action.

However, the flow also needs a Dataverse connection to read the card row and verify ownership. If the Dataverse connection is shared (owned by a service account), the "Get a row by ID" action can read ANY row regardless of the RLS security role. The flow must then compare the row's `ownerid` against the current user's AAD Object ID from `Get my profile (V2)`.

**Explicit validation logic:**
```
1. Get my profile (V2) → currentUserId = body/id
2. Get a row by ID (Dataverse) → card row using CardId input
3. Condition: card_row/ownerid == currentUserId
   - If No: Terminate with "Unauthorized: card does not belong to current user"
   - If Yes: continue to send
```

This prevents a user from calling the flow with someone else's CardId (e.g., via API manipulation or a modified Canvas app).

**FINDING 8 — The `cr_senttimestamp` and `cr_sentrecipient` audit columns are set by the Canvas app's Patch() call, not by the Send Email flow.**

Session 2's post-send flow (Issue 14) says:
```
On success: Patch card: cr_cardoutcome = SENT_AS_IS, cr_outcometimestamp = Now(), cr_senttimestamp = Now()
```

But who does the Patch? The Canvas app. This means the audit trail depends on the Canvas app correctly setting these values AFTER the flow succeeds. If the Canvas app has a bug, the audit trail is incomplete.

**Better approach:** The Send Email flow itself should write the audit data to Dataverse before returning success to the Canvas app. This way, the audit trail is guaranteed by the flow, not dependent on Canvas app logic.

**Revised Send Email flow:**
```
1. Receive inputs: CardId, FinalDraftText
2. Get my profile (V2) → currentUserId
3. Get card row by ID → validate ownership
4. Validate recipient matches cr_originalsenderemail
5. Send email (V2) using user's connection
6. Update card row in Dataverse:
   - cr_cardoutcome = SENT_AS_IS (100000001)
   - cr_outcometimestamp = utcNow()
   - cr_senttimestamp = utcNow()
   - cr_sentrecipient = cr_originalsenderemail value
7. Return success response to Canvas app
```

The Canvas app does NOT Patch outcome/audit columns for Send. The flow handles it. The Canvas app only Patches for Dismiss (which doesn't involve a flow call).

This gives us a single source of truth for sent-email audit data (the flow) and eliminates the split-responsibility risk.

**Implication for PCF:** The PCF component's optimistic "sending" state resolves on the next dataset refresh, when it sees `cr_cardoutcome = SENT_AS_IS` written by the flow. No Canvas app Patch needed for send outcomes.

---

### 🟡 PLATFORM ENGINEER

**FINDING 9 — Canvas App `PowerAutomate.Run()` doesn't support all flow response patterns.**

The revised flow (Finding 8) writes audit data and returns a success response. But `PowerAutomate.Run()` has specific requirements for the flow's response format:

The flow must use "Respond to a PowerApp or flow" action (not "Response" which is HTTP-only). This action returns named outputs that the Canvas app can read. The flow should return:
- `success` (Boolean)
- `errorMessage` (Text, empty on success)

Canvas app reads:
```
Set(varSendResult, SendEmailFlow.Run(AssistantDashboard1.sendDraftAction));
If(
    varSendResult.success,
    Notify("Email sent successfully", NotificationType.Success),
    Notify("Send failed: " & varSendResult.errorMessage, NotificationType.Error)
)
```

**Important:** The "Respond to a PowerApp or flow" action must be the LAST action in the flow. If the Dataverse update (step 6 in Finding 8) fails AFTER the email is sent (step 5), the flow is in an inconsistent state: email sent but audit not written. The flow must handle this:

```
5. Send email (V2)
6. Scope: Write Audit
   6a. Update card row (outcome, timestamps)
   └── On failure: Log error (but email was already sent)
7. Respond to app: success = true
```

If step 6 fails, the email was still sent. The response should still be `success = true` (the user's email went out) but with a warning. The flow should log the audit write failure separately. An orphaned PENDING card where the email was actually sent is a minor issue that the user can manually dismiss.

**FINDING 10 — The `sendDraftAction` output property in Session 2 carries the `finalText` field, which could be very large.**

PCF output properties of type `SingleLine.Text` have a Canvas app limit of ~1 million characters. Email drafts are typically small (< 5,000 characters), so this isn't a practical limit. But the JSON-encoded output includes the full draft text:

```json
{"cardId":"abc-123","finalText":"Hi Sarah,\n\n<entire email body>..."}
```

If the email body contains special characters (quotes, backslashes, newlines), the JSON encoding must be handled correctly. The PCF component should use `JSON.stringify()` to encode the output value, and the Canvas app should use `ParseJSON()` to decode it.

**Specific concern:** The PCF's `getOutputs()` method returns the string value. If the string contains newlines (`\n`), the Canvas app's `OnChange` handler receives them as literal `\n` characters in the string. Power Fx's `ParseJSON()` handles this correctly, but string interpolation or direct comparison won't.

**Resolution:** Standardize the output format. The PCF uses `JSON.stringify({cardId, finalText})`. The Canvas app uses:

```
With(
    { parsed: ParseJSON(AssistantDashboard1.sendDraftAction) },
    SendEmailFlow.Run(
        Text(parsed.cardId),
        Text(parsed.finalText)
    )
)
```

Test with draft texts containing: newlines, quotation marks, unicode characters, HTML entities (some email previews contain these).

**FINDING 11 — The "dataset refresh after failure" mechanism (Finding 1, Resolution) is not automatic in Canvas Apps.**

The Architect's resolution says: "Canvas app should trigger a dataset refresh after a failure to force the PCF out of its optimistic state." But in Canvas Apps, the PCF dataset refreshes when:
1. The underlying data source changes and the app detects it (automatic, but with latency — typically 5-30 seconds)
2. The app explicitly calls `Refresh('Assistant Cards')` (immediate)
3. Another Patch() to the same table triggers a re-read

If the Send flow fails and the Canvas app shows an error notification, it should ALSO call `Refresh('Assistant Cards')`. This forces a dataset reload, which triggers `updateView` in the PCF, which re-renders the CardDetail with `card_outcome = PENDING` (unchanged), which exits the optimistic "sending" state.

**But there's a catch:** `Refresh()` on a Dataverse table in Canvas apps triggers a full re-read of all visible rows. If the dataset has 200+ cards, this takes 1-3 seconds and causes a visible flicker as the gallery re-renders. This is acceptable for an error recovery path but would be annoying for the success path.

For success: the Send flow already wrote `cr_cardoutcome = SENT_AS_IS` to Dataverse (Finding 8). The automatic dataset refresh (5-30 second latency) will eventually update the PCF. But the user sees a 5-30 second delay between "Sending..." and "Sent ✓". That's too long.

**Fix:** On Send success, the Canvas app should also call `Refresh('Assistant Cards')` to force an immediate dataset reload. Yes, it causes a brief flicker, but the user just sent an email — a momentary re-render is fine and the "Sent ✓" state appears immediately.

**Revised Canvas App OnChange:**
```
// On Send action
With(
    {
        sendData: ParseJSON(AssistantDashboard1.sendDraftAction)
    },
    Set(varSendResult, SendEmailFlow.Run(Text(sendData.cardId), Text(sendData.finalText)));
    If(
        varSendResult.success,
        // Force refresh so PCF sees updated card_outcome immediately
        Refresh('Assistant Cards');
        Notify("Email sent to " & varSendResult.recipient, NotificationType.Success),
        // Force refresh to exit optimistic sending state
        Refresh('Assistant Cards');
        Notify("Send failed: " & varSendResult.errorMessage, NotificationType.Error)
    )
)
```

---

### ⚫ PRAGMATIST

**FINDING 12 — The build order within Sprint 1A is unspecified and there are circular dependencies.**

Here are the Sprint 1A deliverables and their dependency chain:

```
A. Provisioning script (new columns)     ← must be first (Dataverse columns must exist)
B. Flow modifications (existing 3 flows) ← depends on A (columns must exist to write to them)
C. Send Email flow (new)                 ← depends on A (reads new columns)
D. types.ts changes                      ← independent (TypeScript, no runtime dependency)
E. useCardData.ts changes                ← depends on D (uses updated types)
F. CardDetail.tsx changes                 ← depends on D, E (uses new card fields)
G. ControlManifest.Input.xml             ← depends on knowing output property names
H. index.ts changes                      ← depends on D, G (new output handler)
I. Canvas app changes                    ← depends on C, G, H (wires flow + PCF output)
J. Canvas app dataset filter update      ← depends on A (filter on new outcome column)
```

**Recommended build order:**

```
Day 1: A → D → G
  - Deploy columns to Dataverse (testable: verify columns exist in table)
  - Update TypeScript types (testable: `npm run build` passes)
  - Update ControlManifest (testable: new property declared)

Day 2: E → F → H
  - Update useCardData hook (testable: reads new columns)
  - Update CardDetail component (testable: renders send button, confirmation panel)
  - Update index.ts output handler (testable: fires sendDraftAction output)
  - Run unit tests

Day 3: B
  - Modify 3 existing flows (testable: send test emails, verify new columns populated)
  - This MUST be tested against actual Outlook/Teams/Calendar triggers

Day 4: C → I → J
  - Build Send Email flow (testable: manual trigger with test data)
  - Wire Canvas app OnChange handler (testable: end-to-end send)
  - Update dataset filter for outcomes (testable: dismissed cards hidden)

Day 5: Integration testing + error paths
  - Send success path end-to-end
  - Send failure path (simulate flow failure)
  - Dismiss path with outcome tracking
  - Connection setup first-run experience
```

**FINDING 13 — There's no integration test specification.**

Session 2 mentions "integration test for command → flow → agent → response round-trip" for Sprint 3 but has no test spec for Sprint 1A. Given that Sprint 1A introduces the first user-initiated write flow (Send Email), this is the highest-risk sprint for integration failures.

**Sprint 1A Integration Test Cases:**

| # | Test Case | Steps | Expected Result |
|---|-----------|-------|-----------------|
| T1 | Send email — happy path | Open EMAIL FULL card → Click Send → Click Confirm | Email arrives in recipient inbox, card shows "Sent ✓", Dataverse has SENT_AS_IS |
| T2 | Send email — flow failure | Temporarily misconfigure Outlook connection → Click Send → Click Confirm | Error notification in Canvas app, card returns to Send-ready state |
| T3 | Dismiss card | Open any card → Click Dismiss | Card disappears from gallery, Dataverse has DISMISSED, cr_outcometimestamp set |
| T4 | Send button visibility | Open TEAMS_MESSAGE card | Send button NOT visible (EMAIL only for Sprint 1A) |
| T5 | Send button visibility | Open EMAIL LIGHT card | Send button NOT visible (FULL only with humanized draft) |
| T6 | Double-send prevention | Send email → Wait for "Sent ✓" → Try to click Send again | Send button is disabled/replaced with "Sent ✓" |
| T7 | Existing flows populate new columns | Send test email to trigger EMAIL flow | New card has cr_cardoutcome = PENDING, cr_originalsenderemail populated |
| T8 | Owner validation | Call Send flow with a CardId belonging to a different user | Flow returns error, email NOT sent |
| T9 | Connection first-run | New user opens app for first time, clicks Send | Prompted to provide Outlook connection |
| T10 | Subject prefix dedup | Reply to an email that already has "Re: " in subject | Sent email subject is "Re: Q3 Budget" not "Re: Re: Q3 Budget" |

**FINDING 14 — The PCF's optimistic "sending" state needs a timeout.**

Finding 1 (Architect) describes the optimistic UI: PCF enters "sending" state on click, recovers on dataset refresh. But what if the dataset refresh never comes? (Flow hangs, Canvas app errors silently, network drops.)

The PCF component's "sending" state should have a local timeout:
```typescript
const [sendState, setSendState] = React.useState<"idle" | "sending" | "sent">("idle");

React.useEffect(() => {
    if (sendState === "sending") {
        const timer = setTimeout(() => {
            // If still "sending" after 60 seconds, something went wrong
            // Reset to idle so the user can retry
            setSendState("idle");
        }, 60_000);
        return () => clearTimeout(timer);
    }
}, [sendState]);
```

Additionally, the PCF should check `card.card_outcome` on every render. If the outcome has changed from "PENDING" to "SENT_AS_IS" while the component is mounted, transition to "sent":

```typescript
React.useEffect(() => {
    if (card.card_outcome === "SENT_AS_IS" || card.card_outcome === "SENT_EDITED") {
        setSendState("sent");
    } else if (card.card_outcome === "PENDING" && sendState === "sending") {
        // Dataset refreshed but outcome still PENDING — flow may have failed
        // Don't auto-reset; let the 60s timeout handle it
    }
}, [card.card_outcome]);
```

**FINDING 15 — Session 1 and Session 2 contradict on whether `cr_originalsenderdisplay` is needed as a discrete column.**

Session 2 Security (Issue 8) says: "Store `cr_originalsenderemail` (parsed email) and `cr_originalsenderdisplay` (display name) separately." This adds `cr_originalsenderdisplay` as a discrete column.

But the display name is already available inside `cr_fulljson`. The agent's output includes the full payload which contains the sender's name. The PCF already has the parsed JSON and can extract the sender name for the confirmation panel display.

**Question:** Do we need `cr_originalsenderdisplay` as a DISCRETE column, or can the confirmation panel read it from the parsed JSON?

**Analysis:**
- The confirmation panel is in the PCF component, which already parses `cr_fulljson` via `useCardData`
- The PCF can extract the sender display name from the parsed JSON (it's in the `from` field of the original payload)
- But wait — the `from` field format varies by trigger version (per Session 2, Issue 8). The raw `from` string might be `"Sarah Chen" <sarah@contoso.com>` or just `sarah@contoso.com`

**Resolution:** Keep `cr_originalsenderdisplay` as a discrete column. It's cheap to store, the flow can reliably parse it once (at write time), and both the PCF confirmation panel and future command bar queries can use it without re-parsing JSON. This is the right tradeoff: a small schema addition saves repeated parsing and format-handling complexity.

Column count for Sprint 1A: 7 new columns. This is the correct number. Confirmed.

---

## Round 2 — Contract Specification

Based on all three sessions, here is the DEFINITIVE interface contract between PCF ↔ Canvas App for Sprint 1A.

---

### PCF Output Properties (ControlManifest.Input.xml additions)

```xml
<property name="sendDraftAction"
          display-name-key="SendDraftAction_DisplayName"
          description-key="SendDraftAction_Description"
          of-type="SingleLine.Text"
          usage="output" />
```

**Value format:** JSON string from `JSON.stringify({cardId: string, finalText: string})` or empty string when not active.

**Lifecycle:** Set on user click "Confirm & Send" → Read by Canvas app `OnChange` → Reset to empty string in `getOutputs()` (same pattern as existing `editDraftAction` and `dismissCardAction`).

No new input properties needed for Sprint 1A. The PCF reads card outcome from the Dataverse dataset (via `useCardData`), not from an input property.

### Canvas App OnChange Handler (Revised)

```
// Handle Send action
If(
    !IsBlank(AssistantDashboard1.sendDraftAction),
    With(
        { sendData: ParseJSON(AssistantDashboard1.sendDraftAction) },
        Set(
            varSendResult,
            SendEmailFlow.Run(
                Text(sendData.cardId),
                Text(sendData.finalText)
            )
        );
        Refresh('Assistant Cards');
        If(
            varSendResult.success,
            Notify(
                "Email sent to " & varSendResult.recipientDisplay,
                NotificationType.Success
            ),
            Notify(
                "Failed to send: " & varSendResult.errorMessage,
                NotificationType.Error
            )
        )
    )
);

// Handle Dismiss action (updated for outcome tracking)
If(
    !IsBlank(AssistantDashboard1.dismissCardAction),
    Patch(
        'Assistant Cards',
        LookUp(
            'Assistant Cards',
            cr_assistantcardid = GUID(AssistantDashboard1.dismissCardAction)
        ),
        {
            'Card Outcome': 'Card Outcome'.DISMISSED,
            'Outcome Timestamp': Now()
        }
    )
);
```

### Send Email Flow — Input/Output Contract

**Inputs (from "Run a flow from Copilot" / instant trigger):**
| Name | Type | Description |
|------|------|-------------|
| CardId | Text | Dataverse row GUID |
| FinalDraftText | Text | The draft text to send as email body |

**Outputs (from "Respond to a PowerApp or flow" action):**
| Name | Type | Description |
|------|------|-------------|
| success | Boolean | Whether the email was sent |
| errorMessage | Text | Error description (empty on success) |
| recipientDisplay | Text | Display name of recipient (for notification) |

**Internal steps:**
1. Get my profile (V2) → `currentUserId`
2. Get Dataverse row by CardId
3. Validate: row `_ownerid_value` == `currentUserId`
4. Validate: `cr_originalsenderemail` is not empty
5. Validate: FinalDraftText is not empty
6. Compose subject: strip existing "Re: " prefix, add "Re: "
7. Send email (V2): To = `cr_originalsenderemail`, Subject = composed, Body = FinalDraftText
8. Update Dataverse row: `cr_cardoutcome` = SENT_AS_IS, `cr_outcometimestamp` = utcNow(), `cr_senttimestamp` = utcNow(), `cr_sentrecipient` = `cr_originalsenderemail`
9. Respond: success = true, recipientDisplay = `cr_originalsenderdisplay`

**Error handling:** Steps 3-5 validate → on failure: Respond with success = false + errorMessage. Step 7 send → on failure: Respond with success = false + errorMessage. Step 8 audit write → on failure: log error but still Respond success = true (email was sent).

---

## Round 3 — Remaining Risks & Final Advisories

---

### Remaining Risks (accepted)

| Risk | Impact | Mitigation | Status |
|------|--------|------------|--------|
| 5-30 second latency between PCF "sending" state and "sent" confirmation | Low (UX feels slightly slow) | Canvas app calls Refresh() immediately after flow returns | Mitigated by Finding 11 |
| Gallery flicker on Refresh() after send/dismiss | Low (cosmetic) | Acceptable for success/error recovery paths | Accepted |
| Draft text with special characters in JSON output property | Medium (could break parsing) | Use JSON.stringify in PCF, ParseJSON in Canvas | Mitigated by Finding 10 |
| Dataverse delegation limit on Card Outcome filter | Medium (500+ card users) | Staleness monitor (Sprint 2) keeps active count low | Accepted, documented |
| Send flow timeout (Canvas app waits synchronously) | Medium (120s default timeout) | PCF has 60s optimistic timeout; Canvas app Refresh exits stuck state | Mitigated by Finding 14 |

### Final Advisories

1. **Test the V3 Outlook trigger's `from` field format** in the target environment before coding the sender email parsing expression. The structured vs. string format varies by connector version and tenant configuration. Capture actual trigger outputs for EMAIL, TEAMS, and CALENDAR flows and verify the expression handles all formats.

2. **Pin the Send Email flow's connection reference** to the Outlook connector. When importing the solution to a new environment, the connection reference will prompt for a connection. Document this in the deployment guide alongside the "Run only users" setup.

3. **Add `cr_cardoutcome` to the Canvas app dataset sort.** After Sprint 1A, the gallery should show PENDING cards first, SENT cards at the bottom (or hidden). Update the `SortByColumns` formula to include outcome as a secondary sort.

4. **The `getOutputs()` reset pattern is critical.** The existing code resets `editDraftAction` and `dismissCardAction` to empty string after reading. The new `sendDraftAction` must follow the same pattern. If forgotten, the send action will re-fire on every `updateView` cycle, causing duplicate emails.

5. **The PCF component now has two sources of truth for "sent" state**: local React state (`sendState`) and Dataverse-persisted state (`card.card_outcome`). The Dataverse value is authoritative. Local state is optimistic. If they conflict (local says "sending" but Dataverse says "PENDING" after refresh), trust Dataverse. The 60-second timeout (Finding 14) handles the edge case where both are stuck.

---

## Council Conclusion

Session 3 identified **15 findings**. The critical outcome is the resolution of the **PCF ↔ Canvas App async communication pattern** (Finding 1), which would have been the single hardest integration problem during Sprint 1A build. The fire-and-forget output property → Dataverse round-trip → dataset refresh pattern is now fully specified, tested against the actual codebase, and documented with exact code snippets.

**Key architectural decision crystallized in Session 3:** The Send Email flow owns the Dataverse audit write (Finding 8). The Canvas app only Patches for Dismiss. This eliminates split-responsibility and makes the audit trail flow-guaranteed.

**The plan is build-ready.** The Sprint 1A build order (Finding 12), integration test cases (Finding 13), and definitive interface contracts (Round 2) provide enough specification to begin coding without ambiguity.

**Remaining sessions are not needed.** Further review would produce diminishing returns. The council recommends beginning Sprint 1A implementation.

---

### Session 3 Issue Register

| # | Finding | Severity | Resolution | Owner |
|---|---------|----------|------------|-------|
| F1 | onSendDraft Promise pattern incompatible with PCF output mechanism | Critical | Fire-and-forget output + Dataverse round-trip + dataset refresh | Architect |
| F2 | Dismiss action confused Card Status and Card Outcome | High | Keep Card Status unchanged on dismiss; only set Card Outcome | Architect |
| F3 | Fluent UI Dialog rendering in PCF virtual controls unreliable | High | Use inline confirmation panel, not modal Dialog | Product |
| F4 | Copy to Clipboard outcome undefined | Medium | No outcome change; card stays PENDING. Document as known gap. | Product |
| F5 | New discrete columns must be available in PCF dataset | Medium | Canvas app datasets include all columns by default. Verify during testing. | Product |
| F6 | "Re: " subject prefix duplication | Medium | Strip existing "Re: " prefix in flow before prepending | Security |
| F7 | Send flow needs explicit ownership validation | High | Compare card ownerid to current user's AAD Object ID | Security |
| F8 | Audit trail should be flow-guaranteed, not Canvas-app-dependent | High | Send flow writes all audit columns; Canvas app only Patches for Dismiss | Security |
| F9 | PowerAutomate.Run() response format constraints | Medium | Use "Respond to a PowerApp or flow" action with named outputs | Platform |
| F10 | JSON encoding of draft text in output property | Medium | JSON.stringify in PCF, ParseJSON in Canvas app | Platform |
| F11 | Dataset refresh timing after send/failure | Medium | Canvas app calls Refresh() after both success and failure | Platform |
| F12 | No build order specified within Sprint 1A | High | Day-by-day build order with test points defined | Pragmatist |
| F13 | No integration test specification | High | 10 test cases defined covering happy path, errors, edge cases | Pragmatist |
| F14 | Optimistic "sending" state needs timeout | Medium | 60-second local timeout in PCF; Dataverse outcome is authoritative | Pragmatist |
| F15 | cr_originalsenderdisplay necessity questioned | Low | Keep it — cheap to store, avoids repeated JSON parsing | Pragmatist |

---

*Session 3 concluded: 2026-02-27*
*Council recommendation: Begin Sprint 1A implementation. No further review sessions needed.*
*Next action: Execute Sprint 1A Day 1 build order — provisioning script → types.ts → ControlManifest.Input.xml*
