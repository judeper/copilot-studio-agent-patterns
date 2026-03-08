/**
 * Agent activity visibility types for the Intelligent Work Layer.
 * Status: PROPOSAL — subject to validation against production payloads.
 */

import type { AgentProducerRef } from "./shared";

export type AgentActivityItem = {
  id: string;
  text: string;
  timeLabel: string;
  tone: "info" | "success" | "warning";
  taskState: "running" | "completed" | "requires_user_action";
  producedBy: AgentProducerRef;
};
