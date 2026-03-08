/**
 * Copilot panel types for the Intelligent Work Layer.
 * Status: PROPOSAL — subject to validation against production payloads.
 */

export type CopilotStarterPrompt = {
  id: string;
  label: string;
};

export type CopilotActionHint = {
  id: string;
  label: string;
  actionType: "summarize" | "prepare" | "convert" | "rewrite" | "plan";
};

export type CopilotPanelModel = {
  currentSuggestion: string;
  draftPrompt?: string;
  starterPrompts: CopilotStarterPrompt[];
  contextualActions?: CopilotActionHint[];
};
