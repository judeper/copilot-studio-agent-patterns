import * as React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { BriefingCard } from '../BriefingCard';
import { dailyBriefingItem } from '../../../test/fixtures/cardFixtures';

// Mock Fluent UI
jest.mock('@fluentui/react-components', () => ({
    Button: (props: Record<string, unknown>) => (
        <button onClick={props.onClick as () => void} disabled={props.disabled as boolean}>
            {props.children as React.ReactNode}
        </button>
    ),
    Text: (props: Record<string, unknown>) => <span>{props.children as React.ReactNode}</span>,
    Badge: (props: Record<string, unknown>) => <span>{props.children as React.ReactNode}</span>,
    Card: (props: Record<string, unknown>) => <div>{props.children as React.ReactNode}</div>,
    Select: (props: Record<string, unknown>) => (
        <select
            value={props.value as string}
            onChange={(e) => {
                const handler = props.onChange as (event: unknown, data: { value: string }) => void;
                handler?.(e, { value: e.target.value });
            }}
            data-testid="hour-select"
        >
            {props.children as React.ReactNode}
        </select>
    ),
    Checkbox: (props: Record<string, unknown>) => (
        <label>
            <input
                type="checkbox"
                checked={props.checked as boolean}
                onChange={props.onChange as () => void}
                data-testid={`checkbox-${props.label}`}
            />
            {props.label as string}
        </label>
    ),
    Switch: (props: Record<string, unknown>) => (
        <label>
            <input
                type="checkbox"
                checked={props.checked as boolean}
                onChange={(e) => {
                    const handler = props.onChange as (event: unknown, data: { checked: boolean }) => void;
                    handler?.(e, { checked: e.target.checked });
                }}
                data-testid="enabled-switch"
            />
            {props.label as string}
        </label>
    ),
}));

// Mock Fluent UI Icons
jest.mock('@fluentui/react-icons', () => ({
    ArrowLeftRegular: () => <span data-testid="icon-arrow-left" />,
    DismissRegular: () => <span data-testid="icon-dismiss" />,
    ChevronDownRegular: () => <span data-testid="icon-chevron-down" />,
    ChevronRightRegular: () => <span data-testid="icon-chevron-right" />,
    CalendarRegular: () => <span data-testid="icon-calendar" />,
    ArrowRightRegular: () => <span data-testid="icon-arrow-right" />,
    WeatherSunnyRegular: () => <span data-testid="icon-weather-sunny" />,
    WeatherMoonRegular: () => <span data-testid="icon-weather-moon" />,
    CheckmarkCircleRegular: () => <span data-testid="icon-checkmark-circle" />,
    ChatBubblesQuestionRegular: () => <span data-testid="icon-chat-bubbles" />,
    LightbulbRegular: () => <span data-testid="icon-lightbulb" />,
}));

describe('ScheduleConfig', () => {
    const mockJump = jest.fn();
    const mockDismiss = jest.fn();
    const mockUpdateSchedule = jest.fn();

    beforeEach(() => {
        jest.clearAllMocks();
    });

    it('renders schedule settings button', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
                onUpdateSchedule={mockUpdateSchedule}
            />,
        );
        expect(screen.getByText('Schedule Settings')).toBeTruthy();
    });

    it('expands schedule panel when clicked', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
                onUpdateSchedule={mockUpdateSchedule}
            />,
        );
        // Panel not visible initially — Save button not rendered
        expect(screen.queryByText('Save')).toBeNull();

        fireEvent.click(screen.getByText('Schedule Settings'));
        expect(screen.getByText('Save')).toBeTruthy();
    });

    it('shows hour dropdown and day checkboxes when expanded', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
                onUpdateSchedule={mockUpdateSchedule}
            />,
        );
        fireEvent.click(screen.getByText('Schedule Settings'));

        expect(screen.getByTestId('hour-select')).toBeTruthy();
        expect(screen.getByText('Mon')).toBeTruthy();
        expect(screen.getByText('Tue')).toBeTruthy();
        expect(screen.getByText('Wed')).toBeTruthy();
        expect(screen.getByText('Thu')).toBeTruthy();
        expect(screen.getByText('Fri')).toBeTruthy();
        expect(screen.getByText('Sat')).toBeTruthy();
        expect(screen.getByText('Sun')).toBeTruthy();
    });

    it('calls onUpdateSchedule with config when Save is clicked', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
                onUpdateSchedule={mockUpdateSchedule}
            />,
        );
        fireEvent.click(screen.getByText('Schedule Settings'));
        fireEvent.click(screen.getByText('Save'));

        expect(mockUpdateSchedule).toHaveBeenCalledTimes(1);
        const config = mockUpdateSchedule.mock.calls[0][0];
        expect(config).toEqual({
            hour: 7,
            minute: 0,
            days: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
            timezone: 'America/New_York',
            enabled: true,
        });
    });

    it('default schedule is Mon-Fri at 7:00 AM', () => {
        render(
            <BriefingCard
                card={dailyBriefingItem}
                onJumpToCard={mockJump}
                onDismissCard={mockDismiss}
                onUpdateSchedule={mockUpdateSchedule}
            />,
        );
        fireEvent.click(screen.getByText('Schedule Settings'));

        // Default hour is 7 → "7:00 AM"
        const select = screen.getByTestId('hour-select') as HTMLSelectElement;
        expect(select.value).toBe('7');

        // Mon-Fri checked, Sat-Sun unchecked
        expect((screen.getByTestId('checkbox-Mon') as HTMLInputElement).checked).toBe(true);
        expect((screen.getByTestId('checkbox-Tue') as HTMLInputElement).checked).toBe(true);
        expect((screen.getByTestId('checkbox-Wed') as HTMLInputElement).checked).toBe(true);
        expect((screen.getByTestId('checkbox-Thu') as HTMLInputElement).checked).toBe(true);
        expect((screen.getByTestId('checkbox-Fri') as HTMLInputElement).checked).toBe(true);
        expect((screen.getByTestId('checkbox-Sat') as HTMLInputElement).checked).toBe(false);
        expect((screen.getByTestId('checkbox-Sun') as HTMLInputElement).checked).toBe(false);
    });
});
