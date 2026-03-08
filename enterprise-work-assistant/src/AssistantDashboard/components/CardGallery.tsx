import * as React from "react";
import type { AssistantCard } from "./types";
import { CardItem } from "./CardItem";
import { HEARTBEAT_TRIGGER_TYPES, FEED_SECTIONS } from "./constants";

type FeedSection = {
    key: string;
    title: string;
    cards: AssistantCard[];
    defaultExpanded: boolean;
    accentColor?: string;
};

export function groupCards(cards: AssistantCard[]): FeedSection[] {
    const assigned = new Set<string>();

    const actionCards = cards.filter((c) => {
        if (c.triage_tier === "FULL" && (c.confidence_score ?? 0) >= 40 && c.card_outcome === "PENDING") {
            assigned.add(c.id);
            return true;
        }
        return false;
    });

    const heartbeatCards = cards.filter((c) => {
        if (!assigned.has(c.id) && (HEARTBEAT_TRIGGER_TYPES as readonly string[]).includes(c.trigger_type)) {
            assigned.add(c.id);
            return true;
        }
        return false;
    });

    const signalCards = cards.filter((c) => {
        if (!assigned.has(c.id) && c.triage_tier === "LIGHT" && c.card_outcome === "PENDING") {
            assigned.add(c.id);
            return true;
        }
        return false;
    });

    const staleCards = cards.filter((c) => {
        if (!assigned.has(c.id) && (c.hours_stale ?? 0) >= 24 && c.card_outcome === "PENDING") {
            assigned.add(c.id);
            return true;
        }
        return false;
    });

    const fyiCards = cards.filter((c) => {
        if (!assigned.has(c.id) && c.card_outcome === "PENDING" && (c.hours_stale ?? 0) < 24) {
            assigned.add(c.id);
            return true;
        }
        return false;
    });

    const sections: FeedSection[] = [
        { key: "action", ...FEED_SECTIONS.action, cards: actionCards },
        { key: "heartbeat", ...FEED_SECTIONS.heartbeat, cards: heartbeatCards },
        { key: "signals", ...FEED_SECTIONS.signals, cards: signalCards },
        { key: "fyi", ...FEED_SECTIONS.fyi, cards: fyiCards },
        { key: "stale", ...FEED_SECTIONS.stale, cards: staleCards },
    ];

    return sections.filter((s) => s.cards.length > 0);
}

interface CardGalleryProps {
    cards: AssistantCard[];
    onSelectCard: (cardId: string) => void;
}

export const CardGallery: React.FC<CardGalleryProps> = ({ cards, onSelectCard }) => {
    const sections = React.useMemo(() => groupCards(cards), [cards]);
    const [collapsed, setCollapsed] = React.useState<Record<string, boolean>>(() => {
        const initial: Record<string, boolean> = {};
        for (const [key, def] of Object.entries(FEED_SECTIONS)) {
            initial[key] = !def.defaultExpanded;
        }
        return initial;
    });

    const toggleSection = React.useCallback((key: string) => {
        setCollapsed((prev) => ({ ...prev, [key]: !prev[key] }));
    }, []);

    if (cards.length === 0) {
        const now = new Date();
        const nextBriefing = new Date(now);
        nextBriefing.setHours(nextBriefing.getHours() + 1, 0, 0, 0);

        return (
            <div className="empty-state">
                <div className="empty-state-icon">✓</div>
                <div className="empty-state-title">You&#39;re all caught up</div>
                <div className="empty-state-meta">
                    Last heartbeat: {now.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                </div>
                <div className="empty-state-meta">
                    Next briefing: {nextBriefing.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                </div>
                <div className="empty-state-cta">⚡ Ask EWA about anything</div>
            </div>
        );
    }

    return (
        <div className="card-gallery">
            {sections.map((section) => (
                <div key={section.key} className="feed-section">
                    <button
                        className="feed-section-header"
                        onClick={() => toggleSection(section.key)}
                        style={section.accentColor ? { borderLeftColor: section.accentColor } : undefined}
                        aria-expanded={!collapsed[section.key]}
                    >
                        <span className="feed-section-title">{section.title}</span>
                        <span className="feed-section-count">{section.cards.length}</span>
                        <span className="feed-section-chevron">
                            {collapsed[section.key] ? "▸" : "▾"}
                        </span>
                    </button>
                    {!collapsed[section.key] && (
                        <div className="feed-section-cards">
                            {section.cards.map((card) => (
                                <CardItem key={card.id} card={card} onClick={onSelectCard} />
                            ))}
                        </div>
                    )}
                </div>
            ))}
        </div>
    );
};
