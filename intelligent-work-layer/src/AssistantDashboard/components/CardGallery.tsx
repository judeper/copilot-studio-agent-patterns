import * as React from "react";
import type { AssistantCard } from "./types";
import { CardItem } from "./CardItem";
import { HEARTBEAT_TRIGGER_TYPES, FEED_SECTIONS } from "./constants";
import { compositeSort } from "../hooks/useCardData";
import { useConversationClusters } from "../hooks/useConversationClusters";
import { Button, Checkbox } from "@fluentui/react-components";
import { BatchActionBar } from "./BatchActionBar";

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
    onBatchDismiss?: (cardIds: string[]) => void;
    onBatchSnooze?: (cardIds: string[], snoozeUntil: string) => void;
}

export const CardGallery: React.FC<CardGalleryProps> = ({ cards, onSelectCard, onBatchDismiss, onBatchSnooze }) => {
    const [visibleCount, setVisibleCount] = React.useState(5);
    // Phase 2A: Batch selection state
    const [selectedIds, setSelectedIds] = React.useState<Set<string>>(() => new Set());
    const selectionActive = selectedIds.size > 0;

    const toggleSelect = React.useCallback((cardId: string) => {
        setSelectedIds((prev) => {
            const next = new Set(prev);
            if (next.has(cardId)) {
                next.delete(cardId);
            } else {
                next.add(cardId);
            }
            return next;
        });
    }, []);

    const toggleSectionSelect = React.useCallback((sectionCards: AssistantCard[]) => {
        setSelectedIds((prev) => {
            const next = new Set(prev);
            const allSelected = sectionCards.every((c) => prev.has(c.id));
            if (allSelected) {
                for (const c of sectionCards) next.delete(c.id);
            } else {
                for (const c of sectionCards) next.add(c.id);
            }
            return next;
        });
    }, []);

    const clearSelection = React.useCallback(() => setSelectedIds(new Set()), []);

    const handleBatchDismiss = React.useCallback(() => {
        if (onBatchDismiss) {
            onBatchDismiss(Array.from(selectedIds));
            clearSelection();
        }
    }, [onBatchDismiss, selectedIds, clearSelection]);

    const handleBatchSnooze = React.useCallback(() => {
        if (onBatchSnooze) {
            const tomorrow = new Date();
            tomorrow.setDate(tomorrow.getDate() + 1);
            tomorrow.setHours(9, 0, 0, 0);
            onBatchSnooze(Array.from(selectedIds), tomorrow.toISOString());
            clearSelection();
        }
    }, [onBatchSnooze, selectedIds, clearSelection]);

    // Phase 1A: Cluster cards by conversation before sorting/sectioning
    const { clusteredCards, clusterMap } = useConversationClusters(cards);
    const sortedCards = React.useMemo(() => compositeSort(clusteredCards), [clusteredCards]);
    const visibleCards = React.useMemo(() => sortedCards.slice(0, visibleCount), [sortedCards, visibleCount]);
    const hasMore = visibleCount < sortedCards.length;
    const sections = React.useMemo(() => groupCards(visibleCards), [visibleCards]);
    const [collapsed, setCollapsed] = React.useState<Record<string, boolean>>(() => {
        const initial: Record<string, boolean> = {};
        for (const [key, def] of Object.entries(FEED_SECTIONS)) {
            initial[key] = !def.defaultExpanded;
        }
        return initial;
    });

    // B3: Track previous card outcomes to detect completion transitions
    const prevOutcomes = React.useRef<Record<string, string>>({});
    const [completingIds, setCompletingIds] = React.useState<Set<string>>(() => new Set());

    React.useEffect(() => {
        const newCompleting = new Set<string>();
        for (const card of cards) {
            const prev = prevOutcomes.current[card.id];
            if (
                prev === "PENDING" &&
                (card.card_outcome === "SENT_AS_IS" || card.card_outcome === "SENT_EDITED" || card.card_outcome === "DISMISSED")
            ) {
                newCompleting.add(card.id);
            }
        }
        // Update tracked outcomes
        const next: Record<string, string> = {};
        for (const card of cards) {
            next[card.id] = card.card_outcome;
        }
        prevOutcomes.current = next;

        if (newCompleting.size > 0) {
            setCompletingIds(newCompleting);
            const timer = window.setTimeout(() => setCompletingIds(new Set()), 350);
            return () => window.clearTimeout(timer);
        }
    }, [cards]);

    const toggleSection = React.useCallback((key: string) => {
        setCollapsed((prev) => ({ ...prev, [key]: !prev[key] }));
    }, []);

    // Reset visible count when cards change
    React.useEffect(() => {
        setVisibleCount(5);
    }, [cards]);

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
                <div className="empty-state-cta">⚡ Ask IWL about anything</div>
            </div>
        );
    }

    return (
        <div className="card-gallery">
            {/* Phase 2A: Batch action bar */}
            <BatchActionBar
                selectedCount={selectedIds.size}
                onDismissAll={handleBatchDismiss}
                onSnoozeAll={handleBatchSnooze}
                onClearSelection={clearSelection}
            />
            {sections.map((section) => (
                <div key={section.key} className="feed-section">
                    <button
                        className="feed-section-header"
                        onClick={() => toggleSection(section.key)}
                        style={section.accentColor ? { borderLeftColor: section.accentColor } : undefined}
                        aria-expanded={!collapsed[section.key]}
                    >
                        {/* Phase 2A: Section-level select all */}
                        {selectionActive && (
                            <Checkbox
                                checked={section.cards.every((c) => selectedIds.has(c.id))}
                                onChange={(e) => {
                                    e.stopPropagation();
                                    toggleSectionSelect(section.cards);
                                }}
                                onClick={(e) => e.stopPropagation()}
                                aria-label={`Select all in ${section.title}`}
                            />
                        )}
                        <span className="feed-section-title">{section.title}</span>
                        <span className="feed-section-count">{section.cards.length}</span>
                        <span className="feed-section-chevron">
                            {collapsed[section.key] ? "▸" : "▾"}
                        </span>
                    </button>
                    {!collapsed[section.key] && (
                        <div className="feed-section-cards">
                            {section.cards.map((card) => {
                                const clusterKey = card.conversation_cluster_id ?? card.id;
                                const cluster = clusterMap.get(clusterKey);
                                const relatedCount = cluster ? cluster.related.length : 0;
                                return (
                                    <div
                                        key={card.id}
                                        className={completingIds.has(card.id) ? "card-item-completing" : undefined}
                                        style={{ display: "flex", alignItems: "flex-start", gap: "4px" }}
                                    >
                                        <Checkbox
                                            checked={selectedIds.has(card.id)}
                                            onChange={() => toggleSelect(card.id)}
                                            aria-label={`Select ${card.item_summary}`}
                                            style={{ marginTop: "12px", opacity: selectionActive ? 1 : 0, transition: "opacity 150ms" }}
                                            onMouseEnter={(e) => { if (!selectionActive) (e.currentTarget as HTMLElement).style.opacity = "0.6"; }}
                                            onMouseLeave={(e) => { if (!selectionActive) (e.currentTarget as HTMLElement).style.opacity = "0"; }}
                                        />
                                        <div style={{ flex: 1 }}>
                                            <CardItem card={card} onClick={onSelectCard} relatedCount={relatedCount} />
                                        </div>
                                    </div>
                                );
                            })}
                        </div>
                    )}
                </div>
            ))}
            {hasMore && (
                <div className="show-more-container">
                    <Button
                        appearance="subtle"
                        className="show-more-button"
                        onClick={() => setVisibleCount((prev) => prev + 5)}
                    >
                        Show next 5 ({sortedCards.length - visibleCount} remaining)
                    </Button>
                </div>
            )}
        </div>
    );
};
