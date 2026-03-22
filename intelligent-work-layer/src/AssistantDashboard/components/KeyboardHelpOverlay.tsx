import * as React from "react";
import { Button, Text } from "@fluentui/react-components";
import { DismissRegular } from "@fluentui/react-icons";

interface KeyboardHelpOverlayProps {
    isOpen: boolean;
    onClose: () => void;
}

const SHORTCUTS = [
    { key: "j", description: "Next card" },
    { key: "k", description: "Previous card" },
    { key: "Enter", description: "Open card detail" },
    { key: "Escape", description: "Close detail / panel" },
    { key: "d", description: "Dismiss selected card" },
    { key: "s", description: "Snooze selected card" },
    { key: "/", description: "Focus command bar" },
    { key: "?", description: "Show this help" },
];

export const KeyboardHelpOverlay: React.FC<KeyboardHelpOverlayProps> = ({ isOpen, onClose }) => {
    React.useEffect(() => {
        if (!isOpen) return;
        const handler = (e: KeyboardEvent) => {
            if (e.key === "Escape") {
                e.preventDefault();
                onClose();
            }
        };
        document.addEventListener("keydown", handler);
        return () => document.removeEventListener("keydown", handler);
    }, [isOpen, onClose]);

    if (!isOpen) return null;

    return (
        <div
            className="keyboard-help-backdrop"
            onClick={onClose}
            role="dialog"
            aria-label="Keyboard shortcuts"
            aria-modal="true"
        >
            <div
                className="keyboard-help-panel"
                onClick={(e) => e.stopPropagation()}
            >
                <div className="keyboard-help-header">
                    <Text as="h2" size={500} weight="semibold">
                        Keyboard Shortcuts
                    </Text>
                    <Button
                        appearance="subtle"
                        icon={<DismissRegular />}
                        onClick={onClose}
                        aria-label="Close"
                    />
                </div>
                <table className="keyboard-help-table">
                    <tbody>
                        {SHORTCUTS.map((s) => (
                            <tr key={s.key}>
                                <td>
                                    <kbd className="keyboard-help-key">{s.key}</kbd>
                                </td>
                                <td>
                                    <Text size={300}>{s.description}</Text>
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </div>
    );
};
