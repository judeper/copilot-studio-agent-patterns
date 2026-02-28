import * as React from "react";
import { FluentProvider, webLightTheme, webDarkTheme } from "@fluentui/react-components";
import type { AssistantCard, AppProps } from "./types";
import { CardGallery } from "./CardGallery";
import { CardDetail } from "./CardDetail";
import { BriefingCard } from "./BriefingCard";
import { FilterBar } from "./FilterBar";

type ViewState =
    | { mode: "gallery" }
    | { mode: "detail"; cardId: string };

function applyFilters(
    cards: AssistantCard[],
    triggerType: string,
    priority: string,
    cardStatus: string,
    temporalHorizon: string,
): AssistantCard[] {
    return cards.filter((card) => {
        if (triggerType && card.trigger_type !== triggerType) return false;
        if (priority && card.priority !== priority) return false;
        if (cardStatus && card.card_status !== cardStatus) return false;
        if (temporalHorizon && card.temporal_horizon !== temporalHorizon) return false;
        return true;
    });
}

/**
 * Sprint 2: Separate briefing cards from regular cards.
 * Briefing cards render at the top of the gallery in a distinct format.
 */
function partitionCards(cards: AssistantCard[]): {
    briefingCards: AssistantCard[];
    regularCards: AssistantCard[];
} {
    const briefingCards: AssistantCard[] = [];
    const regularCards: AssistantCard[] = [];
    for (const card of cards) {
        if (card.trigger_type === "DAILY_BRIEFING") {
            briefingCards.push(card);
        } else {
            regularCards.push(card);
        }
    }
    return { briefingCards, regularCards };
}

/**
 * Detect if the host prefers dark mode via matchMedia.
 * Falls back to light theme if matchMedia is unavailable.
 */
function usePrefersDarkMode(): boolean {
    const [dark, setDark] = React.useState(() =>
        typeof window !== "undefined" && window.matchMedia?.("(prefers-color-scheme: dark)").matches,
    );

    React.useEffect(() => {
        if (typeof window === "undefined" || !window.matchMedia) return;
        const mql = window.matchMedia("(prefers-color-scheme: dark)");
        const handler = (e: MediaQueryListEvent) => setDark(e.matches);
        mql.addEventListener("change", handler);
        return () => mql.removeEventListener("change", handler);
    }, []);

    return dark;
}

export const App: React.FC<AppProps> = ({
    cards,
    filterTriggerType,
    filterPriority,
    filterCardStatus,
    filterTemporalHorizon,
    width,
    height,
    onSelectCard,
    onSendDraft,
    onCopyDraft,
    onDismissCard,
    onJumpToCard,
}) => {
    const [viewState, setViewState] = React.useState<ViewState>({ mode: "gallery" });
    const prefersDark = usePrefersDarkMode();

    const filteredCards = React.useMemo(
        () => applyFilters(cards, filterTriggerType, filterPriority, filterCardStatus, filterTemporalHorizon),
        [cards, filterTriggerType, filterPriority, filterCardStatus, filterTemporalHorizon],
    );

    // Sprint 2: Split briefing cards from regular cards
    const { briefingCards, regularCards } = React.useMemo(
        () => partitionCards(filteredCards),
        [filteredCards],
    );

    // Derive the selected card from the live dataset to avoid stale snapshots
    const selectedCard = React.useMemo(() => {
        if (viewState.mode !== "detail") return null;
        return cards.find((c) => c.id === viewState.cardId) ?? null;
    }, [cards, viewState]);

    // If the selected card was removed from the dataset, return to gallery
    React.useEffect(() => {
        if (viewState.mode === "detail" && !selectedCard) {
            setViewState({ mode: "gallery" });
        }
    }, [viewState, selectedCard]);

    const handleSelectCard = React.useCallback(
        (cardId: string) => {
            const card = cards.find((c) => c.id === cardId);
            if (card) {
                setViewState({ mode: "detail", cardId });
                onSelectCard(cardId);
            }
        },
        [cards, onSelectCard],
    );

    // Sprint 2: Jump to card from briefing — navigates to detail view
    const handleJumpToCard = React.useCallback(
        (cardId: string) => {
            const card = cards.find((c) => c.id === cardId);
            if (card) {
                setViewState({ mode: "detail", cardId });
                onJumpToCard(cardId);
            }
        },
        [cards, onJumpToCard],
    );

    const handleBack = React.useCallback(() => {
        setViewState({ mode: "gallery" });
    }, []);

    return (
        <FluentProvider theme={prefersDark ? webDarkTheme : webLightTheme}>
            <div className="assistant-dashboard" style={{ width, height }}>
                {viewState.mode === "gallery" || !selectedCard ? (
                    <>
                        <FilterBar
                            cardCount={filteredCards.length}
                            filterTriggerType={filterTriggerType}
                            filterPriority={filterPriority}
                            filterCardStatus={filterCardStatus}
                            filterTemporalHorizon={filterTemporalHorizon}
                        />
                        {/* Sprint 2: Briefing cards render above the gallery */}
                        {briefingCards.map((bc) => (
                            <BriefingCard
                                key={bc.id}
                                card={bc}
                                onJumpToCard={handleJumpToCard}
                                onDismissCard={onDismissCard}
                            />
                        ))}
                        <CardGallery
                            cards={regularCards}
                            onSelectCard={handleSelectCard}
                        />
                    </>
                ) : selectedCard.trigger_type === "DAILY_BRIEFING" ? (
                    /* Briefing cards expand inline, no detail view needed */
                    <BriefingCard
                        card={selectedCard}
                        onJumpToCard={handleJumpToCard}
                        onDismissCard={onDismissCard}
                    />
                ) : (
                    <CardDetail
                        card={selectedCard}
                        onBack={handleBack}
                        onSendDraft={onSendDraft}
                        onCopyDraft={onCopyDraft}
                        onDismissCard={onDismissCard}
                    />
                )}
            </div>
        </FluentProvider>
    );
};
