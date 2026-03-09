import type { AssistantCard } from '../components/types';

/**
 * Abstract interface for card data providers.
 * In production: backed by Dataverse typed services from pac-sdk.
 * In dev/test: backed by MockCardDataService with fixture data.
 */
export interface CardDataService {
    getCards(): Promise<AssistantCard[]>;
    updateCardOutcome(cardId: string, outcome: string): Promise<void>;
    saveDraft(cardId: string, draftText: string): Promise<void>;
}
