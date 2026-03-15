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
| **Priority** | 1 business day | VIP contacts requiring fast response (future: configurable list) |
| **General** | 7 business days | Default for unclassified recipients |

### How to Change Timeframes

Via the **Dataverse maker portal** (or Canvas App when available):

1. Open the Nudge Configuration table in **Power Apps → Tables**
2. Navigate to the user's **Nudge Configuration** row
3. Adjust the number of business days for each recipient type
4. Changes take effect on the next daily nudge scan (9 AM)

> **Note**: Business days exclude Saturday and Sunday. Holiday exclusion is not supported in the current version.

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
| **Priority** | (Future enhancement) Contacts on a configurable priority list |
| **General** | Default fallback when no specific classification applies |

For the current MVP, all external recipients use the External timeframe. Priority contact list support will be added in a future update.

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
| Time-based reminder | ❌ Not in MVP | ✅ Yes |
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
| **✏️ Draft Follow-Up** | Generates a full follow-up email draft and shows it for review |
| **⏰ Snooze 2 Days** | Postpones the nudge by 2 business days |
| **✖️ Dismiss** | Permanently dismisses this nudge (won't remind again) |

### Delivery Cadence

Each overdue follow-up generates an individual Adaptive Card notification in Teams. Cards are delivered sequentially during the daily check at **9 AM** (configurable time, in your local timezone).

> **Future enhancement:** Grouping multiple nudges into a batched daily digest is planned for a future release.

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

## Known Limitations

- **Distribution lists**: Emails sent to distribution lists are tracked per recipient on the To-line. The agent cannot distinguish distribution list members from direct recipients without a Graph group membership lookup, which is not implemented.
- **Holiday exclusion**: Business day calculations do not account for holidays. See Nudge Timeframes above.

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
