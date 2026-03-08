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
