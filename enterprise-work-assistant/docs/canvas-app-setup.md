# Canvas App Setup Guide

This guide covers creating the Canvas Power App that serves as the user-facing dashboard for the Enterprise Work Assistant.

## Prerequisites

- Power Platform environment provisioned with Dataverse
- `Assistant Cards` table created (run `scripts/provision-environment.ps1`)
- Power Apps Component Framework (PCF) component deployed (run `scripts/deploy-solution.ps1`)
- PCF for Canvas apps enabled in environment settings (the provisioning script attempts this automatically)

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
- **Items**: `["", "High", "Medium", "Low", "N/A"]`
- **Default**: `""`
- **Name**: `drpPriority`

### Card Status Dropdown
- **Items**: `["", "READY", "LOW_CONFIDENCE", "SUMMARY_ONLY"]`
- **Default**: `""`
- **Name**: `drpCardStatus`

### Temporal Horizon Dropdown
- **Items**: `["", "TODAY", "THIS_WEEK", "NEXT_WEEK", "BEYOND", "N/A"]`
- **Default**: `""`
- **Name**: `drpTemporalHorizon`

> **Note**: The empty string `""` represents "no filter" (show all). `N/A` is included for Priority and Temporal Horizon because non-calendar items (EMAIL, TEAMS_MESSAGE) use these values.

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
    Owner = User()
)
```

This binds the PCF to the user's own Assistant Cards rows. Dataverse Row-Level Security (RLS) provides an additional security layer.

To add server-side filtering (reduces data loaded):

```
SortByColumns(
    Filter(
        'Assistant Cards',
        Owner = User(),
        'Card Status' <> 'Card Status'.NO_OUTPUT
    ),
    "createdon",
    SortOrder.Descending
)
```

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
// Handle Edit Draft action
If(
    !IsBlank(AssistantDashboard1.editDraftAction),
    Set(varEditCardId, AssistantDashboard1.editDraftAction);
    Navigate(scrEditDraft)
);

// Handle Dismiss Card action
If(
    !IsBlank(AssistantDashboard1.dismissCardAction),
    Patch(
        'Assistant Cards',
        LookUp('Assistant Cards', 'Assistant Card' = GUID(AssistantDashboard1.dismissCardAction)),
        { 'Card Status': 'Card Status'.SUMMARY_ONLY }
    )
);
```

### Selected Card tracking

```
Set(varSelectedCardId, AssistantDashboard1.selectedCardId)
```

## 9. (Optional) Edit Draft Screen

Create a second screen `scrEditDraft` for editing and copying drafts:

1. Add a **TextInput** control bound to the humanized draft
2. Add a **Copy** button that copies the draft to clipboard
3. Add a **Back** button that navigates back to Screen1

```
// On the TextInput Default property — uses the display name "Humanized Draft"
LookUp(
    'Assistant Cards',
    'Assistant Card' = GUID(varEditCardId)
).'Humanized Draft'
```

## 10. (Optional) Embed Copilot Agent

To embed the Copilot Studio agent for follow-up questions:

1. Click **Insert** → **Copilot (preview)**
2. Select the "Enterprise Work Assistant" agent
3. Position below or beside the dashboard

This lets users ask follow-up questions about any card directly from the app.

---

## Testing Checklist

- [ ] App loads and connects to Dataverse
- [ ] Filter dropdowns filter the card gallery
- [ ] Clicking a card shows the detail view
- [ ] Back button returns to gallery
- [ ] Edit Draft navigates to edit screen
- [ ] Dismiss Card updates the Dataverse row
- [ ] Cards display correct priority colors (red/amber/green)
- [ ] Low confidence cards show warning message bar
- [ ] Sources render as clickable links
- [ ] Meeting briefings display as formatted text
