import * as React from "react";
import type { AssistantCard } from "../components/types";

export interface ConversationCluster {
    /** The most recent card in the cluster — displayed as the representative */
    representative: AssistantCard;
    /** All other cards in the cluster, ordered newest first */
    related: AssistantCard[];
}

/**
 * Groups cards by conversation_cluster_id and returns a Map of clusters.
 * Cards without a cluster ID are treated as their own single-card cluster.
 * The representative is the most recently created card in the cluster.
 */
export function useConversationClusters(cards: AssistantCard[]): {
    clusteredCards: AssistantCard[];
    clusterMap: Map<string, ConversationCluster>;
} {
    return React.useMemo(() => {
        const groups = new Map<string, AssistantCard[]>();

        for (const card of cards) {
            const key = card.conversation_cluster_id ?? card.id;
            const group = groups.get(key);
            if (group) {
                group.push(card);
            } else {
                groups.set(key, [card]);
            }
        }

        const clusterMap = new Map<string, ConversationCluster>();
        const clusteredCards: AssistantCard[] = [];

        for (const [key, group] of groups) {
            // Sort by created_on descending — newest first
            const sorted = [...group].sort(
                (a, b) => new Date(b.created_on).getTime() - new Date(a.created_on).getTime(),
            );
            const representative = sorted[0];
            const related = sorted.slice(1);

            clusterMap.set(key, { representative, related });
            clusteredCards.push(representative);
        }

        return { clusteredCards, clusterMap };
    }, [cards]);
}
