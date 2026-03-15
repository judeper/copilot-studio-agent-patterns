# IWL Design Review — Productivity & Noise Reduction Assessment

## Problem Statement

Review the Intelligent Work Layer's design to assess whether it effectively makes users productive and shields them from noise, and identify improvements to enhance this experience.

---

## Part 1: What's Working Well

The IWL has strong cognitive science foundations. These elements are effective:

| Feature | Why It Works |
|---------|-------------|
| **Three-tier triage (SKIP/LIGHT/FULL)** | Hard noise gate — SKIP items never reach Dataverse, LIGHT items get summary-only treatment. This is the single most important productivity feature. |
| **5-item focused queue** | Grounded in Cowan's 4±1 working memory research. Prevents inbox-paralysis. |
| **Quiet mode** | One-click focus protection filters Medium-priority cards. Respects Gloria Mark's 23-minute recovery cost. |
| **Three-state confidence** | "Ready / Review suggested / Draft only" avoids the false precision of percentages. Reduces decision fatigue. |
| **Pull-based briefings** | Morning/EOD/Meeting briefings are opt-in, not push notifications. Pull > push for deep work. |
| **Draft ownership framing** | "Your draft" + cursor mid-text leverages Zeigarnik effect — users feel invested, not replaced. |
| **Progressive disclosure** | Research log, sources, key findings hidden behind expand toggles. Info-on-demand prevents overload. |
| **Feed sectioning** | Auto-bucketing into Action Required / Proactive Alerts / New Signals / FYI / Needs Attention — users scan sections, not individual items. |
| **EWMA learning** | 30% recent / 70% historical prevents over-fitting to outliers. Sender profiles improve over time. |
| **Warm-gray palette + reduced motion** | Sustained-use visual design reduces fatigue. |

**Verdict**: The cognitive science grounding is excellent. The _design intent_ is right. The gaps are in **what's designed but not built** and **what's missing from the design entirely**.

---

## Part 2: Critical Gaps — Noise Still Getting Through

### Gap 1: No Conversation Threading (HIGH IMPACT)
**Problem**: A 5-message email thread creates 5 separate cards. The 5-item queue fills with ONE conversation. This is the #1 noise amplifier.
**Evidence**: `conversationclusterid` field exists in the schema but CardGallery doesn't group by it. Card thread view is designed (UX §8) but not implemented.
**Fix**: Implement conversation clustering in CardGallery — show the latest card per cluster, with a "3 related" badge that expands inline. This alone could reduce visible card count by 40-60%.

### Gap 2: No Snooze/Defer (HIGH IMPACT)
**Problem**: Users can only Send or Dismiss. No "remind me at 2pm" or "surface this tomorrow". This forces premature decisions — users either dismiss things they should revisit, or leave them cluttering the queue.
**Evidence**: Snooze is designed (UX §10, leveraging Flow 10 reminder infrastructure) but not implemented. The Reminder Firing flow (Flow 10) already exists.
**Fix**: Add snooze UI with presets (1 hour, tomorrow morning, Friday, custom) that sets `cr_reminderat` and card_status = SNOOZED. Flow 10 already handles the re-surfacing.

### Gap 3: No External Action Detection (HIGH IMPACT)
**Problem**: If a user replies to an email directly in Outlook (bypassing IWL), the card stays in "Action Required" as a phantom task. The user sees work they've already done.
**Evidence**: Flow 5 (Card Outcome Tracker) is designed to detect this via Sent Items polling, but implementation notes say "POC scaffolding" and the detection window is unclear.
**Fix**: Implement the 15-minute Sent Items scan from UX §4. Match by `internetMessageId` or `conversationId`. Auto-dismiss cards with outcome = RESOLVED_EXTERNALLY.

### Gap 4: No Batch Actions (MEDIUM-HIGH IMPACT)
**Problem**: 10 FYI items = 10 individual dismiss clicks. Users avoid the FYI section entirely because clearing it is tedious.
**Evidence**: Batch actions designed (UX §11, 25-card max) but not implemented. No multi-select UI exists.
**Fix**: Add checkbox selection to CardItem + batch action bar (Dismiss All, Snooze All, Archive All). Cap at 25 cards per batch operation.

### Gap 5: LIGHT Tier Card Accumulation (MEDIUM IMPACT)
**Problem**: LIGHT-tier cards (summary-only, no draft) accumulate indefinitely. After a week, the "New Signals" section has 50+ items — noise.
**Evidence**: Auto-archive after 48h designed (UX §3) but not implemented. No scheduled cleanup flow exists.
**Fix**: Implement the 6-hour scheduled flow that marks LIGHT-tier cards with `card_status = EXPIRED` after 48 hours of no interaction.

### Gap 6: No Signal Batching (MEDIUM IMPACT)
**Problem**: Every email/Teams message triggers an immediate agent invocation. During a busy morning, 20 emails arrive in 30 minutes → 20 agent runs → 20 cards appear. Even with quiet mode on, the user sees "20 items waiting" and feels overwhelmed.
**Evidence**: No batching mechanism exists. Each flow trigger processes independently.
**Fix**: Add a 5-minute batching window to Flows 1-2. Collect signals, deduplicate by sender+subject, then invoke the agent once per batch. For email threads, only process the latest message in a thread within the window.

### Gap 7: No Focus Session Integration (MISSING FROM DESIGN)
**Problem**: IWL doesn't know when the user is in deep work. Calendar has "Focus Time" blocks, and Windows/Teams has "Do Not Disturb" — but IWL keeps processing signals and growing the queue during these periods.
**Evidence**: The FocusLaneModel exists in Work OS models (`review.ts`) with `interruptionsHeld` and `focusWindowEnd`, but nothing in the agent flows reads calendar focus blocks or DND status.
**Fix**: Before agent invocation in Flows 1-2, check if user's calendar has a "Focus Time" event in progress. If so, auto-triage all non-URGENT signals to LIGHT tier (never FULL) and defer queue delivery until focus window ends. This could be a "Focus Shield" feature.

---

## Part 3: Trust & Learning Gaps

### Gap 8: No Graduated Autonomy (MISSING FROM DESIGN)
**Problem**: The system is either fully manual (user reviews every draft) or nothing. There's no progression from "show me everything" → "handle routine stuff yourself." Trust is binary.
**Evidence**: UX §5 mentions Observer→Assist→Partner tiers but this is only a concept with no implementation path. The confidence scoring and acceptance rate data are there to power it.
**Fix**: Implement three autonomy tiers:
- **Observer** (default, first 30 days): All items shown, all drafts require review
- **Assist** (acceptance rate >70%, >50 interactions): Auto-dismiss LIGHT items matching learned SKIP patterns. Auto-send drafts with confidence ≥95 to AUTO_HIGH senders (with undo window)
- **Partner** (acceptance rate >85%, >200 interactions): Auto-send all ≥90 confidence drafts with 30-second undo window. Surface only exceptions.
The transition should be suggested by the system, confirmed by the user.

### Gap 9: No "Why Did I Get This?" Explainability (MEDIUM IMPACT)
**Problem**: Users see the urgency rationale on cards but can't trace the full decision chain. "Why was this FULL and not LIGHT?" is unanswerable from the UI.
**Evidence**: The Triage Agent's internal reasoning is lost after classification. Only `urgency_rationale` is surfaced. No triage audit trail in the card.
**Fix**: Add a `triage_reasoning` field to the output schema — a 2-3 sentence explanation of the classification decision, including which sender profile signals and keyword matches drove the tier assignment. Surface it as an expandable "Why this priority?" section in CardDetail.

### Gap 10: Learning System Cold Start (LOW-MEDIUM IMPACT)
**Problem**: The 5-interaction minimum for tone gating means early drafts feel generic and impersonal. Users dismiss them → low acceptance rate → system thinks it's wrong → vicious cycle.
**Evidence**: learning-enhancements.md specifies confidence gating at 50% acceptance + ≥5 interactions. Graph bootstrap imports 90 days of history for sender profiles, but not for tone preferences.
**Fix**: During the Graph bootstrap phase, analyze the user's own sent email patterns (formality, greeting style, sign-off patterns) to seed the UserPersona with baseline tone preferences from day one. This gives drafts a fighting chance before per-sender learning kicks in.

---

## Part 4: UX Polish Gaps

### Gap 11: No Search (MEDIUM IMPACT)
**Problem**: Users can't search past cards by sender, subject, or content. As cards accumulate, finding "that email from Sarah about the Q3 budget" requires scrolling.
**Fix**: Add a search input to FilterBar that filters cards by sender, subject, summary text. Use client-side filtering on the loaded dataset.

### Gap 12: No Keyboard Navigation (LOW-MEDIUM IMPACT)
**Problem**: Power users can't navigate the dashboard without a mouse. Designed (UX §7: j/k/Enter/d/s/?) but not implemented.
**Fix**: Implement keyboard shortcuts with a help overlay (triggered by `?`).

### Gap 13: No Undo for Destructive Actions (LOW-MEDIUM IMPACT)
**Problem**: Dismiss and Send are immediate and permanent. No toast with "Undo" option.
**Fix**: Add 10-second undo toast for dismiss and send actions. Hold the Dataverse write for the undo window.

### Gap 14: No Onboarding (LOW IMPACT FOR POC)
**Problem**: First-run experience is blank dashboard. No setup wizard, no explanation of what IWL does.
**Evidence**: Onboarding designed (UX §1: 3-step wizard) but not implemented.
**Fix**: Implement the 3-step onboarding: display name confirmation, briefing schedule setup, command bar trial.

---

## Part 5: Architectural Improvements

### Gap 15: No Card Deduplication (MEDIUM IMPACT)
**Problem**: Rapid-fire email replies or Teams messages can create duplicate cards for the same conversation within seconds.
**Evidence**: Designed in architecture-enhancements.md (5-minute window query by `conversationclusterid`) but not implemented.
**Fix**: In Flows 1-2, before invoking the agent, query Dataverse for cards with matching `conversationclusterid` created within last 5 minutes. If found, update the existing card instead of creating a new one.

### Gap 16: No Degraded Mode (LOW-MEDIUM IMPACT)
**Problem**: If the Copilot Studio agent is unavailable (throttled, down), signals are silently lost. No card created, no notification.
**Evidence**: Designed in architecture-enhancements.md (3 retries → PENDING_MANUAL card) but not implemented.
**Fix**: Implement retry logic in Flows 1-3 with fallback: after 3 failures, create a minimal card with `card_status = PENDING_MANUAL` containing the raw signal payload so users can act manually.

### Gap 17: No Data Retention Automation (LOW IMPACT FOR POC)
**Problem**: AssistantCards grow indefinitely. After months, the Dataverse table has thousands of resolved cards consuming storage.
**Fix**: Implement a weekly scheduled flow that archives cards with `card_outcome != PENDING` older than 90 days.

---

## Proposed Implementation Priority

Ordered by impact on user productivity and noise reduction:

| Priority | Todo ID | Gap | Impact | Complexity |
|----------|---------|-----|--------|------------|
| **P0** | `conversation-threading` | Gap 1: Conversation Threading | Eliminates #1 noise amplifier | Medium |
| **P0** | `snooze-defer` | Gap 2: Snooze/Defer | Eliminates premature decisions | Low-Medium |
| **P0** | `external-action-detection` | Gap 3: External Action Detection | Eliminates phantom tasks | Medium |
| **P1** | `batch-actions` | Gap 4: Batch Actions | Makes FYI section usable | Low |
| **P1** | `light-tier-auto-archive` | Gap 5: LIGHT Tier Auto-Archive | Prevents LIGHT card pile-up | Low |
| **P1** | `signal-batching` | Gap 6: Signal Batching | Reduces morning card avalanche | Medium |
| **P1** | `focus-shield` | Gap 7: Focus Session Integration | Protects deep work blocks | Medium |
| **P2** | `graduated-autonomy` | Gap 8: Graduated Autonomy | Enables trust progression | High |
| **P2** | `triage-explainability` | Gap 9: Triage Explainability | Builds user trust | Low |
| **P2** | `cold-start-tone-bootstrap` | Gap 10: Cold Start Tone Bootstrap | Better early drafts | Medium |
| **P2** | `card-search` | Gap 11: Search | Findability for past cards | Low |
| **P3** | `keyboard-navigation` | Gap 12: Keyboard Navigation | Power user efficiency | Low |
| **P3** | `undo-actions` | Gap 13: Undo for Destructive Actions | Reduces anxiety | Low |
| **P3** | `onboarding-wizard` | Gap 14: Onboarding | First-run experience | Low |
| **P3** | `card-deduplication` | Gap 15: Card Deduplication | Prevents duplicate cards | Low |
| **P3** | `degraded-mode` | Gap 16: Degraded Mode | Prevents silent failures | Medium |
| **P3** | `data-retention` | Gap 17: Data Retention | Storage hygiene | Low |

---

## Approach

For each improvement, implementation involves a combination of:
- **Agent prompt updates** (adding fields like `triage_reasoning`, `conversation_cluster_action`)
- **Schema updates** (output-schema.json, Dataverse table definitions)
- **Flow updates** (agent-flows.md + JSON flow definitions)
- **PCF component updates** (React components, hooks, styles)
- **Design doc updates** (moving items from "Planned" to "Implemented")

The P0 items (conversation threading, snooze, external action detection) should be implemented first as they address the most significant noise leaks. Each can be implemented independently.
