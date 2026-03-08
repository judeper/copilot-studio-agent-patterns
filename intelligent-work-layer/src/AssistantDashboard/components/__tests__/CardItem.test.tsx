import * as React from 'react';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { CardItem } from '../CardItem';
import { renderWithProviders } from '../../../test/helpers/renderWithProviders';
import { tier3FullItem, tier1SkipItem, calendarBriefingItem } from '../../../test/fixtures/cardFixtures';
import type { AssistantCard } from '../types';

describe('CardItem', () => {
    it('renders card summary text', () => {
        renderWithProviders(
            <CardItem card={tier3FullItem} onClick={jest.fn()} />
        );

        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();
    });

    it('hides READY status badge (default state, no noise)', () => {
        renderWithProviders(
            <CardItem card={tier3FullItem} onClick={jest.fn()} />
        );

        expect(screen.queryByText('READY')).not.toBeInTheDocument();
    });

    it('renders non-READY status badge', () => {
        const lowConfCard: AssistantCard = {
            ...tier3FullItem,
            id: 'low-conf-card',
            card_status: 'LOW_CONFIDENCE',
        };
        renderWithProviders(
            <CardItem card={lowConfCard} onClick={jest.fn()} />
        );

        expect(screen.getByText('LOW_CONFIDENCE')).toBeInTheDocument();
    });

    it('renders temporal horizon badge only for CALENDAR_SCAN trigger', () => {
        renderWithProviders(
            <CardItem card={calendarBriefingItem} onClick={jest.fn()} />
        );

        expect(screen.getByText('TODAY')).toBeInTheDocument();
    });

    it('hides temporal horizon badge for non-CALENDAR_SCAN triggers', () => {
        renderWithProviders(
            <CardItem card={tier3FullItem} onClick={jest.fn()} />
        );

        expect(screen.queryByText('TODAY')).not.toBeInTheDocument();
    });

    it('renders sender display name in header', () => {
        renderWithProviders(
            <CardItem card={tier3FullItem} onClick={jest.fn()} />
        );

        expect(screen.getByText('Fabrikam Legal')).toBeInTheDocument();
    });

    it('renders "Unknown" when sender display is null', () => {
        const noSenderCard: AssistantCard = {
            ...tier1SkipItem,
            id: 'no-sender',
            original_sender_display: null,
        };
        renderWithProviders(
            <CardItem card={noSenderCard} onClick={jest.fn()} />
        );

        expect(screen.getByText('Unknown')).toBeInTheDocument();
    });

    it('calls onClick with card id when clicked', async () => {
        const handleClick = jest.fn();
        renderWithProviders(
            <CardItem card={tier3FullItem} onClick={handleClick} />
        );

        await userEvent.click(screen.getByText(tier3FullItem.item_summary));
        expect(handleClick).toHaveBeenCalledWith(tier3FullItem.id);
    });

    it('has role="button" and tabIndex for accessibility', () => {
        renderWithProviders(
            <CardItem card={tier3FullItem} onClick={jest.fn()} />
        );

        const card = screen.getByRole('button', { name: /Fabrikam Legal/ });
        expect(card).toBeInTheDocument();
        expect(card).toHaveAttribute('tabindex', '0');
    });

    it('triggers onClick on Enter keypress', async () => {
        const handleClick = jest.fn();
        renderWithProviders(
            <CardItem card={tier3FullItem} onClick={handleClick} />
        );

        const card = screen.getByRole('button', { name: /Fabrikam Legal/ });
        card.focus();
        await userEvent.keyboard('{Enter}');
        expect(handleClick).toHaveBeenCalledWith(tier3FullItem.id);
    });
});
