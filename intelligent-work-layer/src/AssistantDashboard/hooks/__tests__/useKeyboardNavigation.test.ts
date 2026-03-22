import { renderHook } from '@testing-library/react';
import { useKeyboardNavigation } from '../useKeyboardNavigation';

function fireKey(key: string, target?: HTMLElement) {
    const event = new KeyboardEvent('keydown', {
        key,
        bubbles: true,
        cancelable: true,
    });
    // Override the read-only target property
    Object.defineProperty(event, 'target', {
        value: target ?? document.body,
        writable: false,
    });
    document.dispatchEvent(event);
}

describe('useKeyboardNavigation', () => {
    const cardIds = ['card-1', 'card-2', 'card-3'];

    it('j key calls onSelectCard with next card', () => {
        const onSelectCard = jest.fn();
        renderHook(() =>
            useKeyboardNavigation({
                cardIds,
                selectedCardId: 'card-1',
                onSelectCard,
                onDismissCard: jest.fn(),
                onShowHelp: jest.fn(),
                enabled: true,
            })
        );

        fireKey('j');
        expect(onSelectCard).toHaveBeenCalledWith('card-2');
    });

    it('k key calls onSelectCard with previous card', () => {
        const onSelectCard = jest.fn();
        renderHook(() =>
            useKeyboardNavigation({
                cardIds,
                selectedCardId: 'card-2',
                onSelectCard,
                onDismissCard: jest.fn(),
                onShowHelp: jest.fn(),
                enabled: true,
            })
        );

        fireKey('k');
        expect(onSelectCard).toHaveBeenCalledWith('card-1');
    });

    it('d key calls onDismissCard with selected card', () => {
        const onDismissCard = jest.fn();
        renderHook(() =>
            useKeyboardNavigation({
                cardIds,
                selectedCardId: 'card-2',
                onSelectCard: jest.fn(),
                onDismissCard,
                onShowHelp: jest.fn(),
                enabled: true,
            })
        );

        fireKey('d');
        expect(onDismissCard).toHaveBeenCalledWith('card-2');
    });

    it('does nothing when disabled', () => {
        const onSelectCard = jest.fn();
        const onDismissCard = jest.fn();
        renderHook(() =>
            useKeyboardNavigation({
                cardIds,
                selectedCardId: 'card-1',
                onSelectCard,
                onDismissCard,
                onShowHelp: jest.fn(),
                enabled: false,
            })
        );

        fireKey('j');
        fireKey('k');
        fireKey('d');
        expect(onSelectCard).not.toHaveBeenCalled();
        expect(onDismissCard).not.toHaveBeenCalled();
    });

    it('does nothing when target is an input element', () => {
        const onSelectCard = jest.fn();
        renderHook(() =>
            useKeyboardNavigation({
                cardIds,
                selectedCardId: 'card-1',
                onSelectCard,
                onDismissCard: jest.fn(),
                onShowHelp: jest.fn(),
                enabled: true,
            })
        );

        const input = document.createElement('input');
        document.body.appendChild(input);
        fireKey('j', input);
        document.body.removeChild(input);

        expect(onSelectCard).not.toHaveBeenCalled();
    });
});
