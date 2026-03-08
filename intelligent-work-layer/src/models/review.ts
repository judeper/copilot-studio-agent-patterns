/**
 * Close-of-day review and focus lane types for the Intelligent Work Layer.
 * Status: PROPOSAL — subject to validation against production payloads.
 */

import type { PrimaryAction, SecondaryAction } from "./shared";

export type ReviewMetric = {
  id: string;
  label: string;
  value: string;
  note: string;
};

export type CarryForwardItem = {
  id: string;
  label: string;
  value: string;
};

export type CloseOfDayReviewModel = {
  metrics: ReviewMetric[];
  carryForward: CarryForwardItem[];
  primaryAction: PrimaryAction;
  secondaryActions?: SecondaryAction[];
};

export type ResumeMarker = {
  title: string;
  detail: string;
  capturedAtUtc: string;
};

export type FocusLaneModel = {
  id: string;
  title: string;
  summary: string;
  focusWindow: string;
  interruptionsHeldCount: number;
  unresolvedDependenciesCount: number;
  resumeMarker?: ResumeMarker;
  nextSmallestStep?: string;
  flowMemory?: string;
  primaryAction: PrimaryAction;
  secondaryActions?: SecondaryAction[];
};
