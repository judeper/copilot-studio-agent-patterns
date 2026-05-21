# Ceremonies — `copilot-studio-agent-patterns`

> Team meetings that happen before or after work.

## Design Review

| Field | Value |
|-------|-------|
| **Trigger** | auto |
| **When** | before |
| **Condition** | Multi-artifact round where 2+ members modify shared contracts (e.g., topic + tool-flow + table schema must agree on response shape) |
| **Facilitator** | @danny |
| **Participants** | all relevant members |
| **Time budget** | focused |
| **Enabled** | ✅ yes |

**Agenda:**
1. Review the contract surface — what each member needs from the others
2. Agree on JSON schemas, GUID placeholders, field names
3. Identify edge cases (env-var deleted, payload >900KB, flow timeout)
4. Assign artifacts; sequence by dependency

**Example trigger:** Round 2 of the v5 build = `tool-log-agent-trace` (@virgil) + `cot-topic-template` (@linus) + `agenttrace-table.json` (@frank) all touch the response schema `{logged: boolean}`. Design review before all three start so the contract is locked.

---

## Retrospective (Reactive)

| Field | Value |
|-------|-------|
| **Trigger** | auto |
| **When** | after |
| **Condition** | Reviewer rejection, build failure, or council finding that contradicts a shipped artifact |
| **Facilitator** | @danny |
| **Participants** | all involved + @rusty |
| **Time budget** | focused |
| **Enabled** | ✅ yes |

**Agenda:**
1. What happened? (facts only)
2. Root cause — was it a missed council finding? An unclear charter? A drift from v5 plan?
3. What should change in the plan, the charters, or the review checklist?
4. Update `decisions.md` if a new pattern emerged

---

## Council Critique (Major Design Changes)

| Field | Value |
|-------|-------|
| **Trigger** | manual |
| **When** | before |
| **Condition** | Any architectural change to the v5 plan beyond a typo or wording fix |
| **Facilitator** | @danny |
| **Participants** | 3-5 AI sub-agents with different lenses (different models) + 1 consensus synthesizer |
| **Time budget** | thorough |
| **Enabled** | ✅ yes (process proven on v5 plan — Round 1 and Round 2) |

**Agenda:**
1. @danny describes the proposed change and what evidence triggered it
2. Each reviewer gets the same context + a distinct lens (e.g., simplicity / feasibility / failure-mode / devil's-advocate / maker walk-through / ALM lifecycle)
3. Each verdict + ranked findings posted to `decisions/inbox/`
4. Consensus synthesizer (typically `claude-opus-4.7-1m-internal`) produces a unified change set with high-confidence consensus, architectural decisions, trade-offs, and confidence assessment
5. @danny applies the consensus to the plan; flagged trade-offs go to Jude for sign-off
6. Scribe archives all critiques + synthesis in `orchestration-log/`

**Why this exists:** Round 1 caught 8 blocking issues (env-var gate placement, correlation ID design, primary name attribute). Round 2 caught 17 critical fixes (error-handling discipline, Coalesce casing, MDA Phase-0 reality, ALM solution source-of-truth). A single-pass review would have shipped a fragile POC.

---

## Round Summary (After Every Build Round)

| Field | Value |
|-------|-------|
| **Trigger** | auto |
| **When** | after |
| **Condition** | 3-5 artifacts completed in a round |
| **Facilitator** | @danny |
| **Participants** | @danny + Scribe |
| **Time budget** | quick |
| **Enabled** | ✅ yes |

**Agenda:**
1. What shipped this round (artifacts + PRs + issue closes)
2. What's in-flight / blocked
3. What's next round (read the SQL `todos` ready-query)
4. Any council findings adopted or pending
5. Any blocking questions for Jude

**Output:** Posted to user as a single TLDR message. Logged to `.squad/log/round-N-summary.md` by Scribe.
