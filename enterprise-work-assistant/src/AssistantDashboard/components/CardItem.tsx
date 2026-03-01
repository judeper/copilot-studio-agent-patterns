import * as React from "react";
import {
    Card,
    Badge,
    Text,
    tokens,
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
import { PRIORITY_COLORS } from "./constants";

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

const statusAppearance: Record<string, "filled" | "outline" | "tint"> = {
    READY: "filled",
    LOW_CONFIDENCE: "tint",
    SUMMARY_ONLY: "outline",
    NO_OUTPUT: "outline",
    NUDGE: "tint",
};

const statusColor: Record<string, "success" | "warning" | "informative" | "subtle"> = {
    READY: "success",
    LOW_CONFIDENCE: "warning",
    SUMMARY_ONLY: "informative",
    NO_OUTPUT: "subtle",
    NUDGE: "warning",
};

export const CardItem: React.FC<CardItemProps> = ({ card, onClick }) => {
    const borderColor = card.priority ? PRIORITY_COLORS[card.priority] : undefined;

    return (
        <Card
            className="assistant-card-item"
            style={borderColor ? { borderLeft: `4px solid ${borderColor}` } : undefined}
            onClick={() => onClick(card.id)}
        >
            <div className="card-item-header">
                <span className="card-item-trigger-icon">
                    {triggerIcons[card.trigger_type] ?? <MailRegular />}
                </span>
                <div className="card-item-badges">
                    <Badge
                        appearance={statusAppearance[card.card_status] ?? "outline"}
                        color={statusColor[card.card_status] ?? "informative"}
                        size="small"
                    >
                        {card.card_status}
                    </Badge>
                    {card.temporal_horizon && (
                        <Badge appearance="outline" size="small">
                            {card.temporal_horizon}
                        </Badge>
                    )}
                </div>
            </div>
            <Text className="card-item-summary" block>
                {card.item_summary}
            </Text>
            <div className="card-item-footer">
                <Text size={200} style={{ color: tokens.colorNeutralForeground3 }}>
                    {card.created_on}
                </Text>
            </div>
        </Card>
    );
};
