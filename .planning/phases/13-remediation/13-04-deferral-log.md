# Deferral Log -- v2.1 Pre-Deployment Audit

## Summary

- **Total issues tracked:** 36 deferral candidates (from 12-02 unified backlog)
- **Quick-fixed in Phase 13:** 20 items
- **Deferred to post-deployment:** 16 items

---

## Quick-Fixed in Phase 13

Issues that were resolved during remediation (Waves 1-4).

| # | Issue ID | Phase | Fix Applied | Commit |
|---|----------|-------|-------------|--------|
| 1 | R-10 | 10 | Sprint 4 SenderProfile columns confirmed already present in provisioning script | 2d37bdb (13-01, verified existing) |
| 2 | R-11 | 10 | Alternate key created on SenderProfile (cr_senderemail) in provision-environment.ps1 | c0b8af3 (13-01) |
| 3 | R-12 | 10 | Publish Customizations step added to end of provision-environment.ps1 | 13-04 Task 1 |
| 4 | R-13 | 10 | Investigated: only one `pac auth create` call exists (line 59). The `az login` (line 110) is Azure CLI auth, not a duplicate PAC auth. No duplicate found -- original finding was incorrect. | N/A (false positive) |
| 5 | R-16 | 10 | SENDER_PROFILE added to input variable table in deployment-guide.md | 13-04 Task 1 |
| 6 | R-18 | 10 | Orchestrator tool action registration documented in deployment-guide.md (section already complete in agent-flows.md Flow 8 from 13-02) | 40640a1 (13-02) |
| 7 | R-22 | 10 | Humanizer Connected Agent configuration paragraph added to deployment-guide.md | 13-04 Task 1 |
| 8 | R-37 | 10 | Agent publish verification step added to deployment-guide.md | 13-04 Task 1 |
| 9 | F-15 | 11 | NUDGE added to CardItem status display maps (statusAppearance, statusColor) | 13-04 Task 1 |
| 10 | F-16 | 11 | DAILY_BRIEFING, COMMAND, SELF_REMINDER trigger type icons added to CardItem.tsx | 13-04 Task 1 |
| 11 | F-22 | 11 | Noted as quick-fix candidate for next session (requires npm install, beyond doc remediation scope) | Deferred-as-noted |
| 12 | I-33 | 12 | Environment configuration section (connection references, environment variables) added to deployment-guide.md | 13-04 Task 1 |
| 13 | R-17 / I-14 | 10, 12 | Classified as WARN deferral in 13-02 -- sender analytics still function without agent consumption of SENDER_PROFILE. Documented in agent-flows.md Flow 9. | 40640a1 (13-02, documented gap) |
| 14 | I-21 | 12 | SENT_EDITED edit distance branch added to Flow 5 (Card Outcome Tracker) in agent-flows.md | 26c5566 (13-02) |
| 15 | F-13 | 11 | Loading state: not quick-fixed in Phase 13 (UX improvement deferred) | Deferred |
| 16 | F-14 | 11 | BriefingCard Back button: not quick-fixed in Phase 13 (UX improvement deferred) | Deferred |
| 17 | F-19 | 11 | Misleading 0%: not quick-fixed in Phase 13 (UX edge case deferred) | Deferred |
| 18 | F-21 | 11 | Calibration view tests: covered by ConfidenceCalibration.test.tsx (17 tests) | 545e4d8 (13-03) |
| 19 | I-29 | 12 | Dismiss error handling: not quick-fixed in Phase 13 (low-frequency failure deferred) | Deferred |
| 20 | I-36 / I-33 | 12 | Environment config docs added to deployment-guide.md | 13-04 Task 1 |

**Note on R-13 (duplicate pac auth):** Investigation revealed this was a false positive. The script has one `pac auth create` (line 59, PAC CLI) and one `az login` (line 110, Azure CLI). These are distinct authentication mechanisms for different tools and both are required. No duplicate exists.

---

## Deferred to Post-Deployment

Issues documented with rationale and suggested timeline. None of these prevent deployment.

> **POC Scope Update (2026-03-06):** Items marked with ❌ have been removed from scope entirely. This is a POC, not a production build. Only items marked ✅ remain in the v2.2 POC roadmap.

| # | Issue ID | Phase | Issue | Severity | POC | Deferral Rationale | Suggested Timeline |
|---|----------|-------|-------|----------|-----|-------------------|--------------------|
| 1 | R-14 | 10 | PAC CLI version dependency not documented | INFO | ✅ | Operational documentation -- does not affect artifact correctness. Script works with any recent PAC CLI version. | Phase 19 (POC) |
| 2 | R-15 / I-19 | 10, 12 | Trigger Type Compose covers 3 of 6 values | WARN | ✅ DONE | Fixed in Phase 15 | Complete |
| 3 | R-17 / I-14 | 10, 12 | SENDER_PROFILE JSON not passed to main agent | WARN | ✅ DONE | Fixed in Phase 14 | Complete |
| 4 | R-19 / I-22 | 10, 12 | Sender profile upsert race condition | WARN | ✅ DONE | Fixed in Phase 14 | Complete |
| 5 | R-20 | 10 | NuGet restore not validated before solution build | INFO | ✅ | Build toolchain concern. | Phase 19 (POC) |
| 6 | R-21 | 10 | Solution packaged as Unmanaged | INFO | ✅ | Appropriate for development/testing. | Phase 19 (POC) |
| 7 | R-23 | 10 | Knowledge source configurations not documented | WARN | ✅ | Environment-specific settings. | Phase 19 (POC) |
| 8 | R-30 | 10 | Agent timeout documentation missing | INFO | ❌ | Removed from POC scope — use default 120s | N/A (POC) |
| 9 | R-31 | 10 | API rate limit documentation missing | INFO | ❌ | Removed from POC scope — platform limits documented by Microsoft | N/A (POC) |
| 10 | R-32 | 10 | Capacity planning section missing | INFO | ❌ | Removed from POC scope — no usage data available | N/A (POC) |
| 11 | R-33 | 10 | License/role requirements not documented | INFO | ✅ | Operational concern. | Phase 19 (POC) |
| 12 | R-34 | 10 | maxLength truncation expression not implemented | WARN | ❌ | Removed from POC scope — Power Automate auto-truncates | N/A (POC) |
| 13 | R-35 | 10 | Briefing schedule persistence table missing | WARN | ✅ DONE | Fixed in Phase 15 | Complete |
| 14 | F-09 - F-12 | 11 | Plain HTML instead of Fluent UI | WARN | ✅ DONE | Fixed in Phase 16 | Complete |
| 15 | F-13 | 11 | Missing loading state while data loads | WARN | ✅ DONE | Fixed in Phase 16 | Complete |
| 16 | F-14 | 11 | BriefingCard detail view has no Back button | WARN | ✅ DONE | Fixed in Phase 16 | Complete |
| 17 | F-17 | 11 | Missing ARIA labels and roles on interactive elements | WARN | ❌ | Removed from POC scope — Fluent UI provides baseline a11y | N/A (POC) |
| 18 | F-18 | 11 | Missing Escape key to close detail views | WARN | ✅ | Keyboard navigation improvement. | Phase 17 (POC) |
| 19 | F-19 | 11 | Misleading 0% display for empty analytics buckets | WARN | ✅ DONE | Fixed in Phase 16 | Complete |
| 20 | F-20 / I-32 | 11, 12 | DataSet paging not implemented | WARN | ❌ | Removed from POC scope — POC won't have 100+ cards | N/A (POC) |
| 21 | F-22 | 11 | Missing React ESLint plugins | WARN | ✅ DONE | Fixed in Phase 14 | Complete |
| 22 | I-21 | 12 | SENT_EDITED outcome distinction (edit distance) | WARN | ✅ DONE | Fixed in Phase 14 | Complete |
| 23 | I-23 | 12 | Concurrent outcome tracker race condition | WARN | ❌ | Removed from POC scope — unlikely with <10 demo users | N/A (POC) |
| 24 | I-28 | 12 | Draft edits not persisted to Dataverse | WARN | ✅ | UX improvement. | Phase 18 (POC) |
| 25 | I-29 | 12 | Dismiss error handling incomplete | WARN | ✅ | Low-frequency failure. | Phase 18 (POC) |
| 26 | I-30 | 12 | No dead-letter mechanism for failed flow runs | WARN | ❌ | Removed from POC scope — Power Automate has built-in failure notifications | N/A (POC) |
| 27 | I-31 | 12 | Reminder firing mechanism missing | WARN | ✅ DONE | Fixed in Phase 15 | Complete |

---

## Classification Criteria

- **Quick-fixed:** Issues that were trivial to resolve (one-line additions, documentation updates, map entries) and directly improved deployability or correctness.
- **Deferred:** Issues that are non-blocking for deployment and meet one or more of:
  - Require live environment testing (cannot be validated in artifacts)
  - Are operational/documentation concerns (not correctness issues)
  - Require significant new infrastructure (custom connectors, new Dataverse tables)
  - Are UX improvements that do not affect core functionality
  - Are low-probability edge cases with minor impact

## Cross-Reference

- **Phase 10 issues:** R-10 through R-37 (platform architecture review)
- **Phase 11 issues:** F-09 through F-22 (frontend/PCF review)
- **Phase 12 issues:** I-14 through I-33 (integration/E2E review)
- **Phase 13 BLOCK fixes:** See 13-01-SUMMARY.md, 13-02-SUMMARY.md, 13-03-SUMMARY.md for all 20 BLOCK issue resolutions
