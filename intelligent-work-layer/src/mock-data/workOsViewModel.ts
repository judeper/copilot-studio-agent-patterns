import type { WorkOsViewModel } from "../models/workOsViewModel";
import { mockActivities } from "./activities";
import { mockBriefingPack } from "./briefingPack";
import { mockCopilotPanel } from "./copilot";
import { mockFocusLane } from "./focusLane";
import { mockInterruptionWorkbench } from "./interruptionWorkbench";
import { mockLaunchPoints } from "./launchPoints";
import { mockQueue } from "./queue";
import { mockCloseOfDayReview } from "./review";
import { mockScenario } from "./scenario";

export const mockWorkOsViewModel: WorkOsViewModel = {
  schemaVersion: "1.0",
  session: {
    userId: "user@contoso.com",
    userDisplayName: "Demo User",
    tenantId: "00000000-0000-0000-0000-000000000000",
    locale: "en-US",
    timeZone: "America/New_York",
    generatedAtUtc: "2026-03-08T08:30:00Z"
  },
  shell: {
    quietMode: true,
    allowedInterruptions: "critical_only",
    currentMoment: "morning_briefing",
    searchQuery: "",
    appliedFilters: ["high-impact", "next-2-hours", "manager-and-customers"]
  },
  scenario: mockScenario,
  queue: mockQueue,
  surfaces: {
    morningBriefing: {
      summary:
        "The day is front-loaded around one customer decision, one protected focus block, and one meeting that needs prep.",
      preparedItems: mockQueue.slice(0, 3)
    },
    focusLane: mockFocusLane,
    interruptionWorkbench: mockInterruptionWorkbench,
    briefingPack: mockBriefingPack,
    closeOfDayReview: mockCloseOfDayReview
  },
  activities: mockActivities,
  copilot: mockCopilotPanel,
  launchPoints: mockLaunchPoints
};
