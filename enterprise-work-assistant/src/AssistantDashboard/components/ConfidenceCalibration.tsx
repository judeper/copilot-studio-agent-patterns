import * as React from "react";
import { useState, useMemo } from "react";
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
                <button className="calibration-back" onClick={onBack}>
                    ← Back to Dashboard
                </button>
                <h2>Agent Performance</h2>
                <span className="calibration-sample">
                    Based on {resolvedCards.length} resolved cards
                </span>
            </div>

            {/* Tab bar */}
            <div className="calibration-tabs">
                {(["accuracy", "triage", "drafts", "senders"] as const).map((tab) => (
                    <button
                        key={tab}
                        className={`calibration-tab ${activeTab === tab ? "calibration-tab-active" : ""}`}
                        onClick={() => setActiveTab(tab)}
                    >
                        {tab === "accuracy" && "Confidence Accuracy"}
                        {tab === "triage" && "Triage Quality"}
                        {tab === "drafts" && "Draft Quality"}
                        {tab === "senders" && "Top Senders"}
                    </button>
                ))}
            </div>

            {/* Tab content */}
            <div className="calibration-content">
                {activeTab === "accuracy" && (
                    <div className="calibration-section">
                        <p className="calibration-description">
                            Does higher confidence actually predict that you'll act on the card?
                            Each row shows cards in a confidence range and what percentage you responded to.
                        </p>
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
                                            <span
                                                className={
                                                    b.accuracy >= 70
                                                        ? "calibration-good"
                                                        : b.accuracy >= 40
                                                          ? "calibration-ok"
                                                          : "calibration-poor"
                                                }
                                            >
                                                {b.accuracy}%
                                            </span>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}

                {activeTab === "triage" && (
                    <div className="calibration-section">
                        <p className="calibration-description">
                            How well is the triage classifier working? FULL cards should mostly be acted on.
                            LIGHT cards being dismissed is expected behavior.
                        </p>
                        <div className="calibration-stats-grid">
                            <div className="calibration-stat-card">
                                <div className="calibration-stat-value">{triageStats.fullAccuracy}%</div>
                                <div className="calibration-stat-label">FULL card action rate</div>
                                <div className="calibration-stat-detail">
                                    {triageStats.fullActed} acted / {triageStats.fullTotal} total
                                </div>
                            </div>
                            <div className="calibration-stat-card">
                                <div className="calibration-stat-value">{triageStats.fullDismissed}</div>
                                <div className="calibration-stat-label">FULL cards dismissed</div>
                                <div className="calibration-stat-detail">
                                    These were over-triaged (could have been LIGHT)
                                </div>
                            </div>
                            <div className="calibration-stat-card">
                                <div className="calibration-stat-value">{triageStats.lightDismissRate}%</div>
                                <div className="calibration-stat-label">LIGHT card dismiss rate</div>
                                <div className="calibration-stat-detail">
                                    {triageStats.lightDismissed} / {triageStats.lightTotal} — expected to be high
                                </div>
                            </div>
                        </div>
                    </div>
                )}

                {activeTab === "drafts" && (
                    <div className="calibration-section">
                        <p className="calibration-description">
                            How often are you sending drafts as-is vs editing them? A high as-is rate means
                            the agent is calibrated well for your voice and preferences.
                        </p>
                        <div className="calibration-stats-grid">
                            <div className="calibration-stat-card">
                                <div className="calibration-stat-value">{draftStats.asIsRate}%</div>
                                <div className="calibration-stat-label">Sent as-is rate</div>
                                <div className="calibration-stat-detail">
                                    {draftStats.asIs} of {draftStats.total} sent drafts
                                </div>
                            </div>
                            <div className="calibration-stat-card">
                                <div className="calibration-stat-value">{draftStats.edited}</div>
                                <div className="calibration-stat-label">Drafts edited before send</div>
                                <div className="calibration-stat-detail">
                                    These needed human refinement
                                </div>
                            </div>
                        </div>
                    </div>
                )}

                {activeTab === "senders" && (
                    <div className="calibration-section">
                        <p className="calibration-description">
                            Your most active senders ranked by signal volume, with your response rate for each.
                        </p>
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
                                            <span
                                                className={
                                                    s.responseRate >= 70
                                                        ? "calibration-good"
                                                        : s.responseRate >= 40
                                                          ? "calibration-ok"
                                                          : "calibration-poor"
                                                }
                                            >
                                                {s.responseRate}%
                                            </span>
                                        </td>
                                    </tr>
                                ))}
                                {topSenders.length === 0 && (
                                    <tr>
                                        <td colSpan={4} style={{ textAlign: "center", color: "#888" }}>
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
