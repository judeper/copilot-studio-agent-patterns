# Configuration Guide — Email Productivity Agent

This guide explains how to customize the Email Productivity Agent's behavior for your needs.

> **Settings options:** Configure nudge settings via the **Teams Settings Card** (Flow 7), the **Canvas App** (see `docs/canvas-app-setup.md`), or directly in the **Dataverse maker portal** (Power Apps → Tables → Nudge Configuration).

---

## Nudge Timeframes

The agent uses configurable follow-up periods based on recipient type. Each user has their own settings stored in the NudgeConfiguration Dataverse table.

### Default Settings

| Recipient Type | Default Follow-Up Period | When to Use |
|---------------|-------------------------|-------------|
| **Internal** | 3 business days | Colleagues in the same organization (same email domain) |
| **External** | 5 business days | External contacts, clients, vendors |
| **Priority** | 1 business day | VIP contacts requiring fast response (managed via Canvas App Priority Contacts tab) |
| **General** | 7 business days | Default for unclassified recipients |

### How to Change Timeframes

Via the **Dataverse maker portal** (or Canvas App when available):

1. Open the Nudge Configuration table in **Power Apps → Tables**
2. Navigate to the user's **Nudge Configuration** row
3. Adjust the number of business days for each recipient type
4. Changes take effect on the next daily nudge scan (9 AM)

> **Note**: Business days exclude Saturday and Sunday. Holidays configured in the Holiday Calendar are also excluded — see the [Holiday Calendar](#holiday-calendar) section below.

### Disabling Nudges

To temporarily disable all nudge notifications:

1. Open the Nudge Configuration table in **Power Apps → Tables** (or Settings → Nudge Configuration in the Canvas App when available)
2. Toggle **"Nudges Enabled"** to Off
3. The Sent Items Tracker will continue logging emails, but no nudge notifications will be delivered
4. Toggle back to On to resume nudging (pending nudges from the disabled period will be caught up)

---

## Recipient Type Detection

The agent automatically classifies recipients when tracking sent emails:

| Classification | Logic |
|---------------|-------|
| **Internal** | Recipient's email domain matches your organization's tenant domain |
| **External** | Recipient's email domain differs from your tenant domain |
| **Priority** | Contact appears in the user's Priority Contacts list (managed via Canvas App) |
| **General** | Default fallback when no specific classification applies |

> **Note:** The classifier produces Internal, External, and Priority values. Priority is assigned when the recipient appears in the user's Priority Contacts list. General is the default fallback for unclassified recipients.

---

## Snooze Behavior (Phase 2)

### How Snoozing Works

The agent uses a **managed email folder** called `EPA-Snoozed` (not Outlook's native snooze). To snooze an email:

1. Move the email to the **EPA-Snoozed** folder in Outlook
2. The Snooze Detection flow (runs every 15 minutes) detects it and tracks it
3. When a new reply arrives on that thread, the agent automatically moves the email back to your Inbox

### Important: EPA-Snoozed vs Outlook Native Snooze

| Feature | EPA-Snoozed (This Agent) | Outlook "Remind Me" (Native) |
|---------|--------------------------|------------------------------|
| Auto-unsnooze on reply | ✅ Yes | ❌ No |
| Time-based reminder | ✅ Yes (via Flow 15) | ✅ Yes |
| Folder | EPA-Snoozed (managed) | Scheduled (hidden) |
| Works with agent | ✅ Yes | ❌ Not tracked by agent |

**Use EPA-Snoozed** if you want automatic unsnooze on new replies.
**Use Outlook's "Remind Me"** if you want a time-based reminder regardless of replies.

### Auto-Unsnooze Notifications

When the agent unsnoozes an email, you'll receive a brief Teams notification:

> 📬 **Sarah Chen** replied to "Project Timeline Review" — she has concerns about Q3 milestones and wants to schedule a discussion.

The notification includes who replied and a brief context hint from the reply.

### Working Hours

Unsnoozing behavior is driven by the Snooze Agent decision (`UNSNOOZE` or `SUPPRESS`). If your current prompt policy does not suppress outside working hours, matching replies are moved back to Inbox immediately and you receive the Teams notification right away.

> **Tuning option:** Adjust the Snooze Agent prompt policy if you want working-hours-aware suppression logic.

---

## Nudge Notifications

### Where Nudges Appear

Nudge notifications are delivered as **Teams Adaptive Cards** in your 1:1 chat with the Power Automate Flow bot. Each card shows:

- 📧 Email subject
- 👤 Recipient who hasn't replied
- 📅 How long since you sent it
- 📝 Thread summary (AI-generated context)
- ✍️ Suggested follow-up draft

### Action Buttons

| Button | What It Does |
|--------|-------------|
| **✏️ Draft Follow-Up** | Invokes the Copilot agent to generate a full follow-up email draft and posts it via Teams for review |
| **⏰ Snooze** | Opens a duration picker (1 day to 2 weeks) and postpones the nudge for the selected period |
| **✖️ Dismiss** | Permanently dismisses this nudge (won't remind again) |

### Delivery Cadence

Each overdue follow-up generates an individual Adaptive Card notification in Teams. Cards are delivered sequentially during the daily check at **9 AM** (configurable time, in your local timezone).

> **Digest mode:** When enabled, multiple nudges are grouped into a single daily digest card instead of individual cards. See the [Nudge Digest Mode](#nudge-digest-mode) section below.

---

## What Emails Are Tracked

### Tracked (Logged to FollowUpTracking)
- Emails you send via Outlook (To-line recipients only)
- One tracking record per recipient per email

### Not Tracked (Filtered Out)
- Auto-replies and out-of-office responses
- Calendar invitations and responses
- Emails to no-reply addresses
- Emails where you are in the To/CC (self-sends)
- CC recipients (only To-line recipients are tracked)
- Emails with only BCC recipients (no To-line recipients) — the agent tracks To-line recipients only. BCC recipients are not visible to the Graph API `toRecipients` property.

### When Tracking Stops
A tracking record is resolved (no more nudging) when:
- ✅ The recipient replies (detected via Graph API)
- ✖️ You dismiss the nudge
- 🕐 The record is older than 90 days (auto-cleaned)

---

## Priority Contacts

Priority Contacts let you flag specific people for the fastest follow-up threshold. When a recipient is on your Priority Contacts list, they are classified as **Priority** and use the `cr_prioritydays` setting (default: 1 business day).

### Managing Priority Contacts

1. Open the **Canvas App** and navigate to the **Priority Contacts** tab
2. Click **Add Contact** and search by name or email address
3. To remove a contact, select it and click **Remove**

Changes take effect on the next Flow 1 (Sent Items Tracker) run. Emails already tracked retain their original recipient type unless the tracking row is deleted and re-created.

### Priority Contact Behavior

- **Follow-up threshold**: Priority contacts use `cr_prioritydays` (default 1 business day), the shortest of all recipient types
- **Nudge cards**: Nudge cards for priority contacts display a star badge to visually distinguish them
- **Snooze unsnooze**: Replies from contacts on the priority list always trigger an immediate unsnooze, regardless of working-hours suppression rules

### Dataverse Details

Priority contacts are stored in the **cr_prioritycontacts** table, with one row per user/contact pair. The `cr_contactemail` column holds the contact's email address, and `cr_ownerid` links to the user who added the contact.

---

## Holiday Calendar

The Holiday Calendar lets you define dates that should be excluded from business day calculations and optionally skip nudge delivery entirely.

### Adding Holidays

1. Open the **Canvas App** and navigate to the **Holiday Calendar** tab
2. Click **Add Holiday** and enter the date, name, and scope
3. To remove a holiday, select it and click **Delete**

### Holiday Types

| Scope | Description | Example |
|-------|-------------|---------|
| **Org-Wide** | Applies to all users in the organization | New Year's Day, company shutdown |
| **Personal** | Applies only to the user who created it | Personal vacation day, religious observance |

### How Holidays Affect Behavior

- **Flow 1 (Sent Items Tracker)**: When calculating the follow-up date, holidays are excluded from business day counts. For example, if the follow-up period is 3 business days and one of those days is a holiday, the follow-up date is pushed forward by one additional calendar day.
- **Flow 2 (Nudge Delivery)**: When `cr_skipholidaynudges` is enabled in NudgeConfiguration, Flow 2 skips nudge delivery entirely on holidays. Pending nudges are delivered on the next non-holiday business day.

### Dataverse Details

Holidays are stored in the **cr_holidaycalendar** table. Key columns: `cr_date` (the holiday date), `cr_name` (display name), `cr_scope` (OrgWide or Personal), and `cr_ownerid` (the user who created the entry; relevant for Personal scope holidays).

---

## Nudge Digest Mode

By default, each overdue follow-up generates an individual Adaptive Card in Teams. When **Digest Mode** is enabled, all pending nudges for the day are combined into a single daily digest card.

### Enabling Digest Mode

1. Open the **Canvas App** and go to **Settings**
2. Toggle **Digest Mode** to On
3. Or set `cr_digestmode = true` directly in the **NudgeConfiguration** Dataverse table

### What Changes in Digest Mode

| Aspect | Individual Mode (default) | Digest Mode |
|--------|--------------------------|-------------|
| Card delivery | One card per overdue email | Single card listing all overdue emails |
| Action buttons | Per card | Per item within the digest card (Draft Follow-Up, Snooze, Dismiss still work individually) |
| Delivery time | Sequentially during the 9 AM run | Single card at 9 AM |

> **Note:** Even in digest mode, each item in the digest card retains its own action buttons (Draft Follow-Up, Snooze, Dismiss). Clicking an action applies only to that specific item.

---

## Snooze Duration

The snooze feature now supports a configurable duration picker, allowing you to choose exactly how long to postpone a nudge.

### Duration Picker

When you click the **Snooze** button on a nudge card, a duration picker appears with the following options:

- 1 day
- 2 days
- 3 days
- 1 week
- 2 weeks

### Default Snooze Duration

The default snooze duration is controlled by the `cr_defaultsnoozehours` setting in NudgeConfiguration. If no duration is selected from the picker, this default is used. The initial value is 48 hours (2 days).

### Timer-Based Unsnooze (Flow 15)

When a message is snoozed with a duration, the `cr_snoozeuntil` timestamp is set on the Snoozed Conversations row. **Flow 15** (Snooze Timer) runs on a recurring schedule and checks for rows where `cr_snoozeuntil` has passed. When the timer expires:

1. The snoozed email is automatically moved back to the user's Inbox
2. A Teams notification informs the user that the snooze period has ended
3. The tracking row's `cr_snoozed` flag is reset so the email is eligible for nudging again

> **Note:** Messages are also unsnoozed immediately if a reply arrives (via Flow 4), regardless of the remaining snooze duration. Priority contact replies always trigger immediate unsnooze.

---

## Distribution Lists

Emails sent to distribution lists (DLs) are automatically expanded so that replies from individual DL members are tracked separately.

### How DL Expansion Works

1. **Flow 1** detects that a To-line recipient is a distribution list (via Graph API group lookup)
2. The DL is expanded to its individual members (capped at **100 members** per DL)
3. One tracking row is created per member, with `cr_recipienttype` set based on standard classification rules (Internal, External, or Priority)
4. The `cr_dlsourceemail` field on each tracking row stores the original distribution list email address, linking member rows back to the DL

### Limitations

- DL expansion is capped at **100 members**. If a DL has more than 100 members, only the first 100 are tracked.
- Nested distribution lists (DLs within DLs) are expanded one level deep only.

---

## Analytics Dashboard

The Canvas App includes an **Analytics** tab that provides insight into your email follow-up patterns and agent effectiveness.

### Accessing Analytics

1. Open the **Canvas App**
2. Navigate to the **Analytics** tab

### Available Metrics

| Metric | Description |
|--------|-------------|
| **Total Tracked** | Total number of emails tracked by the agent |
| **Response Rate** | Percentage of tracked emails that received a reply |
| **Nudge Effectiveness** | Percentage of nudged emails that subsequently received a reply |
| **Dismissed Rate** | Percentage of tracked emails dismissed by the user without a reply |
| **Average Reply Days** | Average number of business days between sending an email and receiving a reply |

### Data Aggregation

Analytics data is aggregated weekly by **Flow 17** (Analytics Aggregation). Flow 17 runs on a weekly schedule (default: Sunday at midnight) and computes the metrics above across all tracking rows for the user. Aggregated results are stored in the **cr_analyticsweekly** Dataverse table.

> **Note:** The Analytics tab shows data starting from the first week Flow 17 ran. Historical data from before Flow 17 was enabled is not retroactively computed.

---

## Known Limitations

- **Distribution lists**: Emails sent to distribution lists are automatically expanded to track per-member replies (capped at 100 members per DL). See the [Distribution Lists](#distribution-lists) section for details.
- **Distribution list cap**: If a distribution list has more than 100 members, only the first 100 are tracked. The remaining members are not monitored for replies.

---

## Troubleshooting

### "I'm not receiving nudge notifications"

1. Check that **Nudges Enabled** is On in your NudgeConfiguration
2. Verify the Power Automate flows are turned on (Flow 1 and Flow 2)
3. Check that the Power Automate Flow bot is not blocked in your Teams settings
4. Review Flow 2's run history for errors

### "A reply was received but the nudge still fired"

This can happen if:
- The reply arrived after the 9 AM nudge scan had already started
- The recipient changed the email subject (new conversationId — known limitation)
- The reply was from a different person on the thread (the agent tracks specific recipients)

### "The EPA-Snoozed folder disappeared"

The Snooze Detection flow will automatically recreate it on the next 15-minute cycle. Any previously snoozed messages in the deleted folder are lost.

### "I want to stop tracking a specific email"

Open the nudge notification in Teams and click **✖️ Dismiss**. This permanently stops tracking for that specific recipient on that email.

### "No priority contacts appearing"

1. Open the **cr_prioritycontacts** Dataverse table and verify it has rows for your user (`cr_ownerid` matches your user ID)
2. Confirm the `cr_contactemail` values match the exact email addresses you expect
3. If rows exist but classification is not working, check that Flow 1 is running and processing new sent emails

### "Holidays not affecting follow-up dates"

1. Open the **cr_holidaycalendar** Dataverse table and verify it has entries
2. Confirm the `cr_date` values are correct and cover the expected dates (format: YYYY-MM-DD)
3. Check the `cr_scope` column — Personal holidays only apply to the user who created them
4. Verify that Flow 1 is using the updated holiday calendar by checking recent run history

### "Digest card not appearing"

1. Open the **NudgeConfiguration** Dataverse table for your user
2. Verify that `cr_digestmode` is set to **true**
3. Confirm that Flow 2 ran at its scheduled time (9 AM) and check its run history for errors
4. Ensure there are overdue follow-ups pending — digest mode still requires at least one pending nudge
