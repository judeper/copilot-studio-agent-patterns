import { useState, useEffect, useCallback } from 'react';
import type { AssistantCard } from '../components/types';
import type { CardDataService } from '../services/CardDataService';

/**
 * Hook that replaces the PCF useCardData hook.
 * Instead of reading from a PCF DataSet, it uses a CardDataService.
 */
export function useCards(service: CardDataService): {
    cards: AssistantCard[];
    loading: boolean;
    error: Error | null;
    refresh: () => void;
} {
    const [cards, setCards] = useState<AssistantCard[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<Error | null>(null);

    const refresh = useCallback(() => {
        setLoading(true);
        service
            .getCards()
            .then((result) => {
                setCards(result);
                setError(null);
            })
            .catch((err) => {
                setError(err instanceof Error ? err : new Error(String(err)));
            })
            .finally(() => {
                setLoading(false);
            });
    }, [service]);

    useEffect(() => {
        refresh();
    }, [refresh]);

    return { cards, loading, error, refresh };
}
