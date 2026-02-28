import * as React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { CommandBar } from '../CommandBar';
import type { OrchestratorResponse } from '../types';

describe('CommandBar', () => {
    const mockExecute = jest.fn();
    const mockJump = jest.fn();

    const defaultProps = {
        currentCardId: null,
        onExecuteCommand: mockExecute,
        onJumpToCard: mockJump,
        lastResponse: null,
        isProcessing: false,
    };

    beforeEach(() => {
        jest.clearAllMocks();
    });

    it('renders input field and send button', () => {
        render(<CommandBar {...defaultProps} />);
        expect(screen.getByPlaceholderText('Type a command...')).toBeTruthy();
        expect(screen.getByText('Send')).toBeTruthy();
    });

    it('shows context-aware placeholder when card is selected', () => {
        render(<CommandBar {...defaultProps} currentCardId="card-123" />);
        expect(
            screen.getByPlaceholderText('Ask about this card or type a command...'),
        ).toBeTruthy();
    });

    it('renders quick action chips when not expanded', () => {
        render(<CommandBar {...defaultProps} />);
        expect(screen.getByText("What's urgent?")).toBeTruthy();
        expect(screen.getByText('Draft status')).toBeTruthy();
        expect(screen.getByText('My day')).toBeTruthy();
    });

    it('send button is disabled when input is empty', () => {
        render(<CommandBar {...defaultProps} />);
        const sendBtn = screen.getByText('Send') as HTMLButtonElement;
        expect(sendBtn.disabled).toBe(true);
    });

    it('calls onExecuteCommand when Send is clicked', () => {
        render(<CommandBar {...defaultProps} />);
        const input = screen.getByPlaceholderText('Type a command...');
        fireEvent.change(input, { target: { value: 'What needs attention?' } });
        fireEvent.click(screen.getByText('Send'));
        expect(mockExecute).toHaveBeenCalledWith(
            'What needs attention?',
            null,
        );
    });

    it('calls onExecuteCommand with currentCardId when set', () => {
        render(<CommandBar {...defaultProps} currentCardId="card-456" />);
        const input = screen.getByPlaceholderText(
            'Ask about this card or type a command...',
        );
        fireEvent.change(input, { target: { value: 'Make this shorter' } });
        fireEvent.click(screen.getByText('Send'));
        expect(mockExecute).toHaveBeenCalledWith(
            'Make this shorter',
            'card-456',
        );
    });

    it('calls onExecuteCommand on Enter key', () => {
        render(<CommandBar {...defaultProps} />);
        const input = screen.getByPlaceholderText('Type a command...');
        fireEvent.change(input, { target: { value: 'Show urgent items' } });
        fireEvent.keyDown(input, { key: 'Enter' });
        expect(mockExecute).toHaveBeenCalledWith('Show urgent items', null);
    });

    it('clears input after submit', () => {
        render(<CommandBar {...defaultProps} />);
        const input = screen.getByPlaceholderText(
            'Type a command...',
        ) as HTMLInputElement;
        fireEvent.change(input, { target: { value: 'test' } });
        fireEvent.click(screen.getByText('Send'));
        expect(input.value).toBe('');
    });

    it('shows "Thinking..." when processing', () => {
        // Submit a command first to create conversation
        const { rerender } = render(<CommandBar {...defaultProps} />);
        const input = screen.getByPlaceholderText('Type a command...');
        fireEvent.change(input, { target: { value: 'test' } });
        fireEvent.click(screen.getByText('Send'));

        // Re-render with isProcessing=true
        rerender(<CommandBar {...defaultProps} isProcessing={true} />);
        expect(screen.getByText('Thinking...')).toBeTruthy();
    });

    it('disables input and send button when processing', () => {
        render(<CommandBar {...defaultProps} isProcessing={true} />);
        const input = screen.getByPlaceholderText(
            'Type a command...',
        ) as HTMLInputElement;
        const sendBtn = screen.getByText('...') as HTMLButtonElement;
        expect(input.disabled).toBe(true);
        expect(sendBtn.disabled).toBe(true);
    });

    it('executes quick action on chip click', () => {
        render(<CommandBar {...defaultProps} />);
        fireEvent.click(screen.getByText("What's urgent?"));
        expect(mockExecute).toHaveBeenCalledWith(
            'What needs my attention right now?',
            null,
        );
    });

    it('shows clear button after conversation exists', () => {
        render(<CommandBar {...defaultProps} />);
        const input = screen.getByPlaceholderText('Type a command...');
        fireEvent.change(input, { target: { value: 'test' } });
        fireEvent.click(screen.getByText('Send'));
        expect(screen.getByTitle('Clear conversation')).toBeTruthy();
    });

    it('clears conversation on clear button click', () => {
        render(<CommandBar {...defaultProps} />);
        const input = screen.getByPlaceholderText('Type a command...');
        fireEvent.change(input, { target: { value: 'test' } });
        fireEvent.click(screen.getByText('Send'));
        // Clear
        fireEvent.click(screen.getByTitle('Clear conversation'));
        // Quick actions should reappear
        expect(screen.getByText("What's urgent?")).toBeTruthy();
    });

    it('renders card links from response', () => {
        const response: OrchestratorResponse = {
            response_text: 'Here are your urgent items.',
            card_links: [
                { card_id: 'card-001', label: 'Fabrikam contract' },
                { card_id: 'card-002', label: 'Budget email' },
            ],
            side_effects: [],
        };

        // First submit a command to create conversation
        const { rerender } = render(<CommandBar {...defaultProps} />);
        const input = screen.getByPlaceholderText('Type a command...');
        fireEvent.change(input, { target: { value: 'test' } });
        fireEvent.click(screen.getByText('Send'));

        // Re-render with response
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

    it('calls onJumpToCard when card link is clicked', () => {
        const response: OrchestratorResponse = {
            response_text: 'Found it.',
            card_links: [{ card_id: 'card-abc', label: 'Test card' }],
            side_effects: [],
        };

        const { rerender } = render(<CommandBar {...defaultProps} />);
        const input = screen.getByPlaceholderText('Type a command...');
        fireEvent.change(input, { target: { value: 'test' } });
        fireEvent.click(screen.getByText('Send'));

        rerender(
            <CommandBar
                {...defaultProps}
                lastResponse={response}
                isProcessing={false}
            />,
        );

        fireEvent.click(screen.getByText('Test card →'));
        expect(mockJump).toHaveBeenCalledWith('card-abc');
    });
});
