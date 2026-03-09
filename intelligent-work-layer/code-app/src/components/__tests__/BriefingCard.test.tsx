import React from 'react';
import { vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { BriefingCard } from '../BriefingCard';
import { dailyBriefingItem } from '../../test/fixtures/cardFixtures';
import type { AssistantCard } from '../types';

// Mock Fluent UI
vi.mock('@fluentui/react-components', () => ({
    Button: (props: Record<string, unknown>) => (
        <button onClick={props.onClick as () => void} disabled={props.disabled as boolean}>
            {props.children as React.ReactNode}
        </button>
    ),
    Text: (props: Record<string, unknown>) => <span>{props.children as React.ReactNode}</span>,
    Badge: (props: Record<string, unknown>) => <span>{props.children as React.ReactNode}</span>,
    Card: (props: Record<string, unknown>) => (
        <div onClickCapture={props.onClickCapture as () => void}>
            {props.children as React.ReactNode}
        </div>
    ),
}));

// Mock Fluent UI Icons
vi.mock('@fluentui/react-icons', () => ({
    ArrowLeftRegular: () => <span data-testid="icon-arrow-left" />,
    DismissRegular: () => <span data-testid="icon-dismiss" />,
    ChevronDownRegular: () => <span data-testid="icon-chevron-down" />,
    ChevronRightRegular: () => <span data-testid="icon-chevron-right" />,
    CalendarRegular: () => <span data-testid="icon-calendar" />,
    ArrowRightRegular: () => <span data-testid="icon-arrow-right" />,
    WeatherSunnyRegular: () => <span data-testid="icon-weather-sunny" />,
    WeatherMoonRegular: () => <span data-testid="icon-weather-moon" />,
    CheckmarkCircleRegular: () => <span data-testid="icon-checkmark-circle" />,
    ChatBubblesQuestionRegular: () => <span data-testid="icon-chat-bubbles" />,
    LightbulbRegular: () => <span data-testid="icon-lightbulb" />,
}));

describe('BriefingCard', () => {
    const mockJump = vi.fn();
    const mockDismiss = vi.fn();

    beforeEach(() => {
        vi.clearAllMocks();
    });

    it('renders the day shape narrative', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        expect(screen.getAllByText(/8 open items/).length).toBeGreaterThan(0);
    });

    it('renders action items with rank numbers', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        expect(screen.getByText('#1')).toBeTruthy();
        expect(screen.getByText('#2')).toBeTruthy();
    });

    it('renders the briefing date', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        expect(screen.getByText('2026-02-28')).toBeTruthy();
    });

    it('renders stale alerts section', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        expect(screen.getByText('Overdue Items')).toBeTruthy();
        expect(screen.getByText(/US Bank compliance/)).toBeTruthy();
    });

    it('calls onJumpToCard when "Open card" is clicked', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        const jumpLinks = screen.getAllByText('Open card');
        fireEvent.click(jumpLinks[0]);
        expect(mockJump).toHaveBeenCalledWith('full-001');
    });

    it('calls onDismissCard when "Dismiss briefing" is clicked', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        fireEvent.click(screen.getByText('Dismiss briefing'));
        expect(mockDismiss).toHaveBeenCalledWith('briefing-001');
    });

    it('FYI section is collapsed by default', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        // FYI header visible but items not rendered
        expect(screen.getByText(/For Your Information/)).toBeTruthy();
        expect(screen.queryByText(/QBR with Northwind/)).toBeNull();
    });

    it('FYI section expands on click', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        fireEvent.click(screen.getByText(/For Your Information/));
        expect(screen.getByText(/QBR with Northwind/)).toBeTruthy();
    });

    it('renders error state for invalid briefing JSON', () => {
        const badCard: AssistantCard = {
            ...dailyBriefingItem,
            draft_payload: 'not valid json{',
        };
        render(
            <BriefingCard
                card={badCard}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        expect(screen.getByText(/Unable to parse briefing data/)).toBeTruthy();
    });

    it('renders empty state when no action items', () => {
        const emptyCard: AssistantCard = {
            ...dailyBriefingItem,
            draft_payload: JSON.stringify({
                briefing_type: 'DAILY',
                briefing_date: '2026-02-28',
                total_open_items: 0,
                day_shape: 'Your inbox is clear.',
                action_items: [],
            }),
        };
        render(
            <BriefingCard
                card={emptyCard}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        expect(screen.getAllByText(/inbox is clear/).length).toBeGreaterThan(0);
    });

    it('renders calendar correlation on action items', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        expect(screen.getByText(/Q3 Budget Review/)).toBeTruthy();
    });

    it('renders Back button when onBack is provided', () => {
        const mockBack = vi.fn();
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
                onBack={mockBack}
            />,
        );
        const backButton = screen.getByText('Back');
        expect(backButton).toBeTruthy();
        fireEvent.click(backButton);
        expect(mockBack).toHaveBeenCalledTimes(1);
    });

    it('does not render Back button when onBack is omitted', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        expect(screen.queryByText('Back')).toBeNull();
    });

    it('calls onBack when Escape is pressed in detail view', () => {
        const mockBack = vi.fn();
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
                onBack={mockBack}
            />,
        );

        fireEvent.keyDown(document, { key: 'Escape' });
        expect(mockBack).toHaveBeenCalledTimes(1);
    });

    // ── Phase C1: Morning Briefing ──

    it('renders morning briefing summary for DAILY briefing type', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        expect(screen.getByText('Start-of-day summary')).toBeTruthy();
        expect(screen.getByText(/front-loaded around/)).toBeTruthy();
        expect(screen.getByText('Start my day')).toBeTruthy();
    });

    it('renders morning metric tiles', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        expect(screen.getByText('First decision')).toBeTruthy();
        expect(screen.getByText('Protected window')).toBeTruthy();
        expect(screen.getByText('Next context shift')).toBeTruthy();
    });

    it('calls onJumpToCard when Start my day is clicked', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        fireEvent.click(screen.getByText('Start my day'));
        expect(mockJump).toHaveBeenCalledWith('full-001');
    });

    // ── Phase C2: End-of-Day Review ──

    it('renders end-of-day review for END_OF_DAY briefing type', () => {
        const eodCard: AssistantCard = {
            ...dailyBriefingItem,
            draft_payload: JSON.stringify({
                briefing_type: 'END_OF_DAY',
                briefing_date: '2026-02-28',
                total_open_items: 3,
                day_shape: 'Wrapping up your day.',
                action_items: [
                    {
                        rank: 1,
                        card_ids: ['full-001'],
                        thread_summary: 'Remaining item',
                        recommended_action: 'Carry forward to tomorrow',
                        urgency_reason: 'Low urgency',
                        related_calendar: null,
                    },
                ],
            }),
        };
        render(
            <BriefingCard
                card={eodCard}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        expect(screen.getByText('End-of-Day Review')).toBeTruthy();
        expect(screen.getByText('Completed')).toBeTruthy();
        expect(screen.getByText('Deferred')).toBeTruthy();
        expect(screen.getByText('Protected focus')).toBeTruthy();
        expect(screen.getByText('Finalize review')).toBeTruthy();
        expect(screen.getByText('Rebuild tomorrow lane')).toBeTruthy();
    });

    it('renders carry-forward items in EOD review', () => {
        const eodCard: AssistantCard = {
            ...dailyBriefingItem,
            draft_payload: JSON.stringify({
                briefing_type: 'END_OF_DAY',
                briefing_date: '2026-02-28',
                total_open_items: 1,
                day_shape: 'Day is wrapping up.',
                action_items: [
                    {
                        rank: 1,
                        card_ids: ['full-001'],
                        thread_summary: 'Contract item',
                        recommended_action: 'Review contract before deadline',
                        urgency_reason: 'High priority',
                        related_calendar: null,
                    },
                ],
            }),
        };
        render(
            <BriefingCard
                card={eodCard}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        expect(screen.getByText("Tomorrow's carry-forward")).toBeTruthy();
        expect(screen.getAllByText('Review contract before deadline').length).toBeGreaterThanOrEqual(1);
    });

    // ── Phase C3: Enhanced Meeting Briefing ──

    it('renders meeting briefing sections for action items', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        expect(screen.getByText('What changed')).toBeTruthy();
        expect(screen.getByText('Open decisions')).toBeTruthy();
        expect(screen.getByText('Suggested talking points')).toBeTruthy();
    });

    it('shows Briefed badge after clicking on a button inside the card', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        expect(screen.queryByText('Briefed')).toBeNull();
        // Click a button inside the card — the onClickCapture on Card should fire
        fireEvent.click(screen.getByText('Start my day'));
        expect(screen.getByText('Briefed')).toBeTruthy();
    });
});
