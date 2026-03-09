import React, { useState } from 'react';
import { Button, Text, Badge, Card, Select, Checkbox, Switch } from "@fluentui/react-components";
import { ArrowLeftRegular, DismissRegular, ChevronDownRegular, ChevronRightRegular, CalendarRegular, ArrowRightRegular, WeatherSunnyRegular, WeatherMoonRegular, CheckmarkCircleRegular, ChatBubblesQuestionRegular, LightbulbRegular } from "@fluentui/react-icons";
import type { AssistantCard, DailyBriefing, BriefingActionItem, BriefingFyiItem, BriefingStaleAlert, BriefingScheduleConfig, MorningBriefingData, EndOfDayData } from "./types";

interface BriefingCardProps {
    card: AssistantCard;
    allCards?: AssistantCard[];
    onJumpToCard: (cardId: string) => void;
    onDismissCard: (cardId: string) => void;
    onUpdateSchedule?: (config: BriefingScheduleConfig) => void;
    onBack?: () => void;
}

/**
 * Parse the briefing JSON from the card's full JSON output.
 * The Daily Briefing Agent stores its output in cr_fulljson just like other agents,
 * but the briefing_type field distinguishes it.
 */
function parseBriefing(card: AssistantCard): DailyBriefing | null {
    try {
        // The briefing is already parsed as part of the card's JSON in useCardData,
        // but the structured briefing data is in the draft_payload or the full JSON.
        // For briefing cards, the agent output IS the briefing — it's stored in cr_fulljson.
        // useCardData parses cr_fulljson into the card fields. The briefing-specific
        // fields (action_items, fyi_items, etc.) need to be extracted from the raw JSON.
        //
        // The card.draft_payload holds the briefing JSON string for DAILY_BRIEFING cards.
        if (typeof card.draft_payload === "string" && card.draft_payload) {
            return JSON.parse(card.draft_payload) as DailyBriefing;
        }
        if (typeof card.draft_payload === "object" && card.draft_payload !== null) {
            return card.draft_payload as unknown as DailyBriefing;
        }
        return null;
    } catch {
        return null;
    }
}

function ActionItem({
    item,
    onJumpToCard,
}: {
    item: BriefingActionItem;
    onJumpToCard: (cardId: string) => void;
}) {
    return (
        <div className="briefing-action-item">
            <Badge appearance="filled" size="small">#{item.rank}</Badge>
            <div className="briefing-action-content">
                <Text block>{item.thread_summary}</Text>
                <Text block size={300}>
                    {item.recommended_action}
                </Text>
                <Text block size={200}>{item.urgency_reason}</Text>
                {item.related_calendar && (
                    <div className="briefing-action-calendar">
                        <CalendarRegular /> {item.related_calendar}
                    </div>
                )}
                <div className="briefing-action-links">
                    {item.card_ids.map((id) => (
                        <Button
                            key={id}
                            appearance="transparent"
                            data-focus-return={`briefing-action-${id}`}
                            size="small"
                            icon={<ArrowRightRegular />}
                            iconPosition="after"
                            onClick={() => onJumpToCard(id)}
                            title={`Open card ${id.substring(0, 8)}...`}
                        >
                            Open card
                        </Button>
                    ))}
                </div>
            </div>
        </div>
    );
}

function FyiItem({ item }: { item: BriefingFyiItem }) {
    const categoryLabel =
        item.category === "MEETING_PREP"
            ? "Meeting prep"
            : item.category === "INFO_UPDATE"
              ? "Info"
              : "Low priority";

    return (
        <div className="briefing-fyi-item">
            <Badge appearance="outline" size="small">{categoryLabel}</Badge>
            <Text>{item.summary}</Text>
        </div>
    );
}

function StaleAlert({
    alert,
    onJumpToCard,
}: {
    alert: BriefingStaleAlert;
    onJumpToCard: (cardId: string) => void;
}) {
    const severityClass =
        alert.hours_pending > 48
            ? "briefing-stale-critical"
            : "briefing-stale-warning";

    return (
        <div className={`briefing-stale-item ${severityClass}`}>
            <div className="briefing-stale-summary">
                <Text>{alert.summary}</Text>
                <Badge appearance="tint" color="warning" size="small">
                    {Math.round(alert.hours_pending)}h pending
                </Badge>
            </div>
            <div className="briefing-stale-actions">
                <Text size={200}>
                    Suggested: {alert.recommended_action.toLowerCase()}
                </Text>
                <Button
                    appearance="transparent"
                    data-focus-return={`briefing-stale-${alert.card_id}`}
                    size="small"
                    icon={<ArrowRightRegular />}
                    iconPosition="after"
                    onClick={() => onJumpToCard(alert.card_id)}
                >
                    Open
                </Button>
            </div>
        </div>
    );
}

const ALL_DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"] as const;
const DEFAULT_DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"];

function formatHour(hour: number): string {
    const suffix = hour >= 12 ? "PM" : "AM";
    const display = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
    return `${display}:00 ${suffix}`;
}

function ScheduleSettings({
    onUpdateSchedule,
}: {
    onUpdateSchedule: (config: BriefingScheduleConfig) => void;
}) {
    const [expanded, setExpanded] = useState(false);
    const [hour, setHour] = useState(7);
    const [days, setDays] = useState<string[]>([...DEFAULT_DAYS]);
    const [enabled, setEnabled] = useState(true);

    const toggleDay = (day: string) => {
        setDays((prev) =>
            prev.includes(day) ? prev.filter((d) => d !== day) : [...prev, day],
        );
    };

    const handleSave = () => {
        onUpdateSchedule({
            hour,
            minute: 0,
            days,
            timezone: "America/New_York",
            enabled,
        });
    };

    return (
        <div className="briefing-schedule-settings">
            <Button
                appearance="transparent"
                icon={<CalendarRegular />}
                onClick={() => setExpanded(!expanded)}
                size="small"
            >
                Schedule Settings
            </Button>
            {expanded && (
                <div className="briefing-schedule-panel" style={{ padding: "8px 0" }}>
                    <div style={{ marginBottom: 8 }}>
                        <Text size={200} weight="semibold" block>Delivery time</Text>
                        <Select
                            value={String(hour)}
                            onChange={(_e, data) => setHour(Number(data.value))}
                            size="small"
                        >
                            {Array.from({ length: 18 }, (_, i) => i + 5).map((h) => (
                                <option key={h} value={String(h)}>{formatHour(h)}</option>
                            ))}
                        </Select>
                    </div>
                    <div style={{ marginBottom: 8 }}>
                        <Text size={200} weight="semibold" block>Days</Text>
                        {ALL_DAYS.map((day) => (
                            <Checkbox
                                key={day}
                                label={day.substring(0, 3)}
                                checked={days.includes(day)}
                                onChange={() => toggleDay(day)}
                            />
                        ))}
                    </div>
                    <div style={{ marginBottom: 8, display: "flex", alignItems: "center", gap: 8 }}>
                        <Switch
                            checked={enabled}
                            onChange={(_e, data) => setEnabled(data.checked)}
                            label="Enabled"
                        />
                    </div>
                    <Button appearance="primary" size="small" onClick={handleSave}>
                        Save
                    </Button>
                </div>
            )}
        </div>
    );
}

/**
 * Derive morning briefing metrics from action items and FYI items
 * when explicit morning_data is not provided.
 */
function deriveMorningData(briefing: DailyBriefing): MorningBriefingData {
    if (briefing.morning_data) return briefing.morning_data;
    const decisions = briefing.action_items.length;
    const focusBlocks = (briefing.fyi_items ?? []).filter(
        (f) => f.category === "MEETING_PREP",
    ).length;
    const meetingsPrep = (briefing.fyi_items ?? []).filter(
        (f) => f.category === "MEETING_PREP",
    ).length;
    const firstAction = briefing.action_items[0];
    return {
        decisions_count: decisions,
        focus_blocks_count: focusBlocks,
        meetings_needing_prep: meetingsPrep,
        first_decision: firstAction
            ? firstAction.thread_summary.substring(0, 60)
            : "No decisions pending",
        protected_window: focusBlocks > 0 ? "Focus time available" : "No focus blocks",
        next_context_shift: firstAction?.related_calendar ?? "No upcoming shift",
    };
}

/**
 * Derive end-of-day review data from cards when explicit eod_data is not provided.
 */
function deriveEodData(briefing: DailyBriefing, allCards?: AssistantCard[]): EndOfDayData {
    if (briefing.eod_data) return briefing.eod_data;
    const cards = allCards ?? [];
    const completed = cards.filter(
        (c) =>
            c.card_outcome === "SENT_AS_IS" ||
            c.card_outcome === "SENT_EDITED" ||
            c.card_outcome === "DISMISSED",
    ).length;
    const deferred = cards.filter((c) => c.card_outcome === "PENDING").length;
    const carryForward: string[] = [];
    for (const item of briefing.action_items.slice(0, 4)) {
        carryForward.push(item.recommended_action);
    }
    return {
        completed_count: completed,
        deferred_count: deferred,
        protected_focus_hours: 2.5,
        carry_forward: carryForward,
    };
}

function MorningBriefingSection({
    briefing,
    onJumpToCard,
}: {
    briefing: DailyBriefing;
    onJumpToCard: (cardId: string) => void;
}) {
    const data = deriveMorningData(briefing);
    const firstCardId = briefing.action_items[0]?.card_ids[0];

    return (
        <div className="briefing-morning-summary">
            <div className="briefing-morning-header">
                <WeatherSunnyRegular />
                <Text as="h3" size={400} weight="semibold">Start-of-day summary</Text>
            </div>
            <Text block size={300} className="briefing-morning-narrative">
                Your day is front-loaded around {data.decisions_count} decision{data.decisions_count !== 1 ? "s" : ""},{" "}
                {data.focus_blocks_count} protected focus block{data.focus_blocks_count !== 1 ? "s" : ""},{" "}
                and {data.meetings_needing_prep} meeting{data.meetings_needing_prep !== 1 ? "s" : ""} needing prep
            </Text>
            <div className="briefing-metric-grid">
                <div className="briefing-metric-tile">
                    <div className="briefing-metric-label">First decision</div>
                    <div className="briefing-metric-value">{data.first_decision}</div>
                </div>
                <div className="briefing-metric-tile">
                    <div className="briefing-metric-label">Protected window</div>
                    <div className="briefing-metric-value">{data.protected_window}</div>
                </div>
                <div className="briefing-metric-tile">
                    <div className="briefing-metric-label">Next context shift</div>
                    <div className="briefing-metric-value">{data.next_context_shift}</div>
                </div>
            </div>
            {firstCardId && (
                <div className="briefing-morning-action">
                    <Button
                        appearance="primary"
                        size="small"
                        onClick={() => onJumpToCard(firstCardId)}
                    >
                        Start my day
                    </Button>
                </div>
            )}
        </div>
    );
}

function EndOfDaySection({
    briefing,
    allCards,
    onDismissCard,
    cardId,
}: {
    briefing: DailyBriefing;
    allCards?: AssistantCard[];
    onDismissCard: (cardId: string) => void;
    cardId: string;
}) {
    const data = deriveEodData(briefing, allCards);

    return (
        <div className="briefing-eod-section">
            <div className="briefing-eod-header">
                <WeatherMoonRegular />
                <Text as="h3" size={400} weight="semibold">End-of-day review</Text>
            </div>
            <div className="briefing-metric-grid">
                <div className="briefing-metric-tile">
                    <div className="briefing-metric-label">Completed</div>
                    <div className="briefing-metric-value">{data.completed_count}</div>
                </div>
                <div className="briefing-metric-tile">
                    <div className="briefing-metric-label">Deferred</div>
                    <div className="briefing-metric-value">{data.deferred_count}</div>
                </div>
                <div className="briefing-metric-tile">
                    <div className="briefing-metric-label">Protected focus</div>
                    <div className="briefing-metric-value">{data.protected_focus_hours}h</div>
                </div>
            </div>
            {data.carry_forward.length > 0 && (
                <div className="briefing-carry-forward">
                    <Text as="h4" size={300} weight="semibold" block>
                        Tomorrow&apos;s carry-forward
                    </Text>
                    <ul className="briefing-carry-list">
                        {data.carry_forward.map((item, i) => (
                            <li key={`cf-${i}`}>
                                <Text size={200}>{item}</Text>
                            </li>
                        ))}
                    </ul>
                </div>
            )}
            <div className="briefing-eod-actions">
                <Button
                    appearance="primary"
                    size="small"
                    onClick={() => onDismissCard(cardId)}
                >
                    Finalize review
                </Button>
                <Button appearance="secondary" size="small">
                    Rebuild tomorrow lane
                </Button>
            </div>
        </div>
    );
}

function MeetingBriefingSections({
    briefing,
}: {
    briefing: DailyBriefing;
}) {
    const meetingPreps = (briefing.fyi_items ?? []).filter(
        (f) => f.category === "MEETING_PREP",
    );
    if (meetingPreps.length === 0 && briefing.action_items.length === 0) return null;

    // Derive "what changed", "open decisions", and "talking points"
    // from action items and FYI items
    const whatChanged = briefing.action_items
        .filter((a) => a.related_calendar)
        .map((a) => a.urgency_reason);
    const openDecisions = briefing.action_items.map((a) => a.thread_summary);
    const talkingPoints = briefing.action_items.map((a) => a.recommended_action);

    return (
        <div className="briefing-meeting-sections">
            {whatChanged.length > 0 && (
                <div className="briefing-meeting-subsection">
                    <div className="briefing-meeting-subsection-header">
                        <LightbulbRegular />
                        <Text size={300} weight="semibold">What changed</Text>
                    </div>
                    <ul className="briefing-meeting-list">
                        {whatChanged.map((text, i) => (
                            <li key={`wc-${i}`}><Text size={200}>{text}</Text></li>
                        ))}
                    </ul>
                </div>
            )}

            {openDecisions.length > 0 && (
                <div className="briefing-meeting-subsection">
                    <div className="briefing-meeting-subsection-header">
                        <ChatBubblesQuestionRegular />
                        <Text size={300} weight="semibold">Open decisions</Text>
                    </div>
                    <ul className="briefing-meeting-list">
                        {openDecisions.map((text, i) => (
                            <li key={`od-${i}`}><Text size={200}>{text}</Text></li>
                        ))}
                    </ul>
                </div>
            )}

            {talkingPoints.length > 0 && (
                <div className="briefing-meeting-subsection">
                    <div className="briefing-meeting-subsection-header">
                        <ArrowRightRegular />
                        <Text size={300} weight="semibold">Suggested talking points</Text>
                    </div>
                    <ul className="briefing-meeting-list">
                        {talkingPoints.map((text, i) => (
                            <li key={`tp-${i}`}><Text size={200}>{text}</Text></li>
                        ))}
                    </ul>
                </div>
            )}
        </div>
    );
}

export const BriefingCard: React.FC<BriefingCardProps> = ({
    card,
    allCards,
    onJumpToCard,
    onDismissCard,
    onUpdateSchedule,
    onBack,
}) => {
    const [fyiExpanded, setFyiExpanded] = useState(false);
    const [briefed, setBriefed] = useState(false);
    const briefing = parseBriefing(card);

    React.useEffect(() => {
        if (!onBack) return;
        const handleEscapeKey = (e: KeyboardEvent) => {
            if (e.defaultPrevented || e.key !== "Escape") return;
            e.preventDefault();
            onBack();
        };
        document.addEventListener("keydown", handleEscapeKey);
        return () => document.removeEventListener("keydown", handleEscapeKey);
    }, [onBack]);

    if (!briefing) {
        return (
            <Card className="briefing-card briefing-card-error">
                <div className="briefing-header">
                    {onBack && (
                        <Button appearance="subtle" icon={<ArrowLeftRegular />} onClick={onBack}>
                            Back
                        </Button>
                    )}
                    <Text as="h2" size={500} weight="semibold" block>Daily Briefing</Text>
                    <Text size={200}>{card.created_on}</Text>
                </div>
                <Text block>
                    Unable to parse briefing data. The briefing agent may have
                    returned an unexpected format.
                </Text>
            </Card>
        );
    }

    const hasActions = briefing.action_items && briefing.action_items.length > 0;
    const hasFyi = briefing.fyi_items && briefing.fyi_items.length > 0;
    const hasStale = briefing.stale_alerts && briefing.stale_alerts.length > 0;
    const isMorning = briefing.briefing_type === "MORNING" || briefing.briefing_type === "DAILY";
    const isEod = briefing.briefing_type === "END_OF_DAY";
    const isMeetingPrep = briefing.briefing_type === "MEETING_PREP";

    const handleBriefedInteraction = () => {
        if (!briefed) setBriefed(true);
    };

    return (
        <Card className="briefing-card" onClickCapture={handleBriefedInteraction}>
            {/* Back button */}
            {onBack && (
                <Button appearance="subtle" icon={<ArrowLeftRegular />} onClick={onBack}>
                    Back
                </Button>
            )}

            {/* Header */}
            <div className="briefing-header">
                <Text as="h2" size={500} weight="semibold" block>
                    {isEod ? "End-of-Day Review" : isMeetingPrep ? "Meeting Briefing" : "Daily Briefing"}
                </Text>
                <Text size={200}>{briefing.briefing_date}</Text>
                <Badge appearance="outline" size="small">
                    {briefing.total_open_items} open item
                    {briefing.total_open_items !== 1 ? "s" : ""}
                </Badge>
                {briefed && (
                    <Badge
                        appearance="filled"
                        size="small"
                        color="success"
                        icon={<CheckmarkCircleRegular />}
                        className="briefing-briefed-badge"
                    >
                        Briefed
                    </Badge>
                )}
            </div>

            {/* Day Shape */}
            <Text block size={300} className="briefing-day-shape">{briefing.day_shape}</Text>

            {/* Phase C1: Morning Briefing Summary */}
            {isMorning && (
                <MorningBriefingSection briefing={briefing} onJumpToCard={onJumpToCard} />
            )}

            {/* Phase C2: End-of-Day Review */}
            {isEod && (
                <EndOfDaySection
                    briefing={briefing}
                    allCards={allCards}
                    onDismissCard={onDismissCard}
                    cardId={card.id}
                />
            )}

            {/* Stale Alerts (shown first — these need immediate attention) */}
            {hasStale && (
                <div className="briefing-section briefing-stale-section">
                    <Text as="h3" size={400} weight="semibold" block>Overdue Items</Text>
                    {briefing.stale_alerts!.map((alert) => (
                        <StaleAlert
                            key={alert.card_id}
                            alert={alert}
                            onJumpToCard={onJumpToCard}
                        />
                    ))}
                </div>
            )}

            {/* Action Items */}
            {hasActions && (
                <div className="briefing-section briefing-actions-section">
                    <Text as="h3" size={400} weight="semibold" block>Action Items</Text>
                    {briefing.action_items.map((item) => (
                        <ActionItem
                            key={`action-${item.rank}`}
                            item={item}
                            onJumpToCard={onJumpToCard}
                        />
                    ))}
                </div>
            )}

            {/* Phase C3: Enhanced Meeting Briefing Sections */}
            {(isMeetingPrep || hasActions) && (
                <MeetingBriefingSections briefing={briefing} />
            )}

            {/* FYI (collapsible) */}
            {hasFyi && (
                <div className="briefing-section briefing-fyi-section">
                    <Button
                        appearance="transparent"
                        icon={fyiExpanded ? <ChevronDownRegular /> : <ChevronRightRegular />}
                        onClick={() => setFyiExpanded(!fyiExpanded)}
                    >
                        For Your Information ({briefing.fyi_items!.length})
                    </Button>
                    {fyiExpanded &&
                        briefing.fyi_items!.map((item, i) => (
                            <FyiItem key={`fyi-${i}`} item={item} />
                        ))}
                </div>
            )}

            {/* No items state */}
            {!hasActions && !hasStale && !isEod && (
                <div className="briefing-empty">
                    <Text block>Your inbox is clear. No pending items need attention today.</Text>
                </div>
            )}

            {/* Schedule Settings */}
            {onUpdateSchedule && (
                <ScheduleSettings onUpdateSchedule={onUpdateSchedule} />
            )}

            {/* Dismiss briefing */}
            {!isEod && (
                <div className="briefing-footer">
                    <Button
                        appearance="subtle"
                        icon={<DismissRegular />}
                        onClick={() => onDismissCard(card.id)}
                    >
                        Dismiss briefing
                    </Button>
                </div>
            )}
        </Card>
    );
};
