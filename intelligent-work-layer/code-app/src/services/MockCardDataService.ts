import type { CardDataService } from './CardDataService';
import type { AssistantCard } from '../components/types';
import { sampleCards } from '../fixtures/sampleCards';

/**
 * Mock implementation of CardDataService for offline development and testing.
 * Returns sample cards from fixtures and simulates mutations in memory.
 */
export class MockCardDataService implements CardDataService {
    private cards: AssistantCard[];

    constructor(initialCards?: AssistantCard[]) {
        this.cards = initialCards ?? [...sampleCards];
    }

    async getCards(): Promise<AssistantCard[]> {
        return [...this.cards];
    }

    async updateCardOutcome(cardId: string, outcome: string): Promise<void> {
        const card = this.cards.find((c) => c.id === cardId);
        if (card) {
            (card as unknown as Record<string, unknown>).card_outcome = outcome;
        }
    }

    async saveDraft(cardId: string, draftText: string): Promise<void> {
        const card = this.cards.find((c) => c.id === cardId);
        if (card) {
            card.humanized_draft = draftText;
        }
    }
}
