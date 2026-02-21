import * as React from "react";
import {
    Card,
    Badge,
    Text,
} from "@fluentui/react-components";
import { tokens } from "@fluentui/react-components";
import {
    MailRegular,
    ChatRegular,
    CalendarRegular,
} from "@fluentui/react-icons";
import type { AssistantCard } from "./types";

interface CardItemProps {
    card: AssistantCard;
    onClick: (cardId: string) => void;
}

const priorityColors: Record<string, string> = {
    High: tokens.colorPaletteRedBorder2,
    Medium: tokens.colorPaletteMarigoldBorder2,
    Low: tokens.colorPaletteGreenBorder2,
    "N/A": tokens.colorNeutralStroke1,
};

const triggerIcons: Record<string, React.ReactElement> = {
    EMAIL: <MailRegular />,
    TEAMS_MESSAGE: <ChatRegular />,
    CALENDAR_SCAN: <CalendarRegular />,
};

const statusAppearance: Record<string, "filled" | "outline" | "tint"> = {
    READY: "filled",
    LOW_CONFIDENCE: "tint",
    SUMMARY_ONLY: "outline",
    NO_OUTPUT: "outline",
};

const statusColor: Record<string, "success" | "warning" | "informative" | "subtle"> = {
    READY: "success",
    LOW_CONFIDENCE: "warning",
    SUMMARY_ONLY: "informative",
    NO_OUTPUT: "subtle",
};

export const CardItem: React.FC<CardItemProps> = ({ card, onClick }) => {
    const borderColor = priorityColors[card.priority] || tokens.colorNeutralStroke1;

    return (
        <Card
            className="assistant-card-item"
            style={{ borderLeft: `4px solid ${borderColor}` }}
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
                    {card.temporal_horizon !== "N/A" && (
                        <Badge appearance="outline" size="small">
                            {card.temporal_horizon}
                        </Badge>
                    )}
                </div>
            </div>
            <Text className="card-item-summary" block>
                {card.item_summary ?? "No summary available"}
            </Text>
            <div className="card-item-footer">
                <Text size={200} style={{ color: tokens.colorNeutralForeground3 }}>
                    {card.created_on}
                </Text>
            </div>
        </Card>
    );
};
