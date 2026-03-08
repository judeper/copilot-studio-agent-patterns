import * as React from "react";
import { Button } from "@fluentui/react-components";
import { BrainCircuitRegular, SettingsRegular } from "@fluentui/react-icons";

export interface StatusBarProps {
    actionCount: number;
    newCount: number;
    memoryActive: boolean;
    onSettingsClick: () => void;
}

export const StatusBar: React.FC<StatusBarProps> = ({
    actionCount,
    newCount,
    memoryActive,
    onSettingsClick,
}) => {
    return (
        <div className="status-bar">
            <div className="status-bar-brand">
                <BrainCircuitRegular fontSize={20} />
                <span className="status-bar-title">Work Assistant</span>
            </div>
            <button
                className="status-bar-action-count"
                aria-label={`${actionCount} action items, ${newCount} new`}
            >
                {actionCount} action items
            </button>
            <div className="status-bar-right">
                <span
                    className={memoryActive ? "memory-icon-active" : "memory-icon"}
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
