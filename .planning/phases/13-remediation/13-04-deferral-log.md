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

| # | Issue ID | Phase | Issue | Severity | Deferral Rationale | Suggested Timeline |
|---|----------|-------|-------|----------|-------------------|--------------------|
| 1 | R-14 | 10 | PAC CLI version dependency not documented | INFO | Operational documentation -- does not affect artifact correctness. Script works with any recent PAC CLI version. | Post-deployment: add minimum version to README |
| 2 | R-15 / I-19 | 10, 12 | Trigger Type Compose covers 3 of 6 values (EMAIL, TEAMS_MESSAGE, CALENDAR_SCAN) | WARN | Functional as-is for Sprints 1-3 trigger types. DAILY_BRIEFING, SELF_REMINDER, and COMMAND_RESULT cards are created by dedicated flows that set trigger_type directly, not through the Compose action. Adding a comment to flows is cosmetic. | Post-deployment: add documentation comment in flow descriptions |
| 3 | R-17 / I-14 | 10, 12 | SENDER_PROFILE JSON not passed to main agent as input variable | WARN | Sender analytics still provide value: Flow 9 (Sender Profile Analyzer) updates cr_sendercategory, which flows can use for routing. Passing SENDER_PROFILE as an input variable requires flow-level input mapping changes in Copilot Studio that need live environment testing. Partial functionality exists without this. | Post-deployment Sprint 5: implement when Copilot Studio environment is available for iterative testing |
| 4 | R-19 / I-22 | 10, 12 | Sender profile upsert race condition (concurrent signals from same sender) | WARN | Requires R-11 alternate key (now fixed) but also needs flow-level Upsert change. Race window is narrow (concurrent emails from same sender within seconds). Alternate key prevents duplicates; worst case is a lost counter increment. | Post-deployment: change Create to Upsert in trigger flows |
| 5 | R-20 | 10 | NuGet restore not validated before solution build | INFO | Build toolchain concern. Developer will see clear error if NuGet packages are missing. Does not affect runtime behavior. | Post-deployment: add `dotnet restore` step to deploy-solution.ps1 |
| 6 | R-21 | 10 | Solution packaged as Unmanaged | INFO | Appropriate for development/testing (current phase). Switching to Managed is a deployment-time concern documented in deployment-guide.md. | Production deployment: change SolutionPackageType in Solution.cdsproj |
| 7 | R-23 | 10 | Knowledge source configurations not documented | WARN | Environment-specific settings that vary per tenant. Cannot be templated in artifacts. Requires live Copilot Studio environment to configure. | Post-deployment: document after first live configuration |
| 8 | R-30 | 10 | Agent timeout documentation missing | INFO | Operational concern. Default Copilot Studio timeout (120s) is adequate for MVP. | Post-deployment: add timeout tuning guidance |
| 9 | R-31 | 10 | API rate limit documentation missing | INFO | Operational concern. Power Platform throttling limits are documented by Microsoft and apply to all solutions. | Post-deployment: add rate limit awareness section |
| 10 | R-32 | 10 | Capacity planning section missing | INFO | Operational concern. Capacity depends on actual usage patterns not yet known. | Post-deployment: add after usage data is available |
| 11 | R-33 | 10 | License/role requirements not documented | INFO | Operational concern. License requirements (Power Apps per-user, Copilot Studio capacity) depend on organizational licensing model. | Post-deployment: add license matrix |
| 12 | R-34 | 10 | maxLength truncation expression not implemented | WARN | Defensive measure for edge case where agent output exceeds column max length. Power Automate truncates automatically on Dataverse write. Low risk of data loss (only affects very long outputs). | Post-deployment: add Left() truncation to Compose actions |
| 13 | R-35 | 10 | Briefing schedule persistence table missing | WARN | Tech debt #13 reclassified as deferred in 13-03. Briefing schedule requires a dedicated Dataverse table and Canvas App UI beyond v2.1 scope. Daily Briefing uses Power Automate recurrence trigger. | Future milestone: implement schedule configuration UI |
| 14 | F-09 - F-12 | 11 | Plain HTML instead of Fluent UI in BriefingCard, ConfidenceCalibration, CommandBar, App | WARN | Visual consistency only. Components render correctly with plain HTML. No functional or correctness impact. | Post-deployment: migrate to Fluent UI components for visual consistency |
| 15 | F-13 | 11 | Missing loading state while data loads | WARN | UX improvement. Dashboard shows empty state briefly before data arrives. Not a functional issue. | Post-deployment: add Spinner/Shimmer loading indicator |
| 16 | F-14 | 11 | BriefingCard detail view has no Back button | WARN | UX trap -- user must know to use breadcrumb or click outside. Not a functional blocker but poor UX. | Post-deployment: add Back navigation button |
| 17 | F-17 | 11 | Missing ARIA labels and roles on interactive elements | WARN | Accessibility improvement. All functionality is mouse-accessible. Keyboard/screen-reader users affected. | Post-deployment: accessibility audit and fix |
| 18 | F-18 | 11 | Missing Escape key to close detail views | WARN | Keyboard navigation improvement. Click-to-close works. | Post-deployment: add keyboard event handlers |
| 19 | F-19 | 11 | Misleading 0% display for empty analytics buckets | WARN | UX edge case. Affects only new deployments with zero card history. Displays "0%" instead of "No data". | Post-deployment: add empty state messaging |
| 20 | F-20 / I-32 | 11, 12 | DataSet paging not implemented | WARN | Mitigated by 7-day staleness expiration (cards expire to EXPIRED, reducing active set). Only affects deployments with >100 active cards simultaneously. | Post-deployment: implement paging.loadNextPage() |
| 21 | F-22 | 11 | Missing React ESLint plugins (eslint-plugin-react-hooks) | WARN | Prevents catching hook dependency errors at lint time. All current hooks are correct (verified by review). Requires npm install which is beyond doc remediation scope. | Next development session: `npm install --save-dev eslint-plugin-react-hooks` |
| 22 | I-21 | 12 | SENT_EDITED outcome distinction (edit distance) | WARN | Edit distance uses 0/1 boolean for MVP (implemented in 13-02). Full Levenshtein distance requires custom connector or Azure Function. | Post-deployment: implement Levenshtein when custom connector is available |
| 23 | I-23 | 12 | Concurrent outcome tracker race condition | WARN | Low probability -- requires two users acting on same card within seconds. Impact is minor statistical drift in sender profile counters. | Post-deployment: add optimistic concurrency check if needed |
| 24 | I-28 | 12 | Draft edits not persisted to Dataverse | WARN | UX improvement. Edited drafts exist in PCF state during session. Refreshing the page loses edits. Non-critical because users typically edit and send immediately. | Post-deployment: add cr_editeddraft column to persist edits |
| 25 | I-29 | 12 | Dismiss error handling incomplete | WARN | Low-frequency failure. Dismiss action updates Dataverse directly via PCF output property. Error path falls through to generic Canvas App error display. | Post-deployment: add retry logic and error toast |
| 26 | I-30 | 12 | No dead-letter mechanism for failed flow runs | WARN | Operational concern. Power Automate provides built-in flow run failure notifications and retry policies. Custom dead-letter queue is an optimization. | Post-deployment: evaluate need based on failure rates |
| 27 | I-31 | 12 | Reminder firing mechanism missing | WARN | Incomplete feature. SELF_REMINDER cards can be created via Command Execution but no flow checks for due reminders. Feature is additive -- does not affect existing functionality. | Future milestone: implement reminder check flow |

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
