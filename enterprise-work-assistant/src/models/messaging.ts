/**
 * Message decision and interruption types for the Intelligent Work Layer.
 * Status: PROPOSAL — subject to validation against production payloads.
 */

import type {
  AgentProducerRef,
  DraftArtifact,
  GovernanceState,
  SourceContextRef,
} from "./shared";

export type MessageDecisionItem = {
  id: string;
  source: "Outlook" | "Teams";
  senderDisplayName: string;
  title: string;
  summary: string;
  rationale: string;
  confidence: number;
  draft: DraftArtifact;
  governance: GovernanceState;
  sourceContext: SourceContextRef[];
  producedBy: AgentProducerRef;
};

export type InterruptionWorkbenchModel = {
  items: MessageDecisionItem[];
  selectedItemId: string;
};
