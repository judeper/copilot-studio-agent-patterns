# Demo Walkthrough — Email Productivity Agent

Step-by-step guide for demonstrating the Email Productivity Agent after deployment.

---

## Prerequisites

- EPA-Demo-Lab environment fully provisioned (all validation checks passing (`check-test-readiness.ps1` exits with 0 failures))
- Copilot Studio agent provisioned via `provision-copilot.ps1` (Bot ID available)
- 9 flows deployed and ON
- Demo users assigned (Lisa Taylor, Omar Bennett, Hadar Caspit, Will Beringer)
- Lisa Taylor has an Exchange Online mailbox
- Canvas App deployed and accessible (required for Parts 4–8; see [`docs/canvas-app-setup.md`](canvas-app-setup.md) for setup instructions)

## Demo Flow Overview

```
Lisa sends email → Flow 1 tracks → Flow 2 detects no reply → Teams nudge card
                                                                ├── Draft Follow-Up
                                                                ├── Snooze (duration picker) → remind after chosen period
                                                                └── Dismiss
                                                                
Reply arrives on snoozed thread → Flow 4 auto-unsnoozes → Teams notification
```

> **Flows not covered in this demo:** Flows 5 (Data Retention Cleanup), 6 (Snooze Cleanup), and 7b (Settings Card Handler) are background/maintenance flows that run on weekly or event-driven schedules. They operate automatically and don't require manual demonstration. See the [README Flows Summary](../README.md#flows-summary) for details.

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

Or verify via the **Dataverse maker portal**: **Power Apps** → **Tables** → **Follow Up Tracking** → filter by owner.

### Step 3: Trigger the Nudge (Flow 2)

Flow 2 runs daily at 9 AM EST. For an immediate demo:

**Option A — Wait for schedule:** Come back after 9 AM the next day.

> ⚠️ **Timing note:** Default internal follow-up is 3 business days. For a same-day demo, use Option B (Flow 8 with `-ForceNudge`) which bypasses the timing check.

**Option B — Use Flow 8 test harness:**
```powershell
cd email-productivity-agent/scripts

# Deploy Flow 8 (if not already deployed — requires -CopilotBotId for live agent invocation)
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<org>.crm.dynamics.com" `
    -EnvironmentId "<env-id>" `
    -FlowsToCreate "Flow8" `
    -CopilotBotId "<bot-id>"

# Find the tracking ID for Omar's email in Dataverse, then:
pwsh invoke-followup-test-harness.ps1 `
    -EnvironmentId "<env-id>" `
    -TrackingId "<cr_followuptrackingid>" `
    -ForceNudge
```


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
   - Three action buttons: **✏️ Draft Follow-Up**, **⏰ Snooze** (with duration picker), **✖️ Dismiss**

### Step 5: Demo the Actions

Click each button to demonstrate:

| Action | What Happens |
|---|---|
| **✏️ Draft Follow-Up** | Invokes the Copilot agent and posts a full AI-generated follow-up draft in Teams for review |
| **Snooze** | Opens a duration picker (1 day to 2 weeks). Sets `cr_snoozeuntil` to the chosen duration and `cr_snoozed = true`. Flow 15 will unsnooze when the timer expires. |
| **Dismiss** | Sets `cr_dismissedbyuser = true` — email won't be nudged again |

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
2. Lisa receives a Teams notification: "📬 Unsnoozed: Q1 Budget Variance — Please Review by Friday — new reply from Hadar Caspit"
3. The Dataverse snoozed conversation row is updated: `cr_unsnoozedbyagent = true`

---

## Part 3: Settings

### Step 10: Show the Settings Card

**Flow 7** sends the settings card to Teams. Trigger it via the HTTP harness:

```powershell
pwsh invoke-http-flow-harness.ps1 `
    -EnvironmentId "<env-id>" `
    -FlowDisplayName "EPA - Flow 7: Settings Card"
```

Then optionally test the save/restore behavior using **Flow 10** (the HTTP test harness for Flow 7b):

```powershell
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<org>.crm.dynamics.com" `
    -EnvironmentId "<env-id>" `
    -FlowsToCreate "Flow10"

pwsh invoke-http-flow-harness.ps1 `
    -EnvironmentId "<env-id>" `
    -FlowDisplayName "EPA - Flow 10: Settings Handler Test Harness" `
    -BodyJson '{"action":"restore_defaults","responderEmail":"<admin@domain.com>","responderUserPrincipalName":"<admin@domain.com>"}'
```

The settings card appears in Teams with:
- 4 timeframe inputs (Internal: 3, External: 5, Priority: 1, General: 7 days)
- Enable/disable toggle
- Save Settings and Restore Defaults buttons

---

## Part 4: Priority Contacts

### Step 11: Add a Priority Contact

1. Open the **Canvas App** and navigate to the **Priority Contacts** tab
2. Click **Add Contact** and search for **Omar Bennett**
3. Select Omar and click **Save** — he is now a priority contact for Lisa Taylor

### Step 12: Send Email to Priority Contact

1. Open **Outlook** as Lisa Taylor
2. Send a new email to **Omar Bennett** with subject: "Urgent: Contract Renewal Deadline Tomorrow"
3. Wait ~1 minute for Flow 1 to track the email

### Step 13: Verify Priority Classification

1. Go to **make.powerapps.com** → **Tables** → **Follow Up Tracking**
2. Find the new tracking row for Omar's email
3. Confirm that `cr_recipienttype` is set to **Priority**
4. Note that `cr_followupdate` is set to **1 business day** from now (the shortest threshold)

### Step 14: Show Priority Nudge Card

Trigger a nudge via Flow 8 test harness (with `-ForceNudge`). The nudge card for the priority contact displays a **star badge** next to Omar's name, visually distinguishing it from standard nudge cards.

---

## Part 5: Holiday Calendar

### Step 15: Add a Holiday

1. Open the **Canvas App** and navigate to the **Holiday Calendar** tab
2. Click **Add Holiday**
3. Enter tomorrow's date, name it "Demo Holiday", and set scope to **Org-Wide**
4. Click **Save**

### Step 16: Send Email and Verify Holiday Exclusion

1. Open **Outlook** as Lisa Taylor and send an email to **Hadar Caspit** with subject: "Holiday Test — Budget Review"
2. Wait ~1 minute for Flow 1 to track the email
3. Go to **make.powerapps.com** → **Tables** → **Follow Up Tracking**
4. Find the new tracking row and check `cr_followupdate` — the follow-up date should skip tomorrow (the holiday) and land on the next business day after it

### Step 17: Verify Flow 2 Skips on Holiday

1. Ensure `cr_skipholidaynudges` is enabled in **NudgeConfiguration**
2. If demoing on the holiday itself (or adjust the system clock), run Flow 2 or Flow 8
3. Show that Flow 2's run history indicates it skipped delivery because the current date is a holiday
4. On the next non-holiday business day, Flow 2 delivers the pending nudges normally

---

## Part 6: Snooze Duration

### Step 18: Receive a Nudge and Choose Snooze Duration

1. Use Flow 8 test harness to generate a nudge card for an overdue email
2. On the nudge card in Teams, click the **Snooze** button
3. A duration picker appears — select **1 week**
4. Click **Confirm**

### Step 19: Verify Snooze Duration in Dataverse

1. Go to **make.powerapps.com** → **Tables** → **Snoozed Conversations**
2. Find the snoozed row and verify:
   - `cr_snoozed` is **true**
   - `cr_snoozeuntil` is set to approximately 1 week from now

### Step 20: Demonstrate Timer-Based Unsnooze

**Option A — Wait for timer expiry:** Wait for `cr_snoozeuntil` to pass and Flow 15 to run on its schedule.

**Option B — Use Flow 16 test harness:**

```powershell
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<org>.crm.dynamics.com" `
    -EnvironmentId "<env-id>" `
    -FlowsToCreate "Flow16"

pwsh invoke-http-flow-harness.ps1 `
    -EnvironmentId "<env-id>" `
    -FlowDisplayName "EPA - Flow 16: Snooze Timer Test Harness"
```

After the timer fires:
1. The email is moved back to Lisa's **Inbox**
2. Lisa receives a Teams notification that the snooze period has ended
3. The Snoozed Conversations row has `cr_snoozed` reset to **false**

---

## Part 7: Digest Mode

### Step 21: Enable Digest Mode

1. Open the **Canvas App** and go to **Settings**
2. Toggle **Digest Mode** to **On**
3. Or set `cr_digestmode = true` directly in the **NudgeConfiguration** Dataverse table

### Step 22: Trigger Digest Card

1. Ensure there are multiple overdue follow-ups in the **Follow Up Tracking** table (send several demo emails and wait, or use Flow 8 with `-ForceNudge` on multiple tracking rows)
2. Wait for Flow 2 to run at 9 AM, or trigger it manually

### Step 23: Show the Digest Card

1. Open **Microsoft Teams** and find the message from **Power Automate**
2. Instead of multiple individual cards, a **single digest card** appears listing all overdue emails
3. Each item in the digest card has its own action buttons (Draft Follow-Up, Snooze, Dismiss)
4. Click an action on one item to demonstrate that it applies only to that specific email

---

## Part 8: Analytics Dashboard

### Step 24: Generate Analytics Data

Use Flow 18 test harness to run analytics aggregation immediately:

```powershell
pwsh deploy-agent-flows.ps1 `
    -OrgUrl "https://<org>.crm.dynamics.com" `
    -EnvironmentId "<env-id>" `
    -FlowsToCreate "Flow18"

pwsh invoke-http-flow-harness.ps1 `
    -EnvironmentId "<env-id>" `
    -FlowDisplayName "EPA - Flow 18: Analytics Aggregation Test Harness"
```

### Step 25: View Analytics in Canvas App

1. Open the **Canvas App** and navigate to the **Analytics** tab
2. Show the following metrics:
   - **Total Tracked** — total number of emails tracked by the agent
   - **Response Rate** — percentage of tracked emails that received a reply
   - **Nudge Effectiveness** — percentage of nudged emails that subsequently received a reply
   - **Dismissed Rate** — percentage of tracked emails dismissed without a reply
   - **Average Reply Days** — average business days between sending and receiving a reply
3. Note that data is aggregated weekly by Flow 17 — the test harness (Flow 18) triggers the same aggregation logic on demand

---

## Troubleshooting

| Issue | Cause | Fix |
|---|---|---|
| No tracking records after sending email | Flow 1 trigger watches the connection owner's mailbox | Send email from Outlook as the user whose connection is used by Flow 1 |
| Nudge card not appearing | Flow 2 runs at 9 AM daily | Use Flow 8 test harness with `-ForceNudge` |
| Snooze not detected | Flow 3 runs every 15 minutes | Wait or use Flow 11 test harness |
| Auto-unsnooze not working | Reply must go to Lisa's Inbox | Ensure Hadar replies to the same conversation thread |
| Teams card buttons not working | Flow 2b needs the `epa_nudge_card` CardTypeId | Verify the card was posted by Flow 2/8 (not manually) |
| Flow bot blocked in Teams | Power Automate app blocked by Teams admin policy | Teams Admin Center → Teams apps → Permission policies → unblock Power Automate |
| Flow 2b/7b not responding to card clicks | Handler flows are turned off | Power Automate → verify Flow 2b and Flow 7b are ON |
| Snooze flows failing with 403 | Missing Mail.ReadWrite permission | Re-consent the HTTP with Entra ID connection or request admin consent |

---

## Environment Cleanup

To delete the demo environment:

```powershell
pac admin delete --environment "<env-id>" --async
```

Or re-run the lab wizard — it offers to delete the old environment when reconfiguring.
