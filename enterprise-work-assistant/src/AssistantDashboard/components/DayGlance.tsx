import * as React from "react";
import type { AssistantCard } from "./types";

interface DayGlanceProps {
    cards: AssistantCard[];
}

export const DayGlance: React.FC<DayGlanceProps> = ({ cards }) => {
    const calendarCards = cards.filter(
        (c: AssistantCard) => c.trigger_type === "CALENDAR_SCAN" || c.trigger_type === "DAILY_BRIEFING"
    );

    if (calendarCards.length === 0) return null;

    return (
        <div className="day-glance">
            <div className="day-glance-header">Today at a glance</div>
            <div className="day-glance-items">
                {calendarCards.slice(0, 4).map((card: AssistantCard) => (
                    <div key={card.id} className="day-glance-item">
                        <div className="day-glance-item-title">{card.item_summary}</div>
                        <div className="day-glance-item-type">
                            {card.trigger_type === "CALENDAR_SCAN" ? "Meeting" : "Briefing"}
                        </div>
                    </div>
                ))}
            </div>
        </div>
    );
};
