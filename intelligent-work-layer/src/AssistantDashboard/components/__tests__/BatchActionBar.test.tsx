import * as React from 'react';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { BatchActionBar } from '../BatchActionBar';
import { renderWithProviders } from '../../../test/helpers/renderWithProviders';

describe('BatchActionBar', () => {
    it('renders nothing when selectedCount is 0', () => {
        const { container } = renderWithProviders(
            <BatchActionBar
                selectedCount={0}
                onDismissAll={jest.fn()}
                onSnoozeAll={jest.fn()}
                onClearSelection={jest.fn()}
            />
        );

        expect(container.querySelector('.batch-action-bar')).toBeNull();
    });

    it('renders count badge and buttons when selectedCount > 0', () => {
        renderWithProviders(
            <BatchActionBar
                selectedCount={3}
                onDismissAll={jest.fn()}
                onSnoozeAll={jest.fn()}
                onClearSelection={jest.fn()}
            />
        );

        expect(screen.getByText('3')).toBeInTheDocument();
        expect(screen.getByText('selected')).toBeInTheDocument();
        expect(screen.getByText('Dismiss All')).toBeInTheDocument();
        expect(screen.getByText('Snooze All')).toBeInTheDocument();
        expect(screen.getByText('Cancel')).toBeInTheDocument();
    });

    it('calls onDismissAll when Dismiss All clicked', async () => {
        const handleDismissAll = jest.fn();
        renderWithProviders(
            <BatchActionBar
                selectedCount={5}
                onDismissAll={handleDismissAll}
                onSnoozeAll={jest.fn()}
                onClearSelection={jest.fn()}
            />
        );

        await userEvent.click(screen.getByText('Dismiss All'));
        expect(handleDismissAll).toHaveBeenCalledTimes(1);
    });

    it('calls onSnoozeAll when Snooze All clicked', async () => {
        const handleSnoozeAll = jest.fn();
        renderWithProviders(
            <BatchActionBar
                selectedCount={5}
                onDismissAll={jest.fn()}
                onSnoozeAll={handleSnoozeAll}
                onClearSelection={jest.fn()}
            />
        );

        await userEvent.click(screen.getByText('Snooze All'));
        expect(handleSnoozeAll).toHaveBeenCalledTimes(1);
    });

    it('calls onClearSelection when Cancel clicked', async () => {
        const handleClear = jest.fn();
        renderWithProviders(
            <BatchActionBar
                selectedCount={5}
                onDismissAll={jest.fn()}
                onSnoozeAll={jest.fn()}
                onClearSelection={handleClear}
            />
        );

        await userEvent.click(screen.getByText('Cancel'));
        expect(handleClear).toHaveBeenCalledTimes(1);
    });

    it('disables Dismiss All and Snooze All when count > 25', () => {
        renderWithProviders(
            <BatchActionBar
                selectedCount={30}
                onDismissAll={jest.fn()}
                onSnoozeAll={jest.fn()}
                onClearSelection={jest.fn()}
            />
        );

        expect(screen.getByText('Dismiss All').closest('button')).toBeDisabled();
        expect(screen.getByText('Snooze All').closest('button')).toBeDisabled();
        expect(screen.getByText('Cancel').closest('button')).not.toBeDisabled();
    });
});
