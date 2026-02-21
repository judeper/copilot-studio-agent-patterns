---
created: 2026-02-21T17:11:24.223Z
title: Research Copilot Outlook catchup feature for OOO agent
area: general
files: []
---

## Problem

Microsoft Copilot in Outlook has a "Catch Up" feature that activates when a user returns from out-of-office. It generates a succinct, prioritized summary of everything that happened during the OOO window. The prompt structure groups items by theme (Decisions, Actions Needed, FYI Updates) with each bullet containing: title, 1-sentence summary, 1-sentence impact, required action, and urgency level (High/Medium/Low).

Key prompt design patterns observed:
- **Scope**: Analyzes all work signals — emails, tasks, mentions, approvals, deadlines, project updates, decisions made in absence, work completed by others, new priorities/risks/escalations
- **Output format**: Single "Catch Up" section grouped by themes (Decisions, Actions Needed, FYI Updates)
- **Per-item structure**: Title, what happened (1 sentence), why it matters (1 sentence), required action or "No action needed", urgency level
- **Guidelines**: Prioritize immediate actions first, de-dupe threads across emails, synthesize insights (don't list raw activity), full context fast with minimal noise

This is worth researching as a potential new agent pattern for the Enterprise Work Assistant's single-pane-of-glass canvas. A dedicated "Catch Up" or "Return from OOO" agent could complement the existing work assistant by providing a synthesized re-entry summary when users return from time away.

## Solution

Research phase — no implementation yet. Future steps:
1. Deep-dive into the Copilot Outlook catchup feature behavior and prompt patterns
2. Evaluate how a similar agent could integrate with the existing Enterprise Work Assistant canvas
3. Consider data sources (email via Graph API, Teams messages, Planner tasks, etc.)
4. Design a prompt template following the observed pattern (themed grouping, per-item structure, urgency classification)
5. Determine if this becomes a new agent in the multi-agent topology or an additional mode/skill of the existing assistant agent
6. Assess feasibility within Copilot Studio agent orchestration capabilities
