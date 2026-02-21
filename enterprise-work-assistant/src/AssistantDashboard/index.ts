import { IInputs, IOutputs } from "./generated/ManifestTypes";
import * as React from "react";
import { App } from "./components/App";
import { useCardData } from "./hooks/useCardData";
import type { AssistantCard } from "./components/types";

/**
 * AppWrapper — functional component that bridges the PCF dataset API
 * into the typed React component tree using the useCardData hook.
 */
const AppWrapper: React.FC<{
    dataset: ComponentFramework.PropertyTypes.DataSet;
    filterTriggerType: string;
    filterPriority: string;
    filterCardStatus: string;
    filterTemporalHorizon: string;
    width: number;
    height: number;
    onSelectCard: (cardId: string) => void;
    onEditDraft: (cardId: string) => void;
    onDismissCard: (cardId: string) => void;
}> = (props) => {
    // Cast PCF DataSet to the hook's expected interface shape
    const cards: AssistantCard[] = useCardData(props.dataset as Parameters<typeof useCardData>[0]);

    return React.createElement(App, {
        cards,
        filterTriggerType: props.filterTriggerType,
        filterPriority: props.filterPriority,
        filterCardStatus: props.filterCardStatus,
        filterTemporalHorizon: props.filterTemporalHorizon,
        width: props.width,
        height: props.height,
        onSelectCard: props.onSelectCard,
        onEditDraft: props.onEditDraft,
        onDismissCard: props.onDismissCard,
    });
};

export class AssistantDashboard implements ComponentFramework.ReactControl<IInputs, IOutputs> {
    private notifyOutputChanged: () => void;
    private selectedCardId: string = "";
    private editDraftAction: string = "";
    private dismissCardAction: string = "";

    public init(
        context: ComponentFramework.Context<IInputs>,
        notifyOutputChanged: () => void,
    ): void {
        this.notifyOutputChanged = notifyOutputChanged;
        context.mode.trackContainerResize(true);
    }

    public updateView(
        context: ComponentFramework.Context<IInputs>,
    ): React.ReactElement {
        const dataset = context.parameters.cardDataset;
        const width = context.mode.allocatedWidth;
        const height = context.mode.allocatedHeight;

        return React.createElement(AppWrapper, {
            dataset: dataset,
            filterTriggerType: context.parameters.filterTriggerType?.raw ?? "",
            filterPriority: context.parameters.filterPriority?.raw ?? "",
            filterCardStatus: context.parameters.filterCardStatus?.raw ?? "",
            filterTemporalHorizon: context.parameters.filterTemporalHorizon?.raw ?? "",
            width: width > 0 ? width : 800,
            height: height > 0 ? height : 600,
            onSelectCard: (cardId: string) => {
                this.selectedCardId = cardId;
                this.notifyOutputChanged();
            },
            onEditDraft: (cardId: string) => {
                this.editDraftAction = cardId;
                this.notifyOutputChanged();
            },
            onDismissCard: (cardId: string) => {
                this.dismissCardAction = cardId;
                this.notifyOutputChanged();
            },
        });
    }

    public getOutputs(): IOutputs {
        return {
            selectedCardId: this.selectedCardId,
            editDraftAction: this.editDraftAction,
            dismissCardAction: this.dismissCardAction,
        };
    }

    public destroy(): void {
        // Cleanup handled by React
    }
}
