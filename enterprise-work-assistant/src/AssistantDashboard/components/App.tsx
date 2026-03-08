import * as React from "react";
import { FluentProvider, webLightTheme, webDarkTheme, Spinner } from "@fluentui/react-components";
import type { AssistantCard, AppProps } from "./types";
import { CardGallery } from "./CardGallery";
import { CardDetail } from "./CardDetail";
import { BriefingCard } from "./BriefingCard";
import { CommandBar } from "./CommandBar";
import { ConfidenceCalibration } from "./ConfidenceCalibration";
import { ErrorBoundary } from "./ErrorBoundary";
import { FilterBar } from "./FilterBar";
import { StatusBar } from "./StatusBar";

type ViewState =
    | { mode: "gallery"; selectedCardId: string | null }
    | { mode: "calibration" };

type FocusRestoreTarget =
    | { type: "card"; cardId: string }
    | { type: "selector"; selector: string }
    | { type: "element"; element: HTMLElement };

function escapeAttributeValue(value: string): string {
    return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

function focusAfterRender(callback: () => void): void {
    if (typeof window !== "undefined" && typeof window.requestAnimationFrame === "function") {
        window.requestAnimationFrame(callback);
        return;
    }
    setTimeout(callback, 0);
}

function getActiveFocusRestoreTarget(): FocusRestoreTarget | null {
    if (typeof document === "undefined") return null;
    const activeElement = document.activeElement;
    if (!(activeElement instanceof HTMLElement)) return null;
    const focusReturnId = activeElement.getAttribute("data-focus-return");
    if (focusReturnId) {
        return {
            type: "selector",
            selector: `[data-focus-return="${escapeAttributeValue(focusReturnId)}"]`,
        };
    }
    const cardId = activeElement.getAttribute("data-card-id");
    if (cardId) {
        return { type: "card", cardId };
    }
    return { type: "element", element: activeElement };
}

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
    orchestratorResponse,
    isProcessing,
    width,
    height,
    onSelectCard,
    onSendDraft,
    onCopyDraft,
    onDismissCard,
    onJumpToCard,
    onExecuteCommand,
    onSaveDraft,
}) => {
    const [viewState, setViewState] = React.useState<ViewState>({ mode: "gallery", selectedCardId: null });
    const [localFilteredCards, setLocalFilteredCards] = React.useState<AssistantCard[] | null>(null);
    const prefersDark = usePrefersDarkMode();

    const handleFilteredCards = React.useCallback((filtered: AssistantCard[]) => {
        setLocalFilteredCards(filtered);
    }, []);
    const focusRestoreTargetRef = React.useRef<FocusRestoreTarget | null>(null);
    const previousModeRef = React.useRef<ViewState["mode"]>(viewState.mode);

    const selectedCardId = viewState.mode === "gallery" ? viewState.selectedCardId : null;
    const detailOpen = selectedCardId !== null;

    // Close the detail panel on Escape
    React.useEffect(() => {
        if (!detailOpen) return;
        const handler = (e: KeyboardEvent) => {
            if (e.key === "Escape") {
                setViewState({ mode: "gallery", selectedCardId: null });
            }
        };
        document.addEventListener("keydown", handler);
        return () => document.removeEventListener("keydown", handler);
    }, [detailOpen]);

    const restoreFocus = React.useCallback(() => {
        const target = focusRestoreTargetRef.current;
        if (!target || typeof document === "undefined") return;
        focusAfterRender(() => {
            let element: HTMLElement | null = null;
            switch (target.type) {
                case "card":
                    element = document.querySelector(
                        `[data-card-id="${escapeAttributeValue(target.cardId)}"]`,
                    ) as HTMLElement | null;
                    break;
                case "selector":
                    element = document.querySelector(target.selector) as HTMLElement | null;
                    break;
                case "element":
                    element = target.element.isConnected ? target.element : null;
                    break;
            }
            element?.focus();
        });
        focusRestoreTargetRef.current = null;
    }, []);

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
        if (!selectedCardId) return null;
        return cards.find((c) => c.id === selectedCardId) ?? null;
    }, [cards, selectedCardId]);

    // If the selected card was removed from the dataset, close the panel
    React.useEffect(() => {
        if (selectedCardId && !selectedCard) {
            setViewState({ mode: "gallery", selectedCardId: null });
        }
    }, [selectedCardId, selectedCard]);

    React.useEffect(() => {
        const previousMode = previousModeRef.current;
        if (viewState.mode === "gallery" && previousMode !== "gallery") {
            restoreFocus();
        }
        previousModeRef.current = viewState.mode;
    }, [viewState.mode, restoreFocus]);

    // Restore focus when the detail panel closes within gallery mode
    const prevDetailOpenRef = React.useRef(detailOpen);
    React.useEffect(() => {
        if (prevDetailOpenRef.current && !detailOpen) {
            restoreFocus();
        }
        prevDetailOpenRef.current = detailOpen;
    }, [detailOpen, restoreFocus]);

    const handleSelectCard = React.useCallback(
        (cardId: string) => {
            const card = cards.find((c) => c.id === cardId);
            if (card) {
                focusRestoreTargetRef.current = { type: "card", cardId };
                setViewState({ mode: "gallery", selectedCardId: cardId });
                onSelectCard(cardId);
            }
        },
        [cards, onSelectCard],
    );

    // Sprint 2: Jump to card from briefing — opens detail panel
    const handleJumpToCard = React.useCallback(
        (cardId: string) => {
            const card = cards.find((c) => c.id === cardId);
            if (card) {
                focusRestoreTargetRef.current = getActiveFocusRestoreTarget();
                setViewState({ mode: "gallery", selectedCardId: cardId });
                onJumpToCard(cardId);
            }
        },
        [cards, onJumpToCard],
    );

    const handleCloseDetail = React.useCallback(() => {
        setViewState({ mode: "gallery", selectedCardId: null });
    }, []);

    const handleBack = React.useCallback(() => {
        setViewState({ mode: "gallery", selectedCardId: null });
    }, []);

    // Sprint 3: Derive current card ID for context-aware commands
    const currentCardId = selectedCardId;

    // Sprint 4: Navigate to calibration dashboard
    const handleShowCalibration = React.useCallback(() => {
        focusRestoreTargetRef.current = getActiveFocusRestoreTarget();
        setViewState({ mode: "calibration" });
    }, []);

    // F-02: Parse orchestrator response from Canvas app input property
    const parsedOrchestratorResponse = React.useMemo(() => {
        if (!orchestratorResponse) return null;
        try {
            return JSON.parse(orchestratorResponse) as import("./types").OrchestratorResponse;
        } catch {
            return null;
        }
    }, [orchestratorResponse]);

    // Count action items (non-briefing, non-dismissed)
    const actionCount = filteredCards.filter(
        (c) => c.trigger_type !== "DAILY_BRIEFING" && c.card_outcome === "PENDING",
    ).length;
    const newCount = filteredCards.filter(
        (c) => c.card_status === "READY" && c.card_outcome === "PENDING",
    ).length;

    return (
        <FluentProvider theme={prefersDark ? webDarkTheme : webLightTheme}>
            <div className="assistant-dashboard" style={{ width, height, display: "flex", flexDirection: "column" }}>
                <ErrorBoundary>
                <StatusBar
                    actionCount={actionCount}
                    newCount={newCount}
                    memoryActive={cards.length > 0}
                    onSettingsClick={handleShowCalibration}
                />
                {viewState.mode === "calibration" ? (
                    /* Sprint 4: Confidence calibration analytics */
                    <ConfidenceCalibration
                        cards={cards}
                        onBack={handleBack}
                    />
                ) : (
                    <>
                        {/* BriefingStrip placeholder — future: dedicated briefing strip component */}
                        <FilterBar
                            cards={regularCards}
                            onFilteredCards={handleFilteredCards}
                        />
                        {/* UIUX-04: Loading state when cards haven't arrived yet */}
                        {cards.length === 0 && !filterTriggerType && !filterPriority && !filterCardStatus && !filterTemporalHorizon ? (
                            <div className="dashboard-loading" style={{ display: "flex", justifyContent: "center", padding: "48px 0" }}>
                                <Spinner size="large" label="Loading cards..." />
                            </div>
                        ) : (
                            <div className="feed-detail-layout">
                                <div className={detailOpen ? "card-gallery feed-dimmed" : "card-gallery"} style={{ flex: 1, overflow: "auto" }}>
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
                                        cards={localFilteredCards ?? regularCards}
                                        onSelectCard={handleSelectCard}
                                    />
                                </div>
                                {detailOpen && selectedCard && (
                                    selectedCard.trigger_type === "DAILY_BRIEFING" ? (
                                        <div className="detail-panel">
                                            <BriefingCard
                                                card={selectedCard}
                                                onJumpToCard={handleJumpToCard}
                                                onDismissCard={onDismissCard}
                                                onBack={handleCloseDetail}
                                            />
                                        </div>
                                    ) : (
                                        <div className="detail-panel">
                                            <CardDetail
                                                card={selectedCard}
                                                onBack={handleCloseDetail}
                                                onSendDraft={onSendDraft}
                                                onCopyDraft={onCopyDraft}
                                                onDismissCard={onDismissCard}
                                                onSaveDraft={onSaveDraft}
                                            />
                                        </div>
                                    )
                                )}
                                {detailOpen && <div className="detail-backdrop" onClick={handleCloseDetail} />}
                            </div>
                        )}
                    </>
                )}
                </ErrorBoundary>
                {/* Sprint 3: Command bar — persistent bottom panel */}
                <CommandBar
                    currentCardId={currentCardId}
                    selectedCardId={currentCardId}
                    onExecuteCommand={onExecuteCommand}
                    onJumpToCard={handleJumpToCard}
                    lastResponse={parsedOrchestratorResponse}
                    isProcessing={isProcessing}
                />
            </div>
        </FluentProvider>
    );
};
