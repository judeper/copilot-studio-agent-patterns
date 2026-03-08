import type { FocusLaneModel } from "../models/review";

export const mockFocusLane: FocusLaneModel = {
  id: "focus-blueprint-session",
  title: "Finalize Enterprise Work Assistant product blueprint",
  summary: "Open decisions, repository context, and the next three steps are already staged so you can resume without reconstructing the work.",
  focusWindow: "09:00 AM - 10:30 AM",
  interruptionsHeldCount: 3,
  unresolvedDependenciesCount: 1,
  resumeMarker: {
    title: "Resume marker",
    detail: "You last stopped after defining the five product pillars and still need to write the trust model section.",
    capturedAtUtc: "2026-03-08T09:12:00Z"
  },
  nextSmallestStep: "Write the one-paragraph product definition before expanding the blueprint sections.",
  flowMemory: "When you return later, the operating system will reopen this exact work packet with the same next-step state.",
  primaryAction: {
    id: "act-resume-focus",
    label: "Resume work",
    actionType: "resume_focus",
    requiresApproval: false,
    reversible: true
  },
  secondaryActions: [
    {
      id: "act-capture-resume-marker",
      label: "Capture resume marker",
      actionType: "capture_resume_marker"
    },
    {
      id: "act-pause-focus",
      label: "Pause focus",
      actionType: "pause"
    }
  ]
};
