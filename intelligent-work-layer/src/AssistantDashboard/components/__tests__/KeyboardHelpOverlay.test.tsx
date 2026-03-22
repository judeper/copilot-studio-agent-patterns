import * as React from 'react';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { KeyboardHelpOverlay } from '../KeyboardHelpOverlay';
import { renderWithProviders } from '../../../test/helpers/renderWithProviders';

describe('KeyboardHelpOverlay', () => {
    it('renders nothing when isOpen is false', () => {
        const { container } = renderWithProviders(
            <KeyboardHelpOverlay isOpen={false} onClose={jest.fn()} />
        );

        expect(container.querySelector('.keyboard-help-backdrop')).toBeNull();
    });

    it('renders shortcut table when isOpen is true', () => {
        renderWithProviders(
            <KeyboardHelpOverlay isOpen={true} onClose={jest.fn()} />
        );

        expect(screen.getByText('Keyboard Shortcuts')).toBeInTheDocument();
        expect(screen.getByRole('dialog')).toBeInTheDocument();
    });

    it('shows all 8 keyboard shortcuts', () => {
        renderWithProviders(
            <KeyboardHelpOverlay isOpen={true} onClose={jest.fn()} />
        );

        const expectedShortcuts = [
            { key: 'j', description: 'Next card' },
            { key: 'k', description: 'Previous card' },
            { key: 'Enter', description: 'Open card detail' },
            { key: 'Escape', description: 'Close detail / panel' },
            { key: 'd', description: 'Dismiss selected card' },
            { key: 's', description: 'Snooze selected card' },
            { key: '/', description: 'Focus command bar' },
            { key: '?', description: 'Show this help' },
        ];

        for (const shortcut of expectedShortcuts) {
            expect(screen.getByText(shortcut.key)).toBeInTheDocument();
            expect(screen.getByText(shortcut.description)).toBeInTheDocument();
        }
    });

    it('calls onClose when Escape pressed', async () => {
        const handleClose = jest.fn();
        renderWithProviders(
            <KeyboardHelpOverlay isOpen={true} onClose={handleClose} />
        );

        await userEvent.keyboard('{Escape}');
        expect(handleClose).toHaveBeenCalledTimes(1);
    });

    it('calls onClose when backdrop clicked', async () => {
        const handleClose = jest.fn();
        renderWithProviders(
            <KeyboardHelpOverlay isOpen={true} onClose={handleClose} />
        );

        // Click the backdrop (dialog element), not the inner panel
        await userEvent.click(screen.getByRole('dialog'));
        expect(handleClose).toHaveBeenCalledTimes(1);
    });
});
