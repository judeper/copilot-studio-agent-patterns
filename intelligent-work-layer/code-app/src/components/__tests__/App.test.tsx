import React from 'react';
import { render, screen } from '@testing-library/react';
import { App } from '../App';

/**
 * App smoke tests (Code App).
 *
 * The Code App's App component takes NO props — it uses the useCards hook
 * internally. These tests verify basic rendering of the top-level shell.
 */

describe('App', () => {
    it('renders the status bar', () => {
        render(<App />);

        expect(screen.getByText('Work Layer')).toBeInTheDocument();
    });

    it('renders the command bar pill', () => {
        render(<App />);

        expect(screen.getByText(/Ask IWL/)).toBeInTheDocument();
    });

    it('renders without crashing', () => {
        const { container } = render(<App />);

        expect(container).toBeTruthy();
    });
});
