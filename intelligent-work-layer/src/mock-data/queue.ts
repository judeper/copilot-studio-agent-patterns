import type { WorkQueueItem } from "../models/queue";

export const mockQueue: WorkQueueItem[] = [
  {
    id: "queue-approve-scope-reply",
    itemType: "draft_reply",
    title: "Approve customer scope reply",
    source: "Outlook",
    priority: "Critical",
    state: "NeedsApproval",
    reason: "Reply SLA is approaching and next week workshop scope is still unconfirmed.",
    expectedOutcome: "Unblocks workshop planning and protects customer confidence.",
    confidence: 93,
    estimatedEffort: "6 min",
    visibleFromMoment: "morning_briefing",
    action: {
      id: "act-approve-scope-reply",
      label: "Approve and send",
      actionType: "approve_and_send",
      requiresApproval: true,
      reversible: false
    },
    governance: {
      approvalRequired: true,
      approvalState: "pending",
      reviewability: "full_preview",
      interventionAllowed: true,
      auditVisible: true,
      rationaleVisible: true
    },
    sourceContext: [
      {
        id: "outlook-thread-pinnacle-scope",
        source: "Outlook",
        label: "Pinnacle follow-up on scope",
        deepLink: "msteams://m365/outlook/mail/pinnacle-scope-thread",
        previewAvailable: true
      }
    ],
    relatedEntities: [
      { id: "person-derek", entityType: "person", label: "Derek D'Amore" },
      { id: "customer-pinnacle", entityType: "customer", label: "Pinnacle" },
      { id: "meeting-workshop", entityType: "meeting", label: "Pinnacle workshop planning" }
    ],
    updatedAtUtc: "2026-03-08T08:34:00Z",
    producedBy: {
      agentId: "triage-agent-01",
      agentName: "Communication Triage Agent",
      agentType: "triage",
      runId: "run-triage-1001"
    }
  },
  {
    id: "queue-focus-blueprint",
    itemType: "focus_block",
    title: "Protect blueprint focus block",
    source: "Planner",
    priority: "High",
    state: "Suggested",
    reason: "The most valuable morning work is product-definition writing, and noncritical traffic should not fragment it.",
    expectedOutcome: "Preserves deep work and keeps the session resumable.",
    confidence: 94,
    estimatedEffort: "90 min",
    visibleFromMoment: "morning_briefing",
    action: {
      id: "act-resume-focus",
      label: "Resume focus",
      actionType: "resume_focus",
      requiresApproval: false,
      reversible: true
    },
    governance: {
      approvalRequired: false,
      approvalState: "not_required",
      reviewability: "summary_preview",
      interventionAllowed: true,
      auditVisible: true,
      rationaleVisible: true
    },
    relatedEntities: [
      { id: "task-blueprint", entityType: "task", label: "Work OS product blueprint" }
    ],
    updatedAtUtc: "2026-03-08T08:29:00Z",
    producedBy: {
      agentId: "planning-agent-01",
      agentName: "Planning Agent",
      agentType: "planning",
      runId: "run-plan-3001"
    }
  },
  {
    id: "queue-manager-priority-view",
    itemType: "quick_reply",
    title: "Respond to manager Teams request",
    source: "Teams",
    priority: "High",
    state: "Suggested",
    reason: "Direct manager ask for a concise priority view before Monday.",
    expectedOutcome: "Keeps leadership aligned without breaking work momentum.",
    confidence: 97,
    estimatedEffort: "2 min",
    visibleFromMoment: "triage_interruption",
    action: {
      id: "act-open-manager-reply",
      label: "Open workbench",
      actionType: "open_workbench",
      requiresApproval: false,
      reversible: true
    },
    governance: {
      approvalRequired: false,
      approvalState: "not_required",
      reviewability: "full_preview",
      interventionAllowed: true,
      auditVisible: true,
      rationaleVisible: true
    },
    sourceContext: [
      {
        id: "teams-thread-priorities",
        source: "Teams",
        label: "Latest customer priorities",
        deepLink: "https://teams.microsoft.com/l/message/priority-view-thread",
        previewAvailable: true
      }
    ],
    relatedEntities: [
      { id: "person-michelle", entityType: "person", label: "Michelle Bozeman" }
    ],
    updatedAtUtc: "2026-03-08T09:43:00Z",
    producedBy: {
      agentId: "triage-agent-01",
      agentName: "Communication Triage Agent",
      agentType: "triage",
      runId: "run-triage-1002"
    }
  },
  {
    id: "queue-open-progressive-briefing",
    itemType: "briefing_pack",
    title: "Open Progressive briefing pack",
    source: "Calendar",
    priority: "High",
    state: "Ready",
    reason: "Meeting starts soon and still carries unresolved dependencies.",
    expectedOutcome: "Reduces live problem-solving and improves meeting readiness.",
    confidence: 88,
    estimatedEffort: "8 min",
    visibleFromMoment: "meeting_briefing",
    action: {
      id: "act-open-progressive-pack",
      label: "Open briefing",
      actionType: "open_briefing",
      requiresApproval: false,
      reversible: true
    },
    governance: {
      approvalRequired: false,
      approvalState: "not_required",
      reviewability: "summary_preview",
      interventionAllowed: true,
      auditVisible: true,
      rationaleVisible: true
    },
    sourceContext: [
      {
        id: "calendar-progressive-core-team",
        source: "Calendar",
        label: "Progressive core team",
        deepLink: "msteams://m365/calendar/event/progressive-core-team",
        previewAvailable: true
      }
    ],
    relatedEntities: [
      { id: "meeting-progressive-core-team", entityType: "meeting", label: "Progressive core team" },
      { id: "customer-progressive", entityType: "customer", label: "Progressive" }
    ],
    updatedAtUtc: "2026-03-08T10:46:00Z",
    producedBy: {
      agentId: "briefing-agent-01",
      agentName: "Briefing Agent",
      agentType: "briefing",
      runId: "run-brief-2001"
    }
  },
  {
    id: "queue-generate-eod-review",
    itemType: "review_task",
    title: "Generate close-of-day review",
    source: "Planner",
    priority: "High",
    state: "Suggested",
    reason: "The operating system should carry forward what matters into tomorrow’s focus lane.",
    expectedOutcome: "Tomorrow starts with clarity instead of residue.",
    confidence: 91,
    estimatedEffort: "4 min",
    visibleFromMoment: "end_of_day_review",
    action: {
      id: "act-generate-eod-review",
      label: "Generate review",
      actionType: "generate_review",
      requiresApproval: false,
      reversible: true
    },
    governance: {
      approvalRequired: false,
      approvalState: "not_required",
      reviewability: "summary_preview",
      interventionAllowed: true,
      auditVisible: true,
      rationaleVisible: true
    },
    updatedAtUtc: "2026-03-08T17:09:00Z",
    producedBy: {
      agentId: "review-agent-01",
      agentName: "Review Agent",
      agentType: "planning",
      runId: "run-review-4001"
    }
  }
];
