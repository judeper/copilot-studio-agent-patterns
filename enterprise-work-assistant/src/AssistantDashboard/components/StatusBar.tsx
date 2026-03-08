import * as React from "react";
import { Button, Badge } from "@fluentui/react-components";
import { BrainCircuitRegular, SettingsRegular } from "@fluentui/react-icons";

export interface StatusBarProps {
    actionCount: number;
    newCount: number;
    memoryActive: boolean;
    onSettingsClick: () => void;
    quietMode?: boolean;
    quietHeldCount?: number;
    nextMeetingTime?: string | null;
}

export const StatusBar: React.FC<StatusBarProps> = ({
    actionCount,
    newCount,
    memoryActive,
    onSettingsClick,
    quietMode,
    quietHeldCount,
    nextMeetingTime,
}) => {
    const [pulsing, setPulsing] = React.useState(false);
    const prevCountRef = React.useRef(actionCount);

    // Pulse briefly when actionCount changes (new data arrived)
    React.useEffect(() => {
        if (actionCount !== prevCountRef.current && memoryActive) {
            setPulsing(true);
            const timer = setTimeout(() => setPulsing(false), 3000);
            prevCountRef.current = actionCount;
            return () => clearTimeout(timer);
        }
        prevCountRef.current = actionCount;
    }, [actionCount, memoryActive]);
    return (
        <div className="status-bar">
            <div className="status-bar-brand">
                <BrainCircuitRegular fontSize={20} />
                <span className="status-bar-title">Work Assistant</span>
            </div>
            <div className="status-bar-metrics">
                <button
                    className="status-bar-action-count"
                    aria-label={`${actionCount} decisions ready, ${newCount} new`}
                >
                    {actionCount} decisions ready
                </button>
                <span className="status-bar-focus-status" aria-label={`Focus: ${quietMode ? "Quiet" : "Open"}`}>
                    {quietMode ? "🔇 Quiet" : "📡 Open"}
                </span>
                {nextMeetingTime && (
                    <span className="status-bar-next-meeting" title="Next meeting">
                        📅 {nextMeetingTime}
                    </span>
                )}
            </div>
            <div className="status-bar-right">
                {quietMode && (quietHeldCount ?? 0) > 0 && (
                    <span className="status-bar-held-items">
                        <Badge appearance="outline" color="informative" size="small">
                            {quietHeldCount} items reviewed and ready
                        </Badge>
                    </span>
                )}
                <span
                    className={memoryActive ? `memory-icon-active${pulsing ? " memory-pulse" : ""}` : "memory-icon"}
                    title={memoryActive ? "Semantic memory active" : "No knowledge facts loaded"}
                    aria-label={memoryActive ? "Semantic memory active" : "No knowledge facts loaded"}
                >
                    ●
                </span>
                <Button
                    appearance="subtle"
                    icon={<SettingsRegular />}
                    size="small"
                    onClick={onSettingsClick}
                    aria-label="Settings"
                />
            </div>
        </div>
    );
};
