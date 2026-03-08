import * as React from "react";
import { Switch } from "@fluentui/react-components";
import type { AssistantCard } from "./types";
import { HEARTBEAT_TRIGGER_TYPES } from "./constants";

type SortMode = "newest" | "priority" | "staleness";

const SORT_LABELS: Record<SortMode, string> = {
    newest: "↓ Newest",
    priority: "↓ Priority",
    staleness: "↓ Staleness",
};

const SORT_CYCLE: SortMode[] = ["newest", "priority", "staleness"];

export interface FilterBarProps {
    cards: AssistantCard[];
    onFilteredCards: (cards: AssistantCard[]) => void;
    onQuietModeChange?: (quiet: boolean, heldCount: number) => void;
}

function computeCounts(cards: AssistantCard[]) {
    let email = 0;
    let teams = 0;
    let calendar = 0;
    let proactive = 0;
    let stale = 0;
    for (const c of cards) {
        if (c.trigger_type === "EMAIL") email++;
        else if (c.trigger_type === "TEAMS_MESSAGE") teams++;
        else if (c.trigger_type === "CALENDAR_SCAN") calendar++;
        if ((HEARTBEAT_TRIGGER_TYPES as readonly string[]).includes(c.trigger_type)) proactive++;
        if ((c.hours_stale ?? 0) >= 24) stale++;
    }
    return { email, teams, calendar, proactive, stale };
}

function sortCards(cards: AssistantCard[], mode: SortMode): AssistantCard[] {
    const sorted = [...cards];
    switch (mode) {
        case "newest":
            sorted.sort((a, b) => new Date(b.created_on).getTime() - new Date(a.created_on).getTime());
            break;
        case "priority": {
            const order: Record<string, number> = { High: 0, Medium: 1, Low: 2, "N/A": 3 };
            sorted.sort((a, b) => (order[a.priority ?? "N/A"] ?? 3) - (order[b.priority ?? "N/A"] ?? 3));
            break;
        }
        case "staleness":
            sorted.sort((a, b) => (b.hours_stale ?? 0) - (a.hours_stale ?? 0));
            break;
    }
    return sorted;
}

export const FilterBar: React.FC<FilterBarProps> = ({ cards, onFilteredCards, onQuietModeChange }) => {
    const [activeChips, setActiveChips] = React.useState<Set<string>>(() => new Set(["all"]));
    const [sortMode, setSortMode] = React.useState<SortMode>("newest");
    const [quietMode, setQuietMode] = React.useState(false);

    const counts = React.useMemo(() => computeCounts(cards), [cards]);

    const toggleChip = React.useCallback((key: string) => {
        setActiveChips((prev) => {
            if (key === "all") {
                return new Set(["all"]);
            }
            const next = new Set(prev);
            next.delete("all");
            if (next.has(key)) {
                next.delete(key);
            } else {
                next.add(key);
            }
            return next.size === 0 ? new Set(["all"]) : next;
        });
    }, []);

    const cycleSortMode = React.useCallback(() => {
        setSortMode((prev) => {
            const idx = SORT_CYCLE.indexOf(prev);
            return SORT_CYCLE[(idx + 1) % SORT_CYCLE.length];
        });
    }, []);

    React.useEffect(() => {
        let filtered = cards;
        if (!activeChips.has("all")) {
            filtered = cards.filter((c) => {
                if (activeChips.has("email") && c.trigger_type === "EMAIL") return true;
                if (activeChips.has("teams") && c.trigger_type === "TEAMS_MESSAGE") return true;
                if (activeChips.has("calendar") && c.trigger_type === "CALENDAR_SCAN") return true;
                if (activeChips.has("proactive") && (HEARTBEAT_TRIGGER_TYPES as readonly string[]).includes(c.trigger_type)) return true;
                if (activeChips.has("stale") && (c.hours_stale ?? 0) >= 24) return true;
                return false;
            });
        }
        // Quiet mode: filter out Medium-priority cards
        let heldCount = 0;
        if (quietMode) {
            const before = filtered.length;
            filtered = filtered.filter((c) => c.priority !== "Medium");
            heldCount = before - filtered.length;
        }
        onFilteredCards(sortCards(filtered, sortMode));
        onQuietModeChange?.(quietMode, heldCount);
    }, [cards, activeChips, sortMode, quietMode, onFilteredCards, onQuietModeChange]);

    const chips = [
        { key: "all", label: "All", count: cards.length },
        { key: "email", label: "📧 Email", count: counts.email },
        { key: "teams", label: "💬 Teams", count: counts.teams },
        { key: "calendar", label: "📅 Calendar", count: counts.calendar },
        { key: "proactive", label: "✦ Proactive", count: counts.proactive },
        { key: "stale", label: "⏰ Stale", count: counts.stale },
    ];

    return (
        <div className="filter-bar" role="toolbar" aria-label="Filter cards">
            {chips.map((chip) => (
                <button
                    key={chip.key}
                    className={`filter-chip${activeChips.has(chip.key) ? " filter-chip-active" : ""}`}
                    onClick={() => toggleChip(chip.key)}
                    aria-pressed={activeChips.has(chip.key)}
                >
                    {chip.label}
                    {chip.count > 0 && <span className="filter-chip-count">{chip.count}</span>}
                </button>
            ))}
            <button
                className="filter-chip filter-chip-sort"
                onClick={cycleSortMode}
            >
                {SORT_LABELS[sortMode]}
            </button>
            <Switch
                checked={quietMode}
                onChange={(_ev, data) => setQuietMode(data.checked)}
                label="Quiet"
                style={{ marginLeft: "auto", flexShrink: 0 }}
            />
        </div>
    );
};
