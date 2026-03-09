import { useState, useEffect, useCallback, useRef } from 'react';
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
    const isMountedRef = useRef(true);

    const refresh = useCallback(() => {
        setLoading(true);
        service
            .getCards()
            .then((result) => {
                if (isMountedRef.current) {
                    setCards(result);
                    setError(null);
                }
            })
            .catch((err) => {
                if (isMountedRef.current) {
                    setError(err instanceof Error ? err : new Error(String(err)));
                }
            })
            .finally(() => {
                if (isMountedRef.current) {
                    setLoading(false);
                }
            });
    }, [service]);

    useEffect(() => {
        isMountedRef.current = true;
        refresh();
        return () => {
            isMountedRef.current = false;
        };
    }, [refresh]);

    return { cards, loading, error, refresh };
}
