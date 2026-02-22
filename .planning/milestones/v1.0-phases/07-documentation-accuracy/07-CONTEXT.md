# Phase 7: Documentation Accuracy - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Correct the deployment guide and agent-flows documentation so a developer can follow them to a working deployment without hitting incorrect instructions. Fixes cover: Copilot Studio UI paths, Power Automate expression examples, "Run a prompt" action configuration, research tool action registration, Bun/Node prerequisites, and item_summary nullability in the PA schema. No new documentation files — only corrections and additions to existing docs.

</domain>

<decisions>
## Implementation Decisions

### Instruction depth & format
- Claude decides appropriate depth per section based on complexity (step-by-step where complex, concise where straightforward)
- Text-only — no screenshots or image placeholders
- "Run a prompt" action documentation goes inline in agent-flows.md where contextually relevant, not as a separate section
- Research tool action registration: full steps in deployment guide, brief mention in agent-flows.md with cross-reference link to the deployment guide

### Expression examples scope
- Cover a common patterns set: Choice column integer-to-label mapping, null handling, JSON parsing — the patterns a PA developer actually needs for this solution
- Present as code block with brief explanation of what it does and when to use it
- Use real field names from the solution (triage_tier, priority, confidence_score) — directly copy-pasteable
- PA simplified schema scope: Claude decides whether to show relevant fields only or full schema based on what makes the doc most useful

### Prerequisites & versioning
- Include install commands, not just version numbers
- Cover Windows + macOS platforms (winget/choco + brew)
- List all tools needed: dev tools (Bun, Node.js, .NET SDK) plus Power Platform tools (PAC CLI, Azure CLI) and environment requirements
- Use "tested with" versions (e.g., "Tested with Bun 1.2.x, Node.js 20.x") rather than just minimum versions

### UI path resilience
- Claude decides per-path whether to use exact menu paths or function-first descriptions with path hints, based on how stable each path is
- Add "Last verified: Feb 2026" per-section dates for UI-dependent instructions so readers know freshness
- Research phase should verify current Copilot Studio UI paths against live Microsoft documentation and release notes
- Troubleshooting: Claude decides based on likely deployment issues whether to add brief tips

### Claude's Discretion
- Documentation depth per section (step-by-step vs concise reference)
- PA simplified schema scope (relevant fields vs full schema)
- UI path description style per path (exact vs function-first)
- Whether to include a brief troubleshooting section

</decisions>

<specifics>
## Specific Ideas

- Expression examples should be directly copy-pasteable with real solution field names
- Per-section "Last verified" dates for UI-dependent instructions
- Cross-reference pattern: deployment guide has full steps, agent-flows.md links to them for registration topics

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-documentation-accuracy*
*Context gathered: 2026-02-21*
