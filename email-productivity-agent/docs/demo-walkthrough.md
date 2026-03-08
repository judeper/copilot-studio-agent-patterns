# Demo Walkthrough — Email Productivity Agent

Step-by-step guide for demonstrating the Email Productivity Agent after deployment.

---

## Prerequisites

- EPA-Demo-Lab environment fully provisioned (all 12 validation checks passing)
- 9 flows deployed and ON
- Demo users assigned (Lisa Taylor, Omar Bennett, Hadar Caspit, William Beringer, Sonia Rees)
- Lisa Taylor has an Exchange Online mailbox
- Teams client can render emoji characters in Adaptive Cards (no external image dependencies)

## Demo Flow Overview

```
Lisa sends email → Flow 1 tracks → Flow 2 detects no reply → Teams nudge card
                                                                ├── Draft Follow-Up
                                                                ├── Snooze 2 Days → EPA-Snoozed folder
                                                                └── Dismiss
                                                                
Reply arrives on snoozed thread → Flow 4 auto-unsnoozes → Teams notification
```

---

## Part 1: Follow-Up Nudges

### Step 1: Send Demo Emails (as Lisa Taylor)

Sign into Outlook as **Lisa Taylor** and send these 3 emails:

| # | To | Subject | Purpose |
|---|---|---|---|
| 1 | Omar Bennett | Q2 Headcount Request — Department Approval Needed | NUDGE target (expects follow-up) |
| 2 | Hadar Caspit | Q1 Budget Variance — Please Review by Friday | SNOOZE target (will be snoozed later) |
| 3 | Will Beringer | FYI: Updated IT Policy — No Action Needed | SKIP target (should be auto-skipped by agent) |

> **Why from Outlook?** Flow 1's trigger watches Lisa's Sent Items via the Outlook connector. Emails sent via Graph API (application permissions) don't trigger the connector.

### Step 2: Verify Flow 1 Tracked the Emails

Wait ~1 minute, then check Dataverse:

1. Go to **make.powerapps.com** → select the EPA environment
2. Navigate to **Tables** → **Follow Up Tracking**
3. You should see 3 rows (one per recipient)

Or query via CLI:
```powershell
pwsh invoke-followup-test-harness.ps1 `
    -EnvironmentId "<env-id>" `
    -TrackingId "<tracking-id-from-dataverse>" `
    -ForceNudge
```

### Step 3: Trigger the Nudge (Flow 2)

Flow 2 runs daily at 9 AM EST. For an immediate demo:

**Option A — Wait for schedule:** Come back after 9 AM the next day.

**Option B — Use Flow 8 test harness:**
```powershell
cd email-productivity-agent/scripts

# Deploy Flow 8 (if not already deployed)
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<org>.crm.dynamics.com" `
    -EnvironmentId "<env-id>" `
    -FlowsToCreate "Flow8"

# Find the tracking ID for Omar's email in Dataverse, then:
pwsh invoke-followup-test-harness.ps1 `
    -EnvironmentId "<env-id>" `
    -TrackingId "<cr_followuptrackingid>" `
    -ForceNudge
```

**Option C — Manual trigger:** Go to Power Automate → find "EPA - Flow 2" → Run.

### Step 4: Show the Teams Nudge Card

After Flow 2 or Flow 8 runs:
1. Open **Microsoft Teams**
2. Find the message from **Power Automate** in your chat
3. The nudge card shows:
   - Email subject and recipient
   - Days since sent
   - Nudge priority (High/Medium/Low)
   - Thread summary
   - Suggested follow-up draft
   - Two action buttons: **Snooze 2 Days**, **Dismiss**

### Step 5: Demo the Actions

Click each button to demonstrate:

| Action | What Happens |
|---|---|
| **Snooze 2 Days** | Sets `cr_followupdate = now + 2 days`, resets `cr_nudgesent = false` — you'll be reminded again in 2 days |
| **Dismiss** | Sets `cr_dismissedbyuser = true` — email won't be nudged again |

> **Note:** Draft generation via Copilot is planned for a future release. The current POC focuses on the nudge → snooze → auto-unsnooze pipeline.

---

## Part 2: Smart Snooze

### Step 6: Move Email to EPA-Snoozed Folder

1. Open **Outlook** as Lisa Taylor
2. Find Hadar Caspit's email ("Q1 Budget Variance")
3. Create the `EPA-Snoozed` folder in Lisa's mailbox (if it doesn't exist — Flow 3 also creates it automatically)
4. Move the email to `EPA-Snoozed`

### Step 7: Trigger Snooze Detection (Flow 3)

Flow 3 runs every 15 minutes. Wait or manually trigger it:

```powershell
# Deploy Flow 11 (Snooze Detection Test Harness)
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<org>.crm.dynamics.com" `
    -EnvironmentId "<env-id>" `
    -FlowsToCreate "Flow11"

pwsh invoke-http-flow-harness.ps1 `
    -EnvironmentId "<env-id>" `
    -FlowDisplayName "EPA - Flow 11: Snooze Detection Test Harness"
```

Check Dataverse → **Snoozed Conversations** table — a row should appear with the email's conversation ID.

### Step 8: Simulate a Reply (as Hadar Caspit)

1. Sign into Outlook as **Hadar Caspit**
2. Reply to Lisa's "Q1 Budget Variance" email
3. This triggers Flow 4 (Auto-Unsnooze)

### Step 9: Verify Auto-Unsnooze

After Hadar's reply:
1. The email moves back to Lisa's **Inbox** automatically
2. Lisa receives a Teams notification: "📬 Unsnoozed: Q1 Budget Variance — new reply from Hadar Caspit"
3. The Dataverse snoozed conversation row is updated: `cr_unsnoozedbyagent = true`

---

## Part 3: Settings

### Step 10: Show the Settings Card

Manually trigger Flow 7 from Power Automate, or use the test harness:

```powershell
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<org>.crm.dynamics.com" `
    -EnvironmentId "<env-id>" `
    -FlowsToCreate "Flow10"

pwsh invoke-http-flow-harness.ps1 `
    -EnvironmentId "<env-id>" `
    -FlowDisplayName "EPA - Flow 10: Settings Handler Test Harness" `
    -BodyJson '{"action":"restore_defaults","responderEmail":"<admin@example.com>","responderUserPrincipalName":"<admin@example.com>"}'
```

The settings card appears in Teams with:
- 4 timeframe inputs (Internal: 3, External: 5, Priority: 1, General: 7 days)
- Enable/disable toggle
- Save Settings and Restore Defaults buttons

---

## Troubleshooting

| Issue | Cause | Fix |
|---|---|---|
| No tracking records after sending email | Flow 1 trigger watches the connection owner's mailbox | Send email from Outlook as the user whose connection is used by Flow 1 |
| Nudge card not appearing | Flow 2 runs at 9 AM daily | Use Flow 8 test harness with `-ForceNudge` |
| Snooze not detected | Flow 3 runs every 15 minutes | Wait or use Flow 11 test harness |
| Auto-unsnooze not working | Reply must go to Lisa's Inbox | Ensure Hadar replies to the same conversation thread |
| Teams card buttons not working | Flow 2b needs the `epa_nudge_card` CardTypeId | Verify the card was posted by Flow 2/8 (not manually) |

---

## Environment Cleanup

To delete the demo environment:

```powershell
pac admin delete --environment "<env-id>" --async
```

Or re-run the lab wizard — it offers to delete the old environment when reconfiguring.
