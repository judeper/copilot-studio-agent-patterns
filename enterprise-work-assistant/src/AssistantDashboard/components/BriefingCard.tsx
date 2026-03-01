import * as React from "react";
import { useState } from "react";
import { Button, Text, Badge, Card } from "@fluentui/react-components";
import { ArrowLeftRegular, DismissRegular, ChevronDownRegular, ChevronRightRegular, CalendarRegular, ArrowRightRegular } from "@fluentui/react-icons";
import type { AssistantCard, DailyBriefing, BriefingActionItem, BriefingFyiItem, BriefingStaleAlert } from "./types";

interface BriefingCardProps {
    card: AssistantCard;
    onJumpToCard: (cardId: string) => void;
    onDismissCard: (cardId: string) => void;
    onBack?: () => void;
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
            <Badge appearance="filled" size="small">#{item.rank}</Badge>
            <div className="briefing-action-content">
                <Text block>{item.thread_summary}</Text>
                <Text block size={300}>
                    {item.recommended_action}
                </Text>
                <Text block size={200}>{item.urgency_reason}</Text>
                {item.related_calendar && (
                    <div className="briefing-action-calendar">
                        <CalendarRegular /> {item.related_calendar}
                    </div>
                )}
                <div className="briefing-action-links">
                    {item.card_ids.map((id) => (
                        <Button
                            key={id}
                            appearance="transparent"
                            size="small"
                            icon={<ArrowRightRegular />}
                            iconPosition="after"
                            onClick={() => onJumpToCard(id)}
                            title={`Open card ${id.substring(0, 8)}...`}
                        >
                            Open card
                        </Button>
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
            <Badge appearance="outline" size="small">{categoryLabel}</Badge>
            <Text>{item.summary}</Text>
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
                <Text>{alert.summary}</Text>
                <Badge appearance="tint" color="warning" size="small">
                    {Math.round(alert.hours_pending)}h pending
                </Badge>
            </div>
            <div className="briefing-stale-actions">
                <Text size={200}>
                    Suggested: {alert.recommended_action.toLowerCase()}
                </Text>
                <Button
                    appearance="transparent"
                    size="small"
                    icon={<ArrowRightRegular />}
                    iconPosition="after"
                    onClick={() => onJumpToCard(alert.card_id)}
                >
                    Open
                </Button>
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
    onBack,
}) => {
    const [fyiExpanded, setFyiExpanded] = useState(false);
    const briefing = parseBriefing(card);

    if (!briefing) {
        return (
            <Card className="briefing-card briefing-card-error">
                <div className="briefing-header">
                    {onBack && (
                        <Button appearance="subtle" icon={<ArrowLeftRegular />} onClick={onBack}>
                            Back
                        </Button>
                    )}
                    <Text as="h2" size={500} weight="semibold" block>Daily Briefing</Text>
                    <Text size={200}>{card.created_on}</Text>
                </div>
                <Text block>
                    Unable to parse briefing data. The briefing agent may have
                    returned an unexpected format.
                </Text>
            </Card>
        );
    }

    const hasActions = briefing.action_items && briefing.action_items.length > 0;
    const hasFyi = briefing.fyi_items && briefing.fyi_items.length > 0;
    const hasStale = briefing.stale_alerts && briefing.stale_alerts.length > 0;

    return (
        <Card className="briefing-card">
            {/* Back button */}
            {onBack && (
                <Button appearance="subtle" icon={<ArrowLeftRegular />} onClick={onBack}>
                    Back
                </Button>
            )}

            {/* Header */}
            <div className="briefing-header">
                <Text as="h2" size={500} weight="semibold" block>Daily Briefing</Text>
                <Text size={200}>{briefing.briefing_date}</Text>
                <Badge appearance="outline" size="small">
                    {briefing.total_open_items} open item
                    {briefing.total_open_items !== 1 ? "s" : ""}
                </Badge>
            </div>

            {/* Day Shape */}
            <Text block size={300} className="briefing-day-shape">{briefing.day_shape}</Text>

            {/* Stale Alerts (shown first — these need immediate attention) */}
            {hasStale && (
                <div className="briefing-section briefing-stale-section">
                    <Text as="h3" size={400} weight="semibold" block>Overdue Items</Text>
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
                    <Text as="h3" size={400} weight="semibold" block>Action Items</Text>
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
                    <Button
                        appearance="transparent"
                        icon={fyiExpanded ? <ChevronDownRegular /> : <ChevronRightRegular />}
                        onClick={() => setFyiExpanded(!fyiExpanded)}
                    >
                        For Your Information ({briefing.fyi_items!.length})
                    </Button>
                    {fyiExpanded &&
                        briefing.fyi_items!.map((item, i) => (
                            <FyiItem key={`fyi-${i}`} item={item} />
                        ))}
                </div>
            )}

            {/* No items state */}
            {!hasActions && !hasStale && (
                <div className="briefing-empty">
                    <Text block>Your inbox is clear. No pending items need attention today.</Text>
                </div>
            )}

            {/* Dismiss briefing */}
            <div className="briefing-footer">
                <Button
                    appearance="subtle"
                    icon={<DismissRegular />}
                    onClick={() => onDismissCard(card.id)}
                >
                    Dismiss briefing
                </Button>
            </div>
        </Card>
    );
};
