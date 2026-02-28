# Integration/E2E Review -- Verdict

## Overall Verdict: FAIL

**10 deploy-blocking integration issues must be remediated in Phase 13 before deployment.**

The integration and end-to-end architecture is fundamentally sound -- the 5-layer data flow (prompt -> schema -> Dataverse -> flow -> TypeScript) is correctly designed, authentication is platform-managed and complete, XSS prevention is comprehensive (no dangerouslySetInnerHTML), and 4 of 7 user workflows complete end-to-end. However, 3 genuinely new deploy-blocking issues were discovered that single-layer reviews could not have found: prompt injection vulnerability across all agents, missing staleness refresh in the PCF, and missing monitoring/alerting strategy. Additionally, 7 Phase 10/11 BLOCK issues were confirmed at the integration level with cross-layer root causes that deepen their severity.

---

## Requirement Status

| Requirement | Status | BLOCK | WARN | INFO | Details |
|-------------|--------|-------|------|------|---------|
| INTG-01 | FAIL | 4 | 4 | 1 | N/A vs null spans 5 layers; NUDGE ingestion mismatch; USER_VIP naming; DISMISSED chain broken |
| INTG-02 | FAIL | 3 | 5 | 1 | 3 of 7 workflows incomplete (Daily Briefing, Command Execution, Reminder); BriefingCard data path undefined |
| INTG-03 | CONDITIONAL PASS | 1 | 3 | 1 | Monitoring strategy missing; dismiss error handling and dead-letter mechanism are non-blocking gaps |
| INTG-04 | FAIL | 2 | 1 | 0 | Prompt injection defense absent across all agents; privilege casing blocks security role deployment |
| INTG-05 | CONDITIONAL PASS | 2 | 3 | 2 | Staleness refresh missing; EXPIRED has no writer; race conditions are low-risk |

### Detailed Requirement Assessment

**INTG-01: Cross-layer contract consistency -- FAIL**

Four BLOCK issues affect field consistency across layers:
- **I-01 (R-01):** The N/A vs null mismatch is the most cross-cutting contract inconsistency in the system, spanning all 5 layers. Each layer has a different understanding of the "not applicable" value for priority and temporal_horizon.
- **I-02 (R-07, F-01):** NUDGE card_status exists in Dataverse and TypeScript but cannot reach the PCF because useCardData reads from cr_fulljson while flows update the discrete column.
- **I-04 (R-02):** USER_VIP/USER_OVERRIDE naming mismatch between prompt and schema means sender-adaptive VIP logic never matches.
- **I-05 (R-04):** DISMISSED outcome exclusion from Card Outcome Tracker breaks the dismiss_count -> dismiss_rate -> AUTO_LOW categorization chain across Flow -> Dataverse -> Sender Profile Analyzer -> Agent prompt.

All 4 BLOCK issues represent data that is lost, corrupted, or misinterpreted between layers. **Status: FAIL.**

**INTG-02: User workflow completeness -- FAIL**

Of 7 user workflows traced end-to-end:
- **PASS (4):** Email Triage (15 steps, complete), Draft Editing (partial -- SENT_EDITED not tracked but edit-send works), Email Send (complete round-trip with error handling), Outcome Tracking (SENT outcomes tracked; DISMISSED partially tracked)
- **FAIL (3):** Daily Briefing (steps 7-10 missing from flow spec; BriefingCard data path undefined), Command Execution (no flow spec; no response path to PCF), Reminder Creation (depends on broken Command Execution; no firing mechanism)

Three workflows have missing steps that prevent completion. **Status: FAIL.**

**INTG-03: Error handling at layer boundaries -- CONDITIONAL PASS**

Error handling exists at most layer boundaries:
- Agent-to-Dataverse: Scope-based error handling with error notification (HANDLED)
- Dataverse-to-PCF: try-catch in useCardData skips malformed records (PARTIAL)
- PCF-to-Power Automate: Send Email returns error to Canvas App (HANDLED for send)
- Power Automate-to-Agent: Scope catches timeout and parse failures (HANDLED)

The single BLOCK issue (I-18: monitoring strategy) is about detecting failures across the system, not about individual boundary handling. WARN issues (dismiss error handling, dead-letter mechanism) are partial gaps that do not cause silent data loss.

**Status: CONDITIONAL PASS.** Most boundaries have defined fallback behavior. The monitoring gap is the primary concern.

**INTG-04: Security model completeness -- FAIL**

Security assessment by domain:
- **Authentication: PASS.** Platform-managed SSO, no custom auth code. All connectors authenticated.
- **Row-level access: CONDITIONAL PASS.** Design correct (UserOwned + Basic depth). Single issue: privilege casing (I-10/R-03) would create empty security role -- fail-secure but blocks deployment.
- **XSS prevention: PASS.** No dangerouslySetInnerHTML. All content rendered through React auto-escaping. isSafeUrl() for URLs.
- **Prompt injection: FAIL.** No explicit injection defense in any agent prompt (I-16). All agents process untrusted content directly. Copilot Studio's built-in safeguards are baseline only.

One unprotected surface (prompt injection) with high potential impact. **Status: FAIL.**

**INTG-05: Async flow correctness -- CONDITIONAL PASS**

Two BLOCK issues:
- **I-17:** No staleness refresh in PCF -- users must manually interact to see new cards
- **I-03 (R-07):** EXPIRED card_outcome has no writer -- cards accumulate indefinitely

Both are related to the missing Staleness Monitor flow spec (R-07). The underlying async patterns (Copilot Studio session isolation, fire-and-forget with feedback, concurrent card creation) are correctly implemented.

WARN issues (sender profile upsert race, outcome tracker race) are unlikely to cause failures in practice. Timing assumptions are generally correct.

**Status: CONDITIONAL PASS.** The core async architecture is sound. BLOCK issues are caused by missing flow specs, not architectural flaws.

---

## UNIFIED Remediation Backlog for Phase 13

### Summary

| Phase | BLOCK Issues | Already Known (from Phase Verdict) | New from Phase 12 Integration Review |
|-------|-------------|-----------------------------------|------------------------------------|
| 10 | 9 | 9 | 5 confirmed with integration implications |
| 11 | 8 | 8 | 3 confirmed with integration implications |
| 12 | 10 | 0 | 3 genuinely new + 7 cross-references |
| **Total Unique** | **20** | **17** | **3 new BLOCK issues** |

**Note on counting:** Phase 12's 10 BLOCK issues include 7 that are cross-references to Phase 10/11 issues (confirming them at integration level). The 3 genuinely new BLOCK issues are: I-16 (prompt injection), I-17 (staleness refresh), I-18 (monitoring strategy). The 1 RELATED-NEW issue (I-15: BriefingCard data path) adds an integration requirement to the existing R-05 fix. Total unique BLOCK issues across all phases: 20 (9 from Phase 10 + 8 from Phase 11 + 3 new from Phase 12).

---

### Wave 1: Schema/Contract Fixes (Independent, Trivial)

Issues that change data contracts must be fixed first because downstream fixes depend on them.

| # | Issue ID | Phase | Artifact | Fix Description | Complexity | Blocked By |
|---|----------|-------|----------|-----------------|------------|------------|
| 1 | R-01 / I-01 | 10, 12 | output-schema.json | Add "N/A" to priority and temporal_horizon enum arrays | Trivial | None |
| 2 | R-02 / I-04 | 10, 12 | main-agent-system-prompt.md | Change "USER_VIP" to "USER_OVERRIDE" | Trivial | None |
| 3 | R-03 / I-10 | 10, 12 | create-security-roles.ps1 | Use PascalCase entity schema names for privilege names | Trivial | None |
| 4 | R-09 / I-11 | 10, 12 | provision-environment.ps1 | Add publisher creation/validation before entity creation | Moderate | None |
| 5 | I-16 | 12 | main-agent-system-prompt.md, orchestrator-agent-prompt.md, daily-briefing-agent-prompt.md | Add prompt injection defense instructions to all 3 agent prompts | Moderate | None |
| 6 | F-06 | 11 | useCardData.ts | Add `dataset` to useMemo dependency array | Trivial | None |
| 7 | F-08 | 11 | PROJECT.md | Remove/reclassify tech debt #7 (staleness polling setInterval) | Trivial | None |

**Wave 1 total: 7 issues.** Estimated effort: ~45 minutes. All independent -- can execute in any order or in parallel.

**Dependency justification:** Schema and contract fixes must land first because the Daily Briefing flow spec (Wave 2) depends on correct schema enums, and the security role fix (R-03) must be in place before deployment testing.

---

### Wave 2: Flow Specifications (Complex, Unblock Wave 3)

Missing flow specs must be written before downstream fixes (frontend, tests) can be validated.

| # | Issue ID | Phase | Artifact | Fix Description | Complexity | Blocked By |
|---|----------|-------|----------|-----------------|------------|------------|
| 8 | R-04 / I-05 | 10, 12 | agent-flows.md (Flow 5) | Add DISMISSED branch for cr_dismisscount + SENT_EDITED edit distance | Moderate | R-10 (Sprint 4 columns) |
| 9 | R-05 / I-06 + I-15 | 10, 12 | agent-flows.md (Flow 6) | Complete Daily Briefing flow spec (steps 7-10) + define output envelope wrapping for BriefingCard | Complex | R-01 (schema alignment) |
| 10 | R-06 / I-07 | 10, 12 | agent-flows.md (Flow 7) | Write Command Execution flow spec (Canvas trigger -> Orchestrator -> response return) | Complex | R-18 (Orchestrator tool docs) |
| 11 | R-07 / I-08 + I-02 + I-03 | 10, 12 | agent-flows.md (Flow 8) | Write Staleness Monitor flow spec (NUDGE creation + EXPIRED transition via discrete column) | Moderate | None |
| 12 | R-08 / I-09 | 10, 12 | agent-flows.md (Flow 9) | Write Sender Profile Analyzer flow spec (weekly categorization + metrics computation) | Moderate | R-04 (dismiss count must flow) |

**Wave 2 total: 5 issues.** Estimated effort: ~2 hours. R-07 can start immediately; R-05 depends on Wave 1's R-01; R-04 depends on Sprint 4 column fix (R-10, deferral candidate); R-06 depends on R-18 (deferral candidate, can work around); R-08 depends on R-04.

**Dependency justification:** Flow specs define the data contracts and behavior that frontend fixes depend on. R-07 must define how NUDGE is set (discrete column update) before F-01 can be fixed. R-06 must define the response format before F-02 can wire the response channel.

**Integration requirement (from Phase 12):** R-05 must include output envelope wrapping instructions per I-15 -- the Daily Briefing flow must wrap the briefing agent response in a standard output-schema.json envelope with trigger_type="DAILY_BRIEFING", draft_payload=JSON.stringify(briefing response), etc. Without this, BriefingCard would render "Unable to parse briefing data."

---

### Wave 3: Frontend Fixes (Depend on Wave 2 Decisions)

Component fixes that depend on contract and flow changes.

| # | Issue ID | Phase | Artifact | Fix Description | Complexity | Blocked By |
|---|----------|-------|----------|-----------------|------------|------------|
| 13 | F-01 / I-02 | 11, 12 | useCardData.ts, output-schema.json | Read card_status from discrete column via getFormattedValue; add NUDGE to schema | Moderate | R-07 (Staleness Monitor defines NUDGE behavior) |
| 14 | F-02 / I-12 | 11, 12 | ControlManifest.Input.xml, index.ts, App.tsx | Add orchestratorResponse + isProcessing input properties; wire to CommandBar | Moderate | R-06 (Command Execution defines response format) |
| 15 | F-03 / I-13 | 11, 12 | ErrorBoundary.tsx (new), App.tsx | Create React error boundary class component; wrap App content area | Moderate | None |
| 16 | F-07 | 11 | BriefingCard.tsx, PROJECT.md | Reclassify tech debt #13 (schedule config) or implement schedule feature | Trivial-Complex | Decision: implement vs reclassify |
| 17 | I-17 | 12 | Canvas App (Timer control) or PCF (Refresh button) | Add periodic DataSet refresh (30-60s timer) or manual "Refresh" button | Moderate | None |
| 18 | I-18 | 12 | agent-flows.md (all flows), Dataverse (error table) | Add error notification to flow error Scopes; define error log table | Moderate | None |

**Wave 3 total: 6 issues.** Estimated effort: ~2 hours. F-03, I-17, and I-18 can start immediately (no Wave 2 dependencies). F-01 depends on R-07; F-02 depends on R-06.

**Dependency justification:** F-01 must know how the Staleness Monitor sets NUDGE (via discrete column, per R-07) to implement the correct ingestion path. F-02 must know the Command Execution flow's response format (per R-06) to design the input property type.

---

### Wave 4: Test Coverage + Validation

Tests and validation that verify all fixes.

| # | Issue ID | Phase | Artifact | Fix Description | Complexity | Blocked By |
|---|----------|-------|----------|-----------------|------------|------------|
| 19 | F-04 | 11 | ConfidenceCalibration.test.tsx (new) | Create test file covering all 4 tabs, empty state, division safety, edge cases | Moderate | None (can parallel with Wave 3) |
| 20 | F-05 | 11 | index.test.ts (new), jest.config.ts | Create tests for PCF lifecycle; remove coverage exclusion | Moderate | F-02 (response property changes affect index.ts) |

**Wave 4 total: 2 issues.** Estimated effort: ~45 minutes. F-04 can parallel with Wave 3. F-05 should wait for F-02 (index.ts interface may change).

---

### Deferral Candidates (All Phases)

WARN issues from all three review phases that could be deferred beyond Phase 13.

| # | Issue ID | Phase | Issue | Recommended Action |
|---|----------|-------|-------|--------------------|
| 1 | R-10 | 10 | Missing Sprint 4 SenderProfile columns in provisioning script | Fix in Phase 13 -- needed by R-04 DISMISSED branch |
| 2 | R-11 | 10 | Missing alternate key creation on SenderProfile table | Fix in Phase 13 -- improves data integrity |
| 3 | R-12 | 10 | Missing Publish Customizations step in script | Fix in Phase 13 -- script completeness |
| 4 | R-13 | 10 | Duplicate pac auth create call | Fix in Phase 13 -- trivial |
| 5 | R-14 | 10 | PAC CLI version dependency | Defer -- document minimum version |
| 6 | R-15 / I-19 | 10, 12 | Trigger Type Compose scope (3 of 6 values) | Defer -- add documentation comment |
| 7 | R-16 | 10 | Missing SENDER_PROFILE in deployment guide input table | Fix in Phase 13 -- one-line addition |
| 8 | R-17 / I-14 | 10, 12 | SENDER_PROFILE not passed to agent in flows | Fix in Phase 13 -- Sprint 4 addendum |
| 9 | R-18 | 10 | Orchestrator tool action registration not documented | Fix in Phase 13 -- needed for R-06 |
| 10 | R-19 / I-22 | 10, 12 | Sender profile upsert race condition | Defer -- depends on R-11 alternate key |
| 11 | R-20 | 10 | NuGet restore validation | Defer -- add dotnet restore step |
| 12 | R-21 | 10 | Unmanaged solution type | Defer -- production concern |
| 13 | R-22 | 10 | Humanizer Connected Agent config | Fix in Phase 13 -- one paragraph |
| 14 | R-23 | 10 | Knowledge source configurations | Defer -- environment-specific |
| 15 | R-30-R-33 | 10 | Agent timeout, rate limits, capacity, license docs | Defer -- operational documentation |
| 16 | R-34 | 10 | maxLength truncation expression | Defer -- defensive measure |
| 17 | R-35 | 10 | Briefing schedule persistence table | Defer -- known tech debt #13 |
| 18 | R-37 | 10 | Agent publish verification step | Fix in Phase 13 -- one step |
| 19 | F-09-F-12 | 11 | Plain HTML instead of Fluent UI (4 components) | Defer -- visual only |
| 20 | F-13 | 11 | Missing loading state | Fix in Phase 13 if time -- UX improvement |
| 21 | F-14 | 11 | BriefingCard has no Back button | Fix in Phase 13 if time -- UX trap |
| 22 | F-15 | 11 | CardItem NUDGE status map missing | Fix in Phase 13 -- needed once F-01 is fixed |
| 23 | F-16 | 11 | Trigger icon map incomplete | Fix in Phase 13 -- trivial |
| 24 | F-17 | 11 | Missing ARIA labels and roles | Defer -- accessibility improvement |
| 25 | F-18 | 11 | Missing Escape key navigation | Defer -- keyboard improvement |
| 26 | F-19 | 11 | Misleading 0% for empty analytics | Fix in Phase 13 if time -- UX |
| 27 | F-20 / I-32 | 11, 12 | DataSet paging not implemented | Defer -- mitigated by staleness expiration |
| 28 | F-21 | 11 | Missing calibration view tests | Fix in Phase 13 -- coverage improvement |
| 29 | F-22 | 11 | Missing React ESLint plugins | Fix in Phase 13 -- prevents future hook bugs |
| 30 | I-21 | 12 | SENT_EDITED outcome distinction | Fix in Phase 13 -- analytics accuracy |
| 31 | I-23 | 12 | Concurrent outcome tracker race condition | Defer -- minor statistical drift |
| 32 | I-28 | 12 | Draft edits not persisted | Defer -- UX improvement |
| 33 | I-29 | 12 | Dismiss error handling | Fix in Phase 13 if time -- error resilience |
| 34 | I-30 | 12 | No dead-letter mechanism | Defer -- operational concern |
| 35 | I-31 | 12 | Reminder firing mechanism missing | Defer -- feature incomplete |
| 36 | I-33 | 12 | Environment variable/connection docs | Fix in Phase 13 -- deployment readiness |

**Recommendation:** Fix items #1-4, #7-9, #18, #22-23, #28-30, #33, #36 in Phase 13 (trivial-to-moderate, directly improve deployability). Defer items #5-6, #10-17, #19-21, #24-27, #31-32, #34-35 to post-deployment milestone.

---

## Key Insights

1. **The integration architecture is fundamentally correct, but 3 genuinely new deploy-blocking gaps were invisible to single-layer reviews.** Prompt injection vulnerability, staleness refresh, and monitoring strategy all span multiple layers and could only be discovered by end-to-end analysis. The AI Council integration review justified its existence by finding these.

2. **Phase 10/11 BLOCK issues are worse than originally assessed.** Cross-layer tracing revealed that many Phase 10/11 issues have deeper integration implications. The NUDGE card_status gap (R-07 + F-01) is actually a 3-layer root cause (Flow sets discrete column, PCF reads JSON blob, and no agent produces NUDGE). Fixing just one layer would not resolve it.

3. **Sprint 4 sender intelligence is non-functional through three independent failure points.** SENDER_PROFILE is not passed to the agent (I-14), USER_VIP doesn't match USER_OVERRIDE (I-04), and dismiss_count is never incremented (I-05). Even fixing one or two of these leaves the feature broken. All three must be fixed for sender-adaptive triage to activate.

4. **4 of 7 user workflows are complete and correct.** Email Triage, Draft Editing, Email Send, and Outcome Tracking (for SENT outcomes) all work end-to-end with correct data flows and error handling. The core triage-to-send pipeline is solid.

5. **The missing flow specifications (R-05, R-06, R-07, R-08) are the single biggest remediation driver.** They account for 4 of the Phase 10 BLOCK issues, enable 2 of the Phase 11 BLOCK fixes (F-01 depends on R-07, F-02 depends on R-06), and resolve 3 of the Phase 12 integration concerns (I-02/NUDGE, I-03/EXPIRED, I-15/BriefingCard). Writing these 4 flow specs unlocks resolution of 9 total BLOCK issues across all phases.

6. **Security posture is mixed: strong authentication and XSS, weak prompt injection.** Platform-managed authentication is excellent (no custom auth code to misconfigure). XSS prevention is comprehensive (no dangerouslySetInnerHTML, React auto-escaping, isSafeUrl). But prompt injection defense is entirely absent. The asymmetry suggests prompt injection was not considered during design because it is a newer attack vector compared to traditional web security.

7. **The 4-wave remediation order correctly reflects actual dependencies.** Schema fixes (Wave 1) must precede flow specs (Wave 2) which must precede frontend fixes (Wave 3) which must precede test validation (Wave 4). This is not arbitrary ordering -- each wave's output is input to the next. Attempting to parallelize across waves would require rework.

---

## Comparison: Agent Agreement

### Overall Agreement

**Agreement rate: 81%** (27 of 33 unique issues had consistent severity across all agents that flagged them)

This is higher than Phase 10 (74%) and Phase 11 (79%), suggesting that integration-level issues have clearer severity signals -- cross-layer problems are more obviously deploy-blocking or non-blocking than single-layer issues.

### Agreement by Topic

| Topic | Agreement Level | Details |
|-------|----------------|---------|
| Cross-layer contract mismatches | HIGH | All agents that flagged N/A/null, USER_VIP, NUDGE, DISMISSED agreed on BLOCK severity |
| Missing flow specs | HIGH | Both IMP and GAP independently identified the same 4 missing flows with identical impact assessment |
| Security (prompt injection) | MODERATE | Only GAP flagged prompt injection; COR and IMP focused on data contracts and workflows rather than security |
| Async timing | LOW | GAP classified concurrent outcome race as BLOCK; reconciliation downgraded to WARN based on probability analysis |
| Platform constraints | HIGH | All agents agreed on Parse JSON, delegation, and PCF event model as known constraints |
| False positives | HIGH | All 5 FALSE rulings were clear-cut upon investigation |

### Disagreements Resolved

7 disagreements were resolved:
- 2 escalated to BLOCK (I-16 prompt injection, I-15 BriefingCard data path)
- 1 downgraded from BLOCK to WARN (I-23 concurrent outcome race)
- 4 confirmed at agent's original severity (I-17, I-18, I-14, I-05)

The most significant disagreement was I-15 (BriefingCard data path): Correctness classified it as non-blocking (COR-I16, COR-I21), viewing it as a documentation gap; Implementability classified it as deploy-blocking (IMP-I07), viewing it as a broken workflow. Resolution: BLOCK -- because even if the Daily Briefing flow is built, BriefingCard would display "Unable to parse briefing data" without explicit output envelope wrapping. The Implementability perspective (functional impact) was more relevant than the Correctness perspective (documentation gap).

### Agent Value Analysis

Each agent contributed unique integration-level insights:
- **Correctness** excelled at cross-layer enum tracing tables that definitively proved contract inconsistencies (I-01, I-02, I-04, I-05). These tables are the strongest evidence in the entire review.
- **Implementability** excelled at end-to-end workflow tracing with per-step PASS/FAIL/MISSING assessment (I-06, I-07, I-15). The workflow traces proved that 3 of 7 workflows cannot complete.
- **Gaps** excelled at security domain audit and async timing analysis (I-16, I-17, I-18, I-23). Prompt injection was the most impactful new finding of the entire review, discovered only by the Gaps agent.

The three-agent approach at the integration level was particularly valuable because integration issues span multiple layers, and each agent brought a different lens (contract accuracy, functional completeness, security/operational gaps) to the same cross-layer behaviors.

### Cross-Phase Comparison

| Metric | Phase 10 | Phase 11 | Phase 12 |
|--------|----------|----------|----------|
| Raw findings | 56 | 60 | 62 |
| Unique after dedup | 33 | 33 | 33 |
| Dedup ratio | 41% | 45% | 47% |
| BLOCK issues | 9 | 8 | 10 |
| Agreement rate | 74% | 79% | 81% |
| False positives | 4 | 4 | 5 |
| Genuinely new | 33 | 33 | 10 |

The increasing dedup ratio (41% -> 45% -> 47%) reflects growing overlap as reviews move up the stack: integration issues are more likely to be seen by multiple agents from different angles. The decreasing "genuinely new" count (33 -> 33 -> 10) reflects that integration review primarily confirms and deepens understanding of known issues rather than finding entirely new ones -- but the 3 genuinely new BLOCK issues (prompt injection, staleness refresh, monitoring) justify the review.
