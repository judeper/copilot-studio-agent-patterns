import * as React from "react";
import {
    Card,
    Badge,
    Text,
} from "@fluentui/react-components";
import {
    MailRegular,
    ChatRegular,
    CalendarRegular,
    WeatherSunnyRegular,
    SlideTextRegular,
    AlertRegular,
} from "@fluentui/react-icons";
import type { AssistantCard } from "./types";

interface CardItemProps {
    card: AssistantCard;
    onClick: (cardId: string) => void;
}

const triggerIcons: Record<string, React.ReactElement> = {
    EMAIL: <MailRegular />,
    TEAMS_MESSAGE: <ChatRegular />,
    CALENDAR_SCAN: <CalendarRegular />,
    DAILY_BRIEFING: <WeatherSunnyRegular />,
    COMMAND_RESULT: <SlideTextRegular />,
    SELF_REMINDER: <AlertRegular />,
};

const HEARTBEAT_TRIGGERS = new Set([
    "PREP_REQUIRED",
    "STALE_TASK",
    "FOLLOW_UP_NEEDED",
    "PATTERN_ALERT",
]);

const statusAppearance: Record<string, "filled" | "outline" | "tint"> = {
    LOW_CONFIDENCE: "tint",
    SUMMARY_ONLY: "outline",
    NO_OUTPUT: "outline",
    NUDGE: "tint",
};

const statusColor: Record<string, "success" | "warning" | "informative" | "subtle"> = {
    LOW_CONFIDENCE: "warning",
    SUMMARY_ONLY: "informative",
    NO_OUTPUT: "subtle",
    NUDGE: "warning",
};

const PRIORITY_CLASSES: Record<string, string> = {
    High: "card-item-priority-high",
    Medium: "card-item-priority-medium",
    Low: "card-item-priority-low",
};

export function formatRelativeTime(dateStr: string): string {
    const date = new Date(dateStr);
    if (isNaN(date.getTime())) return dateStr;
    const diffMs = Date.now() - date.getTime();
    if (diffMs < 0) return dateStr;
    const diffMinutes = Math.floor(diffMs / 60_000);
    if (diffMinutes < 1) return "just now";
    if (diffMinutes < 60) return `${diffMinutes}m ago`;
    const diffHours = Math.floor(diffMinutes / 60);
    if (diffHours < 24) return `${diffHours}h ago`;
    const diffDays = Math.floor(diffHours / 24);
    return `${diffDays}d ago`;
}

function getHoursPending(dateStr: string): number {
    const date = new Date(dateStr);
    if (isNaN(date.getTime())) return 0;
    return Math.max(0, (Date.now() - date.getTime()) / 3_600_000);
}

export const CardItem: React.FC<CardItemProps> = ({ card, onClick }) => {
    const isHeartbeat = HEARTBEAT_TRIGGERS.has(card.trigger_type);
    const hoursPending = getHoursPending(card.created_on);
    const isStale = card.card_outcome === "PENDING" && hoursPending > 24;
    const staleHours = Math.floor(hoursPending);

    const classNames = [
        "assistant-card-item",
        card.priority ? PRIORITY_CLASSES[card.priority] : undefined,
        isHeartbeat ? "card-item-heartbeat" : undefined,
        isStale ? "card-item-stale" : undefined,
    ]
        .filter(Boolean)
        .join(" ");

    const handleKeyDown = React.useCallback(
        (event: React.KeyboardEvent) => {
            if (event.key === "Enter" || event.key === " ") {
                event.preventDefault();
                onClick(card.id);
            }
        },
        [card.id, onClick],
    );

    const senderName = card.original_sender_display ?? "Unknown";
    const ariaLabel = `${senderName}: ${card.item_summary}`;

    return (
        <Card
            className={classNames}
            data-card-id={card.id}
            {...(isHeartbeat ? { "data-card-type": "heartbeat" as string } : {})}
            role="button"
            tabIndex={0}
            aria-label={ariaLabel}
            onKeyDown={handleKeyDown}
            onClick={() => onClick(card.id)}
        >
            {/* Header: icon + sender + relative time */}
            <div className="card-item-header">
                <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                    <span className="card-item-trigger-icon">
                        {isHeartbeat ? (
                            <span>✦</span>
                        ) : (
                            triggerIcons[card.trigger_type] ?? <MailRegular />
                        )}
                    </span>
                    <span className="card-item-sender">{senderName}</span>
                </div>
                <span className="card-item-age">
                    {formatRelativeTime(card.created_on)}
                </span>
            </div>

            {/* Body: 2-line clamped summary */}
            <Text className="card-item-summary" block>
                {card.item_summary}
            </Text>

            {/* Footer: badges + open hint */}
            <div className="card-item-footer">
                <div className="card-item-badges">
                    {card.card_status !== "READY" && (
                        <Badge
                            appearance={statusAppearance[card.card_status] ?? "outline"}
                            color={statusColor[card.card_status] ?? "informative"}
                            size="small"
                        >
                            {card.card_status}
                        </Badge>
                    )}
                    {card.trigger_type === "CALENDAR_SCAN" && card.temporal_horizon && (
                        <Badge appearance="outline" size="small">
                            {card.temporal_horizon}
                        </Badge>
                    )}
                    {isStale && (
                        <Badge appearance="tint" color="warning" size="small">
                            ⏰ {staleHours}h old
                        </Badge>
                    )}
                </div>
                <span className="card-item-open-hint" aria-hidden="true">→</span>
            </div>
        </Card>
    );
};
