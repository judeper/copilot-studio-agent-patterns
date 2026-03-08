/**
 * Adapters bridging existing AssistantCard data to Work OS proposal models.
 * Status: PROPOSAL — evolves with the Work OS contract.
 */

import type {
  AssistantCard,
  CommandSideEffect,
  DraftPayload,
  DraftType,
} from "../AssistantDashboard/components/types";
import type { WorkQueueItem } from "./queue";
import type { AgentActivityItem } from "./activity";
import type { ShellState } from "./scenario";
import type {
  PriorityLevel,
  WorkItemState,
  SourceSystem,
  DraftArtifact,
  GovernanceState,
  PrimaryAction,
  AgentProducerRef,
  SourceContextRef,
} from "./shared";

// ── Internal helpers ────────────────────────────────────────────────

function isDraftPayload(value: unknown): value is DraftPayload {
  return (
    typeof value === "object" &&
    value !== null &&
    "draft_type" in value &&
    "raw_draft" in value
  );
}

function mapPriority(p: AssistantCard["priority"]): PriorityLevel {
  switch (p) {
    case "High":
      return "High";
    case "Medium":
      return "Medium";
    case "Low":
      return "Low";
    case "N/A":
    default:
      return "Low";
  }
}

function mapState(card: AssistantCard): WorkItemState {
  if (card.card_outcome === "SENT_AS_IS" || card.card_outcome === "SENT_EDITED")
    return "Sent";
  if (card.card_outcome === "DISMISSED" || card.card_outcome === "EXPIRED")
    return "Completed";
  if (card.card_status === "READY") {
    return (card.confidence_score ?? 0) >= 90 ? "Ready" : "NeedsApproval";
  }
  if (card.card_status === "LOW_CONFIDENCE") return "Blocked";
  if (card.card_status === "NUDGE") return "Waiting";
  return "Suggested";
}

function mapSource(trigger: AssistantCard["trigger_type"]): SourceSystem {
  switch (trigger) {
    case "EMAIL":
      return "Outlook";
    case "TEAMS_MESSAGE":
      return "Teams";
    case "CALENDAR_SCAN":
      return "Calendar";
    case "PREP_REQUIRED":
    case "STALE_TASK":
    case "FOLLOW_UP_NEEDED":
    case "PATTERN_ALERT":
      return "Internal";
    default:
      return "Internal";
  }
}

function mapItemType(card: AssistantCard): WorkQueueItem["itemType"] {
  const hasDraft = isDraftPayload(card.draft_payload);
  if (card.trigger_type === "EMAIL" && hasDraft) return "draft_reply";
  if (card.trigger_type === "TEAMS_MESSAGE" && hasDraft) return "quick_reply";
  if (card.trigger_type === "CALENDAR_SCAN") return "briefing_pack";
  if (card.trigger_type === "DAILY_BRIEFING") return "briefing_pack";
  return "review_task";
}

function mapDraftChannel(draftType: DraftType): DraftArtifact["channel"] {
  return draftType === "EMAIL" ? "email" : "teams";
}

function formatTimeLabel(date: Date): string {
  const h = date.getHours();
  const m = date.getMinutes();
  const ampm = h >= 12 ? "PM" : "AM";
  const h12 = h % 12 || 12;
  return `${h12}:${m.toString().padStart(2, "0")} ${ampm}`;
}

function mapEffectTone(
  action: CommandSideEffect["action"],
): AgentActivityItem["tone"] {
  return action === "CREATE_CARD" ? "success" : "info";
}

// ── Shared producer refs ────────────────────────────────────────────

const MARL_PRODUCER: AgentProducerRef = {
  agentId: "marl-pipeline",
  agentName: "IWL MARL Pipeline",
  agentType: "triage",
};

const ORCHESTRATOR_PRODUCER: AgentProducerRef = {
  agentId: "orchestrator",
  agentName: "IWL Orchestrator",
  agentType: "copilot_orchestrator",
};

// ── Sub-builders for toWorkQueueItem ────────────────────────────────

function buildGovernance(card: AssistantCard): GovernanceState {
  const confidence = card.confidence_score ?? 0;
  const hasDraft = isDraftPayload(card.draft_payload);
  const hasResearch =
    card.research_log !== null || card.key_findings !== null;
  return {
    approvalRequired: confidence < 90,
    approvalState: confidence >= 90 ? "not_required" : "pending",
    reviewability: hasDraft
      ? "full_preview"
      : hasResearch
        ? "summary_preview"
        : "no_preview",
    interventionAllowed: true,
    auditVisible: true,
    rationaleVisible: true,
  };
}

function buildPrimaryAction(card: AssistantCard): PrimaryAction {
  const confidence = card.confidence_score ?? 0;
  const hasDraft = isDraftPayload(card.draft_payload);

  if (hasDraft) {
    return {
      id: `${card.id}-approve`,
      label: "Approve & Send",
      actionType: "approve_and_send",
      requiresApproval: confidence < 90,
    };
  }
  if (card.trigger_type === "CALENDAR_SCAN") {
    return {
      id: `${card.id}-briefing`,
      label: "Open Briefing",
      actionType: "open_briefing",
      requiresApproval: false,
    };
  }
  return {
    id: `${card.id}-open`,
    label: "Open Workbench",
    actionType: "open_workbench",
    requiresApproval: false,
  };
}

function buildSourceContext(
  card: AssistantCard,
): SourceContextRef[] | undefined {
  if (!card.original_sender_email) return undefined;
  return [
    {
      id: card.source_signal_id ?? card.id,
      source: mapSource(card.trigger_type),
      label: card.original_subject ?? card.item_summary,
      previewAvailable: true,
    },
  ];
}

// ── Public adapters ─────────────────────────────────────────────────

/** Extract a DraftArtifact from a card's draft payload, if present. */
export function toDraftArtifact(
  card: AssistantCard,
): DraftArtifact | undefined {
  if (!isDraftPayload(card.draft_payload)) return undefined;
  const dp = card.draft_payload;
  return {
    id: `${card.id}-draft`,
    content: card.humanized_draft ?? dp.raw_draft,
    channel: mapDraftChannel(dp.draft_type),
    editable: true,
    version: 1,
  };
}

/** Map an AssistantCard to a Work OS WorkQueueItem. */
export function toWorkQueueItem(card: AssistantCard): WorkQueueItem {
  return {
    id: card.id,
    itemType: mapItemType(card),
    title: card.original_subject ?? card.item_summary,
    source: mapSource(card.trigger_type),
    priority: mapPriority(card.priority),
    state: mapState(card),
    reason: card.urgency_reason ?? card.item_summary,
    expectedOutcome: isDraftPayload(card.draft_payload)
      ? "Draft ready for review and send"
      : card.trigger_type === "CALENDAR_SCAN"
        ? "Briefing pack prepared"
        : "Item reviewed",
    confidence: card.confidence_score ?? undefined,
    action: buildPrimaryAction(card),
    governance: buildGovernance(card),
    sourceContext: buildSourceContext(card),
    updatedAtUtc: card.created_on,
    producedBy: MARL_PRODUCER,
  };
}

/** Map a CommandSideEffect to an AgentActivityItem. */
export function toAgentActivityItem(
  effect: CommandSideEffect,
  timestamp: Date = new Date(),
): AgentActivityItem {
  return {
    id: `${effect.action}-${timestamp.getTime()}`,
    text: effect.description,
    timeLabel: formatTimeLabel(timestamp),
    tone: mapEffectTone(effect.action),
    taskState: "completed",
    producedBy: ORCHESTRATOR_PRODUCER,
  };
}

/** Derive partial ShellState from quiet-mode toggle and held-item count. */
export function toShellState(
  quietMode: boolean,
  _heldCount: number,
): Partial<ShellState> {
  return {
    quietMode,
    allowedInterruptions: quietMode ? "critical_only" : "all",
  };
}
