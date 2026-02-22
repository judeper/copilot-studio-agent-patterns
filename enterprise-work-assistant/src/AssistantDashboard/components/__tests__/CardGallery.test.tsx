import * as React from 'react';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { CardGallery } from '../CardGallery';
import { renderWithProviders } from '../../../test/helpers/renderWithProviders';
import { tier2LightItem, tier3FullItem } from '../../../test/fixtures/cardFixtures';

describe('CardGallery', () => {
    it('renders all cards', () => {
        renderWithProviders(
            <CardGallery
                cards={[tier2LightItem, tier3FullItem]}
                onSelectCard={jest.fn()}
            />
        );

        expect(screen.getByText(tier2LightItem.item_summary)).toBeInTheDocument();
        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();
    });

    it('shows empty state message when no cards', () => {
        renderWithProviders(
            <CardGallery cards={[]} onSelectCard={jest.fn()} />
        );

        expect(screen.getByText('No cards match the current filters.')).toBeInTheDocument();
    });

    it('propagates card click to onSelectCard', async () => {
        const handleSelect = jest.fn();
        renderWithProviders(
            <CardGallery
                cards={[tier3FullItem]}
                onSelectCard={handleSelect}
            />
        );

        await userEvent.click(screen.getByText(tier3FullItem.item_summary));
        expect(handleSelect).toHaveBeenCalledWith(tier3FullItem.id);
    });
});
