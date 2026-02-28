import * as React from 'react';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { App } from '../App';
import {
    tier1SkipItem,
    tier2LightItem,
    tier3FullItem,
} from '../../../test/fixtures/cardFixtures';

/**
 * App filter logic tests (TEST-03).
 *
 * The applyFilters function is not exported — we test it through rendered output.
 * App wraps itself in FluentProvider, so we use render() directly (no renderWithProviders).
 */

function renderApp(overrides: Partial<React.ComponentProps<typeof App>> = {}) {
    const defaultProps: React.ComponentProps<typeof App> = {
        cards: [tier2LightItem, tier3FullItem],
        filterTriggerType: '',
        filterPriority: '',
        filterCardStatus: '',
        filterTemporalHorizon: '',
        width: 800,
        height: 600,
        onSelectCard: jest.fn(),
        onSendDraft: jest.fn(),
        onCopyDraft: jest.fn(),
        onDismissCard: jest.fn(),
        onJumpToCard: jest.fn(),
        onExecuteCommand: jest.fn(),
    };

    return render(<App {...defaultProps} {...overrides} />);
}

describe('App filter logic', () => {
    it('shows all cards when no filters are active', () => {
        renderApp();

        expect(screen.getByText(tier2LightItem.item_summary)).toBeInTheDocument();
        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();
    });

    it('filters by trigger type', () => {
        renderApp({ filterTriggerType: 'EMAIL' });

        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();
        expect(screen.queryByText(tier2LightItem.item_summary)).not.toBeInTheDocument();
    });

    it('filters by priority', () => {
        renderApp({ filterPriority: 'High' });

        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();
        expect(screen.queryByText(tier2LightItem.item_summary)).not.toBeInTheDocument();
    });

    it('filters by card status', () => {
        renderApp({ filterCardStatus: 'READY' });

        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();
        expect(screen.queryByText(tier2LightItem.item_summary)).not.toBeInTheDocument();
    });

    it('filters by temporal horizon', () => {
        renderApp({ filterTemporalHorizon: 'TODAY' });

        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();
        expect(screen.queryByText(tier2LightItem.item_summary)).not.toBeInTheDocument();
    });

    it('applies combined filters', () => {
        renderApp({
            filterTriggerType: 'EMAIL',
            filterPriority: 'High',
            filterCardStatus: 'READY',
            filterTemporalHorizon: 'TODAY',
        });

        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();
        expect(screen.queryByText(tier2LightItem.item_summary)).not.toBeInTheDocument();
    });

    it('shows empty state when no cards match filters', () => {
        renderApp({ filterTriggerType: 'CALENDAR_SCAN' });

        expect(screen.getByText('No cards match the current filters.')).toBeInTheDocument();
    });

    it('shows all cards when all filters are empty strings', () => {
        renderApp({
            cards: [tier1SkipItem, tier2LightItem, tier3FullItem],
            filterTriggerType: '',
            filterPriority: '',
            filterCardStatus: '',
            filterTemporalHorizon: '',
        });

        expect(screen.getByText(tier1SkipItem.item_summary)).toBeInTheDocument();
        expect(screen.getByText(tier2LightItem.item_summary)).toBeInTheDocument();
        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();
    });
});

describe('App view state navigation', () => {
    it('navigates to detail view when card is clicked, then back to gallery', async () => {
        const onSelectCard = jest.fn();
        renderApp({
            cards: [tier3FullItem],
            onSelectCard,
        });

        // Gallery view — card summary visible
        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();

        // Click the card to open detail view
        await userEvent.click(screen.getByText(tier3FullItem.item_summary));
        expect(onSelectCard).toHaveBeenCalledWith(tier3FullItem.id);

        // Detail view — Back button should be visible
        expect(screen.getByText('Back')).toBeInTheDocument();

        // Click Back to return to gallery
        await userEvent.click(screen.getByText('Back'));

        // Gallery view restored — card summary visible again in gallery
        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();
    });

    it('returns to gallery when selected card is removed from dataset', async () => {
        const onSelectCard = jest.fn();
        const { rerender } = render(
            <App
                cards={[tier3FullItem]}
                filterTriggerType=""
                filterPriority=""
                filterCardStatus=""
                filterTemporalHorizon=""
                width={800}
                height={600}
                onSelectCard={onSelectCard}
                onSendDraft={jest.fn()}
                onCopyDraft={jest.fn()}
                onDismissCard={jest.fn()}
                onJumpToCard={jest.fn()}
                onExecuteCommand={jest.fn()}
            />
        );

        // Open detail view
        await userEvent.click(screen.getByText(tier3FullItem.item_summary));

        // Re-render with empty cards (card removed from dataset)
        rerender(
            <App
                cards={[]}
                filterTriggerType=""
                filterPriority=""
                filterCardStatus=""
                filterTemporalHorizon=""
                width={800}
                height={600}
                onSelectCard={onSelectCard}
                onSendDraft={jest.fn()}
                onCopyDraft={jest.fn()}
                onDismissCard={jest.fn()}
                onJumpToCard={jest.fn()}
                onExecuteCommand={jest.fn()}
            />
        );

        // Should show gallery empty state
        expect(screen.getByText('No cards match the current filters.')).toBeInTheDocument();
    });
});
