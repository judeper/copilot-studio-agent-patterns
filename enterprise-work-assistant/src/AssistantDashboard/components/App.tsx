import * as React from "react";
import { FluentProvider, webLightTheme } from "@fluentui/react-components";
import type { AssistantCard, AppProps } from "./types";
import { CardGallery } from "./CardGallery";
import { CardDetail } from "./CardDetail";
import { FilterBar } from "./FilterBar";

type ViewState =
    | { mode: "gallery" }
    | { mode: "detail"; card: AssistantCard };

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

export const App: React.FC<AppProps> = ({
    cards,
    filterTriggerType,
    filterPriority,
    filterCardStatus,
    filterTemporalHorizon,
    width,
    height,
    onSelectCard,
    onEditDraft,
    onDismissCard,
}) => {
    const [viewState, setViewState] = React.useState<ViewState>({ mode: "gallery" });

    const filteredCards = React.useMemo(
        () => applyFilters(cards, filterTriggerType, filterPriority, filterCardStatus, filterTemporalHorizon),
        [cards, filterTriggerType, filterPriority, filterCardStatus, filterTemporalHorizon],
    );

    const handleSelectCard = React.useCallback(
        (cardId: string) => {
            const card = cards.find((c) => c.id === cardId);
            if (card) {
                setViewState({ mode: "detail", card });
                onSelectCard(cardId);
            }
        },
        [cards, onSelectCard],
    );

    const handleBack = React.useCallback(() => {
        setViewState({ mode: "gallery" });
    }, []);

    return (
        <FluentProvider theme={webLightTheme}>
            <div className="assistant-dashboard" style={{ width, height }}>
                {viewState.mode === "gallery" ? (
                    <>
                        <FilterBar
                            cardCount={filteredCards.length}
                            filterTriggerType={filterTriggerType}
                            filterPriority={filterPriority}
                            filterCardStatus={filterCardStatus}
                            filterTemporalHorizon={filterTemporalHorizon}
                        />
                        <CardGallery
                            cards={filteredCards}
                            onSelectCard={handleSelectCard}
                        />
                    </>
                ) : (
                    <CardDetail
                        card={viewState.card}
                        onBack={handleBack}
                        onEditDraft={onEditDraft}
                        onDismissCard={onDismissCard}
                    />
                )}
            </div>
        </FluentProvider>
    );
};
