import * as React from "react";
import { useState } from "react";
import type { AssistantCard, DailyBriefing, BriefingActionItem, BriefingFyiItem, BriefingStaleAlert } from "./types";

interface BriefingCardProps {
    card: AssistantCard;
    onJumpToCard: (cardId: string) => void;
    onDismissCard: (cardId: string) => void;
}

/**
 * Parse the briefing JSON from the card's full JSON output.
 * The Daily Briefing Agent stores its output in cr_fulljson just like other agents,
 * but the briefing_type field distinguishes it.
 */
function parseBriefing(card: AssistantCard): DailyBriefing | null {
    try {
        // The briefing is already parsed as part of the card's JSON in useCardData,
        // but the structured briefing data is in the draft_payload or the full JSON.
        // For briefing cards, the agent output IS the briefing — it's stored in cr_fulljson.
        // useCardData parses cr_fulljson into the card fields. The briefing-specific
        // fields (action_items, fyi_items, etc.) need to be extracted from the raw JSON.
        //
        // The card.draft_payload holds the briefing JSON string for DAILY_BRIEFING cards.
        if (typeof card.draft_payload === "string" && card.draft_payload) {
            return JSON.parse(card.draft_payload) as DailyBriefing;
        }
        if (typeof card.draft_payload === "object" && card.draft_payload !== null) {
            return card.draft_payload as unknown as DailyBriefing;
        }
        return null;
    } catch {
        return null;
    }
}

function ActionItem({
    item,
    onJumpToCard,
}: {
    item: BriefingActionItem;
    onJumpToCard: (cardId: string) => void;
}) {
    return (
        <div className="briefing-action-item">
            <div className="briefing-action-rank">#{item.rank}</div>
            <div className="briefing-action-content">
                <div className="briefing-action-summary">{item.thread_summary}</div>
                <div className="briefing-action-recommendation">
                    {item.recommended_action}
                </div>
                <div className="briefing-action-reason">{item.urgency_reason}</div>
                {item.related_calendar && (
                    <div className="briefing-action-calendar">
                        📅 {item.related_calendar}
                    </div>
                )}
                <div className="briefing-action-links">
                    {item.card_ids.map((id) => (
                        <button
                            key={id}
                            className="briefing-jump-link"
                            onClick={() => onJumpToCard(id)}
                            title={`Open card ${id.substring(0, 8)}...`}
                        >
                            Open card →
                        </button>
                    ))}
                </div>
            </div>
        </div>
    );
}

function FyiItem({ item }: { item: BriefingFyiItem }) {
    const categoryLabel =
        item.category === "MEETING_PREP"
            ? "Meeting prep"
            : item.category === "INFO_UPDATE"
              ? "Info"
              : "Low priority";

    return (
        <div className="briefing-fyi-item">
            <span className="briefing-fyi-category">{categoryLabel}</span>
            <span className="briefing-fyi-summary">{item.summary}</span>
        </div>
    );
}

function StaleAlert({
    alert,
    onJumpToCard,
}: {
    alert: BriefingStaleAlert;
    onJumpToCard: (cardId: string) => void;
}) {
    const severityClass =
        alert.hours_pending > 48
            ? "briefing-stale-critical"
            : "briefing-stale-warning";

    return (
        <div className={`briefing-stale-item ${severityClass}`}>
            <div className="briefing-stale-summary">
                {alert.summary}
                <span className="briefing-stale-hours">
                    {Math.round(alert.hours_pending)}h pending
                </span>
            </div>
            <div className="briefing-stale-actions">
                <span className="briefing-stale-recommendation">
                    Suggested: {alert.recommended_action.toLowerCase()}
                </span>
                <button
                    className="briefing-jump-link"
                    onClick={() => onJumpToCard(alert.card_id)}
                >
                    Open →
                </button>
            </div>
        </div>
    );
}

// TODO: Schedule configuration deferred to post-v2.1 milestone
// The Daily Briefing flow (Flow 6) uses a fixed Power Automate recurrence trigger.
// User-configurable scheduling requires a dedicated Dataverse table and UI.

export const BriefingCard: React.FC<BriefingCardProps> = ({
    card,
    onJumpToCard,
    onDismissCard,
}) => {
    const [fyiExpanded, setFyiExpanded] = useState(false);
    const briefing = parseBriefing(card);

    if (!briefing) {
        return (
            <div className="briefing-card briefing-card-error">
                <div className="briefing-header">
                    <h2>Daily Briefing</h2>
                    <span className="briefing-date">{card.created_on}</span>
                </div>
                <p className="briefing-error-message">
                    Unable to parse briefing data. The briefing agent may have
                    returned an unexpected format.
                </p>
            </div>
        );
    }

    const hasActions = briefing.action_items && briefing.action_items.length > 0;
    const hasFyi = briefing.fyi_items && briefing.fyi_items.length > 0;
    const hasStale = briefing.stale_alerts && briefing.stale_alerts.length > 0;

    return (
        <div className="briefing-card">
            {/* Header */}
            <div className="briefing-header">
                <h2>Daily Briefing</h2>
                <span className="briefing-date">{briefing.briefing_date}</span>
                <span className="briefing-count">
                    {briefing.total_open_items} open item
                    {briefing.total_open_items !== 1 ? "s" : ""}
                </span>
            </div>

            {/* Day Shape */}
            <div className="briefing-day-shape">{briefing.day_shape}</div>

            {/* Stale Alerts (shown first — these need immediate attention) */}
            {hasStale && (
                <div className="briefing-section briefing-stale-section">
                    <h3>Overdue Items</h3>
                    {briefing.stale_alerts!.map((alert) => (
                        <StaleAlert
                            key={alert.card_id}
                            alert={alert}
                            onJumpToCard={onJumpToCard}
                        />
                    ))}
                </div>
            )}

            {/* Action Items */}
            {hasActions && (
                <div className="briefing-section briefing-actions-section">
                    <h3>Action Items</h3>
                    {briefing.action_items.map((item) => (
                        <ActionItem
                            key={`action-${item.rank}`}
                            item={item}
                            onJumpToCard={onJumpToCard}
                        />
                    ))}
                </div>
            )}

            {/* FYI (collapsible) */}
            {hasFyi && (
                <div className="briefing-section briefing-fyi-section">
                    <button
                        className="briefing-fyi-toggle"
                        onClick={() => setFyiExpanded(!fyiExpanded)}
                    >
                        <h3>
                            For Your Information ({briefing.fyi_items!.length})
                            <span className="briefing-fyi-chevron">
                                {fyiExpanded ? "▾" : "▸"}
                            </span>
                        </h3>
                    </button>
                    {fyiExpanded &&
                        briefing.fyi_items!.map((item, i) => (
                            <FyiItem key={`fyi-${i}`} item={item} />
                        ))}
                </div>
            )}

            {/* No items state */}
            {!hasActions && !hasStale && (
                <div className="briefing-empty">
                    Your inbox is clear. No pending items need attention today.
                </div>
            )}

            {/* Dismiss briefing */}
            <div className="briefing-footer">
                <button
                    className="briefing-dismiss-button"
                    onClick={() => onDismissCard(card.id)}
                >
                    Dismiss briefing
                </button>
            </div>
        </div>
    );
};
