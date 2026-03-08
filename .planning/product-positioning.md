# Product Positioning — Intelligent Work Layer (IWL)

> **Status:** Approved by AI Council (v3.0 Enhancement Review) and Architecture Council (v2.2 Tech Debt Review).
> This is the primary product definition document. All marketing copy, demo scripts, and README descriptions should derive from this positioning.

---

## 1. Product Identity

| Attribute | Value |
|-----------|-------|
| **Name** | Intelligent Work Layer (IWL) |
| **Category** | Intelligent Work Layer for Microsoft 365 |
| **Value Prop** | An intelligent work layer that intercepts email, Teams, and calendar signals — triaging, researching, and preparing draft responses before the user ever has to ask. |

> **Backward compatibility note:** The Dataverse table prefix `cr_` (e.g., `cr_assistantcards`), the directory name `enterprise-work-assistant/`, solution package names, and PCF component identifiers retain the original "Enterprise Work Assistant" naming for backward compatibility. The product rebrand to "Intelligent Work Layer" (IWL) applies to all user-facing documentation and positioning. The old name "Enterprise Work Assistant" (EWA) is deprecated.

### What It Is NOT

- **Not a replacement for Outlook or Teams.** Users still send email and chat in Teams. The assistant augments those tools — it does not intercept, redirect, or replace them.
- **Not an operating system.** It has no shell, no file system, no process model. It is a companion layer that sits alongside existing Microsoft 365 tools.
- **Not a chatbot.** Users do not converse with the system to get work done. Signals arrive pre-processed; the primary interaction is review, edit, and send — not prompt engineering.
- **Not an AI agent marketplace.** The multi-agent pipeline (22 agents) is an internal architecture concern. Users interact with a single dashboard, not individual agents.

---

## 2. Problem Statement

| Pain Point | Impact |
|-----------|--------|
| Knowledge workers spend **6+ hours/week** on async response composition | Direct productivity loss; compounds across teams |
| Critical signals get buried in inbox noise | Missed deadlines, dropped client threads, reputational risk |
| Context switching between tools fragments attention | Cognitive load from toggling Outlook → Teams → Planner → SharePoint degrades response quality |
| Draft quality varies across interactions | Users repeatedly compose similar responses from scratch; no institutional memory of communication patterns |

The Intelligent Work Layer addresses these by shifting the default from *compose* to *review*. Instead of starting from a blank page, users start from a researched, scored, drafted card — and decide whether to send, edit, or dismiss.

---

## 3. Target Users

### Primary Persona

Enterprise knowledge workers on Microsoft 365 who handle high volumes of asynchronous communication where response time and quality directly impact business outcomes.

### Qualifying Characteristics

| Dimension | Criteria |
|-----------|----------|
| **Role examples** | Legal counsel, finance analysts, executive assistants, sales account managers, project managers |
| **Signal volume** | 50–500 communication signals per day across email and Teams |
| **Outcome sensitivity** | Organizations where a delayed or poorly crafted response has measurable cost (regulatory, revenue, relationship) |
| **Platform requirements** | Microsoft 365 E3/E5 tenant with Power Platform and Copilot Studio licensing |
| **IT posture** | Environments where Power Automate cloud flows, Dataverse, and Copilot Studio agents are permitted |

### Who This Is NOT For

- Individual consumers or personal email accounts
- Organizations without Power Platform licensing
- Teams with < 10 signals/day (insufficient volume to justify the overhead)
- Environments requiring air-gapped or on-premises-only deployments

---

## 4. Key Differentiators (vs. Copilot for Microsoft 365)

| # | Differentiator | Detail |
|---|---------------|--------|
| 1 | **Proactive, not reactive** | Signals arrive pre-processed on a dashboard. Users don't ask — they review. Copilot for M365 requires the user to initiate a prompt. |
| 2 | **Multi-signal intelligence** | Unified triage across email + Teams + calendar in a single dashboard. Copilot for M365 operates within each app's silo (Outlook Copilot, Teams Copilot, etc.). |
| 3 | **Sender behavioral profiling** | Learns sender importance from user behavior patterns (response rate, edit distance, dismiss rate) via EWMA-weighted `cr_senderprofile` records. Copilot for M365 has no per-sender behavioral model. |
| 4 | **MARL confidence scoring** | Multi-agent pipeline with calibrated confidence: Triage → Research → Score → Draft → Humanize. Each stage produces a structured contract consumed by the next. Confidence scores (0–100) gate downstream actions. |
| 5 | **Learning loop** | Episodic memory (`cr_episodicmemories`) captures every decision. Semantic knowledge (`cr_semanticknowledges`) promotes patterns into reusable facts. The system improves over time — draft acceptance rates increase, override rates decrease. |

> **Positioning note:** These differentiators are architectural, not competitive. Copilot for M365 and the Intelligent Work Layer are complementary — IWL handles the proactive triage layer; Copilot handles ad-hoc in-app assistance.

---

## 5. Capability Pipeline

> **Internal Architecture — NOT User-Facing Modes**
>
> These are pipeline stages visible to developers and solution architects. Users never see or select these stages. They interact with a single dashboard: **CardGallery → CardDetail → CommandBar**. The pipeline runs autonomously behind this interface.

### Pipeline Stages

```
Signal (Email / Teams / Calendar)
  │
  ▼
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  TRIAGE  │───▶│ RESEARCH │───▶│  SCORE   │───▶│  DRAFT   │───▶│  REVIEW  │
│  < 2s    │    │ 5 tiers  │    │ 0–100    │    │ ≥ 40     │    │ Human    │
└──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
```

| Stage | Input | Output | Target Latency |
|-------|-------|--------|----------------|
| **Triage** | Raw signal (email metadata, Teams message, calendar event) | SKIP / LIGHT / FULL classification with priority and reasoning | < 2 seconds |
| **Research** | FULL-tier items | Multi-tier source scan: Tier 1 (email/Teams history), Tier 2 (SharePoint/wikis), Tier 3 (Planner tasks), Tier 4 (public web), Tier 5 (official docs) | 5–15 seconds |
| **Score** | Research results + sender profile + episodic context | Confidence score (0–100) with evidence attribution and threshold gating | < 2 seconds |
| **Draft** | Scored research + sender profile (confidence ≥ 40) | Raw draft + tone inference + recipient context; passed to Humanizer Connected Agent for natural rewriting | 3–8 seconds |
| **Review** | Humanized draft + research card on dashboard | User verifies research, edits draft, sends/dismisses → outcome logged → learning loop closes | User-paced |

### Key Design Principles

- **No mode switching.** The pipeline runs end-to-end for every signal. Users see the final result — a card on the dashboard — not intermediate stages.
- **Threshold gating.** SKIP items are not persisted (reduces noise). LIGHT items get a summary card. FULL items get the complete pipeline. Drafts are only generated when confidence ≥ 40.
- **Fail-open.** If any stage fails, the signal is still surfaced — with a degraded card and error context — rather than silently dropped.

---

## 6. Trust Positioning

Trust is the product's core constraint. Every design decision prioritizes user control over automation convenience.

### Guarantees

| Principle | Implementation |
|-----------|---------------|
| **The system NEVER sends anything without explicit user action** | Drafts are prepared and displayed. The user must click Send (or press Enter in CommandBar). There is no auto-send, no scheduled send, no background send. Power Automate Flow 4 fires only on explicit PCF output binding. |
| **Source attribution** | Every research finding includes tier attribution (Tier 1–5) and clickable source links via `verified_sources[]` typed array. The PCF renders these as navigable hyperlinks with URL allowlist validation (https: and mailto: only). |
| **Confidence transparency** | Three-state confidence display (HIGH / MEDIUM / LOW) on every FULL-tier card — based on arXiv 2024 AI trust miscalibration research showing users make better decisions with categorical confidence than raw percentages. Cards below the confidence threshold show a `LOW_CONFIDENCE` visual indicator via `ConfidenceCalibration.tsx`. |
| **Audit trail** | Three-layer audit: (1) Power Automate flow run history (28-day platform default), (2) Episodic memory in `cr_episodicmemories` (90-day retention), (3) Dataverse platform audit logs (tenant-configured). |
| **Right to erasure** | Scripted GDPR Article 17 / CCPA §1798.105 procedure via `user-data-erasure.ps1` with dry-run mode, OneNote cleanup, and 72-hour SLA. See `docs/data-governance.md` for the full runbook. |
| **Sender override** | Users can force FULL / LIGHT / SKIP per sender at any time. Explicit overrides (`USER_EXPLICIT`, `USER_OVERRIDE`) are preserved across learning resets and role changes. |

### Learning Safeguards

| Safeguard | Rule | Rationale |
|-----------|------|-----------|
| **Tone inference gating** | Disabled until draft acceptance rate exceeds **50%** for a given sender (minimum 5 interactions) | Prevents the "uncanny valley" effect where partially-learned tone feels more wrong than a safe default (`SEMI_FORMAL`) |
| **External sender cap** | External senders (outside org domain) capped at `AUTO_MEDIUM` | Prevents external actors from gaming the system via high-frequency or urgent-sounding messages. Legitimate external contacts earn FULL-tier through corroboration signals (shared calendar, Teams channel, conversation history). |
| **Memory poisoning defense** | External senders require corroboration to receive FULL triage | At least one of: shared calendar event (14-day window), Teams channel co-membership, or ≥ 3 prior conversation exchanges |
| **Role change reset** | User-initiated reset preserves `USER_EXPLICIT` facts, resets all `AUTO_*` categories | Prevents stale behavioral models from a previous role from degrading triage quality |

---

## 7. POC Boundary

### What the System IS in the Current POC

- ✅ **Autonomous signal triage and prioritization** — Email, Teams, and Calendar triggers invoke the Copilot Studio agent, which classifies signals into SKIP / LIGHT / FULL tiers
- ✅ **Multi-source research with confidence scoring** — 5-tier research pipeline with 0–100 confidence scoring and source attribution
- ✅ **Draft preparation with humanization** — Humanizer Connected Agent rewrites raw drafts in natural tone for FULL-tier items with confidence ≥ 40
- ✅ **Daily briefings with calendar context** — Daily Briefing Agent generates composite-scored briefings with action items, FYI items, stale alerts, and schedule configuration
- ✅ **Sender behavioral profiling** — EWMA-weighted sender profiles with automatic category inference (AUTO_HIGH, AUTO_LOW, AUTO_MEDIUM)
- ✅ **Learning architecture** — Schemas, table definitions, and flow documentation for episodic memory, semantic knowledge, edit analysis, and active learning patterns are complete
- ✅ **Single-pane dashboard** — PCF React virtual control with CardGallery, CardDetail, BriefingCard, CommandBar, FilterBar, StatusBar, ConfidenceCalibration, and DayGlance. UX grounded in cognitive science: 5-item focused queue (Cowan's 4±1 attention slots), quiet mode for focus protection (Gloria Mark's 23-min interruption cost), morning/EOD/meeting briefing variants, warm-gray palette for 8-hour sustained use (PMC visual fatigue), and `prefers-reduced-motion` support
- ✅ **Data governance runbook** — Retention policies, PII inventory, GDPR/CCPA erasure procedure, OneNote purge, and compliance mapping
- ✅ **22-agent MARL pipeline design** — Router, Calendar, Task, Email Compose, Search, Validation, and Delegation agents designed and documented

### What the System is NOT Yet

- ❌ **Production-hardened** — Full ARIA/screen reader audit, i18n, optimistic concurrency, DataSet paging (100+ cards), and capacity planning are out of scope (POC boundary)
- ❌ **Multi-language** — English-only UI (`1033.resx`) and English-only prompts; non-English content is processed but UI labels remain in English
- ❌ **Fully accessible** — WCAG AA partial compliance (keyboard navigation baseline shipped in Phase 17); full audit deferred
- ❌ **Learning system implemented** — Design docs, schemas, and flow specifications are complete; Power Automate learning flows (bootstrap, edit analyzer, EWMA updates, active learning) are not yet built
- ❌ **Replacement for Outlook or Teams** — The system augments, never replaces, existing Microsoft 365 tools
- ❌ **OneNote bi-directional sync** — Phase 1 (write-only) is functional; Phase 2–3 (read-back, annotation promotion) are designed but not implemented

---

## 8. Success Criteria (POC Phase)

| # | Metric | Target | Measurement Method |
|---|--------|--------|--------------------|
| 1 | **Signal coverage** | Processes EMAIL, TEAMS_MESSAGE, and CALENDAR_SCAN triggers without error | Flow run success rate across Flows 1–3 (target: > 95% success rate over 7-day window) |
| 2 | **Triage accuracy** | User override rate **< 30%** within 14 days of deployment | `cr_episodicmemories` entries where user changed triage tier ÷ total triage decisions |
| 3 | **Draft utility** | **> 50%** of FULL-tier drafts sent as-is or with minor edits (`edit_distance < 0.2`) | `cr_senderprofile.cr_acceptancerate` aggregated across all senders for the user |

### Stretch Goals (Not Required for POC Sign-Off)

| Metric | Target |
|--------|--------|
| Time-to-action reduction | Average minutes from card creation to user action decreases week-over-week |
| Learning velocity score | Composite score > 0.6 after 30 days (requires learning flows to be implemented) |
| Sender profile coverage | > 80% of FULL-tier signals have a non-`AUTO_UNKNOWN` sender profile |

---

*Last updated: 2026-03-08 — Approved by AI Council (v3.0) and Architecture Council (v2.2). Rebranded to Intelligent Work Layer (IWL).*
