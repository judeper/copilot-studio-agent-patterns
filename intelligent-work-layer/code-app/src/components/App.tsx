import React, { useState, useCallback, useEffect, useRef, useMemo } from 'react';
import { FluentProvider, webLightTheme, webDarkTheme, Spinner } from '@fluentui/react-components';
import type { AssistantCard, BriefingScheduleConfig, OrchestratorResponse } from './types';
import { CardGallery } from './CardGallery';
import { CardDetail } from './CardDetail';
import { BriefingCard } from './BriefingCard';
import { CommandBar } from './CommandBar';
import { ConfidenceCalibration } from './ConfidenceCalibration';
import { DayGlance } from './DayGlance';
import { ErrorBoundary } from './ErrorBoundary';
import { FilterBar } from './FilterBar';
import { StatusBar } from './StatusBar';
import { focusAfterRender } from '../utils/focusUtils';
import { useCards } from '../hooks/useCards';
import { MockCardDataService } from '../services/MockCardDataService';
import '../styles/AssistantDashboard.css';

type ViewState =
    | { mode: 'gallery'; selectedCardId: string | null }
    | { mode: 'calibration' };

type FocusRestoreTarget =
    | { type: 'card'; cardId: string }
    | { type: 'selector'; selector: string }
    | { type: 'element'; element: HTMLElement };

function escapeAttributeValue(value: string): string {
    return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

function getActiveFocusRestoreTarget(): FocusRestoreTarget | null {
    if (typeof document === 'undefined') return null;
    const activeElement = document.activeElement;
    if (!(activeElement instanceof HTMLElement)) return null;
    const focusReturnId = activeElement.getAttribute('data-focus-return');
    if (focusReturnId) {
        return {
            type: 'selector',
            selector: `[data-focus-return="${escapeAttributeValue(focusReturnId)}"]`,
        };
    }
    const cardId = activeElement.getAttribute('data-card-id');
    if (cardId) {
        return { type: 'card', cardId };
    }
    return { type: 'element', element: activeElement };
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

function partitionCards(cards: AssistantCard[]): {
    briefingCards: AssistantCard[];
    regularCards: AssistantCard[];
} {
    const briefingCards: AssistantCard[] = [];
    const regularCards: AssistantCard[] = [];
    for (const card of cards) {
        if (card.trigger_type === 'DAILY_BRIEFING') {
            briefingCards.push(card);
        } else {
            regularCards.push(card);
        }
    }
    return { briefingCards, regularCards };
}

function usePrefersDarkMode(): boolean {
    const [dark, setDark] = useState(() =>
        typeof window !== 'undefined' && window.matchMedia?.('(prefers-color-scheme: dark)').matches,
    );

    useEffect(() => {
        if (typeof window === 'undefined' || !window.matchMedia) return;
        const mql = window.matchMedia('(prefers-color-scheme: dark)');
        const handler = (e: MediaQueryListEvent) => setDark(e.matches);
        mql.addEventListener('change', handler);
        return () => mql.removeEventListener('change', handler);
    }, []);

    return dark;
}

// Singleton service instance — in production, replace with Dataverse-backed service
const cardService = new MockCardDataService();

export const App: React.FC = () => {
    const { cards, loading } = useCards(cardService);

    // In the Code App, filters are managed locally (no Canvas app input properties)
    const filterTriggerType = '';
    const filterPriority = '';
    const filterCardStatus = '';
    const filterTemporalHorizon = '';

    const [viewState, setViewState] = useState<ViewState>({ mode: 'gallery', selectedCardId: null });
    const [localFilteredCards, setLocalFilteredCards] = useState<AssistantCard[] | null>(null);
    const [quietMode, setQuietMode] = useState(false);
    const [quietHeldCount, setQuietHeldCount] = useState(0);
    const [orchestratorResponse, setOrchestratorResponse] = useState<OrchestratorResponse | null>(null);
    const [isProcessing, setIsProcessing] = useState(false);
    const prefersDark = usePrefersDarkMode();

    const handleFilteredCards = useCallback((filtered: AssistantCard[]) => {
        setLocalFilteredCards(filtered);
    }, []);

    const handleQuietModeChange = useCallback((quiet: boolean, heldCount: number) => {
        setQuietMode(quiet);
        setQuietHeldCount(heldCount);
    }, []);

    const focusRestoreTargetRef = useRef<FocusRestoreTarget | null>(null);
    const previousModeRef = useRef<ViewState['mode']>(viewState.mode);

    const selectedCardId = viewState.mode === 'gallery' ? viewState.selectedCardId : null;
    const detailOpen = selectedCardId !== null;

    useEffect(() => {
        if (!detailOpen) return;
        const handler = (e: KeyboardEvent) => {
            if (e.key === 'Escape') {
                setViewState({ mode: 'gallery', selectedCardId: null });
            }
        };
        document.addEventListener('keydown', handler);
        return () => document.removeEventListener('keydown', handler);
    }, [detailOpen]);

    const restoreFocus = useCallback(() => {
        const target = focusRestoreTargetRef.current;
        if (!target || typeof document === 'undefined') return;
        focusAfterRender(() => {
            let element: HTMLElement | null = null;
            switch (target.type) {
                case 'card':
                    element = document.querySelector(
                        `[data-card-id="${escapeAttributeValue(target.cardId)}"]`,
                    ) as HTMLElement | null;
                    break;
                case 'selector':
                    element = document.querySelector(target.selector) as HTMLElement | null;
                    break;
                case 'element':
                    element = target.element.isConnected ? target.element : null;
                    break;
            }
            element?.focus();
        });
        focusRestoreTargetRef.current = null;
    }, []);

    const filteredCards = useMemo(
        () => applyFilters(cards, filterTriggerType, filterPriority, filterCardStatus, filterTemporalHorizon),
        [cards, filterTriggerType, filterPriority, filterCardStatus, filterTemporalHorizon],
    );

    const { briefingCards, regularCards } = useMemo(
        () => partitionCards(filteredCards),
        [filteredCards],
    );

    const selectedCard = useMemo(() => {
        if (!selectedCardId) return null;
        return cards.find((c) => c.id === selectedCardId) ?? null;
    }, [cards, selectedCardId]);

    useEffect(() => {
        if (selectedCardId && !selectedCard) {
            setViewState({ mode: 'gallery', selectedCardId: null });
        }
    }, [selectedCardId, selectedCard]);

    useEffect(() => {
        const previousMode = previousModeRef.current;
        if (viewState.mode === 'gallery' && previousMode !== 'gallery') {
            restoreFocus();
        }
        previousModeRef.current = viewState.mode;
    }, [viewState.mode, restoreFocus]);

    const prevDetailOpenRef = useRef(detailOpen);
    useEffect(() => {
        if (prevDetailOpenRef.current && !detailOpen) {
            restoreFocus();
        }
        prevDetailOpenRef.current = detailOpen;
    }, [detailOpen, restoreFocus]);

    const handleSelectCard = useCallback(
        (cardId: string) => {
            const card = cards.find((c) => c.id === cardId);
            if (card) {
                focusRestoreTargetRef.current = { type: 'card', cardId };
                setViewState({ mode: 'gallery', selectedCardId: cardId });
            }
        },
        [cards],
    );

    const handleJumpToCard = useCallback(
        (cardId: string) => {
            const card = cards.find((c) => c.id === cardId);
            if (card) {
                focusRestoreTargetRef.current = getActiveFocusRestoreTarget();
                setViewState({ mode: 'gallery', selectedCardId: cardId });
            }
        },
        [cards],
    );

    const handleCloseDetail = useCallback(() => {
        setViewState({ mode: 'gallery', selectedCardId: null });
    }, []);

    const handleBack = useCallback(() => {
        setViewState({ mode: 'gallery', selectedCardId: null });
    }, []);

    const currentCardId = selectedCardId;

    const handleShowCalibration = useCallback(() => {
        focusRestoreTargetRef.current = getActiveFocusRestoreTarget();
        setViewState({ mode: 'calibration' });
    }, []);

    // Action handlers — in the Code App these interact with the service directly
    const handleSendDraft = useCallback(
        (cardId: string, _finalText: string, editDistanceRatio: number) => {
            const outcome = editDistanceRatio > 0 ? 'SENT_EDITED' : 'SENT_AS_IS';
            cardService.updateCardOutcome(cardId, outcome);
        },
        [],
    );

    const handleCopyDraft = useCallback((_cardId: string) => {
        // Copy handled in CardDetail — no-op at app level
    }, []);

    const handleDismissCard = useCallback((cardId: string) => {
        cardService.updateCardOutcome(cardId, 'DISMISSED');
    }, []);

    const handleSaveDraft = useCallback((cardId: string, editedText: string) => {
        cardService.saveDraft(cardId, editedText);
    }, []);

    const handleExecuteCommand = useCallback((_command: string, _currentCardId: string | null) => {
        setIsProcessing(true);
        // Simulate command processing
        setTimeout(() => {
            setOrchestratorResponse({
                response_text: 'Command received. This is a mock response — connect to Copilot Studio for live orchestration.',
                card_links: [],
                side_effects: [],
            });
            setIsProcessing(false);
        }, 1500);
    }, []);

    const handleUpdateSchedule = useCallback((_config: BriefingScheduleConfig) => {
        // In production, this would persist to Dataverse BriefingSchedule table
    }, []);

    const actionCount = filteredCards.filter(
        (c) => c.trigger_type !== 'DAILY_BRIEFING' && c.card_outcome === 'PENDING',
    ).length;
    const newCount = filteredCards.filter(
        (c) => c.card_status === 'READY' && c.card_outcome === 'PENDING',
    ).length;

    const nextMeetingTime = useMemo(() => {
        const now = Date.now();
        const calendarCards = filteredCards
            .filter((c) => c.trigger_type === 'CALENDAR_SCAN' && c.card_outcome === 'PENDING')
            .map((c) => new Date(c.created_on))
            .filter((d) => !isNaN(d.getTime()) && d.getTime() > now)
            .sort((a, b) => a.getTime() - b.getTime());
        if (calendarCards.length === 0) return null;
        return calendarCards[0].toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }, [filteredCards]);

    return (
        <FluentProvider theme={prefersDark ? webDarkTheme : webLightTheme}>
            <div className="assistant-dashboard" style={{ width: '100vw', height: '100vh', display: 'flex', flexDirection: 'column' }}>
                <ErrorBoundary>
                    <StatusBar
                        actionCount={actionCount}
                        newCount={newCount}
                        memoryActive={cards.length > 0}
                        onSettingsClick={handleShowCalibration}
                        quietMode={quietMode}
                        quietHeldCount={quietHeldCount}
                        nextMeetingTime={nextMeetingTime}
                    />
                    {viewState.mode === 'calibration' ? (
                        <ConfidenceCalibration
                            cards={cards}
                            onBack={handleBack}
                        />
                    ) : (
                        <>
                            <FilterBar
                                cards={regularCards}
                                onFilteredCards={handleFilteredCards}
                                onQuietModeChange={handleQuietModeChange}
                            />
                            {loading ? (
                                <div className="dashboard-loading" style={{ display: 'flex', justifyContent: 'center', padding: '48px 0' }}>
                                    <Spinner size="large" label="Loading cards..." />
                                </div>
                            ) : (
                                <div className="feed-detail-layout">
                                    <div className={detailOpen ? 'card-gallery feed-dimmed' : 'card-gallery'} style={{ flex: 1, overflow: 'auto' }}>
                                        {briefingCards.map((bc) => (
                                            <BriefingCard
                                                key={bc.id}
                                                card={bc}
                                                allCards={cards}
                                                onJumpToCard={handleJumpToCard}
                                                onDismissCard={handleDismissCard}
                                                onUpdateSchedule={handleUpdateSchedule}
                                            />
                                        ))}
                                        <CardGallery
                                            cards={localFilteredCards ?? regularCards}
                                            onSelectCard={handleSelectCard}
                                        />
                                        <DayGlance cards={filteredCards} />
                                    </div>
                                    {detailOpen && selectedCard && (
                                        selectedCard.trigger_type === 'DAILY_BRIEFING' ? (
                                            <div className="detail-panel">
                                                <BriefingCard
                                                    card={selectedCard}
                                                    allCards={cards}
                                                    onJumpToCard={handleJumpToCard}
                                                    onDismissCard={handleDismissCard}
                                                    onUpdateSchedule={handleUpdateSchedule}
                                                    onBack={handleCloseDetail}
                                                />
                                            </div>
                                        ) : (
                                            <div className="detail-panel">
                                                <CardDetail
                                                    card={selectedCard}
                                                    onBack={handleCloseDetail}
                                                    onSendDraft={handleSendDraft}
                                                    onCopyDraft={handleCopyDraft}
                                                    onDismissCard={handleDismissCard}
                                                    onSaveDraft={handleSaveDraft}
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
                <CommandBar
                    currentCardId={currentCardId}
                    selectedCardId={currentCardId}
                    onExecuteCommand={handleExecuteCommand}
                    onJumpToCard={handleJumpToCard}
                    lastResponse={orchestratorResponse}
                    isProcessing={isProcessing}
                />
            </div>
        </FluentProvider>
    );
};
