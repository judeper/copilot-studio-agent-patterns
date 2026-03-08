# UX Enhancements — Design Specification

> **Status:** Design · **Version:** 0.1 · **Last Updated:** 2025-07-15
>
> This document specifies upcoming UX enhancements for the Enterprise Work Assistant
> dashboard. Each section is self-contained and can be implemented independently unless
> noted otherwise. Cross-references use Dataverse logical names (`cr_*`) and PCF output
> conventions established in [canvas-app-setup.md](canvas-app-setup.md).

---

## Table of Contents

1. [First-Run Onboarding](#1-first-run-onboarding)
2. [Sender Management UI](#2-sender-management-ui)
3. [Card Auto-Archive](#3-card-auto-archive)
4. [External Action Detection](#4-external-action-detection)
5. [Skill Registry Management UI](#5-skill-registry-management-ui)
6. [CSS Dark Mode Design](#6-css-dark-mode-design)
7. [Keyboard Shortcuts](#7-keyboard-shortcuts)
8. [Card Thread View](#8-card-thread-view)
9. [Card Pin/Star Feature](#9-card-pinstar-feature)
10. [Snooze with Wake-Up Time](#10-snooze-with-wake-up-time)
11. [Batch Actions](#11-batch-actions)

---

## 1. First-Run Onboarding

### Purpose

Guide new users through initial setup so the dashboard is immediately useful on first
launch. The onboarding renders as a special card within the existing `CardGallery`
component — no separate screen or modal required.

### Detection Logic

The Canvas app evaluates two conditions at startup:

| Condition | Check |
|-----------|-------|
| No cards exist | `CountRows(Filter(cr_assistantcards, cr_ownerid = currentUser)) = 0` |
| Briefing not configured | `IsBlank(LookUp(cr_userpersonas, cr_ownerid = currentUser).cr_briefingschedule)` |

If **both** conditions are true, the app inserts a synthetic onboarding card into the
PCF dataset.

### Onboarding Card Schema

```
cr_assistantcard row:
  cr_triggertype    = "ONBOARDING"
  cr_cardstatus     = "SETUP"
  cr_triagetier     = "FULL"
  cr_itemsummary    = "Welcome to Work Assistant"
  cr_priority       = "High"
  cr_cardoutcome    = "PENDING"
```

> **Note:** `ONBOARDING` is a new `TriggerType` value. The PCF `types.ts` union must
> be extended to include it. `SETUP` is a new `CardStatus` value used exclusively for
> onboarding.

### 3-Step Wizard

The wizard renders inside a `CardDetail`-style panel when the onboarding card is
selected. Steps are tracked via local React state (not persisted until completion).

#### Step 1 — Welcome

- Brief explanation of what Work Assistant does (3–4 sentences).
- Input field: **Display name** (pre-populated from `Office365Users.MyProfile().DisplayName`).
- "Next" button advances to Step 2.

#### Step 2 — Configure Briefing

| Field | Control | Default |
|-------|---------|---------|
| Timezone | Dropdown (IANA zones) | Browser-detected via `Intl.DateTimeFormat().resolvedOptions().timeZone` |
| Schedule days | Multi-select checkboxes | Mon–Fri checked |
| Preferred briefing time | Time picker | `07:30` |

- Writes to `cr_userpersona`: `cr_briefingschedule`, `cr_timezone`, `cr_briefingtime`.
- "Next" button advances to Step 3.

#### Step 3 — Try a Command

- `CommandBar` rendered with a pre-populated value: `Show me my priorities`.
- User can edit or submit as-is.
- On submit the standard `commandAction` output fires, demonstrating real interaction.
- "Finish Setup" button completes the wizard.

### Post-Completion

1. Set the onboarding card: `cr_cardoutcome = "DISMISSED"`, `cr_cardstatus = "DISMISSED"`.
2. If the **Silent Bootstrap** flow is deployed, trigger it via the existing
   `commandAction` output with command `__silent_bootstrap`.
3. The onboarding card is removed from the feed on next refresh.

### PCF Output

```
onboardingCompleteAction: JSON {
    displayName: string,
    timezone: string,
    scheduleDays: string[],
    briefingTime: string
}
```

The Canvas app `OnChange` handler writes these values to `cr_userpersona` and dismisses
the onboarding card.

---

## 2. Sender Management UI

### Purpose

Let users override triage behavior per sender. A user who always wants emails from
their manager triaged as FULL can set that here, bypassing the agent's automatic
categorization.

### Access

Click the **sender name** on any `CardItem` or `CardDetail` → opens a sender detail
panel. The sender name is already rendered via `original_sender_display`; this
enhancement wraps it in a clickable element.

### Sender Detail Panel

| Field | Source | Editable |
|-------|--------|----------|
| Sender email | `cr_assistantcard.cr_originalsenderemail` | No |
| Display name | `cr_assistantcard.cr_originalsenderdisplay` | No |
| Category | `cr_senderprofile.cr_sendercategory` | Yes |
| Interaction count | `cr_senderprofile.cr_interactioncount` | No |
| Response patterns | `cr_senderprofile.cr_responsepatterns` | No |

### Override Controls

Three toggle buttons (mutually exclusive, radio-style):

| Button | Writes | Effect |
|--------|--------|--------|
| **Always FULL** | `cr_sendercategory = "USER_OVERRIDE"`, `cr_overridetier = "FULL"` | All future items from this sender get FULL triage |
| **Always LIGHT** | `cr_sendercategory = "USER_OVERRIDE"`, `cr_overridetier = "LIGHT"` | All future items get LIGHT triage |
| **Always SKIP** | `cr_sendercategory = "USER_OVERRIDE"`, `cr_overridetier = "SKIP"` | All future items are skipped |

**Reset button:** "Reset to automatic" sets `cr_sendercategory = "AUTO"` and clears
`cr_overridetier`.

### PCF Output

```
onSenderOverride: JSON {
    senderEmail: string,
    newCategory: "FULL" | "LIGHT" | "SKIP" | "AUTO"
}
```

The Canvas app `OnChange` handler upserts `cr_senderprofile` (alternate key:
`cr_senderemail + cr_ownerid`).

---

## 3. Card Auto-Archive

### Purpose

Prevent the dashboard from accumulating stale LIGHT-tier cards. Cards that received no
user interaction after 48 hours are automatically dismissed.

### Rule

```
IF   cr_triagetier  = "LIGHT"
AND  cr_cardstatus  = "READY"
AND  cr_createdon   < UtcNow() - 48 hours
AND  cr_cardoutcome IS NULL  (no user action taken)
THEN set cr_cardoutcome = "AUTO_ARCHIVED"
     set cr_cardstatus  = "DISMISSED"
```

> **Note:** `AUTO_ARCHIVED` is a new `CardOutcome` value. The PCF `types.ts` union
> must be extended.

### Implementation — Scheduled Flow

| Property | Value |
|----------|-------|
| **Trigger** | Recurrence — every 6 hours |
| **Scope** | Organization (processes all users) |
| **Query** | `cr_assistantcards?$filter=cr_triagetier eq 'LIGHT' and cr_cardstatus eq 'READY' and cr_createdon lt {threshold} and cr_cardoutcome eq null` |
| **Action** | For each matching row: `PATCH` with `cr_cardoutcome = "AUTO_ARCHIVED"`, `cr_cardstatus = "DISMISSED"` |
| **Batch size** | Process in batches of 50 to respect Dataverse API limits |

### User Opt-Out

| Column | Table | Type | Default |
|--------|-------|------|---------|
| `cr_autoarchiveenabled` | `cr_userpersona` | Boolean | `true` |

When `cr_autoarchiveenabled = false`, the flow excludes that user's cards by joining
on `cr_ownerid`.

---

## 4. External Action Detection

### Purpose

Auto-dismiss cards when the user has already handled the item outside EWA (e.g.,
replied directly in Outlook). This eliminates the most common source of stale cards.

> **Pattern:** Adapted from Email Productivity Agent Flow 2 (Response Detection).
> See `email-productivity-agent/docs/` for the reference implementation.

### Implementation — Scheduled Flow

| Property | Value |
|----------|-------|
| **Trigger** | Recurrence — every 15 minutes |
| **Scope** | Per-user (runs under delegated connection) |

### Flow Steps

1. **Query recent Sent Items** — Graph API: `GET /me/mailFolders/SentItems/messages?$filter=sentDateTime ge {15 min ago}&$select=conversationId,internetMessageHeaders`
2. **Extract identifiers** — For each sent message, extract:
   - `conversationId` (Exchange conversation threading)
   - `In-Reply-To` header from `internetMessageHeaders`
3. **Match against open cards** — Query: `cr_assistantcards?$filter=cr_cardstatus eq 'READY' and cr_conversationclusterid in ({conversationIds})`
4. **Dismiss matched cards** — For each match:
   ```
   cr_cardoutcome = "HANDLED_EXTERNALLY"
   cr_cardstatus  = "DISMISSED"
   ```

> **Note:** `HANDLED_EXTERNALLY` is a new `CardOutcome` value. The PCF `types.ts`
> union must be extended.

### Edge Cases

| Scenario | Handling |
|----------|----------|
| User replies to a thread but card covers a different message in the same thread | Match is still valid — the thread is being actively managed |
| Sent Item is a new message (no In-Reply-To) | No match — only threaded replies trigger detection |
| Graph API throttled | Retry with exponential backoff; skip cycle after 3 failures |

---

## 5. Skill Registry Management UI

### Purpose

Provide a browsing and management interface for user-created skills (reusable
action sequences). Skills are stored in `cr_skillregistry`.

### Access

- **Settings → Skills tab** (via `StatusBar` settings button)
- **Command bar:** Type `manage skills` to navigate directly

### Browse View

A scrollable list with columns:

| Column | Source | Sortable |
|--------|--------|----------|
| Name | `cr_skillname` | Yes |
| Description | `cr_skilldescription` | No |
| Visibility | `cr_skillvisibility` (`PERSONAL` / `SHARED`) | Yes |
| Usage count | `cr_usagecount` | Yes |
| Last used | `cr_lastuseddate` | Yes |
| Success rate | `cr_successrate` (percentage) | Yes |

### Create Skill Form

| Field | Control | Required |
|-------|---------|----------|
| Name | Text input (max 100 chars) | Yes |
| Description | Textarea (max 500 chars) | Yes |
| Trigger pattern | Text input (natural language pattern) | Yes |
| Action steps | Ordered list editor (add/remove/reorder) | Yes (min 1) |
| Visibility | Toggle: Personal / Shared | No (default: Personal) |

### Test Skill

- "Try this skill" button appears after creation or on any existing skill.
- Opens the `CommandBar` with the trigger pattern pre-populated.
- Execution uses the standard `commandAction` pipeline.
- Result displayed inline with success/failure indicator.

### Visibility Toggle

- Only the skill **owner** (`cr_ownerid`) can toggle between `PERSONAL` and `SHARED`.
- Shared skills are read-only for non-owners.
- Toggle fires PCF output:

```
onSkillVisibilityChange: JSON {
    skillId: string,
    visibility: "PERSONAL" | "SHARED"
}
```

### Stats Display

For each skill, a compact stats row:

```
Used 42 times · 95% success · Avg 2.3s
```

Values sourced from `cr_usagecount`, `cr_successrate`, `cr_avgexecutiontime`.

---

## 6. CSS Dark Mode Design

### Problem

The current stylesheet (`AssistantDashboard.css`) and `constants.ts` contain
approximately 48 hardcoded hex color values. This prevents theme switching and makes
dark mode impossible without duplicating every color rule.

### Strategy

Replace all hardcoded colors with CSS custom properties, then provide light and dark
value sets.

### Phase 1 — Define CSS Custom Properties

```css
:root {
    /* Backgrounds */
    --ewa-bg-primary: #fafaff;
    --ewa-bg-secondary: #f0f0f8;
    --ewa-bg-surface: #ffffff;
    --ewa-bg-hover: #eeeef6;
    --ewa-bg-selected: #e8e8f4;

    /* Text */
    --ewa-text-primary: #1a1a2e;
    --ewa-text-secondary: #595959;
    --ewa-text-tertiary: #8c8c8c;
    --ewa-text-inverse: #ffffff;

    /* Brand */
    --ewa-brand: #6366f1;
    --ewa-brand-hover: #4f46e5;
    --ewa-brand-subtle: #eef2ff;
    --ewa-heartbeat: #8b5cf6;
    --ewa-heartbeat-bg: #f5f3ff;

    /* Priority */
    --ewa-priority-high: #ef4444;
    --ewa-priority-high-bg: #fef2f2;
    --ewa-priority-medium: #f59e0b;
    --ewa-priority-medium-bg: #fffbeb;
    --ewa-priority-low: #22c55e;
    --ewa-priority-low-bg: #f0fdf4;

    /* Confidence */
    --ewa-confidence-high: #16a34a;
    --ewa-confidence-mid: #ca8a04;
    --ewa-confidence-low: #dc2626;

    /* Borders & Dividers */
    --ewa-border: #e0e0f0;
    --ewa-border-subtle: #f0f0f8;
    --ewa-divider: #e5e5e5;

    /* Shadows */
    --ewa-shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.05);
    --ewa-shadow-md: 0 4px 6px rgba(0, 0, 0, 0.07);
    --ewa-shadow-lg: 0 10px 15px rgba(0, 0, 0, 0.1);

    /* Stale */
    --ewa-stale: #f59e0b;
    --ewa-stale-bg: #fffbeb;

    /* Status */
    --ewa-success: #16a34a;
    --ewa-success-bg: #f0fdf4;
    --ewa-warning: #f59e0b;
    --ewa-warning-bg: #fffbeb;
    --ewa-error: #dc2626;
    --ewa-error-bg: #fef2f2;
    --ewa-info: #3b82f6;
    --ewa-info-bg: #eff6ff;

    /* Briefing card gradient */
    --ewa-briefing-bg: linear-gradient(135deg, #f0f4ff 0%, #faf0ff 100%);
    --ewa-briefing-border: #d0d0e8;

    /* Misc */
    --ewa-overlay: rgba(0, 0, 0, 0.4);
    --ewa-focus-ring: #6366f1;
    --ewa-scrollbar-thumb: #c0c0d0;
    --ewa-scrollbar-track: #f0f0f8;
}
```

### Phase 2 — Replace Hardcoded Colors

Systematically replace each hex value in `AssistantDashboard.css` and inline styles
with the corresponding `var(--ewa-*)` token. Also update `EWA_COLORS` in
`constants.ts` to reference CSS custom properties via `getComputedStyle()` where
values are needed in TypeScript.

**Example migration:**

```css
/* Before */
.briefing-card {
    background: linear-gradient(135deg, #f0f4ff 0%, #faf0ff 100%);
    border: 1px solid #d0d0e8;
}

/* After */
.briefing-card {
    background: var(--ewa-briefing-bg);
    border: 1px solid var(--ewa-briefing-border);
}
```

### Phase 3 — Dark Theme Values

```css
@media (prefers-color-scheme: dark) {
    :root {
        --ewa-bg-primary: #1a1a2e;
        --ewa-bg-secondary: #2a2a3e;
        --ewa-bg-surface: #242438;
        --ewa-bg-hover: #32324a;
        --ewa-bg-selected: #3a3a52;

        --ewa-text-primary: #e8e8f0;
        --ewa-text-secondary: #a0a0b0;
        --ewa-text-tertiary: #707080;
        --ewa-text-inverse: #1a1a2e;

        --ewa-brand: #818cf8;
        --ewa-brand-hover: #6366f1;
        --ewa-brand-subtle: #2a2a4e;
        --ewa-heartbeat: #a78bfa;
        --ewa-heartbeat-bg: #2a2a4e;

        --ewa-priority-high: #f87171;
        --ewa-priority-high-bg: #3a1a1a;
        --ewa-priority-medium: #fbbf24;
        --ewa-priority-medium-bg: #3a2e1a;
        --ewa-priority-low: #4ade80;
        --ewa-priority-low-bg: #1a3a1a;

        --ewa-confidence-high: #4ade80;
        --ewa-confidence-mid: #fbbf24;
        --ewa-confidence-low: #f87171;

        --ewa-border: #3a3a52;
        --ewa-border-subtle: #2a2a3e;
        --ewa-divider: #3a3a52;

        --ewa-shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.3);
        --ewa-shadow-md: 0 4px 6px rgba(0, 0, 0, 0.4);
        --ewa-shadow-lg: 0 10px 15px rgba(0, 0, 0, 0.5);

        --ewa-stale: #fbbf24;
        --ewa-stale-bg: #3a2e1a;

        --ewa-success: #4ade80;
        --ewa-success-bg: #1a3a1a;
        --ewa-warning: #fbbf24;
        --ewa-warning-bg: #3a2e1a;
        --ewa-error: #f87171;
        --ewa-error-bg: #3a1a1a;
        --ewa-info: #60a5fa;
        --ewa-info-bg: #1a2a3a;

        --ewa-briefing-bg: linear-gradient(135deg, #1a1a3e 0%, #2a1a3e 100%);
        --ewa-briefing-border: #3a3a52;

        --ewa-overlay: rgba(0, 0, 0, 0.6);
        --ewa-focus-ring: #818cf8;
        --ewa-scrollbar-thumb: #4a4a62;
        --ewa-scrollbar-track: #2a2a3e;
    }
}
```

### Canvas App Limitation

Canvas apps do not propagate `prefers-color-scheme` into embedded PCF controls. To
support explicit theme toggling, also accept a `.ewa-dark` CSS class on the root
`<div>` of the control:

```css
.ewa-dark {
    /* Identical overrides as the @media block above */
    --ewa-bg-primary: #1a1a2e;
    --ewa-bg-secondary: #2a2a3e;
    /* ... */
}
```

The Canvas app sets this class via the existing `themeOverride` input property (new
value: `"dark"`). The PCF `AppWrapper` component applies `className="ewa-dark"` when
`themeOverride === "dark"`.

### Migration Checklist

- [ ] Phase 1: Add `:root` custom properties block to `AssistantDashboard.css`
- [ ] Phase 2: Replace all 48 hardcoded hex colors with `var(--ewa-*)` references
- [ ] Phase 2: Update `EWA_COLORS` in `constants.ts` to use CSS variable fallback
- [ ] Phase 3: Add `@media (prefers-color-scheme: dark)` block
- [ ] Phase 3: Add `.ewa-dark` class block
- [ ] Phase 3: Add `themeOverride` input property handling in `AppWrapper`
- [ ] Visual regression test: compare light theme before/after variable migration

---

## 7. Keyboard Shortcuts

### Shortcut Map

| Key | Action | Context |
|-----|--------|---------|
| `j` | Select next card in gallery | Gallery view, no input focused |
| `k` | Select previous card in gallery | Gallery view, no input focused |
| `Enter` | Open selected card detail | Card selected in gallery |
| `Escape` | Close detail panel | Detail panel open (already implemented) |
| `d` | Dismiss current card | Card selected or detail open |
| `s` | Send draft | Detail open with sendable draft |
| `/` | Focus command bar | Any view, no input focused |
| `?` | Show keyboard shortcuts help overlay | Any view, no input focused |

### Implementation

Add a global `keydown` event listener on the `.assistant-dashboard` container element
in `App.tsx`:

```typescript
useEffect(() => {
    const handler = (e: KeyboardEvent) => {
        const target = e.target as HTMLElement;
        const isInput = target.tagName === "INPUT"
            || target.tagName === "TEXTAREA"
            || target.isContentEditable;

        if (isInput) return;

        switch (e.key) {
            case "j": selectNextCard(); break;
            case "k": selectPreviousCard(); break;
            case "Enter": openSelectedCard(); break;
            case "d": dismissSelectedCard(); break;
            case "s": sendCurrentDraft(); break;
            case "/": e.preventDefault(); focusCommandBar(); break;
            case "?": setShowShortcutsHelp(true); break;
        }
    };

    containerRef.current?.addEventListener("keydown", handler);
    return () => containerRef.current?.removeEventListener("keydown", handler);
}, [/* deps */]);
```

### Help Overlay

A modal overlay triggered by `?` showing all shortcuts in a two-column table. Dismissed
by `Escape` or clicking outside. Rendered as a new `KeyboardShortcutsHelp` component.

### Accessibility

- All shortcut-driven actions remain accessible via mouse and touch.
- Shortcuts are disabled when any text input, textarea, or contentEditable element is
  focused.
- The help overlay is announced to screen readers via `role="dialog"` and
  `aria-label="Keyboard shortcuts"`.
- Shortcut hints are **not** shown on card buttons to avoid visual clutter; they are
  discoverable via the `?` overlay only.

---

## 8. Card Thread View

### Purpose

Show a conversation timeline when multiple cards share the same
`cr_conversationclusterid`. This helps users see the full history of an email thread
or Teams conversation across triage cycles.

### Access

A **thread icon** (chain link or conversation bubble) appears on any `CardItem` where
other cards share the same `cr_conversationclusterid`. Clicking it opens the thread
view.

### Thread View Layout

Vertical timeline rendered in the `CardDetail` panel area:

```
┌─────────────────────────────────┐
│  Thread: Re: Q3 Budget Review   │
│  3 cards · Started 2 days ago   │
├─────────────────────────────────┤
│                                 │
│  ● EMAIL · High · 2d ago        │  ← First card
│    "Initial budget request..."  │
│    → SENT_AS_IS                 │
│                                 │
│  ● EMAIL · Medium · 1d ago      │  ← Second card
│    "Follow-up with revisions"   │
│    → DISMISSED                  │
│                                 │
│  ◉ EMAIL · High · 2h ago        │  ← Current card (highlighted)
│    "Final approval needed"      │
│    → PENDING                    │
│                                 │
└─────────────────────────────────┘
```

### Timeline Node Design

Each node shows:

| Element | Source |
|---------|--------|
| Icon | Determined by `trigger_type` (envelope for EMAIL, chat bubble for TEAMS, etc.) |
| Priority color | Left border color from priority (High=red, Medium=amber, Low=green) |
| Timestamp | `cr_createdon` — absolute + relative (e.g., "Jul 12, 2:30 PM · 2 days ago") |
| Summary | `cr_itemsummary` (truncated to 80 chars) |
| Outcome badge | `cr_cardoutcome` rendered as a pill (color-coded) |
| Current indicator | Filled circle (`◉`) for the card that opened the thread view |

### Data Query

```
cr_assistantcards?$filter=cr_conversationclusterid eq '{selectedClusterId}'
    &$orderby=cr_createdon asc
    &$select=cr_assistantcardid,cr_triggertype,cr_priority,cr_itemsummary,
             cr_cardoutcome,cr_cardstatus,cr_createdon
```

> **Note:** This query runs in the Canvas app and passes results to the PCF via a
> secondary dataset binding or a JSON input property. See
> [canvas-app-setup.md](canvas-app-setup.md) §8 for dataset binding patterns.

### Navigation

Clicking any node in the timeline navigates to that card's `CardDetail` view, using
the existing `onSelectCard` mechanism.

---

## 9. Card Pin/Star Feature

### Purpose

Let users pin important cards to the top of the feed for quick access without
dismissing them.

### New Card Outcome

```
CardOutcome: "PINNED"
```

> Unlike other outcomes (`SENT_AS_IS`, `DISMISSED`, etc.), `PINNED` does **not**
> dismiss the card. The card remains in `cr_cardstatus = "READY"` and stays visible.

### UI

- **Star icon** in the `CardItem` header (right-aligned, beside the priority badge).
- Unfilled star = not pinned; filled star = pinned.
- Click to toggle.

### Feed Section Order

`CardGallery.groupCards()` adds a new top-level section:

```
1. Pinned            ← NEW (cards with cr_cardoutcome = "PINNED")
2. Action Required
3. Proactive Alerts
4. New Signals
5. FYI
6. Needs Attention
```

Pinned cards are sorted by `cr_createdon` descending (newest pinned first).

### PCF Output

```
onPinCard: JSON {
    cardId: string,
    pinned: boolean
}
```

**Pin action:** Canvas app sets `cr_cardoutcome = "PINNED"` (card stays `READY`).

**Unpin action:** Canvas app sets `cr_cardoutcome = NULL`, `cr_cardstatus = "READY"`
(card returns to its natural feed section).

### Constraints

- A card cannot be both `PINNED` and another outcome simultaneously.
- Sending or dismissing a pinned card removes the pin (outcome changes to
  `SENT_AS_IS`, `DISMISSED`, etc.).

---

## 10. Snooze with Wake-Up Time

### Purpose

Allow users to temporarily hide a card and have it resurface at a chosen time. This
reuses the existing `SELF_REMINDER` infrastructure (Flow 10: Reminder Firing).

### Access

**Snooze button** on the `CardDetail` panel → opens a date/time picker popover.

### Quick Options

| Label | Computed Time |
|-------|--------------|
| In 1 hour | `now + 1h` |
| Tomorrow morning | Next day at user's `cr_briefingtime` (default `07:30`) |
| Next Monday | Next Monday at `cr_briefingtime` |
| Custom… | Opens full date/time picker |

### Snooze Flow

1. User selects a wake-up datetime.
2. PCF fires output:
   ```
   onSnoozeCard: JSON {
       cardId: string,
       wakeUpTime: string  // ISO 8601
   }
   ```
3. Canvas app updates the card:
   ```
   cr_cardstatus   = "SNOOZED"
   cr_remindertime = {selected datetime}
   ```
4. Card disappears from the feed (filtered out by `cr_cardstatus ≠ "SNOOZED"`).
5. **Flow 10 (Reminder Firing)** checks `cr_remindertime` on its existing schedule.
   When `cr_remindertime ≤ UtcNow()`:
   ```
   cr_cardstatus = "READY"
   cr_remindertime = NULL
   ```
6. Card reappears in the feed with a visual indicator: `"Snoozed — now active"` badge
   (amber pill, similar to the stale indicator).

> **Note:** `SNOOZED` is a new `CardStatus` value. The PCF `types.ts` union and
> `FilterBar` component must be updated to handle it.

### Edge Cases

| Scenario | Handling |
|----------|----------|
| User snoozes a pinned card | Pin is cleared (`cr_cardoutcome = NULL`) before snoozing |
| Wake-up time is in the past | Card immediately re-activates on next flow run |
| Card is auto-archived while snoozed | Auto-archive flow skips cards with `cr_cardstatus = "SNOOZED"` |

---

## 11. Batch Actions

### Purpose

Allow users to perform bulk operations on multiple cards at once, reducing repetitive
clicks when processing a backlog of low-priority items.

### Multi-Select Mode

- **Checkbox** appears on each `CardItem` on hover (left side, before the priority
  indicator).
- Clicking the checkbox toggles selection without opening the card.
- **Header checkbox** in the `CardGallery` section header selects/deselects all
  visible cards in that section.
- Selection state is managed via React state in `App.tsx`:
  `const [selectedCardIds, setSelectedCardIds] = useState<Set<string>>(new Set())`.

### Batch Action Bar

When `selectedCardIds.size > 0`, a floating action bar appears at the bottom of the
gallery (above the `CommandBar`):

```
┌───────────────────────────────────────────────────┐
│  ✓ 7 selected    [Dismiss All] [Snooze All] [Mark Read]  [Cancel]  │
└───────────────────────────────────────────────────┘
```

### Available Actions

| Action | Behavior |
|--------|----------|
| **Dismiss All** | Sets `cr_cardoutcome = "DISMISSED"`, `cr_cardstatus = "DISMISSED"` for all selected |
| **Snooze All** | Opens the snooze time picker (§10), applies the same time to all selected |
| **Mark All Read** | Sets a `cr_isread = true` flag (removes "new" badge) without dismissing |

### Confirmation Dialog

Before executing any batch action, display a confirmation:

```
Dismiss 7 cards?
This cannot be undone.
[Cancel]  [Dismiss]
```

### PCF Output

```
onBatchAction: JSON {
    cardIds: string[],
    action: "DISMISS" | "SNOOZE" | "MARK_READ",
    snoozeTime?: string  // ISO 8601, only for SNOOZE action
}
```

The Canvas app processes cards **sequentially** using a `ForAll()` loop to respect
Dataverse transaction limits.

### Limits

| Constraint | Value | Reason |
|------------|-------|--------|
| Max batch size | 25 cards | Prevent Canvas app `ForAll()` timeout (default 60s) |
| Selection overflow | "Select up to 25 cards" toast | Shown when user tries to select card #26 |
| Undo | Not supported in v1 | Batch operations are final after confirmation |

---

## Appendix: Type Extensions Summary

The following type changes are required across all enhancements:

```typescript
// types.ts additions

export type TriggerType =
    | /* existing values */
    | "ONBOARDING";          // §1

export type CardStatus =
    | /* existing values */
    | "SETUP"                // §1
    | "SNOOZED";             // §10

export type CardOutcome =
    | /* existing values */
    | "AUTO_ARCHIVED"        // §3
    | "HANDLED_EXTERNALLY"   // §4
    | "PINNED";              // §9
```

> **Important:** Dataverse option sets must be updated to include these new values
> before deploying the corresponding flows or PCF changes. See
> [deployment-guide.md](deployment-guide.md) for option set update procedures.

---

## Interaction Patterns

- **Progressive Disclosure (Glance → Act → Go Deep)**:
  - Glance: CardItem shows priority badge, sender, subject, 1-line summary
  - Act: CardDetail expands to research log, key findings, sources, humanized draft, action buttons
  - Go Deep: Command bar for natural language queries, thread view for conversation history
- **Pull-Based Interruption Model**: Cards appear in dashboard (user opens app). No push notifications. Daily briefing is opt-in via schedule. Stale alerts shown in briefing card, not separate notifications.
- **Inline Actions**: Send (EMAIL FULL only, explicit click required), Edit (inline with autosave), Dismiss, Copy, Snooze
- **Command Pattern**: Natural language input → structured response + side effects. No auto-execution of complex commands.
- **What stays hidden**: SKIP items not surfaced. Low-confidence research shown with warning badge, not hidden.

---

## Graduated Trust Tiers (Future Design)

Design for production deployment — extending the tone inference gating pattern:

| Trust Tier | Trigger | Capability |
|-----------|---------|------------|
| **Observe** (Day 0-14) | Default for new users | Triage + research only. Summaries shown, no drafts generated. System builds sender profiles silently. |
| **Assist** (Day 15-30) | Acceptance rate ≥ 30% | Drafts generated but behind "Show Draft" click. Learning suggestions enabled. |
| **Partner** (Day 31+) | Acceptance rate ≥ 50%, override rate ≤ 20% | Full capability. Drafts shown inline. Active learning triggers. |
| **Never auto-send** | Permanent | Send always requires explicit user action. Inviolable. |

Implementation: Extend cr_userpersona with cr_trusttier (Choice) and cr_trusttierchangedon (DateTime). Flow 5 evaluates tier advancement criteria on each outcome event.

---

## SKIP Audit Log (Future Design)

Address the biggest trust gap: "What if it skips something important?"

- Lightweight logging table: cr_skipaudit with columns: cr_signalid, cr_senderaddress, cr_subjectline, cr_skipreason, cr_createdon
- Retention: 7 days (short — just enough to verify nothing was missed)
- UI: "View skipped items" link in StatusBar showing last 24 hours
- Privacy: Store subject line hash + sender, not full email body
