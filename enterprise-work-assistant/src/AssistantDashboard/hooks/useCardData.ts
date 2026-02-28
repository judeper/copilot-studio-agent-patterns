import * as React from "react";
import type { AssistantCard, TriggerType, TriageTier, Priority, CardStatus, TemporalHorizon, CardOutcome } from "../components/types";

interface DataSet {
    sortedRecordIds: string[];
    records: Record<string, DataSetRecord>;
}

interface DataSetRecord {
    getRecordId(): string;
    getValue(columnName: string): string | number | null;
    getFormattedValue(columnName: string): string;
}

/**
 * Maps Dataverse Choice column formatted values to CardOutcome type.
 * Dataverse returns the label text (e.g., "PENDING") from getFormattedValue().
 */
function parseCardOutcome(formatted: string | undefined): CardOutcome {
    switch (formatted) {
        case "SENT_AS_IS": return "SENT_AS_IS";
        case "SENT_EDITED": return "SENT_EDITED";
        case "DISMISSED": return "DISMISSED";
        case "EXPIRED": return "EXPIRED";
        default: return "PENDING";
    }
}

/**
 * Converts the PCF dataset API into a typed AssistantCard array.
 * Reads discrete columns for display and parses cr_fulljson for the full object.
 * Skips malformed rows rather than crashing the gallery.
 *
 * @param dataset - PCF DataSet object (mutated in place by the platform)
 * @param version - Counter incremented on each updateView call; forces useMemo
 *                  to recompute since the dataset reference itself never changes.
 */
export function useCardData(dataset: DataSet | undefined, version: number): AssistantCard[] {
    return React.useMemo(() => {
        if (!dataset || !dataset.sortedRecordIds || dataset.sortedRecordIds.length === 0) {
            return [];
        }

        const cards: AssistantCard[] = [];

        for (const id of dataset.sortedRecordIds) {
            const record = dataset.records[id];
            if (!record) continue;

            try {
                const fullJsonStr = record.getValue("cr_fulljson") as string | null;
                if (!fullJsonStr) continue;

                const parsed = JSON.parse(fullJsonStr);

                const card: AssistantCard = {
                    id: record.getRecordId(),
                    trigger_type: (parsed.trigger_type as TriggerType) ?? "EMAIL",
                    triage_tier: (parsed.triage_tier as TriageTier) ?? "LIGHT",
                    item_summary: parsed.item_summary ?? "",
                    priority: parsed.priority && parsed.priority !== "N/A"
                        ? (parsed.priority as Priority)
                        : null,
                    temporal_horizon: parsed.temporal_horizon && parsed.temporal_horizon !== "N/A"
                        ? (parsed.temporal_horizon as TemporalHorizon)
                        : null,
                    research_log: parsed.research_log ?? null,
                    key_findings: parsed.key_findings ?? null,
                    verified_sources: Array.isArray(parsed.verified_sources) ? parsed.verified_sources : null,
                    confidence_score: typeof parsed.confidence_score === "number" ? parsed.confidence_score : null,
                    card_status: (parsed.card_status as CardStatus) ?? "SUMMARY_ONLY",
                    draft_payload: parsed.draft_payload ?? null,
                    low_confidence_note: parsed.low_confidence_note ?? null,
                    humanized_draft: record.getValue("cr_humanizeddraft") as string | null,
                    created_on: record.getFormattedValue("createdon") ?? "",
                    // Sprint 1A — read from discrete Dataverse columns
                    card_outcome: parseCardOutcome(record.getFormattedValue("cr_cardoutcome")),
                    original_sender_email: record.getValue("cr_originalsenderemail") as string | null,
                    original_sender_display: record.getValue("cr_originalsenderdisplay") as string | null,
                    original_subject: record.getValue("cr_originalsubject") as string | null,
                    // Sprint 1B — clustering & source identity
                    conversation_cluster_id: record.getValue("cr_conversationclusterid") as string | null,
                    source_signal_id: record.getValue("cr_sourcesignalid") as string | null,
                };

                cards.push(card);
            } catch {
                // Skip malformed rows — don't crash the gallery for one bad record
                console.warn(`useCardData: failed to parse record ${id}, skipping.`);
                continue;
            }
        }

        return cards;
    }, [version]);
}
