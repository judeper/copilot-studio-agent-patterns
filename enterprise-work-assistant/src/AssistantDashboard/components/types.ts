export type TriggerType = "EMAIL" | "TEAMS_MESSAGE" | "CALENDAR_SCAN" | "DAILY_BRIEFING" | "SELF_REMINDER" | "COMMAND_RESULT";

// Sprint 3 — Command Bar / Orchestrator types

export interface CommandCardLink {
    card_id: string;
    label: string;
}

export interface CommandSideEffect {
    action: "UPDATE_CARD" | "CREATE_CARD" | "REFINE_DRAFT";
    description: string;
}

export interface OrchestratorResponse {
    response_text: string;
    card_links: CommandCardLink[];
    side_effects: CommandSideEffect[];
}
export type TriageTier = "SKIP" | "LIGHT" | "FULL";
export type Priority = "High" | "Medium" | "Low";
export type TemporalHorizon = "TODAY" | "THIS_WEEK" | "NEXT_WEEK" | "BEYOND";
export type CardStatus = "READY" | "LOW_CONFIDENCE" | "SUMMARY_ONLY" | "NO_OUTPUT" | "NUDGE";
export type CardOutcome = "PENDING" | "SENT_AS_IS" | "SENT_EDITED" | "DISMISSED" | "EXPIRED";

// Sprint 2 — Daily Briefing types

export interface BriefingActionItem {
    rank: number;
    card_ids: string[];
    thread_summary: string;
    recommended_action: string;
    urgency_reason: string;
    related_calendar: string | null;
}

export interface BriefingFyiItem {
    card_ids: string[];
    summary: string;
    category: "MEETING_PREP" | "INFO_UPDATE" | "LOW_PRIORITY";
}

export interface BriefingStaleAlert {
    card_id: string;
    summary: string;
    hours_pending: number;
    recommended_action: "RESPOND" | "DELEGATE" | "DISMISS";
}

export interface DailyBriefing {
    briefing_type: "DAILY";
    briefing_date: string;
    total_open_items: number;
    day_shape: string;
    action_items: BriefingActionItem[];
    fyi_items?: BriefingFyiItem[];
    stale_alerts?: BriefingStaleAlert[];
}
export type RecipientRelationship = "Internal colleague" | "External client" | "Leadership" | "Unknown";
export type InferredTone = "formal" | "semi-formal" | "direct" | "collaborative";
export type DraftType = "EMAIL" | "TEAMS_MESSAGE";

export interface VerifiedSource {
    title: string;
    url: string;
    tier: 1 | 2 | 3 | 4 | 5;
}

export interface DraftPayload {
    draft_type: DraftType;
    raw_draft: string;
    research_summary: string;
    recipient_relationship: RecipientRelationship;
    inferred_tone: InferredTone;
    confidence_score: number;
    user_context: string;
}

export interface AssistantCard {
    id: string;
    trigger_type: TriggerType;
    triage_tier: TriageTier;
    item_summary: string;
    priority: Priority | null;
    temporal_horizon: TemporalHorizon | null;
    research_log: string | null;
    key_findings: string | null;
    verified_sources: VerifiedSource[] | null;
    confidence_score: number | null;
    card_status: CardStatus;
    draft_payload: DraftPayload | string | null;
    low_confidence_note: string | null;
    humanized_draft: string | null;
    created_on: string;
    // Sprint 1A — Outcome tracking & send context
    card_outcome: CardOutcome;
    original_sender_email: string | null;
    original_sender_display: string | null;
    original_subject: string | null;
    // Sprint 1B — Clustering & source identity
    conversation_cluster_id: string | null;
    source_signal_id: string | null;
}

export interface AppProps {
    cards: AssistantCard[];
    filterTriggerType: string;
    filterPriority: string;
    filterCardStatus: string;
    filterTemporalHorizon: string;
    orchestratorResponse: string | null; // F-02: JSON response from command execution flow
    isProcessing: boolean; // F-02: Whether a command is currently being processed
    width: number;
    height: number;
    onSelectCard: (cardId: string) => void;
    onSendDraft: (cardId: string, finalText: string, editDistanceRatio: number) => void;
    onCopyDraft: (cardId: string) => void;
    onDismissCard: (cardId: string) => void;
    onJumpToCard: (cardId: string) => void; // Sprint 2: navigate to a specific card from briefing
    onExecuteCommand: (command: string, currentCardId: string | null) => void; // Sprint 3: command bar
}
