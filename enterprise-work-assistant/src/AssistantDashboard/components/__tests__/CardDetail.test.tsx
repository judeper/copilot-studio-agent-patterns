import * as React from 'react';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { CardDetail } from '../CardDetail';
import { renderWithProviders } from '../../../test/helpers/renderWithProviders';
import {
    tier3FullItem,
    tier1SkipItem,
    tier2LightItem,
    lowConfidenceItem,
    calendarBriefingItem,
} from '../../../test/fixtures/cardFixtures';
import type { AssistantCard } from '../types';

function renderCardDetail(
    card: AssistantCard,
    overrides: Partial<{
        onBack: () => void;
        onSendDraft: (id: string, text: string) => void;
        onCopyDraft: (id: string) => void;
        onDismissCard: (id: string) => void;
    }> = {},
) {
    const defaultProps = {
        card,
        onBack: jest.fn(),
        onSendDraft: jest.fn(),
        onCopyDraft: jest.fn(),
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

    // ── Sprint 1A: Send flow tests ──

    it('renders Send button for EMAIL FULL READY cards with humanized draft', () => {
        renderCardDetail(tier3FullItem);

        expect(screen.getByText('Send')).toBeInTheDocument();
    });

    it('does NOT render Send button for TEAMS_MESSAGE cards', () => {
        renderCardDetail(tier2LightItem);

        expect(screen.queryByText('Send')).not.toBeInTheDocument();
    });

    it('does NOT render Send button for CALENDAR_SCAN cards', () => {
        renderCardDetail(calendarBriefingItem);

        expect(screen.queryByText('Send')).not.toBeInTheDocument();
    });

    it('does NOT render Send button for LOW_CONFIDENCE cards (no humanized draft)', () => {
        renderCardDetail(lowConfidenceItem);

        expect(screen.queryByText('Send')).not.toBeInTheDocument();
    });

    it('shows inline confirmation panel on Send click', async () => {
        renderCardDetail(tier3FullItem);

        await userEvent.click(screen.getByText('Send'));

        expect(screen.getByText('Confirm send')).toBeInTheDocument();
        expect(screen.getByText(/Fabrikam Legal/)).toBeInTheDocument();
        expect(screen.getByText(/Contract Renewal/)).toBeInTheDocument();
        expect(screen.getByText('Confirm & Send')).toBeInTheDocument();
        expect(screen.getByText('Cancel')).toBeInTheDocument();
    });

    it('calls onSendDraft with card ID and draft text on Confirm & Send', async () => {
        const onSendDraft = jest.fn();
        renderCardDetail(tier3FullItem, { onSendDraft });

        await userEvent.click(screen.getByText('Send'));
        await userEvent.click(screen.getByText('Confirm & Send'));

        expect(onSendDraft).toHaveBeenCalledWith(
            tier3FullItem.id,
            tier3FullItem.humanized_draft,
        );
    });

    it('hides confirmation panel on Cancel', async () => {
        renderCardDetail(tier3FullItem);

        await userEvent.click(screen.getByText('Send'));
        expect(screen.getByText('Confirm send')).toBeInTheDocument();

        await userEvent.click(screen.getByText('Cancel'));
        expect(screen.queryByText('Confirm send')).not.toBeInTheDocument();
    });

    it('shows "Sent" badge for cards with SENT_AS_IS outcome', () => {
        const sentCard: AssistantCard = {
            ...tier3FullItem,
            id: 'sent-001',
            card_outcome: 'SENT_AS_IS',
        };

        renderCardDetail(sentCard);

        expect(screen.getByText('Sent')).toBeInTheDocument();
        // Send button should be replaced with disabled "Sent" button
        expect(screen.queryByText('Send')).not.toBeInTheDocument();
    });

    it('shows "Dismissed" badge for dismissed cards', () => {
        const dismissedCard: AssistantCard = {
            ...tier3FullItem,
            id: 'dismissed-001',
            card_outcome: 'DISMISSED',
        };

        renderCardDetail(dismissedCard);

        expect(screen.getByText('Dismissed')).toBeInTheDocument();
    });

    it('hides Dismiss button for already-sent cards', () => {
        const sentCard: AssistantCard = {
            ...tier3FullItem,
            id: 'sent-002',
            card_outcome: 'SENT_AS_IS',
        };

        renderCardDetail(sentCard);

        expect(screen.queryByText('Dismiss')).not.toBeInTheDocument();
    });

    // ── Copy to Clipboard ──

    it('renders Copy to Clipboard for cards with draft_payload', () => {
        renderCardDetail(tier3FullItem);

        expect(screen.getByText('Copy to Clipboard')).toBeInTheDocument();
    });

    it('calls onCopyDraft when Copy to Clipboard is clicked', async () => {
        const onCopyDraft = jest.fn();
        renderCardDetail(tier3FullItem, { onCopyDraft });

        await userEvent.click(screen.getByText('Copy to Clipboard'));
        expect(onCopyDraft).toHaveBeenCalledWith(tier3FullItem.id);
    });

    // ── Dismiss ──

    it('calls onDismissCard when Dismiss button is clicked', async () => {
        const onDismissCard = jest.fn();
        renderCardDetail(tier3FullItem, { onDismissCard });

        await userEvent.click(screen.getByText('Dismiss'));
        expect(onDismissCard).toHaveBeenCalledWith(tier3FullItem.id);
    });

    // ── Existing rendering tests ──

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

    // Sprint 2: Inline editing tests

    it('shows "Edit draft" button for sendable cards', () => {
        renderCardDetail(tier3FullItem);
        expect(screen.getByText('Edit draft')).toBeInTheDocument();
    });

    it('hides "Edit draft" button for non-sendable cards', () => {
        renderCardDetail(calendarBriefingItem);
        expect(screen.queryByText('Edit draft')).not.toBeInTheDocument();
    });

    it('enters editing mode when "Edit draft" is clicked', () => {
        renderCardDetail(tier3FullItem);
        fireEvent.click(screen.getByText('Edit draft'));
        expect(screen.getByText(/Editing/)).toBeInTheDocument();
        expect(screen.getByText('Revert to original')).toBeInTheDocument();
    });

    it('reverts to original when "Revert to original" is clicked', () => {
        renderCardDetail(tier3FullItem);
        fireEvent.click(screen.getByText('Edit draft'));
        expect(screen.getByText(/Editing/)).toBeInTheDocument();
        fireEvent.click(screen.getByText('Revert to original'));
        expect(screen.queryByText(/Editing/)).not.toBeInTheDocument();
    });

    it('confirmation panel shows "(edited)" when draft is modified', () => {
        renderCardDetail(tier3FullItem);
        // Enter edit mode
        fireEvent.click(screen.getByText('Edit draft'));
        // Modify the draft text
        const textarea = screen.getByDisplayValue(tier3FullItem.humanized_draft!);
        fireEvent.change(textarea, { target: { value: 'Modified draft text' } });
        // Click Send
        fireEvent.click(screen.getByText('Send'));
        // Confirmation panel should indicate it was edited
        expect(screen.getByText(/edited/)).toBeInTheDocument();
    });

    it('confirmation panel shows "(as-is)" when draft is NOT modified', () => {
        renderCardDetail(tier3FullItem);
        // Click Send without editing
        fireEvent.click(screen.getByText('Send'));
        expect(screen.getByText(/as-is/)).toBeInTheDocument();
    });
});
