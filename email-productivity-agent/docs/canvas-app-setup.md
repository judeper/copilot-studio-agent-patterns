# Canvas App Setup Guide — Email Productivity Agent

This guide covers building and publishing the 5-screen Email Productivity Agent app. The app gives users full control over nudge settings, priority contacts, holiday calendars, follow-up history, and analytics. After publishing, sync the generated source files back into the repo for review.

## Prerequisites

- Power Platform environment provisioned with Dataverse
- `cr_nudgeconfiguration`, `cr_followuptracking`, `cr_snoozedconversation`, `cr_prioritycontacts`, `cr_holidaycalendars`, and `cr_nudgeanalyticses` tables created
- Power Apps Premium licensing for pilot users
- PAC CLI installed for source sync
- Office 365 Users connector available in the app

## Source-Control Strategy

Power Apps supports pro-code workflows, but the supported source-controlled output is the generated `Src\*.pa.yaml` content created by Power Apps / PAC CLI. Build the app in Power Apps Studio, publish it, then sync the generated source files back into the repo with `scripts\sync-settings-canvas-app-source.ps1`.

> Only `Src\*.pa.yaml` files are intended for source review. Do not treat unpacked JSON/editor metadata as stable source files.

## 1. Create the Canvas App

1. Go to **make.powerapps.com**
2. Select the Email Productivity Agent environment
3. Click **Create** > **Blank app** > **Blank canvas app**
4. Name the app **Email Productivity Agent**
5. Choose **Tablet** layout

## 2. Add Data Sources

Add these data sources:

- **Dataverse**
  - `Nudge Configurations`
  - `Follow-Up Tracking`
  - `Snoozed Conversations`
  - `Priority Contacts`
  - `Holiday Calendars`
  - `Nudge Analytics`
- **Office 365 Users**

> **Column display names:** The formulas throughout this guide reference Dataverse columns by their **display names** (e.g., `'Internal Follow-Up Days'` for logical column `cr_internaldays`). These display names are set during table provisioning by `provision-environment.ps1`. If your environment uses different display names, update the formulas accordingly. The key mappings are:
>
> | Display Name | Logical Name |
> |---|---|
> | `Owner User ID` | `cr_owneruserid` |
> | `Internal Follow-Up Days` | `cr_internaldays` |
> | `External Follow-Up Days` | `cr_externaldays` |
> | `Priority Follow-Up Days` | `cr_prioritydays` |
> | `General Follow-Up Days` | `cr_generaldays` |
> | `Nudges Enabled` | `cr_nudgesenabled` |
> | `Digest Mode` | `cr_digestmode` |
> | `Default Snooze Hours` | `cr_defaultsnoozehours` |
> | `Skip Holiday Nudges` | `cr_skipholidaynudges` |
> | `Config Label` | `cr_configlabel` |
> | `Contact Email` | `cr_contactemail` |
> | `Contact Name` | `cr_contactname` |
> | `Holiday Date` | `cr_holidaydate` |
> | `Holiday Name` | `cr_holidayname` |
> | `Organization Wide` | `cr_isorgwide` |
> | `Period Label` | `cr_periodlabel` |
> | `Total Tracked` | `cr_totaltracked` |
> | `Total Replied` | `cr_totalreplied` |
> | `Total Nudged` | `cr_totalnudged` |
> | `Total Dismissed` | `cr_totaldismissed` |
> | `Average Reply Days` | `cr_avgreplydays` |

## 3. Tab Navigation Component

Create five screens: `scrSettings`, `scrPriorityContacts`, `scrHolidayCalendar`, `scrNudgeHistory`, `scrAnalytics`.

On each screen, add a horizontal container or button row at the top that serves as the tab bar. The tab bar contains five buttons with identical layout across all screens:

| Button | Text | OnSelect |
|---|---|---|
| `btnTabSettings` | `"Settings"` | `Navigate(scrSettings, ScreenTransition.None)` |
| `btnTabContacts` | `"Priority Contacts"` | `Navigate(scrPriorityContacts, ScreenTransition.None)` |
| `btnTabHolidays` | `"Holiday Calendar"` | `Navigate(scrHolidayCalendar, ScreenTransition.None)` |
| `btnTabHistory` | `"Nudge History"` | `Navigate(scrNudgeHistory, ScreenTransition.None)` |
| `btnTabAnalytics` | `"Analytics"` | `Navigate(scrAnalytics, ScreenTransition.None)` |

Highlight the active tab with conditional formatting. On each button, set:

```powerfx
// Fill (active tab highlight) — example for btnTabSettings on scrSettings
Fill = If(App.ActiveScreen = scrSettings, RGBA(0, 120, 212, 1), RGBA(240, 240, 240, 1))

// Color (text)
Color = If(App.ActiveScreen = scrSettings, White, RGBA(50, 50, 50, 1))
```

Replace `scrSettings` with the corresponding screen for each tab on each screen. Copy the entire tab bar across all five screens. The `App.ActiveScreen` comparison ensures the correct tab is highlighted regardless of which screen the bar lives on.

## 4. App Initialization Formula

Set the app's **OnStart** formula:

```powerfx
Set(varCurrentUserId, Office365Users.MyProfileV2().id);
Set(
    varDefaultConfig,
    {
        InternalDays: 3,
        ExternalDays: 5,
        PriorityDays: 1,
        GeneralDays: 7,
        NudgesEnabled: true,
        DigestMode: false,
        DefaultSnoozeHours: 48,
        SkipHolidayNudges: true
    }
);
Set(
    varConfigRecord,
    LookUp('Nudge Configurations', 'Owner User ID' = varCurrentUserId)
);
If(
    IsBlank(varConfigRecord),
    Set(
        varConfigRecord,
        Patch(
            'Nudge Configurations',
            Defaults('Nudge Configurations'),
            {
                'Config Label': User().FullName & " Nudge Config",
                'Owner User ID': varCurrentUserId,
                'Internal Follow-Up Days': varDefaultConfig.InternalDays,
                'External Follow-Up Days': varDefaultConfig.ExternalDays,
                'Priority Follow-Up Days': varDefaultConfig.PriorityDays,
                'General Follow-Up Days': varDefaultConfig.GeneralDays,
                'Nudges Enabled': varDefaultConfig.NudgesEnabled,
                'Digest Mode': varDefaultConfig.DigestMode,
                'Default Snooze Hours': varDefaultConfig.DefaultSnoozeHours,
                'Skip Holiday Nudges': varDefaultConfig.SkipHolidayNudges
            }
        )
    )
);
```

After saving the app formula, select **App** > **Run OnStart** once in Studio.

## 5. Screen: Settings (scrSettings)

### Controls

Create the following controls on `scrSettings`:

| Control | Name | Purpose |
|---|---|---|
| Label | `lblTitle` | Screen title: "Nudge Settings" |
| Text input | `txtInternalDays` | Internal follow-up days |
| Text input | `txtExternalDays` | External follow-up days |
| Text input | `txtPriorityDays` | Priority follow-up days |
| Text input | `txtGeneralDays` | General follow-up days |
| Toggle | `tglNudgesEnabled` | Master enable/disable |
| Toggle | `tglDigestMode` | Deliver nudges as daily digest |
| Text input | `txtDefaultSnoozeHours` | Default snooze duration (hours) |
| Toggle | `tglSkipHolidayNudges` | Skip nudges on holidays |
| Button | `btnSave` | Save changes |
| Button | `btnRestoreDefaults` | Restore default settings |
| Button | `btnReload` | Reload Dataverse values |
| Label | `lblFollowUpCount` | Count of pending follow-ups |
| Label | `lblSnoozedCount` | Count of active snoozed conversations |

Set each numeric text input's **Format** to **Number**.

### Control Defaults

#### Text inputs

```powerfx
// txtInternalDays.Default
Text(Coalesce(varConfigRecord.'Internal Follow-Up Days', varDefaultConfig.InternalDays))

// txtExternalDays.Default
Text(Coalesce(varConfigRecord.'External Follow-Up Days', varDefaultConfig.ExternalDays))

// txtPriorityDays.Default
Text(Coalesce(varConfigRecord.'Priority Follow-Up Days', varDefaultConfig.PriorityDays))

// txtGeneralDays.Default
Text(Coalesce(varConfigRecord.'General Follow-Up Days', varDefaultConfig.GeneralDays))

// txtDefaultSnoozeHours.Default
Text(Coalesce(varConfigRecord.'Default Snooze Hours', varDefaultConfig.DefaultSnoozeHours))
```

#### Toggles

```powerfx
// tglNudgesEnabled.Default
Coalesce(varConfigRecord.'Nudges Enabled', varDefaultConfig.NudgesEnabled)

// tglDigestMode.Default
Coalesce(varConfigRecord.'Digest Mode', varDefaultConfig.DigestMode)

// tglSkipHolidayNudges.Default
Coalesce(varConfigRecord.'Skip Holiday Nudges', varDefaultConfig.SkipHolidayNudges)
```

#### Summary labels

```powerfx
// lblFollowUpCount.Text
"Pending follow-ups: " &
CountRows(
    Filter(
        'Follow-Up Tracking',
        Owner = LookUp(Users, 'Azure AD Object ID' = varCurrentUserId),
        'Response Received' = false,
        'Dismissed By User' = false
    )
)

// lblSnoozedCount.Text
"Active snoozes: " &
CountRows(
    Filter(
        'Snoozed Conversations',
        Owner = LookUp(Users, 'Azure AD Object ID' = varCurrentUserId),
        'Unsnoozed By Agent' = false
    )
)
```

### Save Button

Set `btnSave.OnSelect`:

```powerfx
Set(
    varConfigRecord,
    Patch(
        'Nudge Configurations',
        varConfigRecord,
        {
            'Internal Follow-Up Days': Max(1, Min(30, IfError(Value(txtInternalDays.Text), varDefaultConfig.InternalDays))),
            'External Follow-Up Days': Max(1, Min(30, IfError(Value(txtExternalDays.Text), varDefaultConfig.ExternalDays))),
            'Priority Follow-Up Days': Max(1, Min(30, IfError(Value(txtPriorityDays.Text), varDefaultConfig.PriorityDays))),
            'General Follow-Up Days': Max(1, Min(30, IfError(Value(txtGeneralDays.Text), varDefaultConfig.GeneralDays))),
            'Nudges Enabled': tglNudgesEnabled.Value,
            'Digest Mode': tglDigestMode.Value,
            'Default Snooze Hours': Max(1, Min(720, IfError(Value(txtDefaultSnoozeHours.Text), varDefaultConfig.DefaultSnoozeHours))),
            'Skip Holiday Nudges': tglSkipHolidayNudges.Value
        }
    )
);
Refresh('Nudge Configurations');
Set(
    varConfigRecord,
    LookUp('Nudge Configurations', 'Owner User ID' = varCurrentUserId)
);
Notify("Settings saved.", NotificationType.Success);
```

### Restore Defaults Button

Set `btnRestoreDefaults.OnSelect`:

```powerfx
Set(
    varConfigRecord,
    Patch(
        'Nudge Configurations',
        varConfigRecord,
        {
            'Internal Follow-Up Days': varDefaultConfig.InternalDays,
            'External Follow-Up Days': varDefaultConfig.ExternalDays,
            'Priority Follow-Up Days': varDefaultConfig.PriorityDays,
            'General Follow-Up Days': varDefaultConfig.GeneralDays,
            'Nudges Enabled': varDefaultConfig.NudgesEnabled,
            'Digest Mode': varDefaultConfig.DigestMode,
            'Default Snooze Hours': varDefaultConfig.DefaultSnoozeHours,
            'Skip Holiday Nudges': varDefaultConfig.SkipHolidayNudges
        }
    )
);
Reset(txtInternalDays);
Reset(txtExternalDays);
Reset(txtPriorityDays);
Reset(txtGeneralDays);
Reset(tglNudgesEnabled);
Reset(tglDigestMode);
Reset(txtDefaultSnoozeHours);
Reset(tglSkipHolidayNudges);
Notify("Defaults restored.", NotificationType.Success);
```

### Reload Button

Set `btnReload.OnSelect`:

```powerfx
Refresh('Nudge Configurations');
Set(
    varConfigRecord,
    LookUp('Nudge Configurations', 'Owner User ID' = varCurrentUserId)
);
Reset(txtInternalDays);
Reset(txtExternalDays);
Reset(txtPriorityDays);
Reset(txtGeneralDays);
Reset(tglNudgesEnabled);
Reset(tglDigestMode);
Reset(txtDefaultSnoozeHours);
Reset(tglSkipHolidayNudges);
Notify("Latest settings loaded.", NotificationType.Information);
```

## 6. Screen: Priority Contacts (scrPriorityContacts)

### Controls

| Control | Name | Purpose |
|---|---|---|
| Label | `lblContactsTitle` | Screen title: "Priority Contacts" |
| Label | `lblContactCount` | Contact count display |
| Gallery | `galContacts` | List of priority contacts |
| Text input | `txtNewContactEmail` | New contact email (required) |
| Text input | `txtNewContactName` | New contact name (optional) |
| Text input | `txtNewContactNotes` | Notes (optional) |
| Button | `btnAddContact` | Add contact |

### Gallery

Set `galContacts.Items`:

```powerfx
Filter('Priority Contacts', 'Owner User ID' = varCurrentUserId)
```

Gallery template layout (three labels per row):

```powerfx
// lblGalContactEmail.Text (bold, primary)
ThisItem.'Contact Email'

// lblGalContactName.Text (subtle, secondary)
Coalesce(ThisItem.'Contact Name', "")

// lblGalContactNotes.Text (subtle, italic)
Coalesce(ThisItem.Notes, "")
```

Add a trash icon (`icoDeleteContact`) inside the gallery template:

```powerfx
// icoDeleteContact.OnSelect
Remove('Priority Contacts', ThisItem);
Notify("Contact removed.", NotificationType.Success);
```

### Contact Count Label

```powerfx
// lblContactCount.Text
CountRows(galContacts.AllItems) & " priority contacts"
```

### Add Contact Button

Set `btnAddContact.OnSelect`:

```powerfx
If(
    IsBlank(txtNewContactEmail.Text),
    Notify("Email address is required.", NotificationType.Error),
    Patch(
        'Priority Contacts',
        Defaults('Priority Contacts'),
        {
            'Contact Email': Lower(txtNewContactEmail.Text),
            'Contact Name': txtNewContactName.Text,
            'Owner User ID': varCurrentUserId,
            Notes: txtNewContactNotes.Text
        }
    );
    Reset(txtNewContactEmail);
    Reset(txtNewContactName);
    Reset(txtNewContactNotes);
    Notify("Contact added.", NotificationType.Success)
);
```

Set `btnAddContact.DisplayMode`:

```powerfx
If(IsBlank(txtNewContactEmail.Text), DisplayMode.Disabled, DisplayMode.Edit)
```

## 7. Screen: Holiday Calendar (scrHolidayCalendar)

### Controls

| Control | Name | Purpose |
|---|---|---|
| Label | `lblHolidayTitle` | Screen title: "Holiday Calendar" |
| Gallery | `galHolidays` | List of holidays |
| DatePicker | `dpkHolidayDate` | New holiday date |
| Text input | `txtHolidayName` | New holiday name (required) |
| Button | `btnAddHoliday` | Add holiday |
| Button | `btnImportUSHolidays` | Bulk-import US Federal Holidays |

### Gallery

Set `galHolidays.Items`:

```powerfx
SortByColumns(
    Filter(
        'Holiday Calendars',
        'Owner User ID' = varCurrentUserId Or 'Organization Wide' = true
    ),
    "cr_holidaydate",
    SortOrder.Ascending
)
```

Gallery template layout:

```powerfx
// lblGalHolidayDate.Text
Text(ThisItem.'Holiday Date', "yyyy-mm-dd")

// lblGalHolidayName.Text
ThisItem.'Holiday Name'

// lblGalOrgBadge.Text (visible only for org-wide holidays)
"ORG-WIDE"

// lblGalOrgBadge.Visible
ThisItem.'Organization Wide'
```

Add a trash icon (`icoDeleteHoliday`) inside the gallery template. Users can only delete their own holidays, not org-wide entries created by others:

```powerfx
// icoDeleteHoliday.Visible
ThisItem.'Owner User ID' = varCurrentUserId

// icoDeleteHoliday.OnSelect
Remove('Holiday Calendars', ThisItem);
Notify("Holiday removed.", NotificationType.Success);
```

### Add Holiday Button

Set `btnAddHoliday.OnSelect`:

```powerfx
If(
    IsBlank(txtHolidayName.Text),
    Notify("Holiday name is required.", NotificationType.Error),
    Patch(
        'Holiday Calendars',
        Defaults('Holiday Calendars'),
        {
            'Holiday Date': dpkHolidayDate.SelectedDate,
            'Holiday Name': txtHolidayName.Text,
            'Owner User ID': varCurrentUserId,
            'Organization Wide': false
        }
    );
    Reset(dpkHolidayDate);
    Reset(txtHolidayName);
    Notify("Holiday added.", NotificationType.Success)
);
```

Set `btnAddHoliday.DisplayMode`:

```powerfx
If(IsBlank(txtHolidayName.Text), DisplayMode.Disabled, DisplayMode.Edit)
```

### Bulk Import: US Federal Holidays

Set `btnImportUSHolidays.OnSelect`. This creates the standard US Federal Holidays for the current calendar year. The `ForAll` + `Patch` pattern creates all rows in a single pass:

```powerfx
ForAll(
    Table(
        { HolidayDate: Date(Year(Today()), 1, 1), HolidayName: "New Year's Day" },
        { HolidayDate: Date(Year(Today()), 1, 20), HolidayName: "Martin Luther King Jr. Day" },
        { HolidayDate: Date(Year(Today()), 2, 17), HolidayName: "Presidents' Day" },
        { HolidayDate: Date(Year(Today()), 5, 26), HolidayName: "Memorial Day" },
        { HolidayDate: Date(Year(Today()), 6, 19), HolidayName: "Juneteenth" },
        { HolidayDate: Date(Year(Today()), 7, 4), HolidayName: "Independence Day" },
        { HolidayDate: Date(Year(Today()), 9, 1), HolidayName: "Labor Day" },
        { HolidayDate: Date(Year(Today()), 10, 13), HolidayName: "Columbus Day" },
        { HolidayDate: Date(Year(Today()), 11, 11), HolidayName: "Veterans Day" },
        { HolidayDate: Date(Year(Today()), 11, 27), HolidayName: "Thanksgiving Day" },
        { HolidayDate: Date(Year(Today()), 12, 25), HolidayName: "Christmas Day" }
    ),
    Patch(
        'Holiday Calendars',
        Defaults('Holiday Calendars'),
        {
            'Holiday Date': HolidayDate,
            'Holiday Name': HolidayName,
            'Owner User ID': varCurrentUserId,
            'Organization Wide': false
        }
    )
);
Notify("US Federal Holidays imported for " & Text(Year(Today())), NotificationType.Success);
```

> **Note:** Some US Federal Holidays fall on variable dates (e.g., third Monday of January). The dates above are approximate fixed dates. For exact date calculation in Power Fx, you would need additional logic to compute "Nth weekday of month." Adjust the hardcoded dates each year or replace with computed values as needed.

## 8. Screen: Nudge History (scrNudgeHistory)

### Controls

| Control | Name | Purpose |
|---|---|---|
| Label | `lblHistoryTitle` | Screen title: "Nudge History" |
| Label | `lblHistoryCount` | "Showing X of Y follow-ups" |
| Dropdown | `drpStatusFilter` | Status filter |
| Gallery | `galHistory` | Follow-up tracking list |

### Status Filter

Set `drpStatusFilter.Items`:

```powerfx
["All", "Pending", "Nudged", "Replied", "Dismissed"]
```

### Gallery

Set `galHistory.Items`:

```powerfx
Sort(
    Filter(
        'Follow-Up Tracking',
        Owner = LookUp(Users, 'Azure AD Object ID' = varCurrentUserId),
        // Status filter logic
        drpStatusFilter.Selected.Value = "All"
        Or (drpStatusFilter.Selected.Value = "Pending"
            And 'Response Received' = false
            And 'Nudge Sent' = false
            And 'Dismissed By User' = false)
        Or (drpStatusFilter.Selected.Value = "Nudged"
            And 'Nudge Sent' = true
            And 'Response Received' = false
            And 'Dismissed By User' = false)
        Or (drpStatusFilter.Selected.Value = "Replied"
            And 'Response Received' = true)
        Or (drpStatusFilter.Selected.Value = "Dismissed"
            And 'Dismissed By User' = true)
    ),
    'Follow-Up Date',
    SortOrder.Descending
)
```

Gallery template layout:

```powerfx
// lblGalSubject.Text (bold, primary)
ThisItem.'Original Subject'

// lblGalRecipient.Text (secondary)
ThisItem.'Recipient Email'

// lblGalSentDate.Text
"Sent: " & Text(ThisItem.'Sent Date Time', "mmm dd, yyyy")

// lblGalDaysWaiting.Text
If(
    ThisItem.'Response Received' Or ThisItem.'Dismissed By User',
    "",
    Text(
        DateDiff(ThisItem.'Sent Date Time', Now(), TimeUnit.Days)
    ) & " days waiting"
)
```

### Status Badge

Add a label (`lblGalStatusBadge`) inside the gallery template for the color-coded status badge:

```powerfx
// lblGalStatusBadge.Text
If(
    ThisItem.'Response Received',
    "Replied",
    If(
        ThisItem.'Dismissed By User',
        "Dismissed",
        If(
            ThisItem.'Nudge Sent' And Not(ThisItem.'Response Received'),
            "Nudged",
            "Pending"
        )
    )
)

// lblGalStatusBadge.Fill
If(
    ThisItem.'Response Received',
    RGBA(16, 124, 16, 0.15),
    If(
        ThisItem.'Dismissed By User',
        RGBA(128, 128, 128, 0.15),
        If(
            ThisItem.'Nudge Sent',
            RGBA(255, 185, 0, 0.15),
            RGBA(0, 120, 212, 0.15)
        )
    )
)

// lblGalStatusBadge.Color
If(
    ThisItem.'Response Received',
    RGBA(16, 124, 16, 1),
    If(
        ThisItem.'Dismissed By User',
        RGBA(100, 100, 100, 1),
        If(
            ThisItem.'Nudge Sent',
            RGBA(170, 120, 0, 1),
            RGBA(0, 120, 212, 1)
        )
    )
)
```

### Count Label

```powerfx
// lblHistoryCount.Text
"Showing " & CountRows(galHistory.AllItems) & " of " &
CountRows(
    Filter(
        'Follow-Up Tracking',
        Owner = LookUp(Users, 'Azure AD Object ID' = varCurrentUserId)
    )
) & " follow-ups"
```

## 9. Screen: Analytics (scrAnalytics)

### OnVisible

Set `scrAnalytics.OnVisible` to load the most recent analytics row for the current user:

```powerfx
Set(
    varLatestAnalytics,
    First(
        Sort(
            Filter(
                'Nudge Analytics',
                'Owner User ID' = varCurrentUserId
            ),
            'Period Start',
            SortOrder.Descending
        )
    )
);
```

### Controls

| Control | Name | Purpose |
|---|---|---|
| Label | `lblAnalyticsTitle` | Screen title: "Analytics" |
| Label | `lblPeriodLabel` | Current period display |
| Label | `lblTotalTracked` | Total tracked this period |
| Label | `lblResponseRate` | Response rate percentage |
| Label | `lblNudgeEffectiveness` | Nudge effectiveness percentage |
| Label | `lblDismissedRate` | Dismissed rate percentage |
| Label | `lblAvgReplyDays` | Average reply time in days |
| Label | `lblNoData` | "No analytics data yet" message |

### Period Label

```powerfx
// lblPeriodLabel.Text
If(
    IsBlank(varLatestAnalytics),
    "",
    varLatestAnalytics.'Period Label'
)
```

### Summary Cards

Display each metric inside a card-style container (rectangle background + label). Set the label formulas:

```powerfx
// lblTotalTracked.Text
"Total Tracked" & Char(10) &
If(
    IsBlank(varLatestAnalytics),
    "--",
    Text(varLatestAnalytics.'Total Tracked')
)

// lblResponseRate.Text
"Response Rate" & Char(10) &
If(
    IsBlank(varLatestAnalytics),
    "--",
    Text(
        varLatestAnalytics.'Total Replied'
            / Max(1, varLatestAnalytics.'Total Tracked')
            * 100,
        "0.0"
    ) & "%"
)

// lblNudgeEffectiveness.Text
"Nudge Rate" & Char(10) &
If(
    IsBlank(varLatestAnalytics),
    "--",
    Text(
        varLatestAnalytics.'Total Nudged'
            / Max(1, varLatestAnalytics.'Total Tracked')
            * 100,
        "0.0"
    ) & "%"
)

// lblDismissedRate.Text
"Dismissed Rate" & Char(10) &
If(
    IsBlank(varLatestAnalytics),
    "--",
    Text(
        varLatestAnalytics.'Total Dismissed'
            / Max(1, varLatestAnalytics.'Total Tracked')
            * 100,
        "0.0"
    ) & "%"
)

// lblAvgReplyDays.Text
"Avg Reply Time" & Char(10) &
If(
    IsBlank(varLatestAnalytics) Or IsBlank(varLatestAnalytics.'Average Reply Days'),
    "--",
    Text(varLatestAnalytics.'Average Reply Days', "0.0") & " days"
)
```

### No Data Message

```powerfx
// lblNoData.Visible
IsBlank(varLatestAnalytics)

// lblNoData.Text
"No analytics data yet. Analytics are generated weekly by the aggregation flow."
```

## 10. Publish and Share

1. Save the app
2. Publish the current version
3. Share it with pilot users
4. Confirm pilot users have:
   - Power Apps Premium access
   - the Email Productivity Agent security role
5. Verify that all five screens are accessible via the tab bar and that navigation works on first launch

## 11. Sync Source Files into the Repo

After publishing:

```powershell
cd email-productivity-agent\scripts
pwsh sync-settings-canvas-app-source.ps1 `
    -AppName "Email Productivity Agent" `
    -EnvironmentId "<environment-guid>"
```

The script extracts the app into `email-productivity-agent\power-apps\settings-canvas-app\`.

## 12. Validation Checklist

### Settings screen (scrSettings)

- [ ] The app loads the current user's config row on startup
- [ ] First-time users get a default configuration row automatically
- [ ] Save / restore / reload buttons work for all fields including digest mode, snooze hours, and skip holiday nudges
- [ ] Numeric inputs clamp to valid ranges (1-30 for day fields, 1-720 for snooze hours)
- [ ] Disabling nudges in the app causes Flow 2 to skip reminder delivery
- [ ] Changing day thresholds affects future follow-up timing

### Priority Contacts screen (scrPriorityContacts)

- [ ] Gallery shows only the current user's priority contacts
- [ ] Adding a contact with an email address creates a new row in `Priority Contacts`
- [ ] Adding a contact without an email shows a validation error
- [ ] Contact email is stored lowercase
- [ ] Delete icon removes the contact from Dataverse
- [ ] Contact count label updates after add/delete

### Holiday Calendar screen (scrHolidayCalendar)

- [ ] Gallery shows the current user's holidays plus org-wide holidays
- [ ] Org-wide holidays display the "ORG-WIDE" badge
- [ ] Adding a holiday creates a new row with the selected date and name
- [ ] Delete icon only appears on the user's own holidays (not org-wide)
- [ ] Bulk import creates US Federal Holiday rows for the current year
- [ ] Duplicate holidays are handled gracefully (alternate key prevents duplicates per user per date)

### Nudge History screen (scrNudgeHistory)

- [ ] Gallery shows follow-ups owned by the current user
- [ ] Default sort is by follow-up date descending (most recent first)
- [ ] Status filter dropdown correctly filters by Pending, Nudged, Replied, and Dismissed
- [ ] Status badges display correct text and color for each state
- [ ] "Days waiting" shows only for active (non-resolved) follow-ups
- [ ] Count label shows filtered count vs total count

### Analytics screen (scrAnalytics)

- [ ] OnVisible loads the most recent analytics row for the current user
- [ ] All five metric cards display values when data exists
- [ ] Percentage calculations handle zero-total gracefully (no division by zero)
- [ ] "No analytics data yet" message shows when no rows exist
- [ ] Average Reply Days shows "--" when the field is null

### Tab Navigation

- [ ] All five tab buttons navigate to the correct screen
- [ ] Active tab is visually highlighted on each screen
- [ ] Navigation works in both directions (any tab to any other tab)

### Source Sync

- [ ] The synced `Src\*.pa.yaml` files land in source control cleanly
