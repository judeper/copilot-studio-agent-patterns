import type { ScenarioState } from "../models/scenario";

export const mockScenario: ScenarioState = {
  currentMoment: "morning_briefing",
  progressIndex: 0,
  moments: [
    {
      id: "morning_briefing",
      label: "Morning briefing",
      timeLabel: "08:30 AM",
      eyebrow: "Start the day with clarity",
      title: "Your day is already organized before the first click",
      body: "The operating system assembles a calm morning briefing with priorities, reply-ready drafts, meeting prep, and protected focus windows before work begins.",
      heroMetric: "3 decisions ready",
      suggestedCopilotPrompt: "Summarize my day, highlight risks, and protect my best focus window.",
      status: "active"
    },
    {
      id: "protected_focus",
      label: "Protected focus mode",
      timeLabel: "09:05 AM",
      eyebrow: "Deep work in motion",
      title: "Quiet mode protects the work that actually moves the day",
      body: "Noncritical interruptions stay out. The system preserves resume markers, keeps only the next three actions visible, and surfaces escalation only when it truly matters.",
      heroMetric: "2 interruptions allowed",
      suggestedCopilotPrompt: "Keep me in flow, capture where I stop, and only allow critical interruptions.",
      status: "upcoming"
    },
    {
      id: "triage_interruption",
      label: "Triage interruption",
      timeLabel: "09:42 AM",
      eyebrow: "Interrupt only with purpose",
      title: "A critical thread breaks through with a prepared next action",
      body: "The interruption is not a raw notification. It arrives as a summarized decision card with rationale, confidence, and an editable draft that can be approved without context switching.",
      heroMetric: "1 SLA risk surfaced",
      suggestedCopilotPrompt: "Show me only the interruption that cannot wait and prepare the fastest safe response.",
      status: "upcoming"
    },
    {
      id: "meeting_briefing",
      label: "Meeting briefing pack",
      timeLabel: "10:45 AM",
      eyebrow: "Prepared context",
      title: "Walk into the meeting with context already assembled",
      body: "The operating system lowers context-switch cost by building a meeting pack with decisions, blockers, related messages, and suggested talking points before the meeting begins.",
      heroMetric: "Briefing pack ready",
      suggestedCopilotPrompt: "Prepare me for the next meeting with open questions, decisions, and talking points.",
      status: "upcoming"
    },
    {
      id: "end_of_day_review",
      label: "End-of-day review",
      timeLabel: "05:10 PM",
      eyebrow: "Close the loop",
      title: "The day ends with decisions captured and tomorrow already shaped",
      body: "The operating system closes open loops, records what moved, defers the right items into tomorrow’s focus lane, and generates a concise narrative of progress and remaining risk.",
      heroMetric: "Tomorrow prepared",
      suggestedCopilotPrompt: "Summarize what moved, what is still open, and what belongs in tomorrow’s focus block.",
      status: "upcoming"
    }
  ]
};
