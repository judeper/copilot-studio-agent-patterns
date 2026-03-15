# Canvas App Setup Guide — Email Productivity Agent Settings

This guide covers building and publishing the user-facing settings app for the Email Productivity Agent, then syncing the generated source files back into the repo for review.

## Prerequisites

- Power Platform environment provisioned with Dataverse
- `cr_nudgeconfiguration`, `cr_followuptracking`, and `cr_snoozedconversation` tables created
- Power Apps Premium licensing for pilot users
- PAC CLI installed for source sync
- Office 365 Users connector available in the app

## Source-Control Strategy

Power Apps supports pro-code workflows, but the supported source-controlled output is the generated `Src\*.pa.yaml` content created by Power Apps / PAC CLI. Build the app in Power Apps Studio, publish it, then sync the generated source files back into the repo with `scripts\sync-settings-canvas-app-source.ps1`.

> Only `Src\*.pa.yaml` files are intended for source review. Do not treat unpacked JSON/editor metadata as stable source files.

## 1. Create the Canvas App

1. Go to **make.powerapps.com**
2. Select the Email Productivity Agent environment
3. Click **Create** → **Blank app** → **Blank canvas app**
4. Name the app **Email Productivity Agent Settings**
5. Choose **Tablet** layout

## 2. Add Data Sources

Add these data sources:

- **Dataverse**
  - `Nudge Configurations`
  - `Follow Up Trackings`
  - `Snoozed Conversations`
- **Office 365 Users**

> **Column display names:** The formulas throughout this guide reference Dataverse columns by their **display names** (e.g., `'Internal Days'` for logical column `cr_internaldays`). These display names are set during table provisioning by `provision-environment.ps1`. If your environment uses different display names, update the formulas accordingly. The key mappings are:
>
> | Display Name | Logical Name |
> |---|---|
> | `Owner User ID` | `cr_owneruserid` |
> | `Internal Days` | `cr_internaldays` |
> | `External Days` | `cr_externaldays` |
> | `Priority Days` | `cr_prioritydays` |
> | `General Days` | `cr_generaldays` |
> | `Nudges Enabled` | `cr_nudgesenabled` |
> | `Config Label` | `cr_configlabel` |

## 3. Add the Main Screen Controls

Create a single screen named `scrSettings` with these controls:

| Control | Name | Purpose |
|---|---|---|
| Label | `lblTitle` | Screen title |
| Text input | `txtInternalDays` | Internal follow-up days |
| Text input | `txtExternalDays` | External follow-up days |
| Text input | `txtPriorityDays` | Priority follow-up days |
| Text input | `txtGeneralDays` | General follow-up days |
| Toggle | `tglNudgesEnabled` | Master enable/disable |
| Button | `btnSave` | Save changes |
| Button | `btnRestoreDefaults` | Restore default settings |
| Button | `btnReload` | Reload Dataverse values |
| Label | `lblFollowUpCount` | Optional count of pending follow-ups |
| Label | `lblSnoozedCount` | Optional count of active snoozed conversations |

Set each text input's **Format** to **Number**.

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
        NudgesEnabled: true
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
                'Internal Days': varDefaultConfig.InternalDays,
                'External Days': varDefaultConfig.ExternalDays,
                'Priority Days': varDefaultConfig.PriorityDays,
                'General Days': varDefaultConfig.GeneralDays,
                'Nudges Enabled': varDefaultConfig.NudgesEnabled
            }
        )
    )
);
```

After saving the app formula, select **App** → **Run OnStart** once in Studio.

## 5. Control Defaults

Set these formulas:

### Text inputs

```powerfx
// txtInternalDays.Default
Text(Coalesce(varConfigRecord.'Internal Days', varDefaultConfig.InternalDays))

// txtExternalDays.Default
Text(Coalesce(varConfigRecord.'External Days', varDefaultConfig.ExternalDays))

// txtPriorityDays.Default
Text(Coalesce(varConfigRecord.'Priority Days', varDefaultConfig.PriorityDays))

// txtGeneralDays.Default
Text(Coalesce(varConfigRecord.'General Days', varDefaultConfig.GeneralDays))
```

### Toggle

```powerfx
// tglNudgesEnabled.Default
Coalesce(varConfigRecord.'Nudges Enabled', varDefaultConfig.NudgesEnabled)
```

### Optional summary labels

```powerfx
// lblFollowUpCount.Text
"Pending follow-ups: " &
CountRows(
    Filter(
        'Follow-Up Trackings',
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

## 6. Save / Restore / Reload Buttons

### Save button

Set `btnSave.OnSelect`:

```powerfx
Set(
    varConfigRecord,
    Patch(
        'Nudge Configurations',
        varConfigRecord,
        {
            'Internal Days': Max(1, Min(30, IfError(Value(txtInternalDays.Text), varDefaultConfig.InternalDays))),
            'External Days': Max(1, Min(30, IfError(Value(txtExternalDays.Text), varDefaultConfig.ExternalDays))),
            'Priority Days': Max(1, Min(30, IfError(Value(txtPriorityDays.Text), varDefaultConfig.PriorityDays))),
            'General Days': Max(1, Min(30, IfError(Value(txtGeneralDays.Text), varDefaultConfig.GeneralDays))),
            'Nudges Enabled': tglNudgesEnabled.Value
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

### Restore defaults button

Set `btnRestoreDefaults.OnSelect`:

```powerfx
Set(
    varConfigRecord,
    Patch(
        'Nudge Configurations',
        varConfigRecord,
        {
            'Internal Days': varDefaultConfig.InternalDays,
            'External Days': varDefaultConfig.ExternalDays,
            'Priority Days': varDefaultConfig.PriorityDays,
            'General Days': varDefaultConfig.GeneralDays,
            'Nudges Enabled': varDefaultConfig.NudgesEnabled
        }
    )
);
Reset(txtInternalDays);
Reset(txtExternalDays);
Reset(txtPriorityDays);
Reset(txtGeneralDays);
Reset(tglNudgesEnabled);
Notify("Defaults restored.", NotificationType.Success);
```

### Reload button

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
Notify("Latest settings loaded.", NotificationType.Information);
```

## 7. Publish and Share

1. Save the app
2. Publish the current version
3. Share it with pilot users
4. Confirm pilot users have:
   - Power Apps Premium access
   - the Email Productivity Agent security role

## 8. Sync Source Files into the Repo

After publishing:

```powershell
cd email-productivity-agent\scripts
pwsh sync-settings-canvas-app-source.ps1 `
    -AppName "Email Productivity Agent Settings" `
    -EnvironmentId "<environment-guid>"
```

The script extracts the app into `email-productivity-agent\power-apps\settings-canvas-app\`.

## 9. Validation Checklist

- The app loads the current user's row only
- First-time users get a default configuration row automatically
- Save / restore / reload buttons work
- Disabling nudges in the app causes Flow 2 to skip reminder delivery
- Changing day thresholds affects future follow-up timing
- The synced `Src\*.pa.yaml` files land in source control cleanly
