import React from 'react';
import { vi } from 'vitest';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { App } from '../App';

describe('App', () => {
    it('renders without crashing', () => {
        render(<App />);
        expect(document.querySelector('.assistant-dashboard')).toBeTruthy();
    });

    it('renders the status bar', () => {
        render(<App />);
        expect(screen.getByText('Work Layer')).toBeInTheDocument();
    });

    it('shows loading spinner initially', () => {
        render(<App />);
        expect(screen.getByText('Loading cards...')).toBeInTheDocument();
    });

    it('displays cards after loading completes', async () => {
        render(<App />);
        await waitFor(() => {
            expect(screen.queryByText('Loading cards...')).not.toBeInTheDocument();
        });
        // Cards from sampleCards fixture should be visible
        expect(screen.getByText(/Q3 budget review/i)).toBeInTheDocument();
    });

    it('renders the command bar pill', async () => {
        render(<App />);
        await waitFor(() => {
            expect(screen.queryByText('Loading cards...')).not.toBeInTheDocument();
        });
        expect(screen.getByText(/Ask IWL/)).toBeInTheDocument();
    });

    it('shows filter bar with chips', async () => {
        render(<App />);
        await waitFor(() => {
            expect(screen.queryByText('Loading cards...')).not.toBeInTheDocument();
        });
        expect(screen.getByText('All')).toBeInTheDocument();
    });

    it('navigates to calibration view when settings clicked', async () => {
        render(<App />);
        await waitFor(() => {
            expect(screen.queryByText('Loading cards...')).not.toBeInTheDocument();
        });
        const settingsButton = screen.getByLabelText('Settings');
        fireEvent.click(settingsButton);
        expect(screen.getByText('Agent Performance')).toBeInTheDocument();
    });

    it('returns to gallery from calibration view', async () => {
        render(<App />);
        await waitFor(() => {
            expect(screen.queryByText('Loading cards...')).not.toBeInTheDocument();
        });
        const settingsButton = screen.getByLabelText('Settings');
        fireEvent.click(settingsButton);
        expect(screen.getByText('Agent Performance')).toBeInTheDocument();

        const backButton = screen.getByText('Back to Dashboard');
        fireEvent.click(backButton);
        expect(screen.queryByText('Agent Performance')).not.toBeInTheDocument();
    });
});
