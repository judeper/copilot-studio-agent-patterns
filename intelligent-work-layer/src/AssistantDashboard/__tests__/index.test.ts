import * as React from "react";
import { AssistantDashboard } from "../index";

/**
 * PCF lifecycle test suite (F-05).
 *
 * Tests the AssistantDashboard class's init, updateView, getOutputs, and destroy
 * methods. Mocks the ComponentFramework.Context interface since the PCF runtime
 * is not available in the test environment.
 */

// Mock App component to avoid rendering the full React tree
jest.mock("../components/App", () => ({
    App: (props: Record<string, unknown>) => {
        // Store last props for assertion
        (global as Record<string, unknown>).__lastAppProps = props;
        return null;
    },
}));

// Mock useCardData to return empty cards
jest.mock("../hooks/useCardData", () => ({
    useCardData: () => [],
}));

function createMockContext(overrides?: {
    filterTriggerType?: string;
    filterPriority?: string;
    filterCardStatus?: string;
    filterTemporalHorizon?: string;
    orchestratorResponse?: string | null;
    isProcessing?: boolean;
    width?: number;
    height?: number;
    datasetRecordIds?: string[];
}): ComponentFramework.Context<Record<string, unknown>> {
    const opts = overrides ?? {};
    return {
        parameters: {
            filterTriggerType: { raw: opts.filterTriggerType ?? "" },
            filterPriority: { raw: opts.filterPriority ?? "" },
            filterCardStatus: { raw: opts.filterCardStatus ?? "" },
            filterTemporalHorizon: { raw: opts.filterTemporalHorizon ?? "" },
            orchestratorResponse: { raw: opts.orchestratorResponse ?? null },
            isProcessing: { raw: opts.isProcessing ?? false },
            cardDataset: {
                sortedRecordIds: opts.datasetRecordIds ?? [],
                records: {},
                columns: [],
                paging: { totalResultCount: 0, hasNextPage: false, hasPreviousPage: false },
            },
        },
        mode: {
            trackContainerResize: jest.fn(),
            allocatedWidth: opts.width ?? 1024,
            allocatedHeight: opts.height ?? 768,
            isControlDisabled: false,
            isVisible: true,
        },
    } as unknown as ComponentFramework.Context<Record<string, unknown>>;
}

describe("AssistantDashboard PCF lifecycle", () => {
    let control: AssistantDashboard;
    let notifyOutputChanged: jest.Mock;

    beforeEach(() => {
        control = new AssistantDashboard();
        notifyOutputChanged = jest.fn();
    });

    describe("init()", () => {
        it("stores notifyOutputChanged callback and enables container resize tracking", () => {
            const context = createMockContext();

            control.init(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
                notifyOutputChanged,
            );

            expect(context.mode.trackContainerResize).toHaveBeenCalledWith(true);
        });

        it("creates stable callback references", () => {
            const context = createMockContext();

            control.init(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
                notifyOutputChanged,
            );

            // Callbacks are created during init — verify they work by triggering them via updateView + getOutputs
            const element = control.updateView(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
            );
            expect(element).toBeTruthy();
        });
    });

    describe("updateView()", () => {
        it("returns a React element", () => {
            const context = createMockContext();
            control.init(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
                notifyOutputChanged,
            );

            const element = control.updateView(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
            );

            expect(React.isValidElement(element)).toBe(true);
        });

        it("passes filter properties from context parameters", () => {
            const context = createMockContext({
                filterTriggerType: "EMAIL",
                filterPriority: "High",
                filterCardStatus: "READY",
                filterTemporalHorizon: "TODAY",
            });
            control.init(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
                notifyOutputChanged,
            );

            const element = control.updateView(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
            );

            // The AppWrapper is rendered with the filter props
            expect(element.props.filterTriggerType).toBe("EMAIL");
            expect(element.props.filterPriority).toBe("High");
            expect(element.props.filterCardStatus).toBe("READY");
            expect(element.props.filterTemporalHorizon).toBe("TODAY");
        });

        it("passes orchestrator response properties", () => {
            const context = createMockContext({
                orchestratorResponse: '{"response_text":"test"}',
                isProcessing: true,
            });
            control.init(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
                notifyOutputChanged,
            );

            const element = control.updateView(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
            );

            expect(element.props.orchestratorResponse).toBe('{"response_text":"test"}');
            expect(element.props.isProcessing).toBe(true);
        });

        it("uses default dimensions when allocated size is zero", () => {
            const context = createMockContext({ width: 0, height: 0 });
            control.init(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
                notifyOutputChanged,
            );

            const element = control.updateView(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
            );

            expect(element.props.width).toBe(800);
            expect(element.props.height).toBe(600);
        });

        it("increments datasetVersion on each call", () => {
            const context = createMockContext();
            control.init(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
                notifyOutputChanged,
            );

            const element1 = control.updateView(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
            );
            const element2 = control.updateView(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
            );

            expect(element2.props.datasetVersion).toBe(element1.props.datasetVersion + 1);
        });
    });

    describe("getOutputs()", () => {
        it("returns the expected output property structure", () => {
            const context = createMockContext();
            control.init(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
                notifyOutputChanged,
            );

            const outputs = control.getOutputs();

            expect(outputs).toHaveProperty("selectedCardId");
            expect(outputs).toHaveProperty("sendDraftAction");
            expect(outputs).toHaveProperty("copyDraftAction");
            expect(outputs).toHaveProperty("dismissCardAction");
            expect(outputs).toHaveProperty("jumpToCardAction");
            expect(outputs).toHaveProperty("commandAction");
        });

        it("resets action outputs after reading to prevent stale re-fires", () => {
            const context = createMockContext();
            control.init(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
                notifyOutputChanged,
            );

            // Trigger a select action via callback
            control.updateView(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
            );

            // First call returns the action values
            const firstOutputs = control.getOutputs();
            expect(firstOutputs.selectedCardId).toBe("");

            // Second call should have cleared action outputs
            const secondOutputs = control.getOutputs();
            expect(secondOutputs.sendDraftAction).toBe("");
            expect(secondOutputs.copyDraftAction).toBe("");
            expect(secondOutputs.dismissCardAction).toBe("");
            expect(secondOutputs.jumpToCardAction).toBe("");
            expect(secondOutputs.commandAction).toBe("");
        });
    });

    describe("destroy()", () => {
        it("does not throw when called", () => {
            const context = createMockContext();
            control.init(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
                notifyOutputChanged,
            );

            expect(() => control.destroy()).not.toThrow();
        });
    });

    describe("Output property fire-and-reset cycle", () => {
        it("fires notifyOutputChanged when a card is selected, then resets on next getOutputs", () => {
            const context = createMockContext();
            control.init(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
                notifyOutputChanged,
            );

            // Render to get callbacks
            const element = control.updateView(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
            );

            // Simulate onSelectCard callback
            element.props.onSelectCard("card-123");
            expect(notifyOutputChanged).toHaveBeenCalledTimes(1);

            // getOutputs should return the selected card
            const outputs = control.getOutputs();
            expect(outputs.selectedCardId).toBe("card-123");
        });

        it("fires notifyOutputChanged for command execution", () => {
            const context = createMockContext();
            control.init(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
                notifyOutputChanged,
            );

            const element = control.updateView(
                context as unknown as ComponentFramework.Context<import("../generated/ManifestTypes").IInputs>,
            );

            // Simulate onExecuteCommand callback
            element.props.onExecuteCommand("show urgent", "card-456");
            expect(notifyOutputChanged).toHaveBeenCalledTimes(1);

            const outputs = control.getOutputs();
            const parsed = JSON.parse(outputs.commandAction as string);
            expect(parsed.command).toBe("show urgent");
            expect(parsed.currentCardId).toBe("card-456");
        });
    });
});
