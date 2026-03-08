import type { BriefingPackModel } from "../models/briefings";

export const mockBriefingPack: BriefingPackModel = {
  id: "briefing-progressive-core-team",
  title: "Progressive core team",
  timeLabel: "11:00 AM - 12:00 PM",
  summary: "Two carry-over actions from last week, one unresolved blocker, and one design decision on approval routing still need alignment.",
  state: "Ready",
  sections: [
    {
      id: "section-what-changed",
      title: "What changed",
      body: "A customer reply was approved and sent this morning, removing one dependency. The planning agent also created a new work packet for three open asks.",
      sectionType: "what_changed"
    },
    {
      id: "section-open-decisions",
      title: "Open decisions",
      body: "Approval routing remains unresolved. The current recommendation is to keep formal approvals in Power Automate while using the agent for intake and status visibility.",
      sectionType: "open_decisions"
    },
    {
      id: "section-talking-points",
      title: "Suggested talking points",
      body: "Confirm decision owner, align the next three milestones, and make the delivery blocker explicit rather than implicit.",
      sectionType: "talking_points"
    }
  ],
  primaryAction: {
    id: "act-open-briefing-pack",
    label: "Open pack",
    actionType: "open_briefing",
    requiresApproval: false,
    reversible: true
  },
  secondaryActions: [
    {
      id: "act-generate-talking-points",
      label: "Generate talking points",
      actionType: "generate_talking_points"
    },
    {
      id: "act-open-calendar-event",
      label: "Open calendar event",
      actionType: "open_source"
    }
  ],
  sourceContext: [
    {
      id: "calendar-progressive-core-team",
      source: "Calendar",
      label: "Progressive core team",
      deepLink: "msteams://m365/calendar/event/progressive-core-team",
      previewAvailable: true
    },
    {
      id: "teams-progressive-thread",
      source: "Teams",
      label: "Progressive core team collaboration thread",
      deepLink: "https://teams.microsoft.com/l/message/progressive-core-team",
      previewAvailable: true
    }
  ],
  producedBy: {
    agentId: "briefing-agent-01",
    agentName: "Briefing Agent",
    agentType: "briefing",
    runId: "run-brief-2001"
  }
};
