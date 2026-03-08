/**
 * Work queue item type for the Intelligent Work Layer priority queue.
 * Status: PROPOSAL — subject to validation against production payloads.
 */

import type {
  AgentProducerRef,
  GovernanceState,
  PrimaryAction,
  PriorityLevel,
  RelatedEntityRef,
  SourceContextRef,
  SourceSystem,
  WorkItemState,
} from "./shared";
import type { ScenarioMomentId } from "./scenario";

export type WorkQueueItem = {
  id: string;
  itemType: "draft_reply" | "focus_block" | "quick_reply" | "briefing_pack" | "review_task";
  title: string;
  source: SourceSystem;
  priority: PriorityLevel;
  state: WorkItemState;
  reason: string;
  expectedOutcome: string;
  confidence?: number;
  estimatedEffort?: string;
  visibleFromMoment?: ScenarioMomentId;
  action: PrimaryAction;
  governance: GovernanceState;
  sourceContext?: SourceContextRef[];
  relatedEntities?: RelatedEntityRef[];
  updatedAtUtc: string;
  producedBy: AgentProducerRef;
};
