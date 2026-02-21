import * as React from "react";
import { Badge, Text, tokens } from "@fluentui/react-components";

interface FilterBarProps {
    cardCount: number;
    filterTriggerType: string;
    filterPriority: string;
    filterCardStatus: string;
    filterTemporalHorizon: string;
}

export const FilterBar: React.FC<FilterBarProps> = ({
    cardCount,
    filterTriggerType,
    filterPriority,
    filterCardStatus,
    filterTemporalHorizon,
}) => {
    const activeFilters: string[] = [];
    if (filterTriggerType) activeFilters.push(filterTriggerType);
    if (filterPriority) activeFilters.push(filterPriority);
    if (filterCardStatus) activeFilters.push(filterCardStatus);
    if (filterTemporalHorizon) activeFilters.push(filterTemporalHorizon);

    return (
        <div className="filter-bar">
            <Text size={300} weight="semibold" style={{ color: tokens.colorNeutralForeground1 }}>
                {cardCount} {cardCount === 1 ? "card" : "cards"}
            </Text>
            {activeFilters.length > 0 && (
                <div className="filter-bar-labels">
                    {activeFilters.map((filter) => (
                        <Badge key={filter} appearance="outline" size="small">
                            {filter}
                        </Badge>
                    ))}
                </div>
            )}
        </div>
    );
};
