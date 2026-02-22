import * as React from 'react';
import { screen } from '@testing-library/react';
import { FilterBar } from '../FilterBar';
import { renderWithProviders } from '../../../test/helpers/renderWithProviders';

describe('FilterBar', () => {
    it('shows singular card count', () => {
        renderWithProviders(
            <FilterBar
                cardCount={1}
                filterTriggerType=""
                filterPriority=""
                filterCardStatus=""
                filterTemporalHorizon=""
            />
        );

        expect(screen.getByText('1 card')).toBeInTheDocument();
    });

    it('shows plural card count', () => {
        renderWithProviders(
            <FilterBar
                cardCount={5}
                filterTriggerType=""
                filterPriority=""
                filterCardStatus=""
                filterTemporalHorizon=""
            />
        );

        expect(screen.getByText('5 cards')).toBeInTheDocument();
    });

    it('shows active filter badges', () => {
        renderWithProviders(
            <FilterBar
                cardCount={3}
                filterTriggerType=""
                filterPriority="High"
                filterCardStatus=""
                filterTemporalHorizon=""
            />
        );

        expect(screen.getByText('High')).toBeInTheDocument();
    });

    it('shows multiple filter badges', () => {
        renderWithProviders(
            <FilterBar
                cardCount={1}
                filterTriggerType="EMAIL"
                filterPriority="High"
                filterCardStatus="READY"
                filterTemporalHorizon="TODAY"
            />
        );

        expect(screen.getByText('EMAIL')).toBeInTheDocument();
        expect(screen.getByText('High')).toBeInTheDocument();
        expect(screen.getByText('READY')).toBeInTheDocument();
        expect(screen.getByText('TODAY')).toBeInTheDocument();
    });

    it('hides filter badge area when no filters active', () => {
        const { container } = renderWithProviders(
            <FilterBar
                cardCount={0}
                filterTriggerType=""
                filterPriority=""
                filterCardStatus=""
                filterTemporalHorizon=""
            />
        );

        // The filter-bar-labels div should not exist when all filters are empty
        expect(container.querySelector('.filter-bar-labels')).toBeNull();
    });
});
