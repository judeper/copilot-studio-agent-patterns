import * as React from 'react';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { OnboardingWizard } from '../OnboardingWizard';
import { renderWithProviders } from '../../../test/helpers/renderWithProviders';

describe('OnboardingWizard', () => {
    it('renders step 0 (Welcome) initially', () => {
        renderWithProviders(<OnboardingWizard onComplete={jest.fn()} />);

        expect(screen.getByText('Welcome to IWL')).toBeInTheDocument();
    });

    it('shows display name input on step 0', () => {
        renderWithProviders(<OnboardingWizard onComplete={jest.fn()} />);

        expect(screen.getByPlaceholderText('Display name')).toBeInTheDocument();
        expect(screen.getByText('What should we call you?')).toBeInTheDocument();
    });

    it('disables Next when name is empty', () => {
        renderWithProviders(<OnboardingWizard onComplete={jest.fn()} />);

        const nextButton = screen.getByText('Next').closest('button')!;
        expect(nextButton).toBeDisabled();
    });

    it('navigates to step 1 when Next clicked (name filled)', async () => {
        renderWithProviders(<OnboardingWizard onComplete={jest.fn()} />);

        await userEvent.type(screen.getByPlaceholderText('Display name'), 'Alice');
        await userEvent.click(screen.getByText('Next'));

        expect(screen.getByText('Daily Briefing Schedule')).toBeInTheDocument();
    });

    it('shows time picker and day selection on step 1', async () => {
        renderWithProviders(<OnboardingWizard onComplete={jest.fn()} />);

        // Navigate to step 1
        await userEvent.type(screen.getByPlaceholderText('Display name'), 'Alice');
        await userEvent.click(screen.getByText('Next'));

        expect(screen.getByText('Time')).toBeInTheDocument();
        expect(screen.getByText('Days')).toBeInTheDocument();
        // Day buttons are abbreviated to 3 chars
        expect(screen.getByText('Mon')).toBeInTheDocument();
        expect(screen.getByText('Tue')).toBeInTheDocument();
        expect(screen.getByText('Wed')).toBeInTheDocument();
        expect(screen.getByText('Thu')).toBeInTheDocument();
        expect(screen.getByText('Fri')).toBeInTheDocument();
        expect(screen.getByText('Sat')).toBeInTheDocument();
        expect(screen.getByText('Sun')).toBeInTheDocument();
    });

    it('navigates to step 2 with Back/Next', async () => {
        renderWithProviders(<OnboardingWizard onComplete={jest.fn()} />);

        // Step 0 -> 1
        await userEvent.type(screen.getByPlaceholderText('Display name'), 'Alice');
        await userEvent.click(screen.getByText('Next'));
        expect(screen.getByText('Daily Briefing Schedule')).toBeInTheDocument();

        // Step 1 -> 2
        await userEvent.click(screen.getByText('Next'));
        expect(screen.getByText('Try a Command')).toBeInTheDocument();

        // Step 2 does not have Back, but verify step 1 Back works
    });

    it('goes back from step 1 to step 0 when Back clicked', async () => {
        renderWithProviders(<OnboardingWizard onComplete={jest.fn()} />);

        // Step 0 -> 1
        await userEvent.type(screen.getByPlaceholderText('Display name'), 'Alice');
        await userEvent.click(screen.getByText('Next'));
        expect(screen.getByText('Daily Briefing Schedule')).toBeInTheDocument();

        // Step 1 -> 0
        await userEvent.click(screen.getByText('Back'));
        expect(screen.getByText('Welcome to IWL')).toBeInTheDocument();
    });

    it('calls onComplete with config when Get Started clicked', async () => {
        const handleComplete = jest.fn();
        renderWithProviders(<OnboardingWizard onComplete={handleComplete} />);

        // Step 0 -> 1
        await userEvent.type(screen.getByPlaceholderText('Display name'), 'Alice');
        await userEvent.click(screen.getByText('Next'));

        // Step 1 -> 2
        await userEvent.click(screen.getByText('Next'));

        // Finish
        await userEvent.click(screen.getByText('Get Started'));

        expect(handleComplete).toHaveBeenCalledTimes(1);
        const config = handleComplete.mock.calls[0][0];
        expect(config).toEqual(
            expect.objectContaining({
                hour: expect.any(Number),
                minute: 0,
                days: expect.any(Array),
                timezone: expect.any(String),
                enabled: true,
            })
        );
        // Default weekdays selected
        expect(config.days).toEqual(
            expect.arrayContaining(['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'])
        );
    });
});
