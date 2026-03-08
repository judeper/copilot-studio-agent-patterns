import type { CopilotPanelModel } from "../models/copilot";

export const mockCopilotPanel: CopilotPanelModel = {
  currentSuggestion: "Summarize what moved today, preserve the final decisions, and carry the right items into tomorrow’s focus lane.",
  draftPrompt: "Prepare a concise close-of-day summary and identify the highest-value starting point for tomorrow.",
  starterPrompts: [
    {
      id: "starter-summarize-morning",
      label: "Summarize what changed since this morning"
    },
    {
      id: "starter-convert-thread",
      label: "Convert the current thread into a work packet"
    },
    {
      id: "starter-prepare-meeting",
      label: "Prepare me for the next meeting"
    },
    {
      id: "starter-close-day",
      label: "Generate a sharper close-of-day summary"
    }
  ],
  contextualActions: [
    {
      id: "ctx-summarize",
      label: "Summarize",
      actionType: "summarize"
    },
    {
      id: "ctx-prepare",
      label: "Prepare",
      actionType: "prepare"
    },
    {
      id: "ctx-plan",
      label: "Plan",
      actionType: "plan"
    }
  ]
};
