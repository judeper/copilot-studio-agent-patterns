import * as React from 'react';
import { fireEvent, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderWithProviders } from '../../../test/helpers/renderWithProviders';
import { CommandBar } from '../CommandBar';
import type { OrchestratorResponse } from '../types';

describe('CommandBar', () => {
    const mockExecute = jest.fn();
    const mockJump = jest.fn();

    const defaultProps = {
        currentCardId: null,
        selectedCardId: null,
        onExecuteCommand: mockExecute,
        onJumpToCard: mockJump,
        lastResponse: null,
        isProcessing: false,
    };

    beforeEach(() => {
        jest.clearAllMocks();
    });

    async function expandPill() {
        const pill = screen.getByText(/Ask IWL/);
        await userEvent.click(pill);
    }

    it('renders collapsed pill by default', () => {
        renderWithProviders(<CommandBar {...defaultProps} />);
        expect(screen.getByText(/Ask IWL/)).toBeTruthy();
    });

    it('renders input field and send button after expanding pill', async () => {
        renderWithProviders(<CommandBar {...defaultProps} />);
        await expandPill();
        expect(screen.getByPlaceholderText('Type a command...')).toBeTruthy();
        expect(screen.getByText('Send')).toBeTruthy();
    });

    it('shows context-aware placeholder when card is selected', async () => {
        renderWithProviders(<CommandBar {...defaultProps} currentCardId="card-123" />);
        await expandPill();
        expect(
            screen.getByPlaceholderText('Ask about this card or type a command...'),
        ).toBeTruthy();
    });

    it('renders quick action chips when not expanded', async () => {
        renderWithProviders(<CommandBar {...defaultProps} />);
        await expandPill();
        expect(screen.getByText("What needs my attention now?")).toBeTruthy();
        expect(screen.getByText('Prepare me for my next meeting')).toBeTruthy();
        expect(screen.getByText('Summarize what changed today')).toBeTruthy();
    });

    it('renders context-aware default chips when no card selected', async () => {
        renderWithProviders(<CommandBar {...defaultProps} />);
        await expandPill();
        expect(screen.getByText('What needs my attention now?')).toBeTruthy();
        expect(screen.getByText('Prepare me for my next meeting')).toBeTruthy();
        expect(screen.getByText('Summarize what changed today')).toBeTruthy();
    });

    it('renders detail chips when selectedCardId is set', async () => {
        renderWithProviders(<CommandBar {...defaultProps} selectedCardId="card-123" />);
        await expandPill();
        expect(screen.getByText('Why is this important?')).toBeTruthy();
        expect(screen.getByText('Improve this draft')).toBeTruthy();
        expect(screen.getByText('Find related threads')).toBeTruthy();
        expect(screen.getByText('Defer to tomorrow')).toBeTruthy();
    });

    it('send button is disabled when input is empty', async () => {
        renderWithProviders(<CommandBar {...defaultProps} />);
        await expandPill();
        const sendBtn = screen.getByRole('button', { name: /Send/ });
        expect(sendBtn).toBeDisabled();
    });

    it('calls onExecuteCommand when Send is clicked', async () => {
        renderWithProviders(<CommandBar {...defaultProps} />);
        await expandPill();
        const input = screen.getByPlaceholderText('Type a command...');
        await userEvent.type(input, 'What needs attention?');
        await userEvent.click(screen.getByText('Send'));
        expect(mockExecute).toHaveBeenCalledWith(
            'What needs attention?',
            null,
        );
    });

    it('calls onExecuteCommand with currentCardId when set', async () => {
        renderWithProviders(<CommandBar {...defaultProps} currentCardId="card-456" />);
        await expandPill();
        const input = screen.getByPlaceholderText(
            'Ask about this card or type a command...',
        );
        await userEvent.type(input, 'Make this shorter');
        await userEvent.click(screen.getByText('Send'));
        expect(mockExecute).toHaveBeenCalledWith(
            'Make this shorter',
            'card-456',
        );
    });

    it('calls onExecuteCommand on Enter key', async () => {
        renderWithProviders(<CommandBar {...defaultProps} />);
        await expandPill();
        const input = screen.getByPlaceholderText('Type a command...');
        await userEvent.type(input, 'Show urgent items{Enter}');
        expect(mockExecute).toHaveBeenCalledWith('Show urgent items', null);
    });

    it('clears input after submit', async () => {
        renderWithProviders(<CommandBar {...defaultProps} />);
        await expandPill();
        const input = screen.getByPlaceholderText(
            'Type a command...',
        ) as HTMLInputElement;
        await userEvent.type(input, 'test');
        await userEvent.click(screen.getByText('Send'));
        expect(input.value).toBe('');
    });

    it('shows "Thinking..." when processing', async () => {
        const { rerender } = renderWithProviders(<CommandBar {...defaultProps} />);
        await expandPill();
        const input = screen.getByPlaceholderText('Type a command...');
        await userEvent.type(input, 'test');
        await userEvent.click(screen.getByText('Send'));

        rerender(<CommandBar {...defaultProps} isProcessing={true} />);
        expect(screen.getByText('Thinking...')).toBeTruthy();
    });

    it('disables input and send button when processing', () => {
        renderWithProviders(<CommandBar {...defaultProps} isProcessing={true} />);
        const input = screen.getByPlaceholderText(
            'Type a command...',
        ) as HTMLInputElement;
        const sendBtn = screen.getByRole('button', { name: '...' });
        expect(input.disabled).toBe(true);
        expect(sendBtn).toBeDisabled();
    });

    it('executes quick action on chip click', async () => {
        renderWithProviders(<CommandBar {...defaultProps} />);
        await expandPill();
        await userEvent.click(screen.getByText("What needs my attention now?"));
        expect(mockExecute).toHaveBeenCalledWith(
            'What needs my attention now?',
            null,
        );
    });

    it('shows clear button after conversation exists', async () => {
        renderWithProviders(<CommandBar {...defaultProps} />);
        await expandPill();
        const input = screen.getByPlaceholderText('Type a command...');
        await userEvent.type(input, 'test');
        await userEvent.click(screen.getByText('Send'));
        expect(screen.getByTitle('Clear conversation')).toBeTruthy();
    });

    it('collapses to pill on clear button click', async () => {
        renderWithProviders(<CommandBar {...defaultProps} />);
        await expandPill();
        const input = screen.getByPlaceholderText('Type a command...');
        await userEvent.type(input, 'test');
        await userEvent.click(screen.getByText('Send'));
        await userEvent.click(screen.getByTitle('Clear conversation'));
        // Should return to collapsed pill
        expect(screen.getByText(/Ask IWL/)).toBeTruthy();
    });

    it('renders card links from response', async () => {
        const response: OrchestratorResponse = {
            response_text: 'Here are your urgent items.',
            card_links: [
                { card_id: 'card-001', label: 'Fabrikam contract' },
                { card_id: 'card-002', label: 'Budget email' },
            ],
            side_effects: [],
        };

        const { rerender } = renderWithProviders(<CommandBar {...defaultProps} />);
        await expandPill();
        const input = screen.getByPlaceholderText('Type a command...');
        await userEvent.type(input, 'test');
        await userEvent.click(screen.getByText('Send'));

        rerender(
            <CommandBar
                {...defaultProps}
                lastResponse={response}
                isProcessing={false}
            />,
        );

        expect(screen.getByText('Fabrikam contract →')).toBeTruthy();
        expect(screen.getByText('Budget email →')).toBeTruthy();
    });

    it('calls onJumpToCard when card link is clicked', async () => {
        const response: OrchestratorResponse = {
            response_text: 'Found it.',
            card_links: [{ card_id: 'card-abc', label: 'Test card' }],
            side_effects: [],
        };

        const { rerender } = renderWithProviders(<CommandBar {...defaultProps} />);
        await expandPill();
        const input = screen.getByPlaceholderText('Type a command...');
        await userEvent.type(input, 'test');
        await userEvent.click(screen.getByText('Send'));

        rerender(
            <CommandBar
                {...defaultProps}
                lastResponse={response}
                isProcessing={false}
            />,
        );

        await userEvent.click(screen.getByText('Test card →'));
        expect(mockJump).toHaveBeenCalledWith('card-abc');
    });

    it('collapses to pill on Escape', async () => {
        renderWithProviders(<CommandBar {...defaultProps} />);
        await expandPill();

        const input = screen.getByPlaceholderText('Type a command...');
        expect(input).toBeTruthy();

        fireEvent.keyDown(document, { key: 'Escape' });

        await waitFor(() => {
            expect(screen.getByText(/Ask IWL/)).toBeTruthy();
            expect(screen.queryByPlaceholderText('Type a command...')).not.toBeInTheDocument();
        });
    });

    it('handles Escape while focus is on a response card link', async () => {
        const response: OrchestratorResponse = {
            response_text: 'Found it.',
            card_links: [{ card_id: 'card-abc', label: 'Test card' }],
            side_effects: [],
        };

        const { rerender } = renderWithProviders(<CommandBar {...defaultProps} />);
        await expandPill();

        await userEvent.click(screen.getByText("What needs my attention now?"));

        rerender(
            <CommandBar
                {...defaultProps}
                lastResponse={response}
                isProcessing={false}
            />,
        );

        const cardLink = screen.getByText('Test card →');
        cardLink.focus();
        expect(cardLink).toHaveFocus();

        fireEvent.keyDown(document, { key: 'Escape' });

        await waitFor(() => {
            expect(screen.queryByText('Test card →')).not.toBeInTheDocument();
            expect(screen.getByText(/Ask IWL/)).toBeTruthy();
        });
    });
});
