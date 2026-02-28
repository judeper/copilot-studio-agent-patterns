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
    onSendDraft: (cardId: string, finalText: string) => void;
    onCopyDraft: (cardId: string) => void;
    onDismissCard: (cardId: string) => void;
    onJumpToCard: (cardId: string) => void;
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
        onSendDraft: props.onSendDraft,
        onCopyDraft: props.onCopyDraft,
        onDismissCard: props.onDismissCard,
        onJumpToCard: props.onJumpToCard,
    });
};

export class AssistantDashboard implements ComponentFramework.ReactControl<IInputs, IOutputs> {
    private notifyOutputChanged: () => void;
    private selectedCardId: string = "";
    private sendDraftAction: string = "";
    private copyDraftAction: string = "";
    private dismissCardAction: string = "";
    private jumpToCardAction: string = "";
    private datasetVersion: number = 0;

    // Stable callback references — created once in init, never recreated
    private handleSelectCard: (cardId: string) => void;
    private handleSendDraft: (cardId: string, finalText: string) => void;
    private handleCopyDraft: (cardId: string) => void;
    private handleDismissCard: (cardId: string) => void;
    private handleJumpToCard: (cardId: string) => void;

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
        this.handleSendDraft = (cardId: string, finalText: string) => {
            // JSON-encode for Canvas app parsing via ParseJSON()
            // Canvas app uses isEdited to set SENT_AS_IS vs SENT_EDITED outcome
            this.sendDraftAction = JSON.stringify({ cardId, finalText });
            this.notifyOutputChanged();
        };
        this.handleCopyDraft = (cardId: string) => {
            this.copyDraftAction = cardId;
            this.notifyOutputChanged();
        };
        this.handleDismissCard = (cardId: string) => {
            this.dismissCardAction = cardId;
            this.notifyOutputChanged();
        };
        this.handleJumpToCard = (cardId: string) => {
            // Sprint 2: Navigate from briefing card to a specific regular card
            this.jumpToCardAction = cardId;
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
            onSendDraft: this.handleSendDraft,
            onCopyDraft: this.handleCopyDraft,
            onDismissCard: this.handleDismissCard,
            onJumpToCard: this.handleJumpToCard,
        });
    }

    public getOutputs(): IOutputs {
        const outputs: IOutputs = {
            selectedCardId: this.selectedCardId,
            sendDraftAction: this.sendDraftAction,
            copyDraftAction: this.copyDraftAction,
            dismissCardAction: this.dismissCardAction,
            jumpToCardAction: this.jumpToCardAction,
        };

        // Reset action outputs after reading to prevent stale re-fires
        this.sendDraftAction = "";
        this.copyDraftAction = "";
        this.dismissCardAction = "";
        this.jumpToCardAction = "";

        return outputs;
    }

    public destroy(): void {
        // Cleanup handled by React
    }
}
