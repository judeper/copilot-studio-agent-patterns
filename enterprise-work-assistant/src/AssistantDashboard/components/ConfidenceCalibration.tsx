import * as React from "react";
import { useState, useMemo } from "react";
import { Button, Text, Badge, Card, TabList, Tab, tokens } from "@fluentui/react-components";
import { ArrowLeftRegular } from "@fluentui/react-icons";
import type { AssistantCard } from "./types";

interface ConfidenceCalibrationProps {
    cards: AssistantCard[];
    onBack: () => void;
}

interface AccuracyBucket {
    range: string;
    total: number;
    acted: number;
    dismissed: number;
    accuracy: number;
}

interface SenderEngagement {
    email: string;
    display: string;
    signalCount: number;
    responseCount: number;
    responseRate: number;
}

/**
 * Sprint 4: Confidence Calibration Dashboard
 *
 * Analytics view showing how well the agent is performing:
 * - Predicted vs actual accuracy (confidence buckets)
 * - Triage accuracy (FULL cards acted on vs dismissed)
 * - Draft quality trend (edit distance over time)
 * - Top senders by engagement
 *
 * Data is computed client-side from the card dataset. For production use
 * with large datasets, this should be replaced with server-side aggregation.
 */
export const ConfidenceCalibration: React.FC<ConfidenceCalibrationProps> = ({
    cards,
    onBack,
}) => {
    const [activeTab, setActiveTab] = useState<"accuracy" | "triage" | "drafts" | "senders">("accuracy");

    // Filter to cards with outcomes (not PENDING)
    const resolvedCards = useMemo(
        () => cards.filter((c) => c.card_outcome !== "PENDING" && c.trigger_type !== "DAILY_BRIEFING"),
        [cards],
    );

    // 1. Confidence accuracy buckets
    const accuracyBuckets = useMemo((): AccuracyBucket[] => {
        const buckets: Record<string, { total: number; acted: number; dismissed: number }> = {
            "90-100": { total: 0, acted: 0, dismissed: 0 },
            "70-89": { total: 0, acted: 0, dismissed: 0 },
            "40-69": { total: 0, acted: 0, dismissed: 0 },
            "0-39": { total: 0, acted: 0, dismissed: 0 },
        };

        for (const card of resolvedCards) {
            if (card.confidence_score === null) continue;
            const score = card.confidence_score;
            const key = score >= 90 ? "90-100" : score >= 70 ? "70-89" : score >= 40 ? "40-69" : "0-39";
            buckets[key].total++;
            if (card.card_outcome === "SENT_AS_IS" || card.card_outcome === "SENT_EDITED") {
                buckets[key].acted++;
            } else if (card.card_outcome === "DISMISSED") {
                buckets[key].dismissed++;
            }
        }

        return Object.entries(buckets).map(([range, data]) => ({
            range,
            ...data,
            accuracy: data.total > 0 ? Math.round((data.acted / data.total) * 100) : 0,
        }));
    }, [resolvedCards]);

    // 2. Triage accuracy
    const triageStats = useMemo(() => {
        const fullCards = resolvedCards.filter((c) => c.triage_tier === "FULL");
        const fullActed = fullCards.filter(
            (c) => c.card_outcome === "SENT_AS_IS" || c.card_outcome === "SENT_EDITED",
        ).length;
        const fullDismissed = fullCards.filter((c) => c.card_outcome === "DISMISSED").length;

        const lightCards = resolvedCards.filter((c) => c.triage_tier === "LIGHT");
        const lightDismissed = lightCards.filter((c) => c.card_outcome === "DISMISSED").length;

        return {
            fullTotal: fullCards.length,
            fullActed,
            fullDismissed,
            fullAccuracy: fullCards.length > 0 ? Math.round((fullActed / fullCards.length) * 100) : 0,
            lightTotal: lightCards.length,
            lightDismissed,
            lightDismissRate: lightCards.length > 0 ? Math.round((lightDismissed / lightCards.length) * 100) : 0,
        };
    }, [resolvedCards]);

    // 3. Top senders by engagement
    const topSenders = useMemo((): SenderEngagement[] => {
        const senderMap = new Map<string, { display: string; signals: number; responses: number }>();

        for (const card of cards) {
            if (!card.original_sender_email) continue;
            const existing = senderMap.get(card.original_sender_email) ?? {
                display: card.original_sender_display ?? card.original_sender_email,
                signals: 0,
                responses: 0,
            };
            existing.signals++;
            if (card.card_outcome === "SENT_AS_IS" || card.card_outcome === "SENT_EDITED") {
                existing.responses++;
            }
            senderMap.set(card.original_sender_email, existing);
        }

        return Array.from(senderMap.entries())
            .map(([email, data]) => ({
                email,
                display: data.display,
                signalCount: data.signals,
                responseCount: data.responses,
                responseRate: data.signals > 0 ? Math.round((data.responses / data.signals) * 100) : 0,
            }))
            .sort((a, b) => b.signalCount - a.signalCount)
            .slice(0, 10);
    }, [cards]);

    // 4. Draft quality — sent-edited ratio
    const draftStats = useMemo(() => {
        const sentCards = resolvedCards.filter(
            (c) => c.card_outcome === "SENT_AS_IS" || c.card_outcome === "SENT_EDITED",
        );
        const asIs = sentCards.filter((c) => c.card_outcome === "SENT_AS_IS").length;
        const edited = sentCards.filter((c) => c.card_outcome === "SENT_EDITED").length;
        return {
            total: sentCards.length,
            asIs,
            edited,
            asIsRate: sentCards.length > 0 ? Math.round((asIs / sentCards.length) * 100) : 0,
        };
    }, [resolvedCards]);

    return (
        <div className="calibration-dashboard">
            <div className="calibration-header">
                <Button appearance="subtle" icon={<ArrowLeftRegular />} onClick={onBack}>
                    Back to Dashboard
                </Button>
                <Text as="h2" size={500} weight="semibold" block>Agent Performance</Text>
                <Badge appearance="outline" size="small">
                    Based on {resolvedCards.length} resolved card{resolvedCards.length !== 1 ? "s" : ""}
                </Badge>
            </div>

            {/* Tab bar */}
            <TabList
                selectedValue={activeTab}
                onTabSelect={(_e, data) => setActiveTab(data.value as typeof activeTab)}
            >
                <Tab value="accuracy">Confidence Accuracy</Tab>
                <Tab value="triage">Triage Quality</Tab>
                <Tab value="drafts">Draft Quality</Tab>
                <Tab value="senders">Top Senders</Tab>
            </TabList>

            {/* Tab content */}
            <div className="calibration-content">
                {activeTab === "accuracy" && (
                    <div className="calibration-section">
                        <Text block size={300} style={{ color: tokens.colorNeutralForeground2 }}>
                            Does higher confidence actually predict that you'll act on the card?
                            Each row shows cards in a confidence range and what percentage you responded to.
                        </Text>
                        <table className="calibration-table">
                            <thead>
                                <tr>
                                    <th>Confidence Range</th>
                                    <th>Cards</th>
                                    <th>Acted On</th>
                                    <th>Dismissed</th>
                                    <th>Action Rate</th>
                                </tr>
                            </thead>
                            <tbody>
                                {accuracyBuckets.map((b) => (
                                    <tr key={b.range}>
                                        <td>{b.range}</td>
                                        <td>{b.total}</td>
                                        <td>{b.acted}</td>
                                        <td>{b.dismissed}</td>
                                        <td>
                                            {b.total === 0 ? (
                                                <Text size={200} style={{ color: tokens.colorNeutralForeground3 }}>No data</Text>
                                            ) : (
                                                <Badge
                                                    appearance="filled"
                                                    color={b.accuracy >= 70 ? "success" : b.accuracy >= 40 ? "warning" : "danger"}
                                                    size="small"
                                                >
                                                    {b.accuracy}%
                                                </Badge>
                                            )}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}

                {activeTab === "triage" && (
                    <div className="calibration-section">
                        <Text block size={300} style={{ color: tokens.colorNeutralForeground2 }}>
                            How well is the triage classifier working? FULL cards should mostly be acted on.
                            LIGHT cards being dismissed is expected behavior.
                        </Text>
                        <div className="calibration-stats-grid">
                            <Card className="calibration-stat-card">
                                <Text size={600} weight="bold" block>
                                    {triageStats.fullTotal === 0 ? (
                                        <Text size={200} style={{ color: tokens.colorNeutralForeground3 }}>No data</Text>
                                    ) : (
                                        <>{triageStats.fullAccuracy}%</>
                                    )}
                                </Text>
                                <Text size={300} weight="semibold" block>FULL card action rate</Text>
                                <Text size={200} style={{ color: tokens.colorNeutralForeground3 }} block>
                                    {triageStats.fullActed} acted / {triageStats.fullTotal} total
                                </Text>
                            </Card>
                            <Card className="calibration-stat-card">
                                <Text size={600} weight="bold" block>{triageStats.fullDismissed}</Text>
                                <Text size={300} weight="semibold" block>FULL cards dismissed</Text>
                                <Text size={200} style={{ color: tokens.colorNeutralForeground3 }} block>
                                    These were over-triaged (could have been LIGHT)
                                </Text>
                            </Card>
                            <Card className="calibration-stat-card">
                                <Text size={600} weight="bold" block>
                                    {triageStats.lightTotal === 0 ? (
                                        <Text size={200} style={{ color: tokens.colorNeutralForeground3 }}>No data</Text>
                                    ) : (
                                        <>{triageStats.lightDismissRate}%</>
                                    )}
                                </Text>
                                <Text size={300} weight="semibold" block>LIGHT card dismiss rate</Text>
                                <Text size={200} style={{ color: tokens.colorNeutralForeground3 }} block>
                                    {triageStats.lightDismissed} / {triageStats.lightTotal} — expected to be high
                                </Text>
                            </Card>
                        </div>
                    </div>
                )}

                {activeTab === "drafts" && (
                    <div className="calibration-section">
                        <Text block size={300} style={{ color: tokens.colorNeutralForeground2 }}>
                            How often are you sending drafts as-is vs editing them? A high as-is rate means
                            the agent is calibrated well for your voice and preferences.
                        </Text>
                        <div className="calibration-stats-grid">
                            <Card className="calibration-stat-card">
                                <Text size={600} weight="bold" block>
                                    {draftStats.total === 0 ? (
                                        <Text size={200} style={{ color: tokens.colorNeutralForeground3 }}>No data</Text>
                                    ) : (
                                        <>{draftStats.asIsRate}%</>
                                    )}
                                </Text>
                                <Text size={300} weight="semibold" block>Sent as-is rate</Text>
                                <Text size={200} style={{ color: tokens.colorNeutralForeground3 }} block>
                                    {draftStats.asIs} of {draftStats.total} sent drafts
                                </Text>
                            </Card>
                            <Card className="calibration-stat-card">
                                <Text size={600} weight="bold" block>{draftStats.edited}</Text>
                                <Text size={300} weight="semibold" block>Drafts edited before send</Text>
                                <Text size={200} style={{ color: tokens.colorNeutralForeground3 }} block>
                                    These needed human refinement
                                </Text>
                            </Card>
                        </div>
                    </div>
                )}

                {activeTab === "senders" && (
                    <div className="calibration-section">
                        <Text block size={300} style={{ color: tokens.colorNeutralForeground2 }}>
                            Your most active senders ranked by signal volume, with your response rate for each.
                        </Text>
                        <table className="calibration-table">
                            <thead>
                                <tr>
                                    <th>Sender</th>
                                    <th>Signals</th>
                                    <th>Responses</th>
                                    <th>Response Rate</th>
                                </tr>
                            </thead>
                            <tbody>
                                {topSenders.map((s) => (
                                    <tr key={s.email}>
                                        <td title={s.email}>{s.display}</td>
                                        <td>{s.signalCount}</td>
                                        <td>{s.responseCount}</td>
                                        <td>
                                            <Badge
                                                appearance="filled"
                                                color={s.responseRate >= 70 ? "success" : s.responseRate >= 40 ? "warning" : "danger"}
                                                size="small"
                                            >
                                                {s.responseRate}%
                                            </Badge>
                                        </td>
                                    </tr>
                                ))}
                                {topSenders.length === 0 && (
                                    <tr>
                                        <td colSpan={4} style={{ textAlign: "center", color: tokens.colorNeutralForeground3 }}>
                                            No sender data yet — resolve some cards first.
                                        </td>
                                    </tr>
                                )}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>
        </div>
    );
};
