import * as React from "react";
import { useState, useCallback, useRef, useEffect } from "react";
import type { OrchestratorResponse, CommandCardLink } from "./types";

interface CommandBarProps {
    currentCardId: string | null;
    onExecuteCommand: (command: string, currentCardId: string | null) => void;
    onJumpToCard: (cardId: string) => void;
    /** The latest response from the orchestrator, passed down from the Canvas app */
    lastResponse: OrchestratorResponse | null;
    /** Whether a command is currently being processed */
    isProcessing: boolean;
}

const QUICK_ACTIONS = [
    { label: "What's urgent?", command: "What needs my attention right now?" },
    { label: "Draft status", command: "Show me all cards with drafts ready to send" },
    { label: "My day", command: "What should I focus on today?" },
];

interface ConversationEntry {
    role: "user" | "assistant";
    text: string;
    cardLinks?: CommandCardLink[];
    timestamp: Date;
}

export const CommandBar: React.FC<CommandBarProps> = ({
    currentCardId,
    onExecuteCommand,
    onJumpToCard,
    lastResponse,
    isProcessing,
}) => {
    const [inputText, setInputText] = useState("");
    const [conversation, setConversation] = useState<ConversationEntry[]>([]);
    const [isExpanded, setIsExpanded] = useState(false);
    const responseRef = useRef<HTMLDivElement>(null);
    const inputRef = useRef<HTMLInputElement>(null);

    // When a new response arrives, add it to conversation history
    useEffect(() => {
        if (lastResponse && !isProcessing) {
            setConversation((prev) => {
                // Avoid duplicating the same response
                const lastEntry = prev[prev.length - 1];
                if (
                    lastEntry?.role === "assistant" &&
                    lastEntry.text === lastResponse.response_text
                ) {
                    return prev;
                }
                return [
                    ...prev,
                    {
                        role: "assistant",
                        text: lastResponse.response_text,
                        cardLinks: lastResponse.card_links,
                        timestamp: new Date(),
                    },
                ];
            });
        }
    }, [lastResponse, isProcessing]);

    // Auto-scroll response panel when new entries are added
    useEffect(() => {
        if (responseRef.current) {
            responseRef.current.scrollTop = responseRef.current.scrollHeight;
        }
    }, [conversation]);

    const handleSubmit = useCallback(() => {
        const trimmed = inputText.trim();
        if (!trimmed || isProcessing) return;

        setConversation((prev) => [
            ...prev,
            { role: "user", text: trimmed, timestamp: new Date() },
        ]);
        setInputText("");
        setIsExpanded(true);
        onExecuteCommand(trimmed, currentCardId);
    }, [inputText, isProcessing, currentCardId, onExecuteCommand]);

    const handleKeyDown = useCallback(
        (e: React.KeyboardEvent) => {
            if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                handleSubmit();
            }
        },
        [handleSubmit],
    );

    const handleQuickAction = useCallback(
        (command: string) => {
            setConversation((prev) => [
                ...prev,
                { role: "user", text: command, timestamp: new Date() },
            ]);
            setIsExpanded(true);
            onExecuteCommand(command, currentCardId);
        },
        [currentCardId, onExecuteCommand],
    );

    const handleClear = useCallback(() => {
        setConversation([]);
        setIsExpanded(false);
    }, []);

    return (
        <div className={`command-bar ${isExpanded ? "command-bar-expanded" : ""}`}>
            {/* Response panel (visible when conversation exists) */}
            {isExpanded && conversation.length > 0 && (
                <div className="command-response-panel" ref={responseRef}>
                    {conversation.map((entry, i) => (
                        <div
                            key={i}
                            className={`command-entry command-entry-${entry.role}`}
                        >
                            <div className="command-entry-text">
                                {entry.text}
                            </div>
                            {entry.cardLinks &&
                                entry.cardLinks.length > 0 && (
                                    <div className="command-card-links">
                                        {entry.cardLinks.map((link) => (
                                            <button
                                                key={link.card_id}
                                                className="command-card-link"
                                                onClick={() =>
                                                    onJumpToCard(link.card_id)
                                                }
                                            >
                                                {link.label} →
                                            </button>
                                        ))}
                                    </div>
                                )}
                        </div>
                    ))}
                    {isProcessing && (
                        <div className="command-entry command-entry-assistant command-thinking">
                            Thinking...
                        </div>
                    )}
                </div>
            )}

            {/* Input row */}
            <div className="command-input-row">
                <input
                    ref={inputRef}
                    type="text"
                    className="command-input"
                    placeholder={
                        currentCardId
                            ? "Ask about this card or type a command..."
                            : "Type a command..."
                    }
                    value={inputText}
                    onChange={(e) => setInputText(e.target.value)}
                    onKeyDown={handleKeyDown}
                    disabled={isProcessing}
                />
                <button
                    className="command-send-button"
                    onClick={handleSubmit}
                    disabled={!inputText.trim() || isProcessing}
                >
                    {isProcessing ? "..." : "Send"}
                </button>
                {conversation.length > 0 && (
                    <button
                        className="command-clear-button"
                        onClick={handleClear}
                        title="Clear conversation"
                    >
                        ✕
                    </button>
                )}
            </div>

            {/* Quick actions (visible when not expanded and not processing) */}
            {!isExpanded && !isProcessing && (
                <div className="command-quick-actions">
                    {QUICK_ACTIONS.map((qa) => (
                        <button
                            key={qa.label}
                            className="command-quick-chip"
                            onClick={() => handleQuickAction(qa.command)}
                        >
                            {qa.label}
                        </button>
                    ))}
                </div>
            )}
        </div>
    );
};
