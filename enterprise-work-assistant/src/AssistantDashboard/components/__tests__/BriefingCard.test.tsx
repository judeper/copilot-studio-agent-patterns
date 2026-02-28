import * as React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { BriefingCard } from '../BriefingCard';
import { dailyBriefingItem } from '../../../test/fixtures/cardFixtures';
import type { AssistantCard } from '../types';

// Mock Fluent UI
jest.mock('@fluentui/react-components', () => ({
    Button: (props: Record<string, unknown>) => (
        <button onClick={props.onClick as () => void} disabled={props.disabled as boolean}>
            {props.children as React.ReactNode}
        </button>
    ),
    Text: (props: Record<string, unknown>) => <span>{props.children as React.ReactNode}</span>,
    Badge: (props: Record<string, unknown>) => <span>{props.children as React.ReactNode}</span>,
}));

describe('BriefingCard', () => {
    const mockJump = jest.fn();
    const mockDismiss = jest.fn();

    beforeEach(() => {
        jest.clearAllMocks();
    });

    it('renders the day shape narrative', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        expect(screen.getByText(/8 open items/)).toBeTruthy();
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

    it('calls onJumpToCard when "Open card →" is clicked', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
            />,
        );
        const jumpLinks = screen.getAllByText('Open card →');
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
        expect(screen.getByText(/inbox is clear/)).toBeTruthy();
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
});
