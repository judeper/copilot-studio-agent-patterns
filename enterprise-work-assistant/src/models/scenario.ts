/**
 * Scenario and shell state types for the Intelligent Work Layer.
 * Status: PROPOSAL — subject to validation against production payloads.
 */

export type ScenarioMomentId =
  | "morning_briefing"
  | "protected_focus"
  | "triage_interruption"
  | "meeting_briefing"
  | "end_of_day_review";

export type ScenarioMoment = {
  id: ScenarioMomentId;
  label: string;
  timeLabel: string;
  eyebrow: string;
  title: string;
  body: string;
  heroMetric: string;
  suggestedCopilotPrompt: string;
  status: "upcoming" | "active" | "completed";
};

export type ScenarioState = {
  currentMoment: ScenarioMomentId;
  moments: ScenarioMoment[];
  progressIndex: number;
};

export type ShellState = {
  quietMode: boolean;
  allowedInterruptions: "critical_only" | "high_and_critical" | "all";
  currentMoment: ScenarioMomentId;
  searchQuery?: string;
  appliedFilters?: string[];
};

export type SessionContext = {
  userId: string;
  userDisplayName: string;
  tenantId?: string;
  locale: string;
  timeZone: string;
  generatedAtUtc: string;
};
