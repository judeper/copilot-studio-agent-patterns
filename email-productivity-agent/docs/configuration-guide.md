# Configuration Guide — Email Productivity Agent

This guide explains how to customize the Email Productivity Agent's behavior for your needs.

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

Via the **Canvas App Settings Screen**:

1. Open the Email Productivity Agent Canvas App
2. Navigate to **Settings** → **Nudge Configuration**
3. Adjust the number of business days for each recipient type
4. Changes take effect on the next daily nudge scan (9 AM)

> **Note**: Business days exclude Saturday and Sunday. Holiday exclusion is not supported in the current version.

### Disabling Nudges

To temporarily disable all nudge notifications:

1. Open Settings → Nudge Configuration
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

The snooze agent respects working hours (7 AM - 7 PM in your timezone). If a reply arrives outside working hours and your snooze was about to expire anyway, the agent may defer unsnoozing to avoid disturbing you.

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

### Daily Digest

Nudges are delivered once daily at **9 AM** (in your local timezone). All pending follow-ups due that day are grouped into a single notification to minimize interruption.

If more than 10 nudges are due on the same day, the card shows the top 10 by priority with a link to view the rest in the dashboard.

---

## What Emails Are Tracked

### Tracked (Logged to FollowUpTracking)
- Emails you send via Outlook (To-line recipients only)
- One tracking record per recipient per email

### Not Tracked (Filtered Out)
- Auto-replies and out-of-office responses
- Calendar invitations and responses
- Emails to no-reply addresses
- Emails to distribution lists
- Emails where you are in the To/CC (self-sends)
- CC recipients (only To-line recipients are tracked)

### When Tracking Stops
A tracking record is resolved (no more nudging) when:
- ✅ The recipient replies (detected via Graph API)
- ✖️ You dismiss the nudge
- 🕐 The record is older than 90 days (auto-cleaned)

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
