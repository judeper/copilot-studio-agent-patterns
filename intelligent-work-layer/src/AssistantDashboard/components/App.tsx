import * as React from "react";
import { FluentProvider, webLightTheme, webDarkTheme, Spinner } from "@fluentui/react-components";
import type { AssistantCard, AppProps } from "./types";
import { CardGallery } from "./CardGallery";
import { CardDetail } from "./CardDetail";
import { useConversationClusters } from "../hooks/useConversationClusters";
import { BriefingCard } from "./BriefingCard";
import { CommandBar } from "./CommandBar";
import { ConfidenceCalibration } from "./ConfidenceCalibration";
import { DayGlance } from "./DayGlance";
import { ErrorBoundary } from "./ErrorBoundary";
import { FilterBar } from "./FilterBar";
import { StatusBar } from "./StatusBar";
import { KeyboardHelpOverlay } from "./KeyboardHelpOverlay";
import { OnboardingWizard } from "./OnboardingWizard";
import { UndoToast, useUndoAction } from "./UndoToast";
import { useKeyboardNavigation } from "../hooks/useKeyboardNavigation";
import { focusAfterRender } from "../utils/focusUtils";

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
    onSnoozeCard,
    onBatchDismiss,
    onBatchSnooze,
    onUpdateSchedule,
}) => {
    const [viewState, setViewState] = React.useState<ViewState>({ mode: "gallery", selectedCardId: null });
    const [localFilteredCards, setLocalFilteredCards] = React.useState<AssistantCard[] | null>(null);
    const [quietMode, setQuietMode] = React.useState(false);
    const [quietHeldCount, setQuietHeldCount] = React.useState(0);
    const [showKeyboardHelp, setShowKeyboardHelp] = React.useState(false);
    const [showOnboarding, setShowOnboarding] = React.useState(false);
    const prefersDark = usePrefersDarkMode();
    const undoAction = useUndoAction();

    const handleFilteredCards = React.useCallback((filtered: AssistantCard[]) => {
        setLocalFilteredCards(filtered);
    }, []);

    const handleQuietModeChange = React.useCallback((quiet: boolean, heldCount: number) => {
        setQuietMode(quiet);
        setQuietHeldCount(heldCount);
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

    // Phase 1A: Conversation cluster data for threading
    const { clusterMap } = useConversationClusters(regularCards);

    // Derive the selected card from the live dataset to avoid stale snapshots
    const selectedCard = React.useMemo(() => {
        if (!selectedCardId) return null;
        return cards.find((c) => c.id === selectedCardId) ?? null;
    }, [cards, selectedCardId]);

    // Phase 1A: Get related cards for the selected card's cluster
    const relatedCards = React.useMemo(() => {
        if (!selectedCard) return [];
        const clusterKey = selectedCard.conversation_cluster_id ?? selectedCard.id;
        const cluster = clusterMap.get(clusterKey);
        return cluster ? cluster.related : [];
    }, [selectedCard, clusterMap]);

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

    // Phase 5A: Keyboard navigation
    const cardIds = React.useMemo(
        () => (localFilteredCards ?? regularCards).map((c) => c.id),
        [localFilteredCards, regularCards],
    );

    const handleShowKeyboardHelp = React.useCallback(() => setShowKeyboardHelp(true), []);

    useKeyboardNavigation({
        cardIds,
        selectedCardId,
        onSelectCard: handleSelectCard,
        onDismissCard: onDismissCard,
        onSnoozeCard: onSnoozeCard,
        onShowHelp: handleShowKeyboardHelp,
        enabled: viewState.mode === "gallery" && !showKeyboardHelp && !showOnboarding,
    });

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

    // Phase 2D: Detect if any card was triaged under Focus Shield
    const focusShieldActive = React.useMemo(
        () => cards.some((c) => c.focus_shield_active === true),
        [cards],
    );

    // Derive next meeting time from CALENDAR_SCAN cards
    const nextMeetingTime = React.useMemo(() => {
        const now = Date.now();
        const calendarCards = filteredCards
            .filter((c) => c.trigger_type === "CALENDAR_SCAN" && c.card_outcome === "PENDING")
            .map((c) => new Date(c.created_on))
            .filter((d) => !isNaN(d.getTime()) && d.getTime() > now)
            .sort((a, b) => a.getTime() - b.getTime());
        if (calendarCards.length === 0) return null;
        return calendarCards[0].toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
    }, [filteredCards]);

    return (
        <FluentProvider theme={prefersDark ? webDarkTheme : webLightTheme}>
            <div className="assistant-dashboard" style={{ width, height, display: "flex", flexDirection: "column" }}>
                <ErrorBoundary>
                <StatusBar
                    actionCount={actionCount}
                    newCount={newCount}
                    memoryActive={cards.length > 0}
                    onSettingsClick={handleShowCalibration}
                    quietMode={quietMode}
                    quietHeldCount={quietHeldCount}
                    nextMeetingTime={nextMeetingTime}
                    focusShieldActive={focusShieldActive}
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
                            onQuietModeChange={handleQuietModeChange}
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
                                            allCards={cards}
                                            onJumpToCard={handleJumpToCard}
                                            onDismissCard={onDismissCard}
                                            onUpdateSchedule={onUpdateSchedule}
                                        />
                                    ))}
                                    <CardGallery
                                        cards={localFilteredCards ?? regularCards}
                                        onSelectCard={handleSelectCard}
                                        onBatchDismiss={onBatchDismiss}
                                        onBatchSnooze={onBatchSnooze}
                                    />
                                    <DayGlance cards={filteredCards} />
                                </div>
                                {detailOpen && selectedCard && (
                                    selectedCard.trigger_type === "DAILY_BRIEFING" ? (
                                        <div className="detail-panel">
                                            <BriefingCard
                                                card={selectedCard}
                                                allCards={cards}
                                                onJumpToCard={handleJumpToCard}
                                                onDismissCard={onDismissCard}
                                                onUpdateSchedule={onUpdateSchedule}
                                                onBack={handleCloseDetail}
                                            />
                                        </div>
                                    ) : (
                                        <div className="detail-panel">
                                            <CardDetail
                                                card={selectedCard}
                                                relatedCards={relatedCards}
                                                onBack={handleCloseDetail}
                                                onSendDraft={onSendDraft}
                                                onCopyDraft={onCopyDraft}
                                                onDismissCard={onDismissCard}
                                                onSnoozeCard={onSnoozeCard}
                                                onSaveDraft={onSaveDraft}
                                            />
                                        </div>
                                    )
                                )}
                                {detailOpen && <div className="detail-backdrop" role="presentation" aria-hidden="true" onClick={handleCloseDetail} />}
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
                {/* Phase 5A: Keyboard shortcuts help overlay */}
                <KeyboardHelpOverlay
                    isOpen={showKeyboardHelp}
                    onClose={() => setShowKeyboardHelp(false)}
                />
                {/* Phase 5B: Undo toast for deferred actions */}
                {undoAction.pending && (
                    <UndoToast
                        message={undoAction.pending.message}
                        onUndo={undoAction.handleUndo}
                        onExpire={undoAction.handleExpire}
                    />
                )}
                {/* Phase 5C: Onboarding wizard for first-run */}
                {showOnboarding && (
                    <OnboardingWizard
                        onComplete={(config) => {
                            onUpdateSchedule(config);
                            setShowOnboarding(false);
                        }}
                    />
                )}
            </div>
        </FluentProvider>
    );
};
