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
import { tokens } from "@fluentui/react-components";
import { ArrowLeftRegular } from "@fluentui/react-icons";
import type { AssistantCard, DraftPayload } from "./types";

interface CardDetailProps {
    card: AssistantCard;
    onBack: () => void;
    onEditDraft: (cardId: string) => void;
    onDismissCard: (cardId: string) => void;
}

const priorityColors: Record<string, string> = {
    High: tokens.colorPaletteRedBorder2,
    Medium: tokens.colorPaletteMarigoldBorder2,
    Low: tokens.colorPaletteGreenBorder2,
    "N/A": tokens.colorNeutralStroke1,
};

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

export const CardDetail: React.FC<CardDetailProps> = ({
    card,
    onBack,
    onEditDraft,
    onDismissCard,
}) => {
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
                <Badge
                    appearance="filled"
                    style={{ backgroundColor: priorityColors[card.priority] }}
                    size="medium"
                >
                    {card.priority}
                </Badge>
                {card.confidence_score !== null && (
                    <Badge appearance="outline" size="medium">
                        Confidence: {card.confidence_score}%
                    </Badge>
                )}
                <Badge appearance="outline" size="medium">
                    {card.trigger_type}
                </Badge>
                {card.temporal_horizon !== "N/A" && (
                    <Badge appearance="tint" size="medium">
                        {card.temporal_horizon}
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
                                <Link
                                    href={/^https?:\/\//.test(source.url) ? source.url : "#"}
                                    target="_blank"
                                    rel="noopener noreferrer"
                                >
                                    {source.title}
                                </Link>
                                <Badge appearance="outline" size="small" className="source-tier-badge">
                                    Tier {source.tier}
                                </Badge>
                            </li>
                        ))}
                    </ul>
                </section>
            )}

            {/* Draft section */}
            {card.draft_payload && card.draft_payload !== "N/A" && (
                <section className="card-detail-section">
                    <Text as="h3" size={400} weight="semibold" block>
                        {card.humanized_draft ? "Humanized Draft" : "Draft"}
                    </Text>
                    {card.humanized_draft ? (
                        <Textarea
                            className="card-detail-draft"
                            value={card.humanized_draft}
                            resize="vertical"
                            readOnly
                            onChange={() => { /* readOnly — no-op to satisfy React controlled component */ }}
                        />
                    ) : isDraftPayloadObject(card.draft_payload) ? (
                        <div className="card-detail-draft-pending">
                            <Spinner size="small" label="Humanizing..." />
                            <Textarea
                                className="card-detail-draft"
                                value={card.draft_payload.raw_draft}
                                resize="vertical"
                                readOnly
                            />
                        </div>
                    ) : (
                        /* Plain text briefing (CALENDAR_SCAN) */
                        <pre className="card-detail-briefing">{card.draft_payload as string}</pre>
                    )}
                </section>
            )}

            {/* Action buttons */}
            <div className="card-detail-actions">
                {card.draft_payload && card.draft_payload !== "N/A" && (
                    <Button appearance="primary" onClick={() => onEditDraft(card.id)}>
                        Edit & Copy Draft
                    </Button>
                )}
                <Button appearance="secondary" onClick={() => onDismissCard(card.id)}>
                    Dismiss Card
                </Button>
            </div>
        </div>
    );
};
