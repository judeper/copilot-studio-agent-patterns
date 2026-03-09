import type { AssistantCard } from '../components/types';

const PRIORITY_WEIGHTS: Record<string, number> = { High: 3, Medium: 2, Low: 1 };

/**
 * Composite sort: ranks cards by priority (60%) + confidence (40%).
 * If no cards have confidence scores, returns input order unchanged.
 */
export function compositeSort(cards: AssistantCard[]): AssistantCard[] {
    const hasConfidence = cards.some((c) => c.confidence_score !== null);
    if (!hasConfidence) return cards;

    return [...cards].sort((a, b) => {
        const aPriority = PRIORITY_WEIGHTS[a.priority ?? ""] ?? 0;
        const bPriority = PRIORITY_WEIGHTS[b.priority ?? ""] ?? 0;
        const aConf = (a.confidence_score ?? 0) / 100;
        const bConf = (b.confidence_score ?? 0) / 100;
        const aScore = aPriority * 0.6 + aConf * 0.4;
        const bScore = bPriority * 0.6 + bConf * 0.4;
        return bScore - aScore;
    });
}
