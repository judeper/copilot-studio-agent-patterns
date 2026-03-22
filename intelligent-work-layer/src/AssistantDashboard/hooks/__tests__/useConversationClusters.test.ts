import { renderHook } from '@testing-library/react';
import { useConversationClusters } from '../useConversationClusters';
import type { AssistantCard } from '../../components/types';
import { tier2LightItem } from '../../../test/fixtures/cardFixtures';

/** Helper to create a card with specific id, cluster id, and created_on */
function makeCard(
    overrides: Partial<AssistantCard> & { id: string },
): AssistantCard {
    return {
        ...tier2LightItem,
        ...overrides,
    };
}

describe('useConversationClusters', () => {
    it('returns empty clusteredCards for empty input', () => {
        const { result } = renderHook(() => useConversationClusters([]));

        expect(result.current.clusteredCards).toHaveLength(0);
        expect(result.current.clusterMap.size).toBe(0);
    });

    it('returns single-card clusters for cards with unique cluster IDs', () => {
        const cards: AssistantCard[] = [
            makeCard({ id: 'a', conversation_cluster_id: 'cluster-a', created_on: '2026-03-22T08:00:00Z' }),
            makeCard({ id: 'b', conversation_cluster_id: 'cluster-b', created_on: '2026-03-22T09:00:00Z' }),
        ];

        const { result } = renderHook(() => useConversationClusters(cards));

        expect(result.current.clusteredCards).toHaveLength(2);
        expect(result.current.clusterMap.size).toBe(2);

        const clusterA = result.current.clusterMap.get('cluster-a')!;
        expect(clusterA.representative.id).toBe('a');
        expect(clusterA.related).toHaveLength(0);
    });

    it('groups cards with same conversation_cluster_id', () => {
        const cards: AssistantCard[] = [
            makeCard({ id: 'c1', conversation_cluster_id: 'shared-cluster', created_on: '2026-03-22T08:00:00Z' }),
            makeCard({ id: 'c2', conversation_cluster_id: 'shared-cluster', created_on: '2026-03-22T10:00:00Z' }),
            makeCard({ id: 'c3', conversation_cluster_id: 'shared-cluster', created_on: '2026-03-22T09:00:00Z' }),
        ];

        const { result } = renderHook(() => useConversationClusters(cards));

        // Only 1 representative in clusteredCards
        expect(result.current.clusteredCards).toHaveLength(1);
        expect(result.current.clusterMap.size).toBe(1);

        const cluster = result.current.clusterMap.get('shared-cluster')!;
        expect(cluster.representative.id).toBe('c2'); // newest
        expect(cluster.related).toHaveLength(2);
    });

    it('uses newest card as representative', () => {
        const cards: AssistantCard[] = [
            makeCard({ id: 'old', conversation_cluster_id: 'grp', created_on: '2026-03-20T08:00:00Z' }),
            makeCard({ id: 'newest', conversation_cluster_id: 'grp', created_on: '2026-03-22T12:00:00Z' }),
            makeCard({ id: 'mid', conversation_cluster_id: 'grp', created_on: '2026-03-21T08:00:00Z' }),
        ];

        const { result } = renderHook(() => useConversationClusters(cards));

        const cluster = result.current.clusterMap.get('grp')!;
        expect(cluster.representative.id).toBe('newest');
    });

    it('cards without cluster ID get their own cluster', () => {
        const cards: AssistantCard[] = [
            makeCard({ id: 'solo-1', conversation_cluster_id: null, created_on: '2026-03-22T08:00:00Z' }),
            makeCard({ id: 'solo-2', conversation_cluster_id: null, created_on: '2026-03-22T09:00:00Z' }),
        ];

        const { result } = renderHook(() => useConversationClusters(cards));

        // Each card uses its own id as key, so 2 separate clusters
        expect(result.current.clusteredCards).toHaveLength(2);
        expect(result.current.clusterMap.size).toBe(2);

        const cluster1 = result.current.clusterMap.get('solo-1')!;
        expect(cluster1.representative.id).toBe('solo-1');
        expect(cluster1.related).toHaveLength(0);
    });

    it('related cards are ordered newest first', () => {
        const cards: AssistantCard[] = [
            makeCard({ id: 'r1', conversation_cluster_id: 'thread', created_on: '2026-03-20T08:00:00Z' }),
            makeCard({ id: 'r2', conversation_cluster_id: 'thread', created_on: '2026-03-21T08:00:00Z' }),
            makeCard({ id: 'r3', conversation_cluster_id: 'thread', created_on: '2026-03-22T08:00:00Z' }),
        ];

        const { result } = renderHook(() => useConversationClusters(cards));

        const cluster = result.current.clusterMap.get('thread')!;
        // r3 is newest (representative), related = [r2, r1] newest first
        expect(cluster.representative.id).toBe('r3');
        expect(cluster.related[0].id).toBe('r2');
        expect(cluster.related[1].id).toBe('r1');
    });
});
