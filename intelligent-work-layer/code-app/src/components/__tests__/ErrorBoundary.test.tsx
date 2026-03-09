import React from 'react';
import { vi } from 'vitest';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ErrorBoundary } from '../ErrorBoundary';
import { renderWithProviders } from '../../test/helpers/renderWithProviders';

const ThrowingComponent = () => {
    throw new Error('Test error');
};

describe('ErrorBoundary', () => {
    let consoleErrorSpy: ReturnType<typeof vi.spyOn>;

    beforeEach(() => {
        // Suppress React error boundary console output during tests
        consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    });

    afterEach(() => {
        consoleErrorSpy.mockRestore();
    });

    it('renders children when no error occurs', () => {
        renderWithProviders(
            <ErrorBoundary>
                <p>Dashboard content</p>
            </ErrorBoundary>
        );

        expect(screen.getByText('Dashboard content')).toBeInTheDocument();
    });

    it('renders fallback UI when a child throws', () => {
        renderWithProviders(
            <ErrorBoundary>
                <ThrowingComponent />
            </ErrorBoundary>
        );

        expect(screen.getByText('Something went wrong')).toBeInTheDocument();
        expect(
            screen.getByText('The dashboard encountered an error. Please refresh the page.')
        ).toBeInTheDocument();
    });

    it('shows a "Try Again" button in error state', () => {
        renderWithProviders(
            <ErrorBoundary>
                <ThrowingComponent />
            </ErrorBoundary>
        );

        expect(screen.getByRole('button', { name: 'Try Again' })).toBeInTheDocument();
    });

    it('logs the error via console.error', () => {
        renderWithProviders(
            <ErrorBoundary>
                <ThrowingComponent />
            </ErrorBoundary>
        );

        expect(consoleErrorSpy).toHaveBeenCalledWith(
            'AssistantDashboard error:',
            expect.any(Error),
            expect.objectContaining({ componentStack: expect.any(String) })
        );
    });

    it('resets error state and re-renders children when "Try Again" is clicked', async () => {
        let shouldThrow = true;

        const ConditionalThrower = () => {
            if (shouldThrow) {
                throw new Error('Conditional error');
            }
            return <p>Recovered content</p>;
        };

        renderWithProviders(
            <ErrorBoundary>
                <ConditionalThrower />
            </ErrorBoundary>
        );

        // Verify error state
        expect(screen.getByText('Something went wrong')).toBeInTheDocument();

        // Fix the error condition before clicking Try Again
        shouldThrow = false;

        await userEvent.click(screen.getByRole('button', { name: 'Try Again' }));

        expect(screen.getByText('Recovered content')).toBeInTheDocument();
        expect(screen.queryByText('Something went wrong')).not.toBeInTheDocument();
    });

    it('does not show fallback UI when children render successfully', () => {
        renderWithProviders(
            <ErrorBoundary>
                <p>All good</p>
            </ErrorBoundary>
        );

        expect(screen.queryByText('Something went wrong')).not.toBeInTheDocument();
        expect(screen.queryByRole('button', { name: 'Try Again' })).not.toBeInTheDocument();
    });
});
