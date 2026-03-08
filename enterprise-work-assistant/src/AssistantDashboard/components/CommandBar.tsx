import * as React from "react";
import { useState, useCallback, useRef, useEffect } from "react";
import { Button, Input, Spinner, Text } from "@fluentui/react-components";
import { SendRegular, DismissCircleRegular } from "@fluentui/react-icons";
import type { OrchestratorResponse, CommandCardLink } from "./types";
import { DEFAULT_COMMAND_CHIPS, DETAIL_COMMAND_CHIPS } from "./constants";
import { focusAfterRender } from "../utils/focusUtils";

interface CommandBarProps {
    currentCardId: string | null;
    /** ID of the currently selected/open card in the detail panel */
    selectedCardId: string | null;
    onExecuteCommand: (command: string, currentCardId: string | null) => void;
    onJumpToCard: (cardId: string) => void;
    /** The latest response from the orchestrator, passed down from the Canvas app */
    lastResponse: OrchestratorResponse | null;
    /** Whether a command is currently being processed */
    isProcessing: boolean;
}

interface ConversationEntry {
    role: "user" | "assistant";
    text: string;
    cardLinks?: CommandCardLink[];
    timestamp: Date;
}

type FocusableButtonElement = HTMLButtonElement | HTMLAnchorElement;

type FocusRestoreTarget =
    | { type: "input" }
    | { type: "send" };

export const CommandBar: React.FC<CommandBarProps> = ({
    currentCardId,
    selectedCardId,
    onExecuteCommand,
    onJumpToCard,
    lastResponse,
    isProcessing,
}) => {
    const [inputText, setInputText] = useState("");
    const [conversation, setConversation] = useState<ConversationEntry[]>([]);
    const [isExpanded, setIsExpanded] = useState(false);
    const [collapsed, setCollapsed] = useState(true);
    const responseRef = useRef<HTMLDivElement>(null);
    const inputRef = useRef<HTMLInputElement>(null);
    const sendButtonRef = useRef<FocusableButtonElement>(null);
    const focusRestoreTargetRef = useRef<FocusRestoreTarget | null>(null);

    const restoreFocus = useCallback(() => {
        const target = focusRestoreTargetRef.current;
        if (!target) return;
        focusAfterRender(() => {
            const element =
                target.type === "input"
                    ? inputRef.current
                    : sendButtonRef.current;
            element?.focus();
        });
        focusRestoreTargetRef.current = null;
    }, []);

    const rememberSubmitFocusTarget = useCallback(() => {
        if (typeof document === "undefined" || document.activeElement !== sendButtonRef.current) {
            focusRestoreTargetRef.current = { type: "input" };
            return;
        }
        focusRestoreTargetRef.current = { type: "send" };
    }, []);

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

    useEffect(() => {
        if (!isExpanded) {
            restoreFocus();
            return;
        }
        focusAfterRender(() => inputRef.current?.focus());
    }, [isExpanded, restoreFocus]);

    useEffect(() => {
        if (collapsed) return;
        const handleEscapeKey = (e: KeyboardEvent) => {
            if (e.defaultPrevented || e.key !== "Escape") return;
            e.preventDefault();
            e.stopPropagation();
            setIsExpanded(false);
            setCollapsed(true);
        };
        document.addEventListener("keydown", handleEscapeKey, true);
        return () => document.removeEventListener("keydown", handleEscapeKey, true);
    }, [collapsed]);

    const handleSubmit = useCallback(() => {
        const trimmed = inputText.trim();
        if (!trimmed || isProcessing) return;

        rememberSubmitFocusTarget();
        setConversation((prev) => [
            ...prev,
            { role: "user", text: trimmed, timestamp: new Date() },
        ]);
        setInputText("");
        setCollapsed(false);
        setIsExpanded(true);
        onExecuteCommand(trimmed, currentCardId);
    }, [inputText, isProcessing, currentCardId, onExecuteCommand, rememberSubmitFocusTarget]);

    const handleKeyDown = useCallback(
        (e: React.KeyboardEvent) => {
            if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                handleSubmit();
            }
        },
        [handleSubmit],
    );

    const handleClear = useCallback(() => {
        focusRestoreTargetRef.current = null;
        setConversation([]);
        setIsExpanded(false);
        setCollapsed(true);
    }, []);

    const handlePillClick = useCallback(() => {
        setCollapsed(false);
        focusAfterRender(() => inputRef.current?.focus());
    }, []);

    const handleChipClick = useCallback(
        (chipText: string) => {
            setConversation((prev) => [
                ...prev,
                { role: "user", text: chipText, timestamp: new Date() },
            ]);
            setCollapsed(false);
            setIsExpanded(true);
            onExecuteCommand(chipText, currentCardId);
        },
        [currentCardId, onExecuteCommand],
    );

    const contextChips = selectedCardId ? DETAIL_COMMAND_CHIPS : DEFAULT_COMMAND_CHIPS;

    // Show collapsed pill when no conversation and not processing
    if (collapsed && !isProcessing) {
        return (
            <div
                className="command-bar-pill"
                onClick={handlePillClick}
                role="button"
                tabIndex={0}
                onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                        e.preventDefault();
                        handlePillClick();
                    }
                }}
            >
                ⚡ Ask EWA...
            </div>
        );
    }

    return (
        <div className={`command-bar command-bar-expanded`}>
            {/* Response panel (visible when conversation exists) */}
            {isExpanded && conversation.length > 0 && (
                <div className="command-response-panel" ref={responseRef} aria-live="polite">
                    {conversation.map((entry, i) => (
                        <div
                            key={i}
                            className={`command-entry command-entry-${entry.role}`}
                        >
                            <div className="command-entry-text">
                                <Text block>{entry.text}</Text>
                            </div>
                            {entry.cardLinks &&
                                entry.cardLinks.length > 0 && (
                                    <div className="command-card-links">
                                        {entry.cardLinks.map((link) => (
                                            <Button
                                                key={link.card_id}
                                                appearance="transparent"
                                                size="small"
                                                onClick={() =>
                                                    onJumpToCard(link.card_id)
                                                }
                                            >
                                                {link.label} →
                                            </Button>
                                        ))}
                                    </div>
                                )}
                        </div>
                    ))}
                    {isProcessing && (
                        <div className="command-entry command-entry-assistant command-thinking">
                            <Spinner size="tiny" label="Thinking..." labelPosition="after" />
                        </div>
                    )}
                </div>
            )}

            {/* Input row */}
            <div className="command-input-row">
                <Input
                    className="command-input"
                    ref={inputRef}
                    placeholder={
                        currentCardId
                            ? "Ask about this card or type a command..."
                            : "Type a command..."
                    }
                    value={inputText}
                    onChange={(_e, data) => setInputText(data.value)}
                    onKeyDown={handleKeyDown}
                    disabled={isProcessing}
                />
                <Button
                    appearance="primary"
                    icon={<SendRegular />}
                    onClick={handleSubmit}
                    ref={sendButtonRef}
                    disabled={!inputText.trim() || isProcessing}
                    size="small"
                >
                    {isProcessing ? "..." : "Send"}
                </Button>
                {conversation.length > 0 && (
                    <Button
                        appearance="subtle"
                        icon={<DismissCircleRegular />}
                        onClick={handleClear}
                        title="Clear conversation"
                        size="small"
                    />
                )}
            </div>

            {/* Context-aware quick chips */}
            {!isExpanded && !isProcessing && (
                <div className="quick-chips">
                    {contextChips.map((chip) => (
                        <button
                            key={chip}
                            className="quick-chip"
                            onClick={() => handleChipClick(chip)}
                        >
                            {chip}
                        </button>
                    ))}
                </div>
            )}


        </div>
    );
};
