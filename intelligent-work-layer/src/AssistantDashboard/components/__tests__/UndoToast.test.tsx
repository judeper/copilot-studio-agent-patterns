import * as React from 'react';
import { screen, act } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { UndoToast } from '../UndoToast';
import { renderWithProviders } from '../../../test/helpers/renderWithProviders';

describe('UndoToast', () => {
    beforeEach(() => {
        jest.useFakeTimers();
    });

    afterEach(() => {
        jest.useRealTimers();
    });

    it('renders message text', () => {
        renderWithProviders(
            <UndoToast
                message="Card dismissed"
                onUndo={jest.fn()}
                onExpire={jest.fn()}
            />
        );

        expect(screen.getByText('Card dismissed')).toBeInTheDocument();
    });

    it('renders Undo button', () => {
        renderWithProviders(
            <UndoToast
                message="Card dismissed"
                onUndo={jest.fn()}
                onExpire={jest.fn()}
            />
        );

        expect(screen.getByText('Undo')).toBeInTheDocument();
    });

    it('calls onUndo when Undo clicked', async () => {
        const handleUndo = jest.fn();
        const user = userEvent.setup({ advanceTimers: jest.advanceTimersByTime });
        renderWithProviders(
            <UndoToast
                message="Card dismissed"
                onUndo={handleUndo}
                onExpire={jest.fn()}
            />
        );

        await user.click(screen.getByText('Undo'));
        expect(handleUndo).toHaveBeenCalledTimes(1);
    });

    it('calls onExpire after 10 seconds', () => {
        const handleExpire = jest.fn();
        renderWithProviders(
            <UndoToast
                message="Card dismissed"
                onUndo={jest.fn()}
                onExpire={handleExpire}
            />
        );

        expect(handleExpire).not.toHaveBeenCalled();

        // Advance past the 10s timeout — the component uses 100ms intervals
        act(() => {
            jest.advanceTimersByTime(10_100);
        });

        expect(handleExpire).toHaveBeenCalledTimes(1);
    });
});
