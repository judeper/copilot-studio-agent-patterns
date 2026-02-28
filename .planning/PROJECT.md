# Enterprise Work Assistant — Second Brain

## What This Is

A comprehensive reference pattern for an AI-powered "second brain" built on Copilot Studio, Power Automate, Dataverse, and a PCF React dashboard. The system proactively manages a knowledge worker's communications by triaging emails, drafting responses, tracking outcomes, learning sender behavior, generating daily briefings, and accepting natural language commands — all within a Canvas App dashboard.

**v1.0** established production readiness: consistent schemas, correct code, accurate docs, deployment scripts, and test infrastructure.

**v2.0** evolved the assistant into a behavioral learning system: outcome tracking with email send flow, conversation clustering, sender profiles, daily briefing agent with staleness monitoring, command bar with orchestrator agent, and sender intelligence with adaptive triage and confidence calibration analytics.

## Core Value

Every artifact in the solution must be correct and consistent — schemas match prompts, code compiles without errors, docs accurately describe the implementation, and scripts work when run. The system should learn from user behavior to improve its assistance over time.

## Requirements

### Validated

**v1.0 Production Readiness:**
- ✓ Fix all schema/prompt inconsistencies (null convention, field types, nullability)
- ✓ Fix remaining code bugs (Badge size, color tokens, XSS, deploy polling, security roles)
- ✓ Resolve table naming inconsistency (cr_assistantcard singular/plural) across all files
- ✓ Add missing Power Automate implementation guidance (Choice expressions, connector actions, research tool)
- ✓ Correct deployment guide UI paths (JSON output mode location)
- ✓ Add unit tests for React PCF components and hooks
- ✓ Re-audit entire solution after fixes to validate correctness

**v2.0 Second Brain Evolution:**
- ✓ Implement outcome tracking with action persistence via Power Automate flows
- ✓ Add send-as-is email flow with fire-and-forget PCF output binding
- ✓ Build conversation clustering to group related cards by thread
- ✓ Create sender profile infrastructure with per-sender behavioral metrics
- ✓ Implement Daily Briefing Agent with composite scoring and configurable schedule
- ✓ Add staleness monitor for overdue item detection
- ✓ Build Command Bar with Orchestrator Agent for natural language workflow control
- ✓ Add SELF_REMINDER and COMMAND_RESULT trigger types to Dataverse schema
- ✓ Implement sender-adaptive triage with automatic priority adjustment
- ✓ Build confidence calibration dashboard with four-tab analytics (Accuracy/Triage/Drafts/Senders)
- ✓ End-to-end review pass fixing 3 bugs, 6 doc errors, 6 gaps

### Active

## Current Milestone: v2.1 Pre-Deployment Audit

**Goal:** Validate the entire reference pattern is correct, implementable, and complete before deploying to a real Power Platform environment.

**Target features:**
- AI Council review of platform architecture (Dataverse, Power Automate, Copilot Studio)
- AI Council review of frontend/PCF layer (React components, hooks, state, tests)
- AI Council review of integration/end-to-end data flows across all layers
- Reconciliation of disagreements via targeted research
- Remediation of any issues found

### Out of Scope

- Building a working Power Platform environment — we're developing the reference pattern files only
- Mobile responsiveness — not relevant to Canvas App PCF dashboard
- TypeScript 5.x upgrade — blocked by pcf-scripts pinning TS 4.9.5; skipLibCheck workaround resolves type-checking issues

## Context

Shipped v2.0 with ~59k LOC TypeScript/CSS (handwritten) across the reference pattern. The PCF virtual control uses React 16.14.0 (platform-provided) with Fluent UI v9, built via Bun 1.3.8. Test suite has 387 test cases across 58 test files covering PCF components, hooks, agents, and utilities.

**Known tech debt (v2.0, medium/low):**
- #7: ~~Staleness polling (setInterval) lacks cleanup on unmount~~ **Resolved/Not Applicable** -- No setInterval exists in PCF source code. Staleness monitoring is handled server-side by the Staleness Monitor flow, not client-side polling. Reclassified during v2.1 Phase 11 review.
- #8: BriefingView test coverage thin on schedule logic
- #9: Command bar error states show raw error strings
- #10: No E2E flow coverage for send-email or set-reminder paths
- #11: Confidence calibration thresholds are hardcoded
- #12: Sender profile 30-day window not configurable
- #13: Daily briefing schedule stored in component state (lost on refresh)

**Legacy tech debt (v1.0, non-blocking):**
- Prompt/Dataverse layers still output "N/A" strings while schema uses null. Bridged at runtime by useCardData.ts ingestion boundary.

## Constraints

- **Tech stack**: PCF virtual control using React 16.14.0 (platform-provided), Fluent UI v9, TypeScript 4.9.5
- **Platform**: Power Apps Canvas Apps, Copilot Studio, Power Automate, Dataverse
- **Compatibility**: Must work with PAC CLI tooling and standard PCF build pipeline
- **Package manager**: Bun 1.3.8 (migrated from npm in v1.0 Phase 3)
- **No runtime testing**: We cannot run the solution locally — validation is through code review, type checking, and unit tests

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Schema fixes first (root contract) | All 5 downstream artifacts derive from output-schema.json; fixing code against wrong types creates rework | ✓ Good — zero rework, clean dependency chain |
| Table naming as separate phase | Touches every layer (schema, code, scripts, docs) — easier to audit in isolation | ✓ Good — zero violations confirmed by audit script |
| Null replaces N/A as not-applicable convention | Eliminates sentinel string ambiguity in typed contracts | ✓ Good — clean TypeScript types, though prompt/Dataverse layers still use N/A (bridged at ingestion) |
| item_summary is non-nullable string | Agent always generates a summary including for SKIP tier | ✓ Good — simplified all downstream null checks |
| Bun migration from npm | Faster installs, deterministic text lockfile | ✓ Good — clean builds, postinstall script handles pcf-scripts compatibility |
| XSS: safe protocol allowlist (https, mailto only) | Minimal attack surface, no http or enterprise schemes until needed | ✓ Good — unsafe URLs render as plain text |
| Tests last in dependency chain | Tests import component code that must be stable first | ✓ Good — no test rewrites needed from upstream changes |
| Skip tests for PowerShell scripts | No local Power Platform environment to test against | ⚠️ Revisit — could add Pester unit tests with mocked cmdlets |
| Function-first language for UI paths in docs | Copilot Studio UI is unstable; describe what to do, hint at where | ✓ Good — docs remain accurate despite UI changes |
| Jest 30 with ts-jest 29.4.6 | Bun resolved latest Jest; ts-jest peerDependencies allow ^29 or ^30 | ✓ Good — working configuration with skipLibCheck workaround |
| Fire-and-forget PCF output binding for email | PCF triggers output property change; Power Automate handles send with audit trail | ✓ Good — UI never blocks, guaranteed persistence |
| Flow-guaranteed audit trail | Outcome tracking persists via Power Automate, not client-side storage | ✓ Good — reliable even if user closes browser |
| Inline panel over dialog for draft editing | Preserves card context during editing, less disruptive UX | ✓ Good — natural workflow, no context switching |
| Sender-adaptive triage thresholds | 80% response + <8h turnaround = AUTO_HIGH; 40% response or 60% dismiss = AUTO_LOW | ✓ Good — empirically defensible boundaries |
| 30-day rolling window for sender profiles | Balances recency (captures relationship changes) against statistical stability | ✓ Good — sufficient sample size without stale data |
| Confidence score modifiers (+10/-10/+5) | Temporal urgency, edit distance penalty, engagement bonus add relational context | ✓ Good — meaningful signal adjustments |

---
*Last updated: 2026-02-28 after v2.1 milestone start*
