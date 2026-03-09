import React from 'react';
import { vi } from 'vitest';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { CardGallery } from '../CardGallery';
import { renderWithProviders } from '../../test/helpers/renderWithProviders';
import { tier2LightItem, tier3FullItem } from '../../test/fixtures/cardFixtures';
import type { AssistantCard } from '../types';

const actionCard: AssistantCard = {
    ...tier3FullItem,
    id: 'action-card',
    triage_tier: 'FULL',
    confidence_score: 87,
    card_outcome: 'PENDING',
    item_summary: 'Action required card',
    hours_stale: 2,
};

const signalCard: AssistantCard = {
    ...tier2LightItem,
    id: 'signal-card',
    triage_tier: 'LIGHT',
    card_outcome: 'PENDING',
    item_summary: 'Signal card',
    hours_stale: 1,
};

describe('CardGallery', () => {
    it('renders cards grouped into sections', () => {
        renderWithProviders(
            <CardGallery
                cards={[actionCard, signalCard]}
                onSelectCard={vi.fn()}
            />
        );

        expect(screen.getByText('Action Required')).toBeInTheDocument();
        expect(screen.getByText('New Signals')).toBeInTheDocument();
        expect(screen.getByText(actionCard.item_summary)).toBeInTheDocument();
        expect(screen.getByText(signalCard.item_summary)).toBeInTheDocument();
    });

    it('shows empty state when no cards', () => {
        renderWithProviders(
            <CardGallery cards={[]} onSelectCard={vi.fn()} />
        );

        expect(screen.getByText("You're all caught up")).toBeInTheDocument();
        expect(screen.getByText(/Ask IWL about anything/)).toBeInTheDocument();
    });

    it('propagates card click to onSelectCard', async () => {
        const handleSelect = vi.fn();
        renderWithProviders(
            <CardGallery
                cards={[actionCard]}
                onSelectCard={handleSelect}
            />
        );

        await userEvent.click(screen.getByText(actionCard.item_summary));
        expect(handleSelect).toHaveBeenCalledWith(actionCard.id);
    });

    it('collapses section when header is clicked', async () => {
        renderWithProviders(
            <CardGallery
                cards={[actionCard]}
                onSelectCard={vi.fn()}
            />
        );

        expect(screen.getByText(actionCard.item_summary)).toBeInTheDocument();
        await userEvent.click(screen.getByText('Action Required'));
        expect(screen.queryByText(actionCard.item_summary)).not.toBeInTheDocument();
    });

    it('hides empty sections', () => {
        renderWithProviders(
            <CardGallery
                cards={[actionCard]}
                onSelectCard={vi.fn()}
            />
        );

        expect(screen.getByText('Action Required')).toBeInTheDocument();
        expect(screen.queryByText('New Signals')).not.toBeInTheDocument();
        expect(screen.queryByText('Proactive Alerts')).not.toBeInTheDocument();
    });
});
