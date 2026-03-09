import { vi } from 'vitest';
import { renderHook, waitFor, act } from '@testing-library/react';
import { useCards } from '../../hooks/useCards';
import type { CardDataService } from '../../services/CardDataService';
import type { AssistantCard } from '../../components/types';

function makeCard(id: string): AssistantCard {
    return {
        id,
        trigger_type: 'EMAIL',
        triage_tier: 'FULL',
        item_summary: `Card ${id}`,
        priority: 'Medium',
        temporal_horizon: 'TODAY',
        research_log: null,
        key_findings: null,
        verified_sources: null,
        confidence_score: 75,
        card_status: 'READY',
        draft_payload: null,
        low_confidence_note: null,
        humanized_draft: null,
        created_on: new Date().toISOString(),
        card_outcome: 'PENDING',
        original_sender_email: null,
        original_sender_display: null,
        original_subject: null,
        conversation_cluster_id: null,
        source_signal_id: null,
        hours_stale: null,
    };
}

function createMockService(cards: AssistantCard[] = []): CardDataService {
    return {
        getCards: vi.fn().mockResolvedValue(cards),
        updateCardOutcome: vi.fn().mockResolvedValue(undefined),
        saveDraft: vi.fn().mockResolvedValue(undefined),
    };
}

describe('useCards', () => {
    it('starts in loading state', () => {
        const service = createMockService();
        const { result } = renderHook(() => useCards(service));
        expect(result.current.loading).toBe(true);
        expect(result.current.cards).toEqual([]);
    });

    it('loads cards from service', async () => {
        const cards = [makeCard('1'), makeCard('2')];
        const service = createMockService(cards);
        const { result } = renderHook(() => useCards(service));

        await waitFor(() => {
            expect(result.current.loading).toBe(false);
        });
        expect(result.current.cards).toHaveLength(2);
        expect(result.current.error).toBeNull();
    });

    it('handles service errors', async () => {
        const service = createMockService();
        (service.getCards as ReturnType<typeof vi.fn>).mockRejectedValue(new Error('Network error'));

        const { result } = renderHook(() => useCards(service));

        await waitFor(() => {
            expect(result.current.loading).toBe(false);
        });
        expect(result.current.error).toBeInstanceOf(Error);
        expect(result.current.error!.message).toBe('Network error');
        expect(result.current.cards).toEqual([]);
    });

    it('provides a refresh function', async () => {
        const service = createMockService([makeCard('1')]);
        const { result } = renderHook(() => useCards(service));

        await waitFor(() => {
            expect(result.current.loading).toBe(false);
        });

        // Refresh should call getCards again
        act(() => {
            result.current.refresh();
        });

        expect(service.getCards).toHaveBeenCalledTimes(2);
    });

    it('does not update state after unmount', async () => {
        let resolveGetCards: (cards: AssistantCard[]) => void;
        const service: CardDataService = {
            getCards: vi.fn().mockImplementation(() => new Promise(resolve => {
                resolveGetCards = resolve;
            })),
            updateCardOutcome: vi.fn(),
            saveDraft: vi.fn(),
        };

        const { unmount } = renderHook(() => useCards(service));

        // Unmount before the promise resolves
        unmount();

        // Resolve the promise after unmount — should not throw
        resolveGetCards!([makeCard('1')]);

        // No assertion needed — test passes if no "setState on unmounted" warning
    });
});
