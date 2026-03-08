/**
 * Top-level Work OS view model for the Intelligent Work Layer.
 * Status: PROPOSAL — subject to validation against production payloads.
 */

import type { AgentActivityItem } from "./activity";
import type { BriefingPackModel } from "./briefings";
import type { CopilotPanelModel } from "./copilot";
import type { InterruptionWorkbenchModel } from "./messaging";
import type { WorkQueueItem } from "./queue";
import type { CloseOfDayReviewModel, FocusLaneModel } from "./review";
import type { ScenarioState, SessionContext, ShellState } from "./scenario";
import type { LaunchPoint } from "./shared";

export type SurfaceRegistry = {
  morningBriefing?: {
    summary: string;
    preparedItems: WorkQueueItem[];
  };
  focusLane?: FocusLaneModel;
  interruptionWorkbench?: InterruptionWorkbenchModel;
  briefingPack?: BriefingPackModel;
  closeOfDayReview?: CloseOfDayReviewModel;
};

export type WorkOsViewModel = {
  schemaVersion: "1.0";
  session: SessionContext;
  shell: ShellState;
  scenario: ScenarioState;
  queue: WorkQueueItem[];
  surfaces: SurfaceRegistry;
  activities: AgentActivityItem[];
  copilot: CopilotPanelModel;
  launchPoints: LaunchPoint[];
};
