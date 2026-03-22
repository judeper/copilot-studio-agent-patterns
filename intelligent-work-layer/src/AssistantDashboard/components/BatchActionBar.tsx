import * as React from "react";
import { Button, Badge, Text } from "@fluentui/react-components";
import { DismissRegular, ClockRegular, DismissCircleRegular } from "@fluentui/react-icons";

const MAX_BATCH_SIZE = 25;

interface BatchActionBarProps {
    selectedCount: number;
    onDismissAll: () => void;
    onSnoozeAll: () => void;
    onClearSelection: () => void;
}

export const BatchActionBar: React.FC<BatchActionBarProps> = ({
    selectedCount,
    onDismissAll,
    onSnoozeAll,
    onClearSelection,
}) => {
    if (selectedCount === 0) return null;

    const overLimit = selectedCount > MAX_BATCH_SIZE;

    return (
        <div className="batch-action-bar" role="toolbar" aria-label="Batch actions">
            <div className="batch-action-bar-info">
                <Badge appearance="filled" color="brand" size="medium">
                    {selectedCount}
                </Badge>
                <Text size={300} weight="semibold">
                    selected
                </Text>
                {overLimit && (
                    <Text size={200} style={{ color: "#d13438" }}>
                        (max {MAX_BATCH_SIZE} per batch)
                    </Text>
                )}
            </div>
            <div className="batch-action-bar-actions">
                <Button
                    appearance="secondary"
                    icon={<DismissRegular />}
                    onClick={onDismissAll}
                    disabled={overLimit}
                    size="small"
                >
                    Dismiss All
                </Button>
                <Button
                    appearance="secondary"
                    icon={<ClockRegular />}
                    onClick={onSnoozeAll}
                    disabled={overLimit}
                    size="small"
                >
                    Snooze All
                </Button>
                <Button
                    appearance="subtle"
                    icon={<DismissCircleRegular />}
                    onClick={onClearSelection}
                    size="small"
                >
                    Cancel
                </Button>
            </div>
        </div>
    );
};
