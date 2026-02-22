import * as React from 'react';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { CardItem } from '../CardItem';
import { renderWithProviders } from '../../../test/helpers/renderWithProviders';
import { tier3FullItem, tier1SkipItem } from '../../../test/fixtures/cardFixtures';

describe('CardItem', () => {
    it('renders card summary text', () => {
        renderWithProviders(
            <CardItem card={tier3FullItem} onClick={jest.fn()} />
        );

        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();
    });

    it('renders card status badge', () => {
        renderWithProviders(
            <CardItem card={tier3FullItem} onClick={jest.fn()} />
        );

        expect(screen.getByText('READY')).toBeInTheDocument();
    });

    it('renders temporal horizon badge when present', () => {
        renderWithProviders(
            <CardItem card={tier3FullItem} onClick={jest.fn()} />
        );

        expect(screen.getByText('TODAY')).toBeInTheDocument();
    });

    it('hides temporal horizon badge when null', () => {
        renderWithProviders(
            <CardItem card={tier1SkipItem} onClick={jest.fn()} />
        );

        expect(screen.queryByText('TODAY')).not.toBeInTheDocument();
        expect(screen.queryByText('THIS_WEEK')).not.toBeInTheDocument();
    });

    it('renders created_on footer text', () => {
        renderWithProviders(
            <CardItem card={tier3FullItem} onClick={jest.fn()} />
        );

        expect(screen.getByText(tier3FullItem.created_on)).toBeInTheDocument();
    });

    it('calls onClick with card id when clicked', async () => {
        const handleClick = jest.fn();
        renderWithProviders(
            <CardItem card={tier3FullItem} onClick={handleClick} />
        );

        await userEvent.click(screen.getByText(tier3FullItem.item_summary));
        expect(handleClick).toHaveBeenCalledWith(tier3FullItem.id);
    });
});
