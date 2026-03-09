import { vi } from 'vitest';
import { compositeSort } from '../../utils/cardTransforms';
import type { AssistantCard } from '../../components/types';

function makeCard(overrides: Partial<AssistantCard>): AssistantCard {
    return {
        id: 'test-card',
        trigger_type: 'EMAIL',
        triage_tier: 'FULL',
        item_summary: 'Test card',
        priority: null,
        temporal_horizon: null,
        research_log: null,
        key_findings: null,
        verified_sources: null,
        confidence_score: null,
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
        ...overrides,
    };
}

describe('compositeSort', () => {
    it('returns input order when no cards have confidence scores', () => {
        const cards = [
            makeCard({ id: 'a', priority: 'High' }),
            makeCard({ id: 'b', priority: 'Low' }),
        ];
        const result = compositeSort(cards);
        expect(result.map(c => c.id)).toEqual(['a', 'b']);
    });

    it('sorts by priority (60%) + confidence (40%)', () => {
        const cards = [
            makeCard({ id: 'low-high-conf', priority: 'Low', confidence_score: 95 }),
            makeCard({ id: 'high-low-conf', priority: 'High', confidence_score: 50 }),
        ];
        const result = compositeSort(cards);
        // High priority (3*0.6=1.8) + 50 conf (0.5*0.4=0.2) = 2.0
        // Low priority (1*0.6=0.6) + 95 conf (0.95*0.4=0.38) = 0.98
        expect(result[0].id).toBe('high-low-conf');
    });

    it('handles empty array', () => {
        expect(compositeSort([])).toEqual([]);
    });

    it('handles single card', () => {
        const cards = [makeCard({ id: 'only', confidence_score: 80 })];
        const result = compositeSort(cards);
        expect(result).toHaveLength(1);
        expect(result[0].id).toBe('only');
    });

    it('handles mix of null and non-null confidence', () => {
        const cards = [
            makeCard({ id: 'no-conf', priority: 'High', confidence_score: null }),
            makeCard({ id: 'has-conf', priority: 'Medium', confidence_score: 90 }),
        ];
        const result = compositeSort(cards);
        // High priority (3*0.6=1.8) + 0 conf = 1.8
        // Medium (2*0.6=1.2) + 90 conf (0.9*0.4=0.36) = 1.56
        expect(result[0].id).toBe('no-conf');
    });

    it('does not mutate the input array', () => {
        const cards = [
            makeCard({ id: 'a', priority: 'Low', confidence_score: 90 }),
            makeCard({ id: 'b', priority: 'High', confidence_score: 50 }),
        ];
        const original = [...cards];
        compositeSort(cards);
        expect(cards.map(c => c.id)).toEqual(original.map(c => c.id));
    });

    it('sorts equal-priority cards by confidence', () => {
        const cards = [
            makeCard({ id: 'low-conf', priority: 'High', confidence_score: 40 }),
            makeCard({ id: 'high-conf', priority: 'High', confidence_score: 95 }),
        ];
        const result = compositeSort(cards);
        expect(result[0].id).toBe('high-conf');
    });
});
