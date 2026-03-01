import * as React from "react";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ConfidenceCalibration } from "../ConfidenceCalibration";
import type { AssistantCard } from "../types";
import {
    tier3FullItem,
    dailyBriefingItem,
} from "../../../test/fixtures/cardFixtures";

/**
 * ConfidenceCalibration test suite (F-04).
 *
 * Covers all 4 analytics tabs, empty states, division safety,
 * and edge cases for the analytics logic.
 */

// Helper: create a card with specific outcome and confidence
function makeCard(overrides: Partial<AssistantCard>): AssistantCard {
    return {
        ...tier3FullItem,
        id: `test-${Math.random().toString(36).substring(7)}`,
        ...overrides,
    };
}

function renderCalibration(cards: AssistantCard[] = []) {
    const onBack = jest.fn();
    const result = render(
        <ConfidenceCalibration cards={cards} onBack={onBack} />,
    );
    return { ...result, onBack };
}

describe("ConfidenceCalibration", () => {
    describe("Confidence Accuracy tab (default)", () => {
        it("renders accuracy table with confidence buckets", () => {
            const cards = [
                makeCard({ confidence_score: 95, card_outcome: "SENT_AS_IS", triage_tier: "FULL" }),
                makeCard({ confidence_score: 75, card_outcome: "SENT_EDITED", triage_tier: "FULL" }),
                makeCard({ confidence_score: 50, card_outcome: "DISMISSED", triage_tier: "FULL" }),
                makeCard({ confidence_score: 20, card_outcome: "EXPIRED", triage_tier: "FULL" }),
            ];
            renderCalibration(cards);

            expect(screen.getByText("Confidence Accuracy")).toBeInTheDocument();
            expect(screen.getByText("90-100")).toBeInTheDocument();
            expect(screen.getByText("70-89")).toBeInTheDocument();
            expect(screen.getByText("40-69")).toBeInTheDocument();
            expect(screen.getByText("0-39")).toBeInTheDocument();
        });

        it("calculates correct action rate percentages", () => {
            // 2 cards in 90-100 bucket: 1 acted, 1 dismissed => 50%
            const cards = [
                makeCard({ confidence_score: 95, card_outcome: "SENT_AS_IS", triage_tier: "FULL" }),
                makeCard({ confidence_score: 92, card_outcome: "DISMISSED", triage_tier: "FULL" }),
            ];
            renderCalibration(cards);

            // The 90-100 bucket should show 50% action rate
            expect(screen.getByText("50%")).toBeInTheDocument();
        });

        it("shows resolved card count in header", () => {
            const cards = [
                makeCard({ confidence_score: 80, card_outcome: "SENT_AS_IS", triage_tier: "FULL" }),
                makeCard({ confidence_score: 60, card_outcome: "DISMISSED", triage_tier: "FULL" }),
                makeCard({ card_outcome: "PENDING", triage_tier: "FULL" }), // excluded — still pending
            ];
            renderCalibration(cards);

            expect(screen.getByText(/Based on 2 resolved cards/)).toBeInTheDocument();
        });

        it("excludes DAILY_BRIEFING cards from resolved count", () => {
            const cards = [
                makeCard({ confidence_score: 80, card_outcome: "SENT_AS_IS", triage_tier: "FULL" }),
                dailyBriefingItem,
            ];
            renderCalibration(cards);

            expect(screen.getByText(/Based on 1 resolved card/)).toBeInTheDocument();
        });
    });

    describe("Triage Quality tab", () => {
        it("shows triage accuracy stats when clicked", async () => {
            const cards = [
                makeCard({ triage_tier: "FULL", card_outcome: "SENT_AS_IS", confidence_score: 80 }),
                makeCard({ triage_tier: "FULL", card_outcome: "DISMISSED", confidence_score: 70 }),
                makeCard({ triage_tier: "LIGHT", card_outcome: "DISMISSED", confidence_score: null }),
            ];
            renderCalibration(cards);

            await userEvent.click(screen.getByRole("tab", { name: "Triage Quality" }));

            expect(screen.getByText("FULL card action rate")).toBeInTheDocument();
            expect(screen.getByText("FULL cards dismissed")).toBeInTheDocument();
            expect(screen.getByText("LIGHT card dismiss rate")).toBeInTheDocument();
        });

        it("calculates correct FULL card action rate", async () => {
            const cards = [
                makeCard({ triage_tier: "FULL", card_outcome: "SENT_AS_IS", confidence_score: 90 }),
                makeCard({ triage_tier: "FULL", card_outcome: "SENT_EDITED", confidence_score: 85 }),
                makeCard({ triage_tier: "FULL", card_outcome: "DISMISSED", confidence_score: 60 }),
            ];
            renderCalibration(cards);

            await userEvent.click(screen.getByRole("tab", { name: "Triage Quality" }));

            // 2/3 FULL cards acted on = 67%
            expect(screen.getByText("67%")).toBeInTheDocument();
        });
    });

    describe("Draft Quality tab", () => {
        it("shows draft quality stats", async () => {
            const cards = [
                makeCard({ card_outcome: "SENT_AS_IS", triage_tier: "FULL", confidence_score: 90 }),
                makeCard({ card_outcome: "SENT_EDITED", triage_tier: "FULL", confidence_score: 70 }),
                makeCard({ card_outcome: "SENT_AS_IS", triage_tier: "FULL", confidence_score: 85 }),
            ];
            renderCalibration(cards);

            await userEvent.click(screen.getByRole("tab", { name: "Draft Quality" }));

            expect(screen.getByText("Sent as-is rate")).toBeInTheDocument();
            expect(screen.getByText("Drafts edited before send")).toBeInTheDocument();
        });

        it("calculates correct as-is rate", async () => {
            const cards = [
                makeCard({ card_outcome: "SENT_AS_IS", triage_tier: "FULL", confidence_score: 90 }),
                makeCard({ card_outcome: "SENT_AS_IS", triage_tier: "FULL", confidence_score: 85 }),
                makeCard({ card_outcome: "SENT_EDITED", triage_tier: "FULL", confidence_score: 70 }),
            ];
            renderCalibration(cards);

            await userEvent.click(screen.getByRole("tab", { name: "Draft Quality" }));

            // 2/3 sent as-is = 67%
            expect(screen.getByText("67%")).toBeInTheDocument();
        });
    });

    describe("Top Senders tab", () => {
        it("shows sender engagement table", async () => {
            const cards = [
                makeCard({ original_sender_email: "alice@contoso.com", original_sender_display: "Alice", card_outcome: "SENT_AS_IS" }),
                makeCard({ original_sender_email: "alice@contoso.com", original_sender_display: "Alice", card_outcome: "DISMISSED" }),
                makeCard({ original_sender_email: "bob@contoso.com", original_sender_display: "Bob", card_outcome: "SENT_EDITED" }),
            ];
            renderCalibration(cards);

            await userEvent.click(screen.getByRole("tab", { name: "Top Senders" }));

            expect(screen.getByText("Alice")).toBeInTheDocument();
            expect(screen.getByText("Bob")).toBeInTheDocument();
        });

        it("shows empty state when no sender data", async () => {
            const cards = [
                makeCard({ original_sender_email: null, card_outcome: "SENT_AS_IS" }),
            ];
            renderCalibration(cards);

            await userEvent.click(screen.getByRole("tab", { name: "Top Senders" }));

            expect(screen.getByText(/No sender data yet/)).toBeInTheDocument();
        });
    });

    describe("Empty state", () => {
        it("renders with zero cards without errors", () => {
            renderCalibration([]);

            expect(screen.getByText("Agent Performance")).toBeInTheDocument();
            expect(screen.getByText(/Based on 0 resolved cards/)).toBeInTheDocument();
        });

        it("shows 'No data' instead of 0% with no resolved cards", () => {
            renderCalibration([]);

            // All accuracy buckets should show "No data" instead of "0%"
            const noDataTexts = screen.getAllByText("No data");
            expect(noDataTexts.length).toBeGreaterThan(0);
            // Should not show any "0%" in the accuracy tab
            expect(screen.queryByText("0%")).toBeNull();
        });
    });

    describe("Division safety", () => {
        it("handles zero total cards without NaN or Infinity", () => {
            const { container } = renderCalibration([]);

            const textContent = container.textContent ?? "";
            expect(textContent).not.toContain("NaN");
            expect(textContent).not.toContain("Infinity");
        });

        it("handles zero sent cards in draft quality without NaN", async () => {
            // All cards dismissed — no sent cards to divide by
            const cards = [
                makeCard({ card_outcome: "DISMISSED", triage_tier: "FULL", confidence_score: 80 }),
                makeCard({ card_outcome: "DISMISSED", triage_tier: "FULL", confidence_score: 60 }),
            ];
            const { container } = renderCalibration(cards);

            await userEvent.click(screen.getByRole("tab", { name: "Draft Quality" }));

            const textContent = container.textContent ?? "";
            expect(textContent).not.toContain("NaN");
            expect(textContent).not.toContain("Infinity");
        });

        it("handles zero FULL cards in triage without NaN", async () => {
            const cards = [
                makeCard({ triage_tier: "LIGHT", card_outcome: "DISMISSED", confidence_score: null }),
            ];
            const { container } = renderCalibration(cards);

            await userEvent.click(screen.getByRole("tab", { name: "Triage Quality" }));

            const textContent = container.textContent ?? "";
            expect(textContent).not.toContain("NaN");
            expect(textContent).not.toContain("Infinity");
        });
    });

    describe("Edge cases", () => {
        it("handles single card", () => {
            const cards = [
                makeCard({ confidence_score: 95, card_outcome: "SENT_AS_IS", triage_tier: "FULL" }),
            ];
            renderCalibration(cards);

            expect(screen.getByText(/Based on 1 resolved card/)).toBeInTheDocument();
            // 90-100 bucket: 1 card, 100% action rate
            expect(screen.getByText("100%")).toBeInTheDocument();
        });

        it("handles all cards in same triage tier", async () => {
            const cards = [
                makeCard({ triage_tier: "FULL", card_outcome: "SENT_AS_IS", confidence_score: 90 }),
                makeCard({ triage_tier: "FULL", card_outcome: "SENT_AS_IS", confidence_score: 80 }),
            ];
            renderCalibration(cards);

            await userEvent.click(screen.getByRole("tab", { name: "Triage Quality" }));

            // 100% FULL card action rate
            expect(screen.getByText("100%")).toBeInTheDocument();
        });

        it("handles null confidence scores gracefully", () => {
            const cards = [
                makeCard({ confidence_score: null, card_outcome: "SENT_AS_IS", triage_tier: "FULL" }),
                makeCard({ confidence_score: null, card_outcome: "DISMISSED", triage_tier: "LIGHT" }),
            ];
            const { container } = renderCalibration(cards);

            const textContent = container.textContent ?? "";
            expect(textContent).not.toContain("NaN");
            expect(textContent).not.toContain("Infinity");
        });

        it("back button calls onBack", async () => {
            const { onBack } = renderCalibration([]);

            await userEvent.click(screen.getByText(/Back to Dashboard/));

            expect(onBack).toHaveBeenCalledTimes(1);
        });

        it("shows 'No data' for empty accuracy buckets with populated cards in other buckets", () => {
            // Only one card in 90-100 bucket, other buckets should show "No data"
            const cards = [
                makeCard({ confidence_score: 95, card_outcome: "SENT_AS_IS", triage_tier: "FULL" }),
            ];
            renderCalibration(cards);

            // 90-100 bucket has data, other 3 buckets show "No data"
            const noDataTexts = screen.getAllByText("No data");
            expect(noDataTexts.length).toBe(3);
        });
    });
});
