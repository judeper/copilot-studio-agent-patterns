import * as React from 'react';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { StatusBar } from '../StatusBar';
import { renderWithProviders } from '../../../test/helpers/renderWithProviders';

describe('StatusBar', () => {
    const defaultProps = {
        actionCount: 5,
        newCount: 2,
        memoryActive: true,
        onSettingsClick: jest.fn(),
    };

    beforeEach(() => {
        jest.clearAllMocks();
    });

    it('renders the "Work Layer" title', () => {
        renderWithProviders(<StatusBar {...defaultProps} />);

        expect(screen.getByText('Work Layer')).toBeInTheDocument();
    });

    it('displays the correct action count', () => {
        renderWithProviders(<StatusBar {...defaultProps} actionCount={12} />);

        expect(screen.getByText('12 decisions ready')).toBeInTheDocument();
    });

    it('sets aria-label with action count and new count', () => {
        renderWithProviders(
            <StatusBar {...defaultProps} actionCount={7} newCount={3} />
        );

        expect(
            screen.getByLabelText('7 decisions ready, 3 new')
        ).toBeInTheDocument();
    });

    it('shows memory active indicator when memoryActive is true', () => {
        renderWithProviders(<StatusBar {...defaultProps} memoryActive={true} />);

        expect(
            screen.getByLabelText('Semantic memory active')
        ).toBeInTheDocument();
    });

    it('shows memory inactive indicator when memoryActive is false', () => {
        renderWithProviders(<StatusBar {...defaultProps} memoryActive={false} />);

        expect(
            screen.getByLabelText('No knowledge facts loaded')
        ).toBeInTheDocument();
    });

    it('applies active CSS class when memoryActive is true', () => {
        renderWithProviders(<StatusBar {...defaultProps} memoryActive={true} />);

        const indicator = screen.getByLabelText('Semantic memory active');
        expect(indicator).toHaveClass('memory-icon-active');
    });

    it('applies inactive CSS class when memoryActive is false', () => {
        renderWithProviders(<StatusBar {...defaultProps} memoryActive={false} />);

        const indicator = screen.getByLabelText('No knowledge facts loaded');
        expect(indicator).toHaveClass('memory-icon');
        expect(indicator).not.toHaveClass('memory-icon-active');
    });

    it('renders a settings button with correct aria-label', () => {
        renderWithProviders(<StatusBar {...defaultProps} />);

        expect(screen.getByRole('button', { name: 'Settings' })).toBeInTheDocument();
    });

    it('fires onSettingsClick when settings button is clicked', async () => {
        const handleClick = jest.fn();
        renderWithProviders(
            <StatusBar {...defaultProps} onSettingsClick={handleClick} />
        );

        await userEvent.click(screen.getByRole('button', { name: 'Settings' }));
        expect(handleClick).toHaveBeenCalledTimes(1);
    });

    it('renders zero action count correctly', () => {
        renderWithProviders(
            <StatusBar {...defaultProps} actionCount={0} newCount={0} />
        );

        expect(screen.getByText('0 decisions ready')).toBeInTheDocument();
        expect(screen.getByLabelText('0 decisions ready, 0 new')).toBeInTheDocument();
    });
});
