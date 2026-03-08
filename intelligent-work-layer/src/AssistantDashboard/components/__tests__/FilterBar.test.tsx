import * as React from 'react';
import { screen, act } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { FilterBar } from '../FilterBar';
import { renderWithProviders } from '../../../test/helpers/renderWithProviders';
import type { AssistantCard } from '../types';
import { tier3FullItem, tier2LightItem, calendarBriefingItem } from '../../../test/fixtures/cardFixtures';

const testCards: AssistantCard[] = [
    { ...tier3FullItem, id: 'email-1', trigger_type: 'EMAIL' },
    { ...tier2LightItem, id: 'teams-1', trigger_type: 'TEAMS_MESSAGE' },
    { ...calendarBriefingItem, id: 'cal-1', trigger_type: 'CALENDAR_SCAN' },
];

describe('FilterBar', () => {
    it('renders all chip buttons', () => {
        renderWithProviders(
            <FilterBar cards={testCards} onFilteredCards={jest.fn()} />
        );

        expect(screen.getByText('All')).toBeInTheDocument();
        expect(screen.getByText(/Email/)).toBeInTheDocument();
        expect(screen.getByText(/Teams/)).toBeInTheDocument();
        expect(screen.getByText(/Calendar/)).toBeInTheDocument();
        expect(screen.getByText(/Proactive/)).toBeInTheDocument();
        expect(screen.getByText(/Stale/)).toBeInTheDocument();
        expect(screen.getByText(/Newest/)).toBeInTheDocument();
    });

    it('calls onFilteredCards with all cards initially', () => {
        const handleFiltered = jest.fn();
        renderWithProviders(
            <FilterBar cards={testCards} onFilteredCards={handleFiltered} />
        );

        expect(handleFiltered).toHaveBeenCalled();
        const lastCall = handleFiltered.mock.calls[handleFiltered.mock.calls.length - 1][0];
        expect(lastCall).toHaveLength(3);
    });

    it('filters to email cards when Email chip clicked', async () => {
        const handleFiltered = jest.fn();
        renderWithProviders(
            <FilterBar cards={testCards} onFilteredCards={handleFiltered} />
        );

        await act(async () => {
            await userEvent.click(screen.getByText(/Email/));
        });

        const lastCall = handleFiltered.mock.calls[handleFiltered.mock.calls.length - 1][0];
        expect(lastCall).toHaveLength(1);
        expect(lastCall[0].trigger_type).toBe('EMAIL');
    });

    it('clicking All clears other filters', async () => {
        const handleFiltered = jest.fn();
        renderWithProviders(
            <FilterBar cards={testCards} onFilteredCards={handleFiltered} />
        );

        await act(async () => {
            await userEvent.click(screen.getByText(/Email/));
        });
        await act(async () => {
            await userEvent.click(screen.getByText('All'));
        });

        const lastCall = handleFiltered.mock.calls[handleFiltered.mock.calls.length - 1][0];
        expect(lastCall).toHaveLength(3);
    });

    it('cycles sort mode on sort button click', async () => {
        renderWithProviders(
            <FilterBar cards={testCards} onFilteredCards={jest.fn()} />
        );

        expect(screen.getByText(/Newest/)).toBeInTheDocument();
        await act(async () => {
            await userEvent.click(screen.getByText(/Newest/));
        });
        expect(screen.getByText(/Priority/)).toBeInTheDocument();
    });
});
