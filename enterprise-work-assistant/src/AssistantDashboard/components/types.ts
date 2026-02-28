export type TriggerType = "EMAIL" | "TEAMS_MESSAGE" | "CALENDAR_SCAN";
export type TriageTier = "SKIP" | "LIGHT" | "FULL";
export type Priority = "High" | "Medium" | "Low";
export type TemporalHorizon = "TODAY" | "THIS_WEEK" | "NEXT_WEEK" | "BEYOND";
export type CardStatus = "READY" | "LOW_CONFIDENCE" | "SUMMARY_ONLY" | "NO_OUTPUT";
export type CardOutcome = "PENDING" | "SENT_AS_IS" | "SENT_EDITED" | "DISMISSED" | "EXPIRED";
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
    width: number;
    height: number;
    onSelectCard: (cardId: string) => void;
    onSendDraft: (cardId: string, finalText: string) => void;
    onCopyDraft: (cardId: string) => void;
    onDismissCard: (cardId: string) => void;
}
