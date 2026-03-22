import * as React from "react";

interface KeyboardNavigationOptions {
    cardIds: string[];
    selectedCardId: string | null;
    onSelectCard: (cardId: string) => void;
    onDismissCard: (cardId: string) => void;
    onSnoozeCard?: (cardId: string, snoozeUntil: string) => void;
    onShowHelp: () => void;
    enabled: boolean;
}

/**
 * Keyboard shortcuts for the card gallery.
 * j/k = next/prev card, Enter = open, d = dismiss, s = snooze,
 * / = focus command bar, ? = show help overlay.
 * Disabled when input/textarea/contentEditable is focused.
 */
export function useKeyboardNavigation({
    cardIds,
    selectedCardId,
    onSelectCard,
    onDismissCard,
    onSnoozeCard,
    onShowHelp,
    enabled,
}: KeyboardNavigationOptions): void {
    React.useEffect(() => {
        if (!enabled) return;
        // Phase 6: Disable keyboard nav on touch devices
        if (typeof window !== "undefined" && window.matchMedia?.("(pointer: coarse)").matches) return;

        const handler = (e: KeyboardEvent) => {
            const target = e.target as HTMLElement | null;
            if (!target || !target.tagName) return;
            const tagName = target.tagName.toLowerCase();
            if (tagName === "input" || tagName === "textarea" || target.isContentEditable) {
                return;
            }

            switch (e.key) {
                case "j": {
                    e.preventDefault();
                    if (cardIds.length === 0) return;
                    const currentIdx = selectedCardId ? cardIds.indexOf(selectedCardId) : -1;
                    const nextIdx = Math.min(currentIdx + 1, cardIds.length - 1);
                    onSelectCard(cardIds[nextIdx]);
                    break;
                }
                case "k": {
                    e.preventDefault();
                    if (cardIds.length === 0) return;
                    const currentIdx = selectedCardId ? cardIds.indexOf(selectedCardId) : 0;
                    const prevIdx = Math.max(currentIdx - 1, 0);
                    onSelectCard(cardIds[prevIdx]);
                    break;
                }
                case "d": {
                    e.preventDefault();
                    if (selectedCardId) {
                        onDismissCard(selectedCardId);
                    }
                    break;
                }
                case "s": {
                    e.preventDefault();
                    if (selectedCardId && onSnoozeCard) {
                        const tomorrow = new Date();
                        tomorrow.setDate(tomorrow.getDate() + 1);
                        tomorrow.setHours(9, 0, 0, 0);
                        onSnoozeCard(selectedCardId, tomorrow.toISOString());
                    }
                    break;
                }
                case "/": {
                    e.preventDefault();
                    const commandInput = document.querySelector<HTMLInputElement>(".command-bar-input input");
                    commandInput?.focus();
                    break;
                }
                case "?": {
                    e.preventDefault();
                    onShowHelp();
                    break;
                }
            }
        };

        document.addEventListener("keydown", handler);
        return () => document.removeEventListener("keydown", handler);
    }, [enabled, cardIds, selectedCardId, onSelectCard, onDismissCard, onSnoozeCard, onShowHelp]);
}
