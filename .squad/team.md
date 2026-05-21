# Squad Team — `copilot-studio-agent-patterns`

> A heist crew building production-ready patterns for Power Platform / Copilot Studio agents. Current job: the **Copilot Agent Debug Logger POC** (per `files/debug-logger-v5-plan.md` — preserved in Jude's session). Future jobs: extending the intelligent-work-layer, email-productivity-agent, and agent-cost-governance-paygo solutions.

## Coordinator

| Name | Role | Notes |
|------|------|-------|
| Squad | Coordinator | Routes work, enforces handoffs and reviewer gates. Does not generate domain artifacts. |

## Members

| Name | Role | Charter | Status |
|------|------|---------|--------|
| Danny | Lead — Triage, planning, decisions, council coordination | `.squad/agents/danny/charter.md` | ✅ Active |
| Rusty | Reviewer — Gate every artifact against plan + council findings | `.squad/agents/rusty/charter.md` | ✅ Active |
| Frank | Schema & Solution — Dataverse tables, solution scaffolding, MDA | `.squad/agents/frank/charter.md` | ✅ Active |
| Virgil | Flow Author — Power Automate flow JSONs (manual + PVA triggers) | `.squad/agents/virgil/charter.md` | ✅ Active |
| Linus | Topic Author — Copilot Studio `.topic.mcs.yml` files | `.squad/agents/linus/charter.md` | ✅ Active |
| Basher | Scripts & ALM — PowerShell automation, PAC CLI, Web API | `.squad/agents/basher/charter.md` | ✅ Active |
| Saul | Docs & Maker UX — README, deployment-guide, maker-guide, click-paths | `.squad/agents/saul/charter.md` | ✅ Active |
| Scribe | Session Logger | `.squad/agents/scribe/charter.md` | 📋 Silent |
| Ralph | Persistent memory / work-queue monitor | `.squad/agents/ralph/charter.md` | 📋 Idle (v1) |

## Coding Agent

<!-- copilot-auto-assign: false -->

| Name | Role | Charter | Status |
|------|------|---------|--------|
| @copilot | Coding Agent | — | 🚫 Disabled for v1 |

### Capabilities

**🟢 Good fit — auto-route when enabled:**
- Bug fixes with clear reproduction steps
- Test coverage (adding missing tests, fixing flaky tests)
- Lint/format fixes and code style cleanup
- Documentation fixes (typos, broken links)

**🟡 Needs review — route to @copilot but flag for squad member PR review:**
- Small isolated features with clear specs
- Refactoring with existing test coverage

**🔴 Not suitable — route to squad member instead (default for v1):**
- Architecture decisions
- Copilot Studio topic / agent design
- Power Automate flow authoring (error-handling shapes are non-trivial)
- Dataverse schema design
- ALM / PowerShell deployment scripts
- Maker-facing documentation with click-paths

## Project Context

- **Owner:** Jude P.
- **Stack:** Microsoft Copilot Studio, Power Automate, Dataverse, Model-Driven Apps, PowerShell, PAC CLI, GitHub Actions
- **Description:** Production-ready patterns for building autonomous agents on the Microsoft Copilot Studio + Power Platform stack.
- **Current job:** Copilot Agent Debug Logger POC (v5 plan in session-state)
- **Created:** 2026-05-21
- **GitHub:** `judeper/copilot-studio-agent-patterns`
- **Casting universe:** Ocean's Eleven (2001)

## Communication Protocols

- **TLDR-first:** Every agent comment starts with a 2-3 sentence TLDR.
- **Council-validated decisions:** When making architectural decisions, run a multi-lens AI council critique with at least 3 reviewers before committing. Pattern proven on v5 plan (Round 1 + Round 2, see `decisions.md`).
- **Sub-agent execution:** The coordinator (Squad / Jude's Copilot CLI session) spawns task-tool sub-agents that adopt the relevant charter. Each sub-agent works against `files/debug-logger-v5-plan.md` and the latest council-validated decisions.
- **Async-first:** Work tracked via GitHub issues in `judeper/copilot-studio-agent-patterns` once GitHub issues are created in Phase 3.
- **Push policy:** All squad work goes on feature branches. PRs are left as drafts. **Merges require Jude's approval.**
