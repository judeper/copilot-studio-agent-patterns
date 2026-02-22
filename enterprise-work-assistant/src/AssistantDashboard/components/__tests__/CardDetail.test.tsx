import * as React from 'react';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { CardDetail } from '../CardDetail';
import { renderWithProviders } from '../../../test/helpers/renderWithProviders';
import {
    tier3FullItem,
    tier1SkipItem,
    lowConfidenceItem,
    calendarBriefingItem,
} from '../../../test/fixtures/cardFixtures';
import type { AssistantCard } from '../types';

function renderCardDetail(
    card: AssistantCard,
    overrides: Partial<{
        onBack: () => void;
        onEditDraft: (id: string) => void;
        onDismissCard: (id: string) => void;
    }> = {},
) {
    const defaultProps = {
        card,
        onBack: jest.fn(),
        onEditDraft: jest.fn(),
        onDismissCard: jest.fn(),
    };
    return renderWithProviders(
        <CardDetail {...defaultProps} {...overrides} />
    );
}

describe('CardDetail', () => {
    it('renders item summary', () => {
        renderCardDetail(tier3FullItem);

        expect(screen.getByText(tier3FullItem.item_summary)).toBeInTheDocument();
    });

    it('renders priority badge', () => {
        renderCardDetail(tier3FullItem);

        expect(screen.getByText('High')).toBeInTheDocument();
    });

    it('renders confidence badge', () => {
        renderCardDetail(tier3FullItem);

        expect(screen.getByText('Confidence: 87%')).toBeInTheDocument();
    });

    it('renders trigger type badge', () => {
        renderCardDetail(tier3FullItem);

        expect(screen.getByText('EMAIL')).toBeInTheDocument();
    });

    it('renders key findings section', () => {
        renderCardDetail(tier3FullItem);

        expect(screen.getByText('Key Findings')).toBeInTheDocument();
        expect(screen.getByText('Contract expires March 1')).toBeInTheDocument();
    });

    it('renders research log section', () => {
        renderCardDetail(tier3FullItem);

        expect(screen.getByText('Research Log')).toBeInTheDocument();
    });

    it('renders verified sources with safe URLs as links', () => {
        renderCardDetail(tier3FullItem);

        const sourceLink = screen.getByText('Fabrikam Contract Portal');
        expect(sourceLink.closest('a')).toHaveAttribute(
            'href',
            'https://fabrikam.example.com/contracts'
        );
    });

    it('renders unsafe URLs as plain text (not links)', () => {
        const unsafeSourceCard: AssistantCard = {
            ...tier3FullItem,
            id: 'unsafe-src-001',
            verified_sources: [
                { title: 'Malicious Site', url: 'javascript:alert(1)', tier: 1 },
            ],
        };

        renderCardDetail(unsafeSourceCard);

        const sourceText = screen.getByText('Malicious Site');
        expect(sourceText.closest('a')).toBeNull();
    });

    it('renders humanized draft textarea', () => {
        renderCardDetail(tier3FullItem);

        expect(screen.getByText('Humanized Draft')).toBeInTheDocument();
        const textarea = screen.getByDisplayValue(tier3FullItem.humanized_draft!);
        expect(textarea).toBeInTheDocument();
    });

    it('renders low confidence warning for LOW_CONFIDENCE cards', () => {
        renderCardDetail(lowConfidenceItem);

        expect(screen.getByText(lowConfidenceItem.low_confidence_note!)).toBeInTheDocument();
    });

    it('calls onBack when Back button is clicked', async () => {
        const onBack = jest.fn();
        renderCardDetail(tier3FullItem, { onBack });

        await userEvent.click(screen.getByText('Back'));
        expect(onBack).toHaveBeenCalled();
    });

    it('calls onEditDraft when Edit & Copy Draft button is clicked', async () => {
        const onEditDraft = jest.fn();
        renderCardDetail(tier3FullItem, { onEditDraft });

        await userEvent.click(screen.getByText('Edit & Copy Draft'));
        expect(onEditDraft).toHaveBeenCalledWith(tier3FullItem.id);
    });

    it('calls onDismissCard when Dismiss Card button is clicked', async () => {
        const onDismissCard = jest.fn();
        renderCardDetail(tier3FullItem, { onDismissCard });

        await userEvent.click(screen.getByText('Dismiss Card'));
        expect(onDismissCard).toHaveBeenCalledWith(tier3FullItem.id);
    });

    it('renders raw draft with Spinner when humanized_draft is null', () => {
        const pendingDraftCard: AssistantCard = {
            ...tier3FullItem,
            id: 'pending-draft-001',
            humanized_draft: null,
        };

        renderCardDetail(pendingDraftCard);

        expect(screen.getByText('Draft')).toBeInTheDocument();
        expect(screen.getByText('Humanizing...')).toBeInTheDocument();
    });

    it('renders plain text briefing for string draft_payload (CALENDAR_SCAN)', () => {
        renderCardDetail(calendarBriefingItem);

        expect(screen.getByText(/Meeting briefing:/)).toBeInTheDocument();
    });

    it('hides priority badge when priority is null', () => {
        renderCardDetail(tier1SkipItem);

        // tier1SkipItem has priority: null — no priority badge should appear
        expect(screen.queryByText('High')).not.toBeInTheDocument();
        expect(screen.queryByText('Medium')).not.toBeInTheDocument();
        expect(screen.queryByText('Low')).not.toBeInTheDocument();
    });

    it('hides confidence badge when confidence_score is null', () => {
        renderCardDetail(tier1SkipItem);

        expect(screen.queryByText(/Confidence:/)).not.toBeInTheDocument();
    });

    it('hides key findings section when key_findings is null', () => {
        renderCardDetail(tier1SkipItem);

        expect(screen.queryByText('Key Findings')).not.toBeInTheDocument();
    });

    it('hides research log section when research_log is null', () => {
        renderCardDetail(tier1SkipItem);

        expect(screen.queryByText('Research Log')).not.toBeInTheDocument();
    });

    it('hides sources section when verified_sources is null', () => {
        renderCardDetail(tier1SkipItem);

        expect(screen.queryByText('Sources')).not.toBeInTheDocument();
    });

    it('hides draft section when draft_payload is null', () => {
        renderCardDetail(tier1SkipItem);

        expect(screen.queryByText('Draft')).not.toBeInTheDocument();
        expect(screen.queryByText('Humanized Draft')).not.toBeInTheDocument();
    });
});
