# Canvas App Setup Guide

This guide covers creating the Canvas Power App that serves as the user-facing dashboard for the Enterprise Work Assistant.

## Prerequisites

- Power Platform environment provisioned with Dataverse
- `Assistant Cards` table created (run `scripts/provision-environment.ps1`)
- Power Apps Component Framework (PCF) component deployed (run `scripts/deploy-solution.ps1`)
- PCF for Canvas apps enabled in environment settings (must be enabled manually — see [deployment-guide.md](deployment-guide.md), Phase 1)

---

## 1. Create the Canvas App

1. Go to **make.powerapps.com** → select your environment
2. Click **+ Create** → **Blank app** → **Blank canvas app**
3. Name: `Enterprise Work Assistant`
4. Format: **Tablet** (recommended for dashboard layout)
5. Click **Create**

## 2. Add Data Source

1. In the left panel, click **Data** → **Add data**
2. Search for **Dataverse**
3. Select the **Assistant Cards** table (display name "Assistant Cards"; the entity logical name is `cr_assistantcard`)
4. Click **Connect**

> **Logical names vs. display names**: In Power Apps formulas, you can use the display name (e.g., `'Assistant Cards'`) for table references and column access. The logical names (e.g., `cr_assistantcard`, `cr_fulljson`) are used in Dataverse API calls, Power Automate expressions, and the provisioning scripts.

## 3. Create Filter Controls

Add four Dropdown controls at the top of Screen1 for filter state:

### Trigger Type Dropdown
- **Items**: `["", "EMAIL", "TEAMS_MESSAGE", "CALENDAR_SCAN"]`
- **Default**: `""`
- **Name**: `drpTriggerType`

### Priority Dropdown
- **Items**: `["", "High", "Medium", "Low"]`
- **Default**: `""`
- **Name**: `drpPriority`

### Card Status Dropdown
- **Items**: `["", "READY", "LOW_CONFIDENCE", "SUMMARY_ONLY"]`
- **Default**: `""`
- **Name**: `drpCardStatus`

### Temporal Horizon Dropdown
- **Items**: `["", "TODAY", "THIS_WEEK", "NEXT_WEEK", "BEYOND"]`
- **Default**: `""`
- **Name**: `drpTemporalHorizon`

> **Note**: The empty string `""` represents "no filter" (show all). SKIP-tier items are not written to Dataverse, so only High/Medium/Low priorities appear. Temporal horizon values (TODAY, THIS_WEEK, etc.) apply to CALENDAR_SCAN items; EMAIL and TEAMS_MESSAGE items have null temporal horizon.

## 4. Import the PCF Component

1. Click **Insert** (+ icon in left panel)
2. Scroll down to **Get more components** or click **Import component**
3. Select the **Code** tab
4. Find **AssistantDashboard** in the list
5. Click **Import**

## 5. Add the PCF Control to Screen

1. Click **Insert** → **Code components** → **AssistantDashboard**
2. Position it to fill the main area below the filter dropdowns

> **Important**: After inserting the control, check its name in the left panel's tree view. The default name is usually `AssistantDashboard1`, but if it differs (e.g., `AssistantDashboard1_1`), update all references in the formulas below to match.

### Sizing (full-screen below filters)

```
X: 0
Y: 120 (below filter bar)
Width: Parent.Width
Height: Parent.Height - 120
```

## 6. Configure Dataset Binding

Select the AssistantDashboard control and set the **cardDataset** property:

```
Filter(
    'Assistant Cards',
    Owner.'Primary Email' = User().Email
)
```

> **Note on Owner comparison**: The Owner column is a lookup type. Comparing directly with `Owner = User()` may not resolve correctly. Using `Owner.'Primary Email' = User().Email` provides a reliable string-based match. Dataverse Row-Level Security (RLS) provides an additional security layer, so even if this formula is adjusted, users only see their own rows.

To add server-side filtering (reduces data loaded):

```
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

> **Delegation warning**: Choice column comparisons (e.g., `'Card Outcome' <> ...`) are **not delegable** to Dataverse. This means the filter is applied client-side to the first 500 rows returned. For most users this is sufficient. If a user accumulates 500+ active cards, the staleness monitor (Sprint 2) will keep the count manageable by expiring old cards.

## 7. Configure Input Properties

Set the filter input properties on the AssistantDashboard control:

| Property | Value |
|----------|-------|
| filterTriggerType | `drpTriggerType.Selected.Value` |
| filterPriority | `drpPriority.Selected.Value` |
| filterCardStatus | `drpCardStatus.Selected.Value` |
| filterTemporalHorizon | `drpTemporalHorizon.Selected.Value` |

## 8. Handle Output Events

### OnChange Handler (on the AssistantDashboard control)

```
// Handle Send action — Sprint 1A: sends email via Power Automate flow
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

// Handle Copy to Clipboard action
If(
    !IsBlank(AssistantDashboard1.copyDraftAction),
    Set(varCopyCardId, AssistantDashboard1.copyDraftAction);
    Navigate(scrCopyDraft)
);

// Handle Dismiss Card action — set outcome to DISMISSED
// Uses the primary key column (cr_assistantcardid) for GUID matching
If(
    !IsBlank(AssistantDashboard1.dismissCardAction),
    Patch(
        'Assistant Cards',
        LookUp('Assistant Cards', cr_assistantcardid = GUID(AssistantDashboard1.dismissCardAction)),
        {
            'Card Outcome': 'Card Outcome'.DISMISSED,
            'Outcome Timestamp': Now()
        }
    )
);

// Sprint 2: Handle Jump to Card from briefing — select the target card
If(
    !IsBlank(AssistantDashboard1.jumpToCardAction),
    // The PCF already navigates to the card's detail view internally.
    // This handler fires the output for any Canvas-level side effects
    // (e.g., scrolling the gallery, updating a context variable).
    Set(varJumpTargetCardId, AssistantDashboard1.jumpToCardAction)
);
```

> **Sprint 1A Notes:**
> - The Send flow writes audit columns (`cr_cardoutcome`, `cr_senttimestamp`, `cr_sentrecipient`) server-side. The Canvas app does NOT Patch these for send actions.
> - The `Refresh('Assistant Cards')` call forces the PCF to re-read the dataset, updating the card's outcome badge from "PENDING" to "Sent ✓".
> - The `SendEmailFlow` must be created as an instant flow with "Run only users" configured so each user provides their own Outlook connection. See [agent-flows.md](agent-flows.md) for the flow specification.
> - For Dismiss, the Canvas app writes the outcome directly (no flow needed). The `Card Status` column is NOT changed on dismiss — Card Status and Card Outcome are orthogonal dimensions.

> **Sprint 2 Notes:**
> - **Inline editing**: The PCF CardDetail component now allows users to edit the humanized draft before sending. The `sendDraftAction` JSON includes the final (possibly edited) text. The Send Email flow receives whatever text the user confirmed — no distinction needed at the flow level.
> - **SENT_EDITED tracking**: To distinguish AS_IS from EDITED sends, the Send Email flow should be updated to compare the final text against the stored `cr_humanizeddraft` column value. If they differ, set `cr_cardoutcome = SENT_EDITED` (100000002) instead of `SENT_AS_IS`. This comparison happens server-side in the flow.
> - **Briefing cards**: DAILY_BRIEFING cards render at the top of the gallery via the BriefingCard component. The Jump to Card handler fires when users click action item links in the briefing.

> **Sprint 3 Notes:**
> - **Command bar**: The PCF CommandBar component fires `commandAction` output with JSON `{"command":"...","currentCardId":"..."}`. The Canvas app OnChange handler calls the Command Execution Flow via PowerAutomate.Run() and passes the response back.
> - **Response handling**: The flow returns `responseJson` which contains `response_text`, `card_links`, and `side_effects`. If `side_effects` is non-empty, the Canvas app should call `Refresh('Assistant Cards')` to reflect any data changes.
> - **SELF_REMINDER cards**: Created by the Orchestrator Agent via the CreateCard tool action. They appear in the dashboard like regular cards with trigger type SELF_REMINDER.

Add this handler to the OnChange block:

```
// Sprint 3: Handle Command action — invoke Orchestrator via Power Automate
If(
    !IsBlank(AssistantDashboard1.commandAction),
    With(
        { cmdData: ParseJSON(AssistantDashboard1.commandAction) },
        Set(
            varCommandResult,
            CommandExecutionFlow.Run(
                Text(cmdData.command),
                User().EntraObjectId,
                Text(cmdData.currentCardId)
            )
        );
        // Parse the response and check for side effects
        With(
            { resp: ParseJSON(varCommandResult.responsejson) },
            // If side effects occurred, refresh the dataset
            If(
                CountRows(Table(resp.side_effects)) > 0,
                Refresh('Assistant Cards')
            )
            // Note: The PCF CommandBar component manages its own response display.
            // The Canvas app stores the response for the PCF to read via an input property,
            // or the PCF can parse the commandAction output directly.
        )
    )
);
```

### Selected Card tracking

```
Set(varSelectedCardId, AssistantDashboard1.selectedCardId)
```

## 9. (Optional) Copy Draft Screen

Create a second screen `scrCopyDraft` for reviewing and copying drafts to clipboard (fallback for users who prefer to send via Outlook manually):

1. Add a **TextInput** control bound to the humanized draft
2. Add a **Copy** button that copies the draft to clipboard
3. Add a **Back** button that navigates back to Screen1

```
// On the TextInput Default property
// Uses the primary key column (cr_assistantcardid) for GUID matching
LookUp(
    'Assistant Cards',
    cr_assistantcardid = GUID(varCopyCardId)
).'Humanized Draft'
```

> **Note**: This screen is a fallback for users who want to paste drafts into Outlook, Teams, or other apps manually. For EMAIL cards, the primary action is the inline Send button in the PCF dashboard. Copy to Clipboard does NOT change the card's outcome — the card stays PENDING until manually dismissed.

## 10. (Optional) Embed Copilot Agent

To embed the Copilot Studio agent for follow-up questions:

1. Click **Insert** → **Copilot (preview)**
2. Select the "Enterprise Work Assistant" agent
3. Position below or beside the dashboard

This lets users ask follow-up questions about any card directly from the app.

---

## 11. Briefing Schedule Configuration

The Daily Briefing schedule is stored in the `Briefing Schedules` Dataverse table, allowing each user to configure when they receive their daily briefing.

### 11.1 Add Data Source

1. In the left panel, click **Data** -> **Add data**
2. Search for **Dataverse**
3. Select the **Briefing Schedules** table
4. Click **Connect**

### 11.2 Add Schedule Configuration Controls

Create a new screen or panel (e.g., `scrSettings`) for schedule configuration:

**Schedule Hour Dropdown**
- **Name**: `drpBriefingHour`
- **Items**: `Sequence(24, 0)` *(generates 0-23)*
- **Default**: `7`
- **DisplayMode**: `DisplayMode.Edit`

**Schedule Minute Dropdown**
- **Name**: `drpBriefingMinute`
- **Items**: `[0, 15, 30, 45]`
- **Default**: `0`

**Schedule Days Checkboxes**

Add seven Checkbox controls, one per day:
- **Names**: `chkMon`, `chkTue`, `chkWed`, `chkThu`, `chkFri`, `chkSat`, `chkSun`
- **Default (weekdays)**: `chkMon.Default = true`, ..., `chkFri.Default = true`, `chkSat.Default = false`, `chkSun.Default = false`

**Timezone Dropdown**
- **Name**: `drpTimezone`
- **Items**: `["America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles", "Europe/London", "Europe/Paris", "Europe/Berlin", "Asia/Tokyo", "Asia/Shanghai", "Australia/Sydney"]`
- **Default**: `"America/New_York"`

> **Tip**: Customize the timezone list for your organization's locations. The full IANA timezone list is available at [Wikipedia: List of tz database time zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones).

**Enabled Toggle**
- **Name**: `tglBriefingEnabled`
- **Default**: `true`

**Save Button**
- **Name**: `btnSaveBriefingSchedule`
- **Text**: `"Save Schedule"`
- **OnSelect**:

```
// On screen load, check for existing schedule (see 11.3 below)
// Use upsert pattern to create or update
Patch(
    'Briefing Schedules',
    If(
        IsBlank(varMySchedule),
        Defaults('Briefing Schedules'),
        varMySchedule
    ),
    {
        'User Display Name': User().FullName,
        'Schedule Hour': drpBriefingHour.Selected.Value,
        'Schedule Minute': drpBriefingMinute.Selected.Value,
        'Schedule Days': Concat(
            Filter(
                Table(
                    {day: "Monday", checked: chkMon.Value},
                    {day: "Tuesday", checked: chkTue.Value},
                    {day: "Wednesday", checked: chkWed.Value},
                    {day: "Thursday", checked: chkThu.Value},
                    {day: "Friday", checked: chkFri.Value},
                    {day: "Saturday", checked: chkSat.Value},
                    {day: "Sunday", checked: chkSun.Value}
                ),
                checked
            ),
            day,
            ","
        ),
        'Time Zone': drpTimezone.Selected.Value,
        'Is Enabled': tglBriefingEnabled.Value,
        Owner: LookUp(Users, 'Primary Email' = User().Email)
    }
);
// Refresh the local variable after save
Set(
    varMySchedule,
    LookUp(
        'Briefing Schedules',
        Owner.'Primary Email' = User().Email
    )
);
Notify("Briefing schedule saved", NotificationType.Success)
```

> **Note**: The `Patch` with `Defaults()` creates a new row. When `varMySchedule` has an existing row, `Patch` updates it instead. This upsert pattern ensures one row per user.

### 11.3 Load Existing Schedule on Screen Load

Set the `OnVisible` property of the settings screen:

```
Set(
    varMySchedule,
    LookUp(
        'Briefing Schedules',
        Owner.'Primary Email' = User().Email
    )
);

// Pre-populate controls if schedule exists
If(
    !IsBlank(varMySchedule),
    UpdateContext({
        locHour: varMySchedule.'Schedule Hour',
        locMinute: varMySchedule.'Schedule Minute',
        locTimezone: varMySchedule.'Time Zone',
        locEnabled: varMySchedule.'Is Enabled'
    })
)
```

Set each dropdown's `Default` to the loaded value (e.g., `drpBriefingHour.Default = If(!IsBlank(varMySchedule), varMySchedule.'Schedule Hour', 7)`).

For the day checkboxes, parse the comma-separated string:
```
chkMon.Default = If(!IsBlank(varMySchedule), "Monday" in varMySchedule.'Schedule Days', true)
chkTue.Default = If(!IsBlank(varMySchedule), "Tuesday" in varMySchedule.'Schedule Days', true)
// ... repeat for each day
```

---

## Testing Checklist

### v1.0 Core Functionality
- [ ] App loads and connects to Dataverse
- [ ] Filter dropdowns filter the card gallery
- [ ] Clicking a card shows the detail view
- [ ] Back button returns to gallery
- [ ] Copy to Clipboard navigates to edit screen
- [ ] Cards display correct priority colors (red/amber/green)
- [ ] Low confidence cards show warning message bar
- [ ] Sources render as clickable links
- [ ] Meeting briefings display as formatted text

### Sprint 1A — Outcome Tracking & Send
- [ ] **T1** Send email happy path: Open EMAIL FULL card → Send → Confirm → Email arrives, card shows "Sent ✓", Dataverse has SENT_AS_IS
- [ ] **T2** Send failure: Misconfigure Outlook connection → Send → Confirm → Error notification, card returns to Send-ready state
- [ ] **T3** Dismiss card: Open any card → Dismiss → Card hidden from gallery, Dataverse has DISMISSED + timestamp
- [ ] **T4** Send button hidden for TEAMS_MESSAGE cards
- [ ] **T5** Send button hidden for EMAIL LIGHT cards (no humanized draft)
- [ ] **T6** Double-send prevention: After successful send, Send button replaced with disabled "Sent ✓"
- [ ] **T7** New columns populated: Send test email to trigger EMAIL flow → New card has cr_cardoutcome = PENDING, cr_originalsenderemail populated
- [ ] **T8** Ownership validation: Call Send flow with CardId belonging to different user → Flow returns error, no email sent
- [ ] **T9** Connection first-run: New user opens app, clicks Send → Prompted for Outlook connection
- [ ] **T10** Subject dedup: Reply to "Re: Q3 Budget" → Sent email subject is "Re: Q3 Budget" not "Re: Re: Q3 Budget"
