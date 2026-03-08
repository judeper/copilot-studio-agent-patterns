/**
 * Briefing pack types for the Intelligent Work Layer.
 * Status: PROPOSAL — subject to validation against production payloads.
 */

import type {
  AgentProducerRef,
  PrimaryAction,
  SecondaryAction,
  SourceContextRef,
} from "./shared";

export type BriefingSection = {
  id: string;
  title: string;
  body: string;
  sectionType: "what_changed" | "open_decisions" | "talking_points" | "risk" | "context";
};

export type BriefingPackModel = {
  id: string;
  title: string;
  timeLabel: string;
  summary: string;
  state: "Ready" | "Briefed";
  sections: BriefingSection[];
  primaryAction: PrimaryAction;
  secondaryActions?: SecondaryAction[];
  sourceContext: SourceContextRef[];
  producedBy: AgentProducerRef;
};
