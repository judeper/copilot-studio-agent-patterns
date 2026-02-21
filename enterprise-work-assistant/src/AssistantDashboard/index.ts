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
    datasetVersion: number;
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
    const cards: AssistantCard[] = useCardData(
        props.dataset as Parameters<typeof useCardData>[0],
        props.datasetVersion,
    );

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
    private datasetVersion: number = 0;

    // Stable callback references — created once in init, never recreated
    private handleSelectCard: (cardId: string) => void;
    private handleEditDraft: (cardId: string) => void;
    private handleDismissCard: (cardId: string) => void;

    public init(
        context: ComponentFramework.Context<IInputs>,
        notifyOutputChanged: () => void,
    ): void {
        this.notifyOutputChanged = notifyOutputChanged;
        context.mode.trackContainerResize(true);

        this.handleSelectCard = (cardId: string) => {
            this.selectedCardId = cardId;
            this.notifyOutputChanged();
        };
        this.handleEditDraft = (cardId: string) => {
            this.editDraftAction = cardId;
            this.notifyOutputChanged();
        };
        this.handleDismissCard = (cardId: string) => {
            this.dismissCardAction = cardId;
            this.notifyOutputChanged();
        };
    }

    public updateView(
        context: ComponentFramework.Context<IInputs>,
    ): React.ReactElement {
        const dataset = context.parameters.cardDataset;
        const width = context.mode.allocatedWidth;
        const height = context.mode.allocatedHeight;

        // Increment version so useMemo in useCardData re-computes
        this.datasetVersion++;

        return React.createElement(AppWrapper, {
            dataset: dataset,
            datasetVersion: this.datasetVersion,
            filterTriggerType: context.parameters.filterTriggerType?.raw ?? "",
            filterPriority: context.parameters.filterPriority?.raw ?? "",
            filterCardStatus: context.parameters.filterCardStatus?.raw ?? "",
            filterTemporalHorizon: context.parameters.filterTemporalHorizon?.raw ?? "",
            width: width > 0 ? width : 800,
            height: height > 0 ? height : 600,
            onSelectCard: this.handleSelectCard,
            onEditDraft: this.handleEditDraft,
            onDismissCard: this.handleDismissCard,
        });
    }

    public getOutputs(): IOutputs {
        const outputs: IOutputs = {
            selectedCardId: this.selectedCardId,
            editDraftAction: this.editDraftAction,
            dismissCardAction: this.dismissCardAction,
        };

        // Reset action outputs after reading to prevent stale re-fires
        this.editDraftAction = "";
        this.dismissCardAction = "";

        return outputs;
    }

    public destroy(): void {
        // Cleanup handled by React
    }
}
