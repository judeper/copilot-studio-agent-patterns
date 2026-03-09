import React from 'react';
import { vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { DayGlance } from '../DayGlance';
import type { AssistantCard } from '../types';

function makeCard(overrides: Partial<AssistantCard>): AssistantCard {
    return {
        id: 'test',
        trigger_type: 'EMAIL',
        triage_tier: 'FULL',
        item_summary: 'Test card',
        priority: null,
        temporal_horizon: null,
        research_log: null,
        key_findings: null,
        verified_sources: null,
        confidence_score: null,
        card_status: 'READY',
        draft_payload: null,
        low_confidence_note: null,
        humanized_draft: null,
        created_on: new Date().toISOString(),
        card_outcome: 'PENDING',
        original_sender_email: null,
        original_sender_display: null,
        original_subject: null,
        conversation_cluster_id: null,
        source_signal_id: null,
        hours_stale: null,
        ...overrides,
    };
}

describe('DayGlance', () => {
    it('returns null when no calendar or briefing cards exist', () => {
        const cards = [
            makeCard({ id: '1', trigger_type: 'EMAIL' }),
            makeCard({ id: '2', trigger_type: 'TEAMS_MESSAGE' }),
        ];
        const { container } = render(<DayGlance cards={cards} />);
        expect(container.firstChild).toBeNull();
    });

    it('renders header when calendar cards exist', () => {
        const cards = [
            makeCard({ id: '1', trigger_type: 'CALENDAR_SCAN', item_summary: 'Team standup' }),
        ];
        render(<DayGlance cards={cards} />);
        expect(screen.getByText('Today at a glance')).toBeInTheDocument();
    });

    it('shows "Meeting" label for CALENDAR_SCAN cards', () => {
        const cards = [
            makeCard({ id: '1', trigger_type: 'CALENDAR_SCAN', item_summary: 'Sprint review' }),
        ];
        render(<DayGlance cards={cards} />);
        expect(screen.getByText('Meeting')).toBeInTheDocument();
        expect(screen.getByText('Sprint review')).toBeInTheDocument();
    });

    it('shows "Briefing" label for DAILY_BRIEFING cards', () => {
        const cards = [
            makeCard({ id: '1', trigger_type: 'DAILY_BRIEFING', item_summary: 'Morning briefing' }),
        ];
        render(<DayGlance cards={cards} />);
        expect(screen.getByText('Briefing')).toBeInTheDocument();
        expect(screen.getByText('Morning briefing')).toBeInTheDocument();
    });

    it('truncates to 4 items maximum', () => {
        const cards = Array.from({ length: 6 }, (_, i) =>
            makeCard({ id: `cal-${i}`, trigger_type: 'CALENDAR_SCAN', item_summary: `Meeting ${i}` }),
        );
        render(<DayGlance cards={cards} />);
        const items = screen.getAllByText(/Meeting \d/);
        expect(items).toHaveLength(4);
    });

    it('filters out non-calendar/briefing cards', () => {
        const cards = [
            makeCard({ id: '1', trigger_type: 'EMAIL', item_summary: 'Email item' }),
            makeCard({ id: '2', trigger_type: 'CALENDAR_SCAN', item_summary: 'Calendar item' }),
            makeCard({ id: '3', trigger_type: 'TEAMS_MESSAGE', item_summary: 'Teams item' }),
        ];
        render(<DayGlance cards={cards} />);
        expect(screen.getByText('Calendar item')).toBeInTheDocument();
        expect(screen.queryByText('Email item')).not.toBeInTheDocument();
        expect(screen.queryByText('Teams item')).not.toBeInTheDocument();
    });
});
