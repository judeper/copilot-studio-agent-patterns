# AI Council Review — Second Brain Evolution Roadmap

**Date:** 2026-02-27
**Subject:** Enterprise Work Assistant → Second Brain Evolution Roadmap (4 Sprints)
**Convened by:** Jude Pereira, Principal Cloud Solution Architect

---

## Council Members

| Seat | Persona | Perspective |
|------|---------|-------------|
| **Architect** | Principal Solutions Architect with 15 years in Microsoft enterprise platforms | System design, integration patterns, long-term maintainability |
| **Product** | Senior Product Manager focused on AI-powered productivity tools | User value, adoption, prioritization, scope discipline |
| **Security & Governance** | Enterprise Security Architect specializing in FSI compliance | Data protection, delegated identity, regulatory risk, DLP |
| **Platform Engineer** | Power Platform + Copilot Studio deep specialist | Connector limits, throttling, licensing, Dataverse performance |
| **Pragmatist** | Staff engineer who has shipped and maintained systems at scale | What actually breaks in production, operational burden, what to cut |

---

## Round 1 — Individual Reviews

---

### 🔷 ARCHITECT

**Overall assessment: Strong foundation, some coupling concerns.**

The sprint ordering is correct. Contract-first (Sprint 1 schema), then synthesis (Sprint 2 briefing), then interaction (Sprint 3 command bar), then learning (Sprint 4 intelligence). This mirrors the data dependency graph precisely, and I appreciate that it was explicitly called out.

**What I'd change:**

**1. The Orchestrator Agent in Sprint 3 is doing too much.** It queries cards, refines drafts, creates reminders, looks up senders, and cross-references calendars. That's six distinct capabilities in one agent. In Copilot Studio, this means one massive system prompt with six tool actions registered. The generative orchestrator has to decide which tools to invoke based on natural language input, and with six tools, the routing accuracy will degrade. I'd recommend splitting the Orchestrator into two agents:

- **Query Agent** — Handles all read operations: card queries, sender lookups, calendar cross-references, thread summaries. This agent has read-only tool actions and cannot mutate state.
- **Action Agent** — Handles all write operations: draft refinement (calls Humanizer), reminder creation, card status updates. This agent has write tool actions and requires explicit user confirmation before executing.

The Command Execution Flow routes to the appropriate agent based on intent classification (which the flow can do with a simple keyword check before invoking the full agent). This separation improves debuggability, reduces prompt complexity per agent, and creates a natural security boundary between read and write operations.

**2. The `cr_conversationclusterid` design needs more thought.** The plan says EMAIL uses `conversationId`, TEAMS uses `threadId`, and CALENDAR uses a hash of `subject + organizer`. But what about cross-channel clustering? If someone emails you about "Project Alpha" and then mentions it in Teams, those should cluster together. A simple ID-based approach won't catch this. I'd recommend:

- Sprint 1: Ship with the simple per-channel IDs as specified (pragmatic, works now)
- Sprint 2: The Daily Briefing Agent performs entity-based clustering as a processing step (extract company names, project names, and people names from card summaries, then cluster by overlap). This is softer than an exact ID match but catches cross-channel threads.
- Defer true cross-channel clustering to Sprint 4 or beyond — it requires entity extraction at card creation time, which adds latency to the main agent.

**3. The archive pattern is mentioned in the risk register but not in any sprint.** The 30-day retention for EXPIRED/DISMISSED cards is noted, but no sprint includes the actual implementation — the Dataverse bulk delete job, the archive table schema, or the flow that moves data. This will bite you at week 6 when the table hits thousands of rows. I'd add a "Sprint 1.5" housekeeping task: a weekly scheduled flow that moves EXPIRED/DISMISSED cards older than 30 days to `cr_assistantcard_archive` (same schema, separate table, no RLS needed since it's analytics-only).

---

### 🟢 PRODUCT

**Overall assessment: The vision is right. The scope needs tightening.**

The "second brain" framing is compelling and the four sprints tell a clear value story: remember → synthesize → converse → learn. Each sprint delivers something the user can feel. That's good product thinking.

**What concerns me:**

**1. Sprint 1 delivers zero visible user value.** The user gets new buttons (Send, Acknowledge) and the system starts tracking outcomes in the background. But the user's daily experience is identical to v1.0. This is a problem for adoption and momentum. If Jude is building this for himself, motivation isn't an issue. But if this is also a reference pattern for FSI customers (which it is — that's the repo's purpose), Sprint 1 needs a visible win.

**My recommendation:** Pull the "one-click send" feature into Sprint 1. Right now, the user copies a draft from the Canvas app and pastes it into Outlook. Adding a "Send Email" button that calls a Power Automate flow to send via the Office 365 Outlook connector is straightforward AND it's the natural place to capture `cr_cardoutcome = SENT_AS_IS` vs `SENT_EDITED`. The send action and the outcome tracking become the same gesture. This makes Sprint 1 feel like an upgrade, not just plumbing.

**2. Sprint 2's Daily Briefing is the highest-value feature in the entire plan. Consider reordering.** The daily briefing is the first feature that makes the user *want* to open the dashboard proactively. Every other feature in the plan amplifies the value of the briefing. I understand the data dependency argument (the briefing is better with outcome data from Sprint 1), but a briefing that synthesizes open cards WITHOUT behavioral data is still dramatically more valuable than no briefing at all. The sender importance and staleness-based ranking can use simple heuristics (priority + age + sender domain) until Sprint 4's actual data is available.

**Counter-argument to myself:** The plan explicitly says Sprint 1 provisions the sender profile table and starts writing basic data. If Sprint 1 ships first, even one week of data makes Sprint 2 measurably better. Okay, I'll concede: the ordering is correct, but Sprint 1 MUST include the one-click send to justify its existence as a user-facing sprint.

**3. The command bar (Sprint 3) is exciting but risks scope creep.** Six capabilities is a lot. For a v1 command bar, I'd ship with three:
- "What needs my attention?" (card synthesis — the killer query)
- "Refine this draft" (iterative editing — the biggest friction reducer)
- "Remind me about [X] on [date]" (self-reminders — creates stickiness)

The sender lookup, thread summary, and calendar cross-reference commands are nice-to-haves. Ship them in Sprint 4 alongside sender intelligence, where they have the most data to work with.

**4. Success metrics need a "Week 1" column.** The plan jumps from "Unknown (no tracking)" to "Sprint 2 Target." Add a "Sprint 1, Week 1" column that just says "Baseline established — all metrics measurable." That's the actual Sprint 1 success criterion.

---

### 🔴 SECURITY & GOVERNANCE

**Overall assessment: Several areas need hardening before this goes to FSI customers.**

The v1.0 design has solid security foundations — ownership-based RLS, delegated identity, PII handling rules in the agent prompt. But the Second Brain evolution introduces new attack surface that the plan doesn't fully address.

**Critical issues:**

**1. The "Send Email" action (proposed by Product for Sprint 1) is a significant escalation of capability.** The v1.0 design principle is "prepare, never act." Sending an email on behalf of the user crosses that boundary. For FSI customers, this requires:

- **Explicit user confirmation UX** — The Canvas app must show the full draft, recipient, and subject line, and require a deliberate "Confirm and Send" action. No accidental sends.
- **Audit trail** — Every sent email must be logged in Dataverse with the full draft, recipient, timestamp, and whether it was sent as-is or after editing. This is not optional for regulated industries.
- **DLP policy review** — Adding the Office 365 Outlook "Send email" action to the Canvas app's flow means the Outlook connector is now being used for WRITE operations, not just READ. Verify this doesn't violate existing DLP policy configurations.
- **Scope limitation** — The send action should ONLY be available for drafts the agent generated. The user should not be able to compose arbitrary emails through this interface (that's what Outlook is for). This prevents the tool from becoming a shadow email client that bypasses corporate email policies.

I don't object to the feature — it's high value — but it needs these guardrails.

**2. The `cr_senderprofile` table contains behavioral intelligence that could be sensitive.** Knowing that someone responds to their CEO within 2 hours but takes 3 days to respond to a vendor is useful data — and potentially embarrassing or politically sensitive if exposed. For FSI:

- The table MUST be UserOwned with the same RLS as `cr_assistantcard`. No admin views, no cross-user queries.
- The "manager/team view" mentioned in the gap analysis as a Phase 3 aspirational feature should be explicitly called out as **requiring a separate governance review** before implementation. Aggregated behavioral data about employees is HR-adjacent and may fall under employment law restrictions.
- Sprint 4's Orchestrator commands like "Who are my most important contacts?" must be scoped to the current user's data only. The Orchestrator Agent prompt needs the same `IDENTITY & SECURITY CONSTRAINTS` block as the main agent.

**3. The Command Execution Flow (Sprint 3) accepts free-text natural language input and can write to Dataverse.** This is the widest attack surface in the plan. Prompt injection via the command bar could potentially:

- Create misleading reminder cards ("Reminder: Wire $50,000 to account X by Friday")
- Update card statuses to hide important items
- Exfiltrate data through crafted queries

**Mitigations required:**
- The Orchestrator Agent prompt needs explicit injection resistance instructions
- Write operations should be confirmed by the user before execution (the Architect's Query/Action agent split helps here)
- Rate limiting on command execution (max 20 commands per hour per user)
- All command inputs and outputs should be logged for audit

**4. The archive table (`cr_assistantcard_archive`) mentioned by the Architect should NOT be exempt from RLS.** Even archived data needs ownership-based security. "Analytics-only" is not a reason to weaken access controls in regulated industries. Use the same security role pattern.

---

### 🟡 PLATFORM ENGINEER

**Overall assessment: Feasible but several platform constraints need attention.**

I've built and maintained Copilot Studio + Power Automate solutions at this complexity level. The architecture is sound. Here are the platform-specific issues the plan needs to address:

**1. Agent invocation costs and throttling.**

Each Copilot Studio agent invocation consumes AI Builder credits (or Copilot Studio messages, depending on licensing). The current v1.0 has 3 flows × however many signals per day. The Second Brain plan adds:

- Sprint 2: Daily Briefing Agent (1 invocation/day, but the input payload could be massive — 50 open cards serialized as JSON)
- Sprint 2: Staleness Monitor (every 4 hours — but this doesn't invoke an agent, just queries Dataverse, so it's cheap)
- Sprint 3: Command Execution Flow (user-driven, unpredictable volume — could be 5/day or 50/day)
- Sprint 4: No new agent invocations (Sender Profile Analyzer is pure Dataverse queries)

**The Daily Briefing Agent input size is the biggest concern.** 50 open cards × ~2KB each = ~100KB of JSON in a single agent invocation. Copilot Studio has input token limits (varies by model, but typically 8K-32K tokens depending on configuration). 100KB of JSON is approximately 25K-30K tokens. This WILL hit the context window limit.

**Mitigation:** The Daily Briefing Flow should pre-summarize cards before passing them to the agent. Instead of passing full JSON for 50 cards, pass a condensed array:

```json
[
  {"id": "...", "summary": "...", "priority": "High", "sender": "...", "age_hours": 48, "cluster_id": "...", "outcome": "PENDING"},
  ...
]
```

This reduces the payload by ~80% and keeps it within token limits. The agent doesn't need `research_log`, `key_findings`, `verified_sources`, or `draft_payload` to produce a briefing — it needs summary, priority, sender, age, and cluster ID.

**2. The Command Execution Flow has a latency problem.**

The plan says the Canvas app calls `PowerAutomate.Run()` synchronously with a 120-second timeout. In practice:

- Power Automate instant flow cold start: 2-5 seconds
- Copilot Studio agent invocation: 5-30 seconds (depending on tool calls)
- If the Orchestrator calls the Humanizer as a connected agent: add another 5-15 seconds
- Total realistic latency: 15-45 seconds for a typical command

This is acceptable but the UX must account for it. The "Thinking..." spinner is mentioned in the plan, which is good. But also consider:

- **Streaming is not available** through Power Automate → Copilot Studio. The user waits for the full response. No partial renders.
- **Timeout handling** — If the flow times out at 120s, the Canvas app needs a graceful error message, not a crash.
- **Optimistic responses** — For common queries ("what's urgent?"), the Canvas app could show a locally-computed answer from cached card data WHILE the full agent response is loading, then replace it when the agent returns.

**3. The "Sender Profile Upsert" in Sprint 1 adds a conditional branch to every signal flow.**

Currently, each flow runs: trigger → pre-filter → compose → invoke agent → parse → write to Dataverse. Sprint 1 adds: → query sender profile → condition (exists?) → update or create row. That's 3-4 additional actions per flow run. For the EMAIL flow processing 50+ emails/day, this adds up.

**Recommendation:** Use a Dataverse "Upsert a row" action instead of the get-then-conditionally-write pattern. Upsert is a single action that creates if not exists, updates if exists. It's available in the Dataverse connector and reduces the sender profile logic from 3-4 actions to 1 action. The `cr_signalcount` increment can be handled with a Dataverse calculated column or a pre-operation plugin, but if that's too complex, accept the multi-step approach and move on.

**4. Canvas app delegation limit is still unresolved.**

The plan mentions the 500-record delegation limit as a known limitation and says Sprint 2's briefing agent mitigates it. That's true for the user experience, but the underlying problem persists: if a user has > 500 PENDING cards, the Daily Briefing Flow's Dataverse query will still return all of them (server-side), but the Canvas app's gallery view will silently truncate. The briefing card masks this for synthesized views, but the gallery view is still broken for power users.

**Recommendation:** Add server-side pagination or a "show more" pattern in Sprint 2. Or accept the limitation and document it prominently. Honestly, if a user has 500+ PENDING cards, the real problem is that they're not processing their cards — the staleness monitor and expiration flow in Sprint 2 should keep the active count well below 500 for engaged users.

---

### ⚫ PRAGMATIST

**Overall assessment: Good plan. Too much plan. Ship faster.**

I've read all four sprint specs. Here's what I think after building and maintaining systems like this:

**1. You're planning Sprint 4 in detail before Sprint 1 is built. Stop.**

Sprint 4's "Sender Profile Analyzer" and "Adaptive Triage" specs are detailed down to the SQL-level query patterns and confidence score adjustments. But Sprint 4 depends on 3+ weeks of behavioral data that doesn't exist yet. By the time you get to Sprint 4, you'll have learned things from Sprints 1-3 that invalidate half of the Sprint 4 spec.

**My recommendation:** Keep Sprint 4 as a one-paragraph description: "Use accumulated behavioral data to personalize triage and improve draft quality. Specific approach TBD based on data patterns observed during Sprints 1-3." Plan Sprint 4 in detail during Sprint 3, when you have actual data to look at.

**2. The edit distance calculation is over-engineered for Sprint 1.**

Levenshtein distance between two strings in Power Fx? In a Canvas app? The plan says "lightweight Power Fx calculation or a Compose action in a helper flow." In practice:

- Power Fx has no built-in Levenshtein function. You'd have to implement it character-by-character, which is computationally expensive in Power Fx for strings longer than a few hundred characters.
- A helper flow adds latency to the send action.
- For Sprint 1, you don't need a precise edit distance. You need a binary signal: **did they edit or not?**

**Simplification:** Sprint 1 tracks `SENT_AS_IS` vs `SENT_EDITED` (binary). That's it. No edit distance. In Sprint 4, when you actually need the granularity, implement edit distance in the Sender Profile Analyzer flow (server-side, in a Power Automate expression or Azure Function) where you can compare the original `cr_humanizeddraft` against the final sent text (which you'll store in a new `cr_finaldraft` column). Don't try to compute it in the Canvas app.

**3. The plan has too many new Dataverse columns in Sprint 1.**

Five new columns on `cr_assistantcard` plus a whole new table (`cr_senderprofile`). That's a lot of schema change for a sprint that's supposed to be "~1 week." In practice:

- Provisioning script updates need testing
- Security role updates need testing
- All 3 existing flows need modification and testing
- Canvas app needs new Patch() formulas and testing
- PCF needs new props, callbacks, and testing

**Recommendation:** Split Sprint 1 into two parts:

- **Sprint 1A (~3 days):** Add `cr_cardoutcome`, `cr_outcometimestamp`, and `cr_sourcesignalid` to the existing table. Update flows to set default outcome. Update Canvas app with Send and Dismiss tracking. Ship this.
- **Sprint 1B (~3 days):** Add `cr_conversationclusterid`. Create `cr_senderprofile` table. Add sender upsert logic to flows. Ship this.

This way you're shipping working code every 3 days instead of waiting a full week. If Sprint 1B takes longer than expected (it will — new table provisioning always has surprises), Sprint 1A is already live and collecting data.

**4. The GitHub Copilot skills and custom agent setup is a nice idea but don't do it first.**

The plan includes creating `.github/agents/` and `.github/skills/` as part of the development strategy. This is useful but it's meta-work — building tools to build tools. Do it when you're frustrated with Copilot giving you wrong patterns for the third time, not proactively. The repo already has clear conventions that Copilot CLI will pick up from context.

**5. One thing the plan doesn't address: what if the main agent's JSON output quality degrades?**

You're about to modify the main agent's input contract (adding `SENDER_PROFILE` in Sprint 4) and triage rules. Every modification to the system prompt is a risk to output quality. The v1.0 remediation research mentions "prompt evaluation test cases" as deferred. By Sprint 4, you're making non-trivial prompt changes and you NEED evaluation. At minimum:

- Save 10-15 representative input payloads (a mix of SKIP, LIGHT, FULL across all trigger types)
- After every prompt change, run all 10-15 through the agent and verify the JSON is valid and the triage classification is reasonable
- This doesn't need to be automated — a manual test pass with saved inputs is fine for now

This is cheap insurance against prompt regression.

---

## Round 2 — Cross-Council Debate

---

**PRODUCT → PRAGMATIST:** You say Sprint 1 should be split into 1A and 1B. I agree with the spirit but I'd split differently. My 1A would include the one-click send feature (which you haven't commented on) because that's the visible user value. Outcome tracking without a Send button means the user still copies and pastes to Outlook and we can't even capture whether they sent it.

**PRAGMATIST → PRODUCT:** Fair point. The Send button is both the value delivery AND the data collection mechanism. Okay, revised split:

- **Sprint 1A:** `cr_cardoutcome` + `cr_outcometimestamp` + Send Email flow + Canvas app Send/Dismiss buttons = visible value + data collection.
- **Sprint 1B:** `cr_conversationclusterid` + `cr_sourcesignalid` + `cr_senderprofile` table + sender upsert = clustering and profiling infrastructure.

I'll accept that.

**SECURITY → PRODUCT:** Your one-click send proposal needs the guardrails I specified. Explicit confirmation UX, audit trail, DLP review, scope limitation. If those aren't in Sprint 1A, the feature doesn't ship.

**PRODUCT → SECURITY:** Agreed. The confirmation UX is non-negotiable. I'd implement it as: user clicks "Send" → modal/dialog shows full recipient, subject, and draft body → user clicks "Confirm and Send" → flow executes → card status updates. The audit trail is just a column on the card row (`cr_senttimestamp`, `cr_sentrecipient`). DLP review is a checklist item, not a code change. This fits in Sprint 1A.

**ARCHITECT → PRAGMATIST:** You say don't plan Sprint 4 in detail. I partially agree — the specific query patterns and confidence adjustments will change. But the SCHEMA for Sprint 4 needs to be decided now, because Sprint 1 provisions the `cr_senderprofile` table. If we get the table shape wrong, we're migrating data in Sprint 4.

**PRAGMATIST → ARCHITECT:** The table shape in the plan is reasonable. `cr_senderemail`, `cr_signalcount`, `cr_responsecount`, `cr_avgresponsehours`, `cr_sendercategory` — these are obvious fields that any analysis approach will need. I'm okay provisioning the table now. I'm objecting to the detailed *flow logic* and *prompt modifications* for Sprint 4, not the schema.

**PLATFORM ENGINEER → ARCHITECT:** Your suggestion to split the Orchestrator into Query Agent and Action Agent is architecturally clean but operationally expensive. Two agents means two Copilot Studio licenses (or at least two agent slots), two system prompts to maintain, and a routing layer in the flow that adds latency and complexity. In my experience, Copilot Studio's generative orchestrator handles 6 tools fine — the accuracy degradation you're worried about is more theoretical than practical at this tool count. I'd ship with one Orchestrator Agent and split only if we observe routing errors in testing.

**ARCHITECT → PLATFORM ENGINEER:** I'll accept shipping as one agent initially, but with the explicit understanding that if command routing accuracy drops below 90% in testing, we split. And the Action Agent's write operations still need user confirmation regardless of whether it's one agent or two.

**SECURITY → PLATFORM ENGINEER:** On the token limit concern for the Daily Briefing Agent — the pre-summarization approach you recommend is correct and also has a security benefit. Passing full `cr_fulljson` blobs to the briefing agent means passing all research logs, source URLs, and draft content. The condensed summary array contains only the fields needed for ranking, reducing the PII surface area in the agent's context window.

**PRAGMATIST → ALL:** Can we agree on one thing? The prompt regression testing I mentioned isn't in any sprint's deliverable checklist. It should be. Before Sprint 4 modifies the main agent prompt, there must be a saved set of test inputs and expected outputs. This is a Sprint 3 deliverable — create the test set while the prompt is stable.

**ALL → PRAGMATIST:** Agreed.

---

## Round 3 — Consensus Recommendations

The council reaches the following consensus:

---

### APPROVED — Sprint Ordering

The dependency chain (Memory → Briefing → Command Bar → Intelligence) is correct. No reordering.

**Vote: 5-0**

---

### APPROVED WITH MODIFICATION — Sprint 1 Scope

**Modification:** Split Sprint 1 into 1A and 1B. Include one-click send in Sprint 1A with Security's guardrails (confirmation UX, audit columns, DLP checklist).

**Sprint 1A deliverables (~3-4 days):**
- `cr_cardoutcome` (Choice) + `cr_outcometimestamp` (DateTime) columns on `cr_assistantcard`
- `cr_senttimestamp` (DateTime) + `cr_sentrecipient` (Text) columns for audit trail
- New flow: "Send Email" (instant trigger from Canvas app, with confirmation pattern)
- Canvas app: Send button with confirmation dialog, Dismiss button with outcome tracking
- PCF: Updated callbacks (`onSendDraft`, `onDismissCard` now write outcomes)
- All 3 existing flows updated to set `cr_cardoutcome = PENDING` on new cards

**Sprint 1B deliverables (~3-4 days):**
- `cr_conversationclusterid` + `cr_sourcesignalid` columns on `cr_assistantcard`
- `cr_senderprofile` table provisioned
- All 3 flows updated with cluster ID, signal ID, and sender upsert
- New flow: "Card Outcome Tracker" (triggered on outcome changes, updates sender profile)

**Vote: 5-0**

---

### APPROVED WITH MODIFICATION — Sprint 2

**Modification:** Daily Briefing Agent receives pre-summarized card data (condensed array), not full JSON blobs. Maximum 50 cards in input. If > 50 PENDING cards exist, truncate to the 50 highest-priority.

**Vote: 5-0**

---

### APPROVED WITH MODIFICATION — Sprint 3

**Modifications:**
1. Ship Orchestrator as a single agent with 3 capabilities for v1 (synthesis queries, draft refinement, self-reminders). Defer sender lookup, thread summary, and calendar cross-reference to Sprint 4. Monitor routing accuracy — split into Query/Action agents if accuracy < 90%.
2. All write operations require user confirmation in the command bar UX (even reminders).
3. Rate limit: max 20 command executions per hour per user.
4. **New deliverable:** Create a prompt regression test set (10-15 saved inputs with expected outputs) while the main agent prompt is stable. This is prerequisite for Sprint 4's prompt modifications.

**Vote: 4-1 (Architect dissents on single agent, accepts with the 90% accuracy trigger)**

---

### APPROVED WITH MODIFICATION — Sprint 4

**Modification:** Reduce Sprint 4 spec to schema + high-level goals. Defer detailed flow logic, prompt modifications, and calibration dashboard specs to Sprint 3 planning, when actual behavioral data is available.

**Retained from current spec:**
- Schema: `cr_senderprofile` enrichment (already provisioned in Sprint 1B)
- Goal: Adaptive triage based on sender importance
- Goal: Confidence calibration using outcome data
- Goal: Additional Orchestrator commands for sender intelligence

**Deferred to Sprint 3 planning:**
- Specific Sender Profile Analyzer flow logic
- Specific main agent prompt modifications
- Specific confidence score adjustments
- Calibration dashboard component design

**Vote: 4-1 (Architect dissents — prefers schema-adjacent design decisions to be locked earlier; accepts because the schema IS locked in Sprint 1B)**

---

### NEW REQUIREMENT — Cross-Cutting

**Prompt regression test set** must be created during Sprint 3 and executed before any Sprint 4 prompt modifications. Minimum 10 saved input payloads covering:
- EMAIL × SKIP, LIGHT, FULL
- TEAMS_MESSAGE × SKIP, LIGHT, FULL
- CALENDAR_SCAN × FULL (multiple temporal horizons)
- Edge cases: unknown sender, low confidence, empty body

**Vote: 5-0**

---

### NEW REQUIREMENT — Governance (Security)

Every sprint's deployment checklist must include:
1. **DLP policy verification** — Confirm new connector combinations are permitted
2. **Security role update** — Any new table or column gets RLS review
3. **Audit trail verification** — Any user action that modifies data is logged

The `cr_senderprofile` table and any future analytics/archive tables must use the same UserOwned + ownership-based RLS pattern. No exceptions.

The "manager/team view" feature (mentioned in the gap analysis) is formally flagged as **requiring a separate governance review** before any design work begins.

**Vote: 5-0**

---

### ADVISORY — Not Blocking

1. **Archive pattern** (Architect): Implement a weekly housekeeping flow that moves EXPIRED/DISMISSED cards older than 30 days to an archive table. Recommend adding to Sprint 2 as a non-blocking task. If not done in Sprint 2, must be done before Sprint 4.

2. **Edit distance calculation** (Pragmatist): Defer to Sprint 4. Sprint 1 tracks binary SENT_AS_IS vs SENT_EDITED only. When Sprint 4 needs granularity, implement server-side in a flow, not in the Canvas app.

3. **Cross-channel clustering** (Architect): Sprint 1B implements per-channel clustering (conversationId, threadId, subject hash). Sprint 2's Daily Briefing Agent performs entity-based soft clustering as a processing step. True cross-channel entity extraction deferred to post-Sprint 4.

4. **GitHub Copilot setup** (Pragmatist): Create `.github/agents/` and `.github/skills/` when the need arises organically during development, not as a proactive task.

5. **Optimistic responses for command bar** (Platform Engineer): Consider implementing a Canvas app-local fast path for "what's urgent?" that reads from cached card data while the full agent response loads. Nice-to-have for Sprint 3, not blocking.

---

## Final Revised Sprint Summary

| Sprint | Duration | Key Deliverables | Modified From Original |
|--------|----------|-----------------|----------------------|
| **1A — Outcome Tracking + Send** | ~3-4 days | One-click send with confirmation, outcome tracking (binary), audit columns | Split from Sprint 1; added send feature with security guardrails |
| **1B — Clustering + Sender Profiles** | ~3-4 days | Conversation clustering, sender profile table, sender upsert in flows | Split from Sprint 1; removed edit distance (deferred to Sprint 4) |
| **2 — Daily Briefing Agent** | ~1 week | Morning briefing, staleness alerts, nudge cards, archive housekeeping flow | Added pre-summarization for token limits; added archive flow as advisory |
| **3 — Command Bar** | ~1.5 weeks | Command bar PCF, Orchestrator Agent (3 capabilities), prompt test set | Reduced from 6 to 3 capabilities; added prompt regression test set; added rate limiting |
| **4 — Sender Intelligence** | ~1.5 weeks | Adaptive triage, sender analysis, expanded Orchestrator commands | Detailed spec deferred to Sprint 3 planning; schema locked in Sprint 1B |

**Estimated total: ~5-6 weeks** (expanded slightly from original 5 weeks due to Sprint 1 split and security guardrails)

---

## Council Conclusion

The Second Brain Evolution Roadmap is **approved with the modifications above.** The vision is sound, the architecture is well-designed, and the sprint ordering correctly mirrors the data dependency graph. The primary modifications are:

1. **Split Sprint 1** for faster shipping cadence and visible user value (send button)
2. **Add security guardrails** for send actions, behavioral data, and command execution
3. **Scope Sprint 3** to 3 core capabilities instead of 6
4. **Defer Sprint 4 detail** until behavioral data is available
5. **Add prompt regression testing** as a Sprint 3 deliverable

The council recommends proceeding to Sprint 1A implementation immediately.

---

*Council session concluded: 2026-02-27*
*Next action: Update roadmap with council modifications, then begin Sprint 1A*
