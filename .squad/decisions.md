# Squad Decisions — `copilot-studio-agent-patterns`

> Council-validated decisions that every member must honor. Each entry cites the round + reviewer that produced it. When a new round contradicts an old decision, the old entry stays for traceability and the new entry supersedes it (linked).

## Decision Index

| ID | Title | Source | Status |
|---|---|---|---|
| D1 | Env-var gate lives INSIDE the flow, not in the topic | Round 1 — Technical Reviewer (BLOCKING) | ✅ Active |
| D2 | `System.Conversation.Id` is the default correlation key | Round 1 — Technical Reviewer (BLOCKING) | ✅ Active |
| D3 | Tool flow follows IWL `tool-search-sharepoint.json` error pattern verbatim | Round 2 — Failure Mode Hunter #1 (BLOCKING) | ✅ Active |
| D4 | Child flow MUST fail-open (Scope_Write → on Failed → Terminate Succeeded) | Round 2 — Failure Mode Hunter #2 (BLOCKING) | ✅ Active |
| D5 | GUID lifecycle = Path B (placeholder + `inject-flow-guid.ps1` post-import substitution) | Round 2 — Synthesizer Section B1 | ✅ Active |
| D6 | Each topic ships in TWO variants: full (Dataverse persistence) + blog-pure (no deps) | Round 2 — Synthesizer Section B3 | ✅ Active |
| D7 | MDA is Phase-0 manual authoring in Maker portal, then `pac solution unpack` into source | Round 2 — Implementation Feasibility (BLOCKING) | ✅ Active |
| D8 | Solution is unmanaged-only for v1 | Round 2 — ALM Reviewer (recommendation) | ✅ Active |
| D9 | Quick Start time = "≈20 minutes for first-time setup; <5 min once tools are installed" (NOT "10 minutes") | Round 2 — Maker Walk-Through + Devil's Advocate | ✅ Active |
| D10 | Council critique with 3+ different-model reviewers + consensus synthesis is the standard for any architectural change | Pattern proven Round 1 + Round 2 | ✅ Active |
| D11 | This squad's coordinator is Jude's Copilot CLI session (not a side `copilot --agent squad` shell) for v1 | Plan Phase decision | ✅ Active |
| D12 | @copilot Coding Agent is OFF for v1 (domain artifacts are "🔴 Not suitable") | Plan Phase decision | ✅ Active |
| D13 | Ralph watch-mode is OFF for v1 (manual rounds; promote later) | Plan Phase decision | ✅ Active |
| D14 | Push policy: feature branches + draft PRs; **merges require Jude's approval** | Plan Phase decision | ✅ Active |
| D15 | PII discipline: never commit real customer/partner/tenant emails, domains, UPNs, org URLs, runtime configs, logs, or dumps. Use `example.com` for samples. Repo guardrail in `.github/workflows/prevent-pii-domains.yml` is the enforced baseline. | Pre-existing repo convention | ✅ Active |

---

## D1 — Env-var gate lives INSIDE the flow

**Source:** Round 1 Technical Reviewer (BLOCKING) — `coalesce(triggerBody, workflow().run.name)` in topic Condition node was structurally unsound.

**Decision:** Both flows (`flow-1-log-agent-trace`, `tool-log-agent-trace`) read `cr_DebugLoggerEnabled` as their FIRST action. Topics never read env vars (no platform precedent).

**Implementation:**
- `Get_DebugLoggerEnabled` action at flow start
- `Condition_IsEnabled` → if false → exit (child: `Terminate(Succeeded)`; tool: `Respond_to_PVA {logged: false}` then `Terminate`)
- Topics ALWAYS run their Message node (preserves blog-faithful visible italic trace) and ALWAYS invoke the tool flow; the flow no-ops when env var is OFF

**Cited in:** `files/debug-logger-v5-plan.md` §Confirmed decisions; §3 flows; §4 topics

---

## D2 — `System.Conversation.Id` is the default correlation key

**Source:** Round 1 Technical Reviewer (BLOCKING) + Reusability Reviewer

**Decision:** Drop the fabricated `Global.correlationId` (was undeclared, would fail topic validation). Use `=System.Conversation.Id` in topic InvokeFlowAction args. Caller may override by packing a `correlation_id` into the existing serialized JSON input (Pattern E in the maker guide).

**Implementation:**
- Topics: `correlation_id: =System.Conversation.Id`
- Flows: input `correlation_id` defaults via `coalesce(triggerBody, workflow().run.name)`
- Schema: `cr_correlationid` Text(100)

**Supersedes:** earlier drafts that referenced `Global.CORRELATION_ID`

---

## D3 — Tool flow error pattern verbatim from IWL

**Source:** Round 2 Failure Mode Hunter Finding #1 (BLOCKING; canonical evidence in `intelligent-work-layer/src/tool-search-sharepoint.json` lines 117-207)

**Decision:** `tool-log-agent-trace` MUST wrap its write in `Scope_Handle_Errors`. On Failed/TimedOut: `Respond_with_error` (PowerVirtualAgentsResponseV2, body `{ "logged": false }`, statusCode 200) MUST execute **BEFORE** `Terminate_Graceful(Failed)`. Otherwise the calling topic hangs.

**Why:** Without respond-before-terminate, a Dataverse outage freezes the calling agent turn. This is the highest-severity blast-radius failure mode in the design.

**Cited in:** `files/debug-logger-v5-plan.md` §3b; `tool-flow` todo

---

## D4 — Child flow MUST fail-open

**Source:** Round 2 Failure Mode Hunter Finding #2 (BLOCKING)

**Decision:** `flow-1-log-agent-trace` wraps its write in `Scope_Write`. On Failed/TimedOut → `Terminate(Succeeded)`. The logger never propagates failure to the caller — a Dataverse outage cannot brick the maker's main flow.

**Implementation:** Also applies to `Get_DebugLoggerEnabled` action — `Configure run after → Failed/TimedOut/Skipped` routes to a Compose that sets `enabled = false` (deleted env var fails open just like env var = false).

**Cited in:** `files/debug-logger-v5-plan.md` §3a; `child-flow` todo

---

## D5 — GUID lifecycle = Path B

**Source:** Round 2 Consensus Synthesizer Section B1 (convergence: Implementation Feasibility + ALM + Maker Walk-Through)

**Decision:** Ship topic YAMLs with `{{TOOL_LOG_AGENT_TRACE_FLOW_ID}}` placeholders. After solution import, run `scripts/inject-flow-guid.ps1` to query the actual flow GUID via PAC CLI and find-replace into `dist/topics/`. Skills CLI imports the substituted topics, OR the maker uses them as Web UI reference.

**Why this over Path A (same-solution auto-binding):** Path A requires topics to be real solution components, which requires either (i) maker authors agent in Maker portal then unpacks (defeats drop-in YAML value) or (ii) we add YAMLs as solution components via Skills CLI — which IS Path B.

**Why this over Path C (Web UI hand-binding only):** Path B matches IWL's repo-canonical `{{FLOW_GUID_*}}` placeholder precedent.

**Cited in:** `files/debug-logger-v5-plan.md` §Confirmed decisions; new `inject-flow-guid-script` todo; `docs-deployment` GUID-substitution subsection

---

## D6 — Topic variants: full + blog-pure

**Source:** Round 2 Consensus Synthesizer Section B3 (response to Devil's Advocate descope pressure)

**Decision:** Each topic concern ships TWO YAML files:
- `<name>.topic.mcs.yml` — full variant (Message node + InvokeFlowAction → Dataverse write)
- `<name>-blog-pure.topic.mcs.yml` — Message-only / capture-only, zero dependencies

**Why:** User scope (full topics with Dataverse persistence) is preserved. Devil's Advocate concern (persistence weakens drop-in claim) is addressed by giving makers both options.

**Cited in:** `files/debug-logger-v5-plan.md` §4 topics; topic-template todos

---

## D7 — MDA Phase-0 manual authoring

**Source:** Round 2 Implementation Feasibility (BLOCKING; universal Power Platform constraint)

**Decision:** Model-driven apps cannot be code-first authored from scratch. The MDA must be created once in Maker portal, then `pac solution clone --name CopilotAgentDebugLogger && pac solution unpack` into `src/Solutions/`. The unpacked MDA XML is committed.

**Implementation:** `deploy-solution.ps1` checks for MDA folder presence and fails loudly if missing. Plan never implies code-first MDA authoring.

**Cited in:** `files/debug-logger-v5-plan.md` §5; `model-driven-app` todo

---

## D8 — Unmanaged-only for v1

**Source:** Round 2 ALM Reviewer recommendation

**Decision:** Solution ships unmanaged. Publisher `cr`, unique name `CopilotAgentDebugLogger`, version `1.0.0.0`. Managed build target deferred to v0.2.

**Why:** POC scope. Customers extend later for cleaner uninstall paths.

**Cited in:** `files/debug-logger-v5-plan.md` §Confirmed decisions; A17

---

## D9 — Quick Start time honest disclosure

**Source:** Round 2 Maker Walk-Through + Devil's Advocate

**Decision:** Quick Start documentation says "≈20 minutes for first-time setup; <5 minutes once tools are installed." Drops the earlier "10 minutes" promise.

**Why:** First-time deploy realistically takes 20-30 min (PAC auth, env-var enable, tool-flow registration per agent, GUID substitution, smoke test). Over-promising on time kills maker trust.

**Cited in:** `files/debug-logger-v5-plan.md` §6 Quick Start

---

## D10 — Council critique process

**Source:** Pattern proven Round 1 (8 blocking findings) + Round 2 (17 critical fixes)

**Decision:** Any architectural change to the v5 plan (or any future architectural decision in this repo) requires:
1. 3-5 AI sub-agent reviewers with different lenses (simplicity / feasibility / failure-mode / devil's-advocate / maker-UX / ALM / etc.) — each using a DIFFERENT model to maximize lens diversity
2. A consensus synthesizer (typically `claude-opus-4.7-1m-internal`) producing a unified change set
3. Trade-offs flagged for Jude's sign-off
4. Updates to `decisions.md` for any new patterns

@danny coordinates; @rusty validates the application of consensus.

---

## D11–D14 — Operational decisions

- **D11**: Jude's Copilot CLI session = squad coordinator (no side `copilot --agent squad` shell needed)
- **D12**: @copilot Coding Agent OFF for v1 (verify `<!-- copilot-auto-assign: false -->` in team.md)
- **D13**: Ralph watch-mode OFF for v1 (manual rounds; `squad triage --execute` available later)
- **D14**: Feature branches + draft PRs; **all merges require Jude's approval**

---

## D15 — PII discipline (pre-existing repo convention)

**Source:** `.github/workflows/prevent-pii-domains.yml` + `.github/copilot-instructions.md`

**Decision:** Never commit real customer, partner, or tenant emails, domains, UPNs, org URLs, runtime configs, logs, dumps, or generated backups. Use neutral placeholders under `example.com` for all sample addresses/domains. If a change touches prompts, docs, mock data, fixtures, or scripts with email-like values, scan for PII before finalizing.

**Enforcement:** @rusty runs the PII guardrail check as part of every PR review.

---

## Governance

- All architectural changes require team consensus (D10).
- Document new patterns here; keep history focused on work, decisions focused on direction.
- When a decision is superseded, leave the old entry with a `❌ Superseded by Dxx` marker.

