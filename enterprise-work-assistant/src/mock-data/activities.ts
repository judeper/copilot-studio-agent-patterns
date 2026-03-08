import type { AgentActivityItem } from "../models/activity";

export const mockActivities: AgentActivityItem[] = [
  {
    id: "activity-morning-summary",
    text: "Morning summary generated with focus window recommendation.",
    timeLabel: "08:29 AM",
    tone: "info",
    taskState: "completed",
    producedBy: {
      agentId: "copilot-orchestrator-01",
      agentName: "Work OS Orchestrator",
      agentType: "copilot_orchestrator",
      runId: "run-orch-0001"
    }
  },
  {
    id: "activity-customer-draft",
    text: "Email agent prepared a customer draft with confidence and rationale.",
    timeLabel: "08:34 AM",
    tone: "success",
    taskState: "completed",
    producedBy: {
      agentId: "triage-agent-01",
      agentName: "Communication Triage Agent",
      agentType: "triage",
      runId: "run-triage-1001"
    }
  },
  {
    id: "activity-focus-held",
    text: "Quiet mode held back three low-priority interruptions during focus time.",
    timeLabel: "09:21 AM",
    tone: "info",
    taskState: "completed",
    producedBy: {
      agentId: "planning-agent-01",
      agentName: "Planning Agent",
      agentType: "planning",
      runId: "run-plan-3001"
    }
  },
  {
    id: "activity-customer-reply-sent",
    text: "Critical customer reply approved and sent from the work surface.",
    timeLabel: "09:43 AM",
    tone: "success",
    taskState: "completed",
    producedBy: {
      agentId: "triage-agent-01",
      agentName: "Communication Triage Agent",
      agentType: "triage",
      runId: "run-triage-1001"
    }
  },
  {
    id: "activity-briefing-ready",
    text: "Meeting briefing pack assembled with fresh thread context.",
    timeLabel: "10:46 AM",
    tone: "info",
    taskState: "completed",
    producedBy: {
      agentId: "briefing-agent-01",
      agentName: "Briefing Agent",
      agentType: "briefing",
      runId: "run-brief-2001"
    }
  },
  {
    id: "activity-close-of-day",
    text: "Close-of-day review prepared with carry-forward suggestions for tomorrow.",
    timeLabel: "05:09 PM",
    tone: "success",
    taskState: "requires_user_action",
    producedBy: {
      agentId: "review-agent-01",
      agentName: "Review Agent",
      agentType: "planning",
      runId: "run-review-4001"
    }
  }
];
