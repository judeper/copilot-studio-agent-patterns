# Intelligent Work Layer — Roadmap

## Current State (v2.2 POC)

The Intelligent Work Layer is a POC-scoped solution. All core features are implemented:
- Main Agent (triage, research, scoring, JSON output)
- Humanizer Agent (Connected Agent for tone calibration)
- Daily Briefing Agent (action items, FYI, stale alerts)
- Orchestrator Agent (command execution with tool actions)
- PCF React Dashboard (gallery, detail, edit, briefing, command bar)
- 10 Power Automate agent flow definitions
- 10 agent tool flow definitions (5 research + 5 orchestrator)
- OneNote Integration (Phase 1 — write-only)
- Dataverse schema (AssistantCards, SenderProfile, BriefingSchedule, ErrorLog)
- Deployment automation (provision-environment, create-security-roles, deploy-solution, deploy-agent-flows, provision-copilot, provision-onenote)

---

## Productivity & Noise Reduction Roadmap

> Identified via the [Design Review — Productivity & Noise Reduction Assessment](design-review-productivity-noise.md). Each gap addresses a specific failure mode where noise still reaches the user or the system fails to protect productivity.

### P0 — Critical Noise Eliminators

| Todo ID | Gap | Description | Complexity |
|---------|-----|-------------|------------|
| `conversation-threading` | Gap 1: No Conversation Threading | Implement conversation clustering in CardGallery — show latest card per cluster with "N related" badge. Reduces visible card count by 40-60%. Uses existing `cr_conversationclusterid`. | Medium |
| `snooze-defer` | Gap 2: No Snooze/Defer | Add snooze UI with presets (1 hour, tomorrow morning, Friday, custom). Sets `cr_snoozeduntil` and `cr_cardstatus = SNOOZED`. Flow 10 handles re-surfacing. | Low-Medium |
| `external-action-detection` | Gap 3: No External Action Detection | Implement 15-minute Sent Items scan in Flow 5. Match by `internetMessageId` or `conversationId`. Auto-dismiss with `cr_cardoutcome = RESOLVED_EXTERNALLY`. | Medium |

### P1 — High-Value Improvements

| Todo ID | Gap | Description | Complexity |
|---------|-----|-------------|------------|
| `batch-actions` | Gap 4: No Batch Actions | Add checkbox selection to CardItem + batch action bar (Dismiss All, Snooze All, Archive All). Cap at 25 cards per batch. | Low |
| `light-tier-auto-archive` | Gap 5: LIGHT Tier Auto-Archive | 6-hour scheduled flow marks LIGHT-tier cards with `cr_cardoutcome = EXPIRED` after 48 hours of no interaction. | Low |
| `signal-batching` | Gap 6: No Signal Batching | 5-minute batching window in Flows 1-2. Collect signals, deduplicate by sender+subject, invoke agent once per batch. | Medium |
| `focus-shield` | Gap 7: No Focus Session Integration | Before agent invocation, check calendar for Focus Time events. Auto-triage non-URGENT signals to LIGHT during focus windows. Sets `cr_focusshieldactive = true`. | Medium |

### P2 — Trust & Learning

| Todo ID | Gap | Description | Complexity |
|---------|-----|-------------|------------|
| `graduated-autonomy` | Gap 8: No Graduated Autonomy | Three tiers: Observer (default, 30 days) → Assist (>70% acceptance, >50 interactions) → Partner (>85%, >200 interactions). Uses `cr_autonomytier`, `cr_totalinteractions`, `cr_acceptancerate` on UserPersona. | High |
| `triage-explainability` | Gap 9: No Triage Explainability | Add `triage_reasoning` field to agent output and `cr_triagereasoning` Dataverse column. Surface as expandable "Why this priority?" in CardDetail. | Low |
| `cold-start-tone-bootstrap` | Gap 10: Cold Start Tone Bootstrap | Extend Graph bootstrap to analyze user's own sent email patterns (formality, greetings, sign-offs). Seed `cr_tonebaseline` on UserPersona. | Medium |
| `card-search` | Gap 11: No Search | Add search input to FilterBar. Client-side filtering by sender, subject, summary text. | Low |

### P3 — Polish & Resilience

| Todo ID | Gap | Description | Complexity |
|---------|-----|-------------|------------|
| `keyboard-navigation` | Gap 12: No Keyboard Navigation | Implement j/k/Enter/d/s/? shortcuts with help overlay. | Low |
| `undo-actions` | Gap 13: No Undo for Destructive Actions | 10-second undo toast for dismiss and send. Hold Dataverse write for undo window. | Low |
| `onboarding-wizard` | Gap 14: No Onboarding | 3-step wizard: display name, briefing schedule, command bar trial. | Low |
| `card-deduplication` | Gap 15: No Card Deduplication | Pre-agent query in Flows 1-2 for matching `cr_conversationclusterid` within 5 minutes. Update existing card instead of creating new. | Low |
| `degraded-mode` | Gap 16: No Degraded Mode | 3-retry logic in Flows 1-3. Fallback: create `PENDING_MANUAL` card with raw signal payload. | Medium |
| `data-retention` | Gap 17: No Data Retention | Weekly scheduled flow archives cards with `cr_cardoutcome != PENDING` older than 90 days. | Low |

---

## Deferred Items (Out of Scope for POC)

### Accessibility
- [ ] Full ARIA audit with screen reader testing (NVDA, JAWS, VoiceOver)
- [ ] WCAG 2.1 AA compliance validation
- [ ] High contrast mode support
- [ ] Reduced motion preference support

### Internationalization (i18n)
- [ ] Additional `.resx` locale files beyond English (1033)
- [ ] Agent prompt localization for non-English tenants
- [ ] RTL layout support
- [ ] Date/time format localization

### Data Integrity & Scale
- [ ] Optimistic concurrency on Dataverse writes (ETags)
- [ ] DataSet paging for 100+ cards (PCF `loadNextPage()`)
- [ ] Capacity planning and load testing
- [ ] Automated data retention flow (delete/archive cards > N days)
- [ ] SKIP item audit trail (separate lightweight Dataverse table or Application Insights)

### OneNote Integration
- [ ] **Phase 2 — Read-Back:** Project logs, sender dossiers, decision logs, annotation promotion to Tier 1 research
- [ ] **Phase 3 — Bi-Directional Sync:** Annotation detection, managed identity, per-agent cost attribution

### Canvas App
- [ ] Offline support / progressive web app capabilities
- [ ] Responsive layout for mobile devices
- [ ] Adaptive Card rendering for richer card display

### Security & Governance
- [ ] Purview/Sentinel audit integration
- [ ] DLP policy validation automation
- [ ] Column-level security on `cr_fulljson` for sensitive data
- [ ] Data classification tagging for PII in card content

### Agent Intelligence
- [ ] Confidence scoring calibration with A/B testing
- [ ] Triage accuracy monitoring dashboard
- [ ] User feedback loop (thumbs up/down on triage decisions)
- [ ] Few-shot classification examples as Knowledge source

### Performance
- [ ] Calendar scan batching (group similar events)
- [ ] Parallel research tool execution
- [ ] Agent response caching for repeated queries
- [ ] Connection throttling retry with exponential backoff
