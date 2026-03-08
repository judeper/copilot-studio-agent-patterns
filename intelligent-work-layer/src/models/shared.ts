/**
 * Shared types for the Intelligent Work Layer agent-to-UI contract.
 * Status: PROPOSAL — subject to validation against production payloads.
 */

export type SourceSystem =
  | "Outlook"
  | "Teams"
  | "Calendar"
  | "Planner"
  | "Files"
  | "Web"
  | "Internal";

export type PriorityLevel = "Critical" | "High" | "Medium" | "Low";

export type WorkItemState =
  | "Suggested"
  | "Ready"
  | "NeedsApproval"
  | "InFocus"
  | "Sent"
  | "Briefed"
  | "Completed"
  | "Blocked"
  | "Waiting";

export type AgentType =
  | "triage"
  | "planning"
  | "briefing"
  | "calendar"
  | "research"
  | "copilot_orchestrator";

export type ApprovalState = "not_required" | "pending" | "approved" | "rejected";

export type Reviewability = "full_preview" | "summary_preview" | "no_preview";

export type SourceContextRef = {
  id: string;
  source: SourceSystem;
  label: string;
  deepLink?: string;
  previewAvailable: boolean;
};

export type RelatedEntityRef = {
  id: string;
  entityType: "person" | "meeting" | "task" | "customer" | "file" | "thread";
  label: string;
};

export type AgentProducerRef = {
  agentId: string;
  agentName: string;
  agentType: AgentType;
  runId?: string;
};

export type GovernanceState = {
  approvalRequired: boolean;
  approvalState: ApprovalState;
  reviewability: Reviewability;
  interventionAllowed: boolean;
  auditVisible: boolean;
  rationaleVisible: boolean;
};

export type PrimaryAction = {
  id: string;
  label: string;
  actionType:
    | "open_workbench"
    | "approve_and_send"
    | "open_briefing"
    | "resume_focus"
    | "generate_review"
    | "open_source"
    | "convert_to_work_packet";
  requiresApproval: boolean;
  reversible?: boolean;
};

export type SecondaryAction = {
  id: string;
  label: string;
  actionType:
    | "improve_tone"
    | "pause"
    | "capture_resume_marker"
    | "generate_talking_points"
    | "open_source"
    | "rebuild_lane";
};

export type LaunchPoint = {
  id: string;
  source: SourceSystem;
  label: string;
  deepLink?: string;
  available: boolean;
};

export type DraftArtifact = {
  id: string;
  content: string;
  channel: "email" | "teams";
  editable: boolean;
  version: number;
};
