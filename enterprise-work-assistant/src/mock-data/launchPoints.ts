import type { LaunchPoint } from "../models/shared";

export const mockLaunchPoints: LaunchPoint[] = [
  {
    id: "launch-outlook",
    source: "Outlook",
    label: "Open Outlook",
    deepLink: "msteams://m365/outlook",
    available: true
  },
  {
    id: "launch-teams",
    source: "Teams",
    label: "Open Teams",
    deepLink: "msteams://teams.microsoft.com",
    available: true
  },
  {
    id: "launch-calendar",
    source: "Calendar",
    label: "Open Calendar",
    deepLink: "msteams://m365/calendar",
    available: true
  },
  {
    id: "launch-planner",
    source: "Planner",
    label: "Open Planner",
    deepLink: "https://planner.cloud.microsoft/",
    available: true
  }
];
