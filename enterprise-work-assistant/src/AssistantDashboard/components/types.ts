export type TriggerType = "EMAIL" | "TEAMS_MESSAGE" | "CALENDAR_SCAN";
export type TriageTier = "SKIP" | "LIGHT" | "FULL";
export type Priority = "High" | "Medium" | "Low" | "N/A";
export type TemporalHorizon = "TODAY" | "THIS_WEEK" | "NEXT_WEEK" | "BEYOND" | "N/A";
export type CardStatus = "READY" | "LOW_CONFIDENCE" | "SUMMARY_ONLY" | "NO_OUTPUT";
export type RecipientRelationship = "Internal colleague" | "External client" | "Leadership" | "Unknown";
export type InferredTone = "formal" | "semi-formal" | "direct" | "collaborative";
export type DraftType = "EMAIL" | "TEAMS_MESSAGE";

export interface VerifiedSource {
    title: string;
    url: string;
    tier: number;
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
    item_summary: string | null;
    priority: Priority;
    temporal_horizon: TemporalHorizon;
    research_log: string | null;
    key_findings: string | null;
    verified_sources: VerifiedSource[] | null;
    confidence_score: number | null;
    card_status: CardStatus;
    draft_payload: DraftPayload | string | null;
    low_confidence_note: string | null;
    humanized_draft: string | null;
    created_on: string;
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
    onEditDraft: (cardId: string) => void;
    onDismissCard: (cardId: string) => void;
}
