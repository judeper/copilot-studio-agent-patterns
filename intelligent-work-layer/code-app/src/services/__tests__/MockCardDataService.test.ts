import { MockCardDataService } from '../../services/MockCardDataService';

describe('MockCardDataService', () => {
    it('returns sample cards', async () => {
        const service = new MockCardDataService();
        const cards = await service.getCards();
        expect(cards.length).toBeGreaterThan(0);
    });

    it('returns a copy of cards (not the same reference)', async () => {
        const service = new MockCardDataService();
        const cards1 = await service.getCards();
        const cards2 = await service.getCards();
        expect(cards1).not.toBe(cards2);
    });

    it('updates card outcome', async () => {
        const service = new MockCardDataService();
        const cards = await service.getCards();
        const cardId = cards[0].id;

        await service.updateCardOutcome(cardId, 'DISMISSED');

        const updated = await service.getCards();
        const card = updated.find(c => c.id === cardId);
        expect((card as Record<string, unknown>).card_outcome).toBe('DISMISSED');
    });

    it('saves draft text', async () => {
        const service = new MockCardDataService();
        const cards = await service.getCards();
        const cardId = cards[0].id;

        await service.saveDraft(cardId, 'Updated draft text');

        const updated = await service.getCards();
        const card = updated.find(c => c.id === cardId);
        expect(card?.humanized_draft).toBe('Updated draft text');
    });

    it('accepts custom initial cards', async () => {
        const customCards = [{
            id: 'custom-1',
            trigger_type: 'EMAIL' as const,
            triage_tier: 'FULL' as const,
            item_summary: 'Custom card',
            priority: null,
            temporal_horizon: null,
            research_log: null,
            key_findings: null,
            verified_sources: null,
            confidence_score: null,
            card_status: 'READY' as const,
            draft_payload: null,
            low_confidence_note: null,
            humanized_draft: null,
            created_on: new Date().toISOString(),
            card_outcome: 'PENDING' as const,
            original_sender_email: null,
            original_sender_display: null,
            original_subject: null,
            conversation_cluster_id: null,
            source_signal_id: null,
            hours_stale: null,
        }];
        const service = new MockCardDataService(customCards);
        const cards = await service.getCards();
        expect(cards).toHaveLength(1);
        expect(cards[0].id).toBe('custom-1');
    });

    it('ignores update for non-existent card', async () => {
        const service = new MockCardDataService();
        // Should not throw
        await service.updateCardOutcome('nonexistent', 'DISMISSED');
        await service.saveDraft('nonexistent', 'text');
    });
});
