import React, { useState, useCallback, useMemo, useEffect, useRef } from 'react';
import {
    Button,
    Badge,
    Text,
    Link,
    Textarea,
    Spinner,
    MessageBar,
    MessageBarBody,
} from "@fluentui/react-components";
import {
    ArrowLeftRegular,
    SendRegular,
    CopyRegular,
    DismissRegular,
    CheckmarkCircleRegular,
} from "@fluentui/react-icons";
import type { AssistantCard, DraftPayload } from "./types";
import { PRIORITY_COLORS, EWA_COLORS, getConfidenceState } from "./constants";
import { isSafeUrl } from "../utils/urlSanitizer";
import { levenshteinRatio } from "../utils/levenshtein";
import { focusAfterRender } from "../utils/focusUtils";

interface CardDetailProps {
    card: AssistantCard;
    onBack: () => void;
    onClose?: () => void;
    onSendDraft: (cardId: string, finalText: string, editDistanceRatio: number) => void;
    onCopyDraft: (cardId: string) => void;
    onDismissCard: (cardId: string) => void;
    onSaveDraft: (cardId: string, editedText: string) => void;
}

const DetailSection: React.FC<{
    title: string;
    count?: number;
    defaultOpen?: boolean;
    children: React.ReactNode;
}> = ({ title, count, defaultOpen = false, children }) => {
    const [isOpen, setIsOpen] = useState(defaultOpen);
    return (
        <section className="detail-section">
            <button
                className="detail-section-toggle"
                onClick={() => setIsOpen(!isOpen)}
                aria-expanded={isOpen}
            >
                <span
                    className="detail-section-chevron"
                    style={{ transform: isOpen ? "rotate(90deg)" : undefined }}
                >
                    ›
                </span>
                <Text as="span" size={400} weight="semibold">
                    {title}
                </Text>
                {count !== undefined && (
                    <Badge appearance="outline" size="small" style={{ marginLeft: "6px" }}>
                        {count}
                    </Badge>
                )}
            </button>
            {isOpen && children}
        </section>
    );
};

/** Whether the card has a sendable EMAIL draft */
function isSendable(card: AssistantCard): boolean {
    return (
        card.trigger_type === "EMAIL" &&
        card.triage_tier === "FULL" &&
        card.card_status === "READY" &&
        card.humanized_draft !== null &&
        card.humanized_draft.length > 0 &&
        card.original_sender_email !== null &&
        card.original_sender_email.length > 0
    );
}

function isDraftPayloadObject(payload: unknown): payload is DraftPayload {
    return typeof payload === "object" && payload !== null && "raw_draft" in payload;
}

function renderKeyFindings(keyFindings: string): React.ReactElement {
    const lines = keyFindings
        .split(/\n|(?:^|\n)\s*[-*\u2022]\s*/)
        .map((line) => line.trim())
        .filter((line) => line.length > 0);

    return (
        <ul className="card-detail-findings">
            {lines.map((line, i) => (
                <li key={i}>{line}</li>
            ))}
        </ul>
    );
}

/**
 * Determine the send display state from the card's Dataverse-persisted outcome
 * combined with local optimistic state.
 */
type SendDisplayState = "idle" | "confirming" | "sending" | "sent";
type FocusableButtonElement = HTMLButtonElement | HTMLAnchorElement;

export const CardDetail: React.FC<CardDetailProps> = ({
    card,
    onBack,
    onClose,
    onSendDraft,
    onCopyDraft,
    onDismissCard,
    onSaveDraft,
}) => {
    const handleClose = onClose ?? onBack;
    const [localSendState, setLocalSendState] = useState<SendDisplayState>("idle");
    const [sendFeedback, setSendFeedback] = useState(false);
    // Sprint 2: Inline editing state
    const [isEditing, setIsEditing] = useState(false);
    const [editedDraft, setEditedDraft] = useState(card.humanized_draft ?? "");
    const editButtonRef = useRef<FocusableButtonElement>(null);
    const sendButtonRef = useRef<FocusableButtonElement>(null);
    const draftTextareaRef = useRef<HTMLTextAreaElement>(null);
    const confirmSendButtonRef = useRef<FocusableButtonElement>(null);

    const focusEditButton = useCallback(() => {
        focusAfterRender(() => editButtonRef.current?.focus());
    }, []);

    const focusSendButton = useCallback(() => {
        focusAfterRender(() => sendButtonRef.current?.focus());
    }, []);

    const closeEditMode = useCallback(
        (restoreFocus: boolean) => {
            setIsEditing(false);
            setEditedDraft(card.humanized_draft ?? "");
            if (restoreFocus) {
                focusEditButton();
            }
        },
        [card.humanized_draft, focusEditButton],
    );

    const closeConfirmPanel = useCallback(
        (restoreFocus: boolean) => {
            setLocalSendState("idle");
            if (restoreFocus) {
                focusSendButton();
            }
        },
        [focusSendButton],
    );

    // Derive effective send state: Dataverse outcome is authoritative over local state
    const effectiveSendState: SendDisplayState = useMemo(() => {
        if (card.card_outcome === "SENT_AS_IS" || card.card_outcome === "SENT_EDITED") {
            return "sent";
        }
        if (card.card_outcome === "DISMISSED") {
            return "idle"; // Dismissed cards show no send state
        }
        return localSendState;
    }, [card.card_outcome, localSendState]);

    // Reset local state when switching to a different card
    useEffect(() => {
        setLocalSendState("idle");
        setSendFeedback(false);
        setIsEditing(false);
        setEditedDraft(card.humanized_draft ?? "");
    }, [card.id, card.humanized_draft]);

    // Timeout: if stuck in "sending" for 60s, reset to idle
    useEffect(() => {
        if (localSendState === "sending") {
            const timer = setTimeout(() => {
                setLocalSendState("idle");
            }, 60_000);
            return () => clearTimeout(timer);
        }
    }, [localSendState]);

    // If the card outcome updated to SENT while we were in "sending", confirm it
    useEffect(() => {
        if (
            (card.card_outcome === "SENT_AS_IS" || card.card_outcome === "SENT_EDITED") &&
            localSendState === "sending"
        ) {
            setLocalSendState("sent");
        }
    }, [card.card_outcome, localSendState]);

    // Escape key: dismiss edit/confirm panel or navigate back
    useEffect(() => {
        const handleEscapeKey = (e: KeyboardEvent) => {
            if (e.defaultPrevented || e.key !== "Escape") return;
            e.preventDefault();
            if (isEditing) {
                closeEditMode(true);
            } else if (localSendState === "confirming") {
                closeConfirmPanel(true);
            } else {
                onBack();
            }
        };
        document.addEventListener("keydown", handleEscapeKey);
        return () => document.removeEventListener("keydown", handleEscapeKey);
    }, [closeConfirmPanel, closeEditMode, isEditing, localSendState, onBack]);

    useEffect(() => {
        if (isEditing) {
            focusAfterRender(() => {
                const textarea = draftTextareaRef.current;
                if (textarea) {
                    textarea.focus();
                    const text = textarea.value;
                    const greetingEnd = text.indexOf("\n\n");
                    if (greetingEnd !== -1) {
                        const pos = greetingEnd + 2;
                        textarea.setSelectionRange(pos, pos);
                    }
                }
            });
        }
    }, [isEditing]);

    useEffect(() => {
        if (effectiveSendState === "confirming") {
            focusAfterRender(() => confirmSendButtonRef.current?.focus());
        }
    }, [effectiveSendState]);

    const handleSendClick = useCallback(() => {
        setLocalSendState("confirming");
    }, []);

    const handleConfirmSend = useCallback(() => {
        const finalText = isEditing ? editedDraft : card.humanized_draft;
        if (!finalText) return;
        setLocalSendState("sending");
        const originalDraft = card.humanized_draft ?? "";
        const ratio = levenshteinRatio(originalDraft, finalText);
        onSendDraft(card.id, finalText, ratio);
        setSendFeedback(true);
        setTimeout(() => setSendFeedback(false), 2000);
    }, [card.id, card.humanized_draft, editedDraft, isEditing, onSendDraft]);

    const handleCancelSend = useCallback(() => {
        closeConfirmPanel(true);
    }, [closeConfirmPanel]);

    // Sprint 2: Enter edit mode
    const handleEditClick = useCallback(() => {
        setIsEditing(true);
        setEditedDraft(card.humanized_draft ?? "");
    }, [card.humanized_draft]);

    // Sprint 2: Cancel editing, revert to original
    const handleCancelEdit = useCallback(() => {
        closeEditMode(true);
    }, [closeEditMode]);

    // Sprint 2: Track whether draft has been modified
    const draftIsModified = isEditing && editedDraft !== (card.humanized_draft ?? "");

    // Phase 18: Persist edited draft to Dataverse with 2-second debounce
    useEffect(() => {
        if (!isEditing || !draftIsModified) return;
        const timer = setTimeout(() => {
            onSaveDraft(card.id, editedDraft);
        }, 2000);
        return () => clearTimeout(timer);
    }, [isEditing, draftIsModified, editedDraft, card.id, onSaveDraft]);

    const handleCopy = useCallback(() => {
        onCopyDraft(card.id);
    }, [card.id, onCopyDraft]);

    const handleDismiss = useCallback(() => {
        onDismissCard(card.id);
    }, [card.id, onDismissCard]);

    const sendable = isSendable(card);
    const isDismissed = card.card_outcome === "DISMISSED";
    const isSent = effectiveSendState === "sent";

    return (
        <div className="card-detail" role="region" aria-label="Card detail">
            {/* Header with back + close */}
            <div className="card-detail-header">
                <Button
                    appearance="subtle"
                    icon={<ArrowLeftRegular />}
                    onClick={onBack}
                >
                    Back
                </Button>
                <button
                    className="detail-close-btn"
                    onClick={handleClose}
                    aria-label="Close detail panel"
                >
                    ✕
                </button>
            </div>

            {/* Sender + age row */}
            {card.original_sender_display && (
                <Text size={300} block style={{ color: "#595959", marginBottom: "4px" }}>
                    {card.original_sender_display}
                    {card.created_on && (
                        <span style={{ marginLeft: "8px", color: "#767676" }}>
                            {card.created_on}
                        </span>
                    )}
                </Text>
            )}

            {/* Badges row */}
            <div className="card-detail-badges">
                {card.priority && (
                    <Badge
                        appearance="filled"
                        style={{ backgroundColor: PRIORITY_COLORS[card.priority] }}
                        size="medium"
                    >
                        {card.priority}
                    </Badge>
                )}
                {card.confidence_score !== null && (() => {
                    const cs = getConfidenceState(card.confidence_score!);
                    return (
                        <span
                            className="confidence-pill"
                            style={{ color: cs.color, backgroundColor: cs.bgColor }}
                        >
                            {cs.label}
                        </span>
                    );
                })()}
                <Badge appearance="outline" size="medium">
                    {card.trigger_type}
                </Badge>
                {card.temporal_horizon && (
                    <Badge appearance="tint" size="medium">
                        {card.temporal_horizon}
                    </Badge>
                )}
                {isSent && (
                    <Badge appearance="filled" size="medium" color="success">
                        Sent
                    </Badge>
                )}
                {isDismissed && (
                    <Badge appearance="filled" size="medium" color="subtle">
                        Dismissed
                    </Badge>
                )}
            </div>

            {/* Summary */}
            <Text as="h2" size={500} weight="semibold" block className="card-detail-summary">
                {card.item_summary}
            </Text>

            {/* Low confidence warning */}
            {card.card_status === "LOW_CONFIDENCE" && card.low_confidence_note && (
                <MessageBar intent="warning" className="card-detail-warning">
                    <MessageBarBody>{card.low_confidence_note}</MessageBarBody>
                </MessageBar>
            )}

            {/* Key findings — collapsible */}
            {card.key_findings && (
                <DetailSection
                    title="Key Findings"
                    count={
                        card.key_findings
                            .split(/\n|(?:^|\n)\s*[-*\u2022]\s*/)
                            .map((l) => l.trim())
                            .filter((l) => l.length > 0).length
                    }
                >
                    {renderKeyFindings(card.key_findings)}
                </DetailSection>
            )}

            {/* Research log — collapsible */}
            {card.research_log && (
                <DetailSection title="Research Log">
                    <pre className="card-detail-research-log">{card.research_log}</pre>
                </DetailSection>
            )}

            {/* Verified sources — collapsible */}
            {card.verified_sources && card.verified_sources.length > 0 && (
                <DetailSection title="Sources" count={card.verified_sources.length}>
                    <ul className="card-detail-sources">
                        {card.verified_sources.map((source, idx) => (
                            <li key={`${source.tier}-${idx}`}>
                                {isSafeUrl(source.url) ? (
                                    <Link
                                        href={source.url}
                                        target="_blank"
                                        rel="noopener noreferrer"
                                    >
                                        {source.title}
                                    </Link>
                                ) : (
                                    <Text>{source.title}</Text>
                                )}
                                <Badge appearance="outline" size="small" className="source-tier-badge">
                                    Tier {source.tier}
                                </Badge>
                            </li>
                        ))}
                    </ul>
                </DetailSection>
            )}

            {/* Draft section */}
            {card.draft_payload && (
                <section className="card-detail-section">
                    <Text as="h3" size={400} weight="semibold" block>
                        {card.humanized_draft ? "Your draft" : "Draft"}
                    </Text>
                    {card.humanized_draft ? (
                        <>
                            {/* Sprint 2: Edit bar above draft */}
                            {sendable && !isSent && !isDismissed && (
                                <div className="card-detail-edit-bar">
                                    {isEditing ? (
                                        <>
                                            <span className="card-detail-edit-indicator">
                                                Editing {draftIsModified ? "(modified)" : ""}
                                            </span>
                                            <Button
                                                appearance="subtle"
                                                size="small"
                                                onClick={handleCancelEdit}
                                            >
                                                Revert to original
                                            </Button>
                                        </>
                                    ) : (
                                        <Button
                                            appearance="subtle"
                                            ref={editButtonRef}
                                            size="small"
                                            onClick={handleEditClick}
                                        >
                                            Edit draft
                                        </Button>
                                    )}
                                </div>
                            )}
                            <Textarea
                                className={`card-detail-draft ${isEditing ? "card-detail-draft-editable" : ""}`}
                                ref={draftTextareaRef}
                                value={isEditing ? editedDraft : card.humanized_draft}
                                resize="vertical"
                                readOnly={!isEditing}
                                onChange={(_e, data) => {
                                    if (isEditing) setEditedDraft(data.value);
                                }}
                            />
                        </>
                    ) : isDraftPayloadObject(card.draft_payload) ? (
                        <div className="card-detail-draft-pending">
                            <Spinner size="small" label="Humanizing..." />
                            <Textarea
                                className="card-detail-draft"
                                value={card.draft_payload.raw_draft}
                                resize="vertical"
                                readOnly
                                onChange={() => { /* readOnly — no-op */ }}
                            />
                        </div>
                    ) : (
                        /* Plain text briefing (CALENDAR_SCAN) */
                        <pre className="card-detail-briefing">{card.draft_payload as string}</pre>
                    )}
                </section>
            )}

            {/* Inline confirmation panel — shown when user clicks Send */}
            {effectiveSendState === "confirming" && sendable && (
                <section className="card-detail-confirm-panel">
                    <Text as="p" size={300} weight="semibold" block>
                        Confirm send {draftIsModified ? "(edited)" : "(as-is)"}
                    </Text>
                    <div className="card-detail-confirm-details">
                        <Text size={200} block>
                            <strong>To:</strong>{" "}
                            {card.original_sender_display
                                ? `${card.original_sender_display} <${card.original_sender_email}>`
                                : card.original_sender_email}
                        </Text>
                        <Text size={200} block>
                            <strong>Subject:</strong> Re: {card.original_subject ?? "(no subject)"}
                        </Text>
                        {draftIsModified && (
                            <Text size={200} block style={{ color: EWA_COLORS.brand }}>
                                Draft has been modified from the original.
                            </Text>
                        )}
                    </div>
                    <div className="card-detail-confirm-actions">
                        <Button
                            appearance="primary"
                            icon={<SendRegular />}
                            onClick={handleConfirmSend}
                            ref={confirmSendButtonRef}
                        >
                            Confirm & Send
                        </Button>
                        <Button
                            appearance="secondary"
                            onClick={handleCancelSend}
                        >
                            Cancel
                        </Button>
                    </div>
                </section>
            )}

            {/* Sending state */}
            {effectiveSendState === "sending" && (
                <section className="card-detail-sending">
                    <Spinner size="small" label="Sending..." />
                </section>
            )}

            {/* Action buttons */}
            {sendFeedback && (
                <div className="send-feedback-message">Draft preference noted</div>
            )}
            <div className="card-detail-actions">
                {/* Send button — EMAIL FULL cards with humanized draft only */}
                {sendable && !isSent && !isDismissed && (
                    <Button
                        appearance="primary"
                        icon={<SendRegular />}
                        onClick={handleSendClick}
                        ref={sendButtonRef}
                        disabled={effectiveSendState !== "idle"}
                    >
                        Send
                    </Button>
                )}

                {/* Sent confirmation */}
                {isSent && (
                    <Button
                        appearance="primary"
                        icon={<CheckmarkCircleRegular />}
                        disabled
                    >
                        Sent
                    </Button>
                )}

                {/* Copy to Clipboard — available for any card with a draft */}
                {card.draft_payload && !isDismissed && (
                    <Button
                        appearance="secondary"
                        icon={<CopyRegular />}
                        onClick={handleCopy}
                    >
                        Copy to Clipboard
                    </Button>
                )}

                {/* Dismiss — available for any non-sent, non-dismissed card */}
                {!isSent && !isDismissed && (
                    <Button
                        appearance="subtle"
                        icon={<DismissRegular />}
                        onClick={handleDismiss}
                    >
                        Dismiss
                    </Button>
                )}
            </div>
        </div>
    );
};
