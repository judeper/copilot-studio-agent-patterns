import * as React from "react";
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
import { PRIORITY_COLORS } from "./constants";
import { isSafeUrl } from "../utils/urlSanitizer";

interface CardDetailProps {
    card: AssistantCard;
    onBack: () => void;
    onSendDraft: (cardId: string, finalText: string) => void;
    onCopyDraft: (cardId: string) => void;
    onDismissCard: (cardId: string) => void;
}

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

export const CardDetail: React.FC<CardDetailProps> = ({
    card,
    onBack,
    onSendDraft,
    onCopyDraft,
    onDismissCard,
}) => {
    const [localSendState, setLocalSendState] = React.useState<SendDisplayState>("idle");
    // Sprint 2: Inline editing state
    const [isEditing, setIsEditing] = React.useState(false);
    const [editedDraft, setEditedDraft] = React.useState(card.humanized_draft ?? "");

    // Derive effective send state: Dataverse outcome is authoritative over local state
    const effectiveSendState: SendDisplayState = React.useMemo(() => {
        if (card.card_outcome === "SENT_AS_IS" || card.card_outcome === "SENT_EDITED") {
            return "sent";
        }
        if (card.card_outcome === "DISMISSED") {
            return "idle"; // Dismissed cards show no send state
        }
        return localSendState;
    }, [card.card_outcome, localSendState]);

    // Reset local state when switching to a different card
    React.useEffect(() => {
        setLocalSendState("idle");
        setIsEditing(false);
        setEditedDraft(card.humanized_draft ?? "");
    }, [card.id, card.humanized_draft]);

    // Timeout: if stuck in "sending" for 60s, reset to idle
    React.useEffect(() => {
        if (localSendState === "sending") {
            const timer = setTimeout(() => {
                setLocalSendState("idle");
            }, 60_000);
            return () => clearTimeout(timer);
        }
    }, [localSendState]);

    // If the card outcome updated to SENT while we were in "sending", confirm it
    React.useEffect(() => {
        if (
            (card.card_outcome === "SENT_AS_IS" || card.card_outcome === "SENT_EDITED") &&
            localSendState === "sending"
        ) {
            setLocalSendState("sent");
        }
    }, [card.card_outcome, localSendState]);

    const handleSendClick = React.useCallback(() => {
        setLocalSendState("confirming");
    }, []);

    const handleConfirmSend = React.useCallback(() => {
        const finalText = isEditing ? editedDraft : card.humanized_draft;
        if (!finalText) return;
        setLocalSendState("sending");
        onSendDraft(card.id, finalText);
    }, [card.id, card.humanized_draft, editedDraft, isEditing, onSendDraft]);

    const handleCancelSend = React.useCallback(() => {
        setLocalSendState("idle");
    }, []);

    // Sprint 2: Enter edit mode
    const handleEditClick = React.useCallback(() => {
        setIsEditing(true);
        setEditedDraft(card.humanized_draft ?? "");
    }, [card.humanized_draft]);

    // Sprint 2: Cancel editing, revert to original
    const handleCancelEdit = React.useCallback(() => {
        setIsEditing(false);
        setEditedDraft(card.humanized_draft ?? "");
    }, [card.humanized_draft]);

    // Sprint 2: Track whether draft has been modified
    const draftIsModified = isEditing && editedDraft !== (card.humanized_draft ?? "");

    const handleCopy = React.useCallback(() => {
        onCopyDraft(card.id);
    }, [card.id, onCopyDraft]);

    const handleDismiss = React.useCallback(() => {
        onDismissCard(card.id);
    }, [card.id, onDismissCard]);

    const sendable = isSendable(card);
    const isDismissed = card.card_outcome === "DISMISSED";
    const isSent = effectiveSendState === "sent";

    return (
        <div className="card-detail">
            {/* Header */}
            <div className="card-detail-header">
                <Button
                    appearance="subtle"
                    icon={<ArrowLeftRegular />}
                    onClick={onBack}
                >
                    Back
                </Button>
            </div>

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
                {card.confidence_score !== null && (
                    <Badge appearance="outline" size="medium">
                        Confidence: {card.confidence_score}%
                    </Badge>
                )}
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

            {/* Key findings */}
            {card.key_findings && (
                <section className="card-detail-section">
                    <Text as="h3" size={400} weight="semibold" block>
                        Key Findings
                    </Text>
                    {renderKeyFindings(card.key_findings)}
                </section>
            )}

            {/* Research log */}
            {card.research_log && (
                <section className="card-detail-section">
                    <Text as="h3" size={400} weight="semibold" block>
                        Research Log
                    </Text>
                    <pre className="card-detail-research-log">{card.research_log}</pre>
                </section>
            )}

            {/* Verified sources */}
            {card.verified_sources && card.verified_sources.length > 0 && (
                <section className="card-detail-section">
                    <Text as="h3" size={400} weight="semibold" block>
                        Sources
                    </Text>
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
                </section>
            )}

            {/* Draft section */}
            {card.draft_payload && (
                <section className="card-detail-section">
                    <Text as="h3" size={400} weight="semibold" block>
                        {card.humanized_draft ? "Humanized Draft" : "Draft"}
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
                            <Text size={200} block style={{ color: "#6366f1" }}>
                                Draft has been modified from the original.
                            </Text>
                        )}
                    </div>
                    <div className="card-detail-confirm-actions">
                        <Button
                            appearance="primary"
                            icon={<SendRegular />}
                            onClick={handleConfirmSend}
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
            <div className="card-detail-actions">
                {/* Send button — EMAIL FULL cards with humanized draft only */}
                {sendable && !isSent && !isDismissed && (
                    <Button
                        appearance="primary"
                        icon={<SendRegular />}
                        onClick={handleSendClick}
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
