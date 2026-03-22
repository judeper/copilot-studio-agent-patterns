import * as React from "react";
import { Button, Text, Input, Select } from "@fluentui/react-components";
import type { BriefingScheduleConfig } from "./types";

interface OnboardingWizardProps {
    onComplete: (config: BriefingScheduleConfig) => void;
}

const DAYS_OF_WEEK = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
const DEFAULT_DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"];

function detectTimezone(): string {
    try {
        return Intl.DateTimeFormat().resolvedOptions().timeZone;
    } catch {
        return "America/New_York";
    }
}

export const OnboardingWizard: React.FC<OnboardingWizardProps> = ({ onComplete }) => {
    const [step, setStep] = React.useState(0);
    const [displayName, setDisplayName] = React.useState("");
    const [hour, setHour] = React.useState(8);
    const [selectedDays, setSelectedDays] = React.useState<Set<string>>(() => new Set(DEFAULT_DAYS));
    const timezone = React.useMemo(() => detectTimezone(), []);

    const toggleDay = React.useCallback((day: string) => {
        setSelectedDays((prev) => {
            const next = new Set(prev);
            if (next.has(day)) {
                next.delete(day);
            } else {
                next.add(day);
            }
            return next;
        });
    }, []);

    const handleFinish = React.useCallback(() => {
        onComplete({
            hour,
            minute: 0,
            days: Array.from(selectedDays),
            timezone,
            enabled: true,
        });
    }, [hour, selectedDays, timezone, onComplete]);

    return (
        <div className="onboarding-wizard" role="region" aria-label="Welcome setup">
            {/* Step indicators */}
            <div className="onboarding-steps">
                {[0, 1, 2].map((s) => (
                    <div
                        key={s}
                        className={`onboarding-step-dot ${s === step ? "active" : ""} ${s < step ? "completed" : ""}`}
                    />
                ))}
            </div>

            {step === 0 && (
                <div className="onboarding-content">
                    <Text as="h2" size={600} weight="semibold" block>
                        Welcome to IWL
                    </Text>
                    <Text size={400} block style={{ marginTop: "8px", color: "#595959" }}>
                        Your intelligent work layer triages emails, Teams messages, and calendar events so you can focus on what matters.
                    </Text>
                    <div style={{ marginTop: "24px" }}>
                        <Text size={300} weight="semibold" block style={{ marginBottom: "4px" }}>
                            What should we call you?
                        </Text>
                        <Input
                            placeholder="Display name"
                            value={displayName}
                            onChange={(_e, data) => setDisplayName(data.value)}
                            style={{ width: "100%" }}
                        />
                    </div>
                    <Button
                        appearance="primary"
                        onClick={() => setStep(1)}
                        style={{ marginTop: "24px" }}
                        disabled={displayName.trim().length === 0}
                    >
                        Next
                    </Button>
                </div>
            )}

            {step === 1 && (
                <div className="onboarding-content">
                    <Text as="h2" size={600} weight="semibold" block>
                        Daily Briefing Schedule
                    </Text>
                    <Text size={400} block style={{ marginTop: "8px", color: "#595959" }}>
                        Choose when you would like your daily briefing.
                    </Text>
                    <div style={{ marginTop: "16px" }}>
                        <Text size={300} weight="semibold" block style={{ marginBottom: "4px" }}>
                            Time
                        </Text>
                        <Select
                            value={String(hour)}
                            onChange={(_e, data) => setHour(Number(data.value))}
                        >
                            {Array.from({ length: 19 }, (_, i) => i + 5).map((h) => (
                                <option key={h} value={h}>
                                    {h === 0 ? "12:00 AM" : h < 12 ? `${h}:00 AM` : h === 12 ? "12:00 PM" : `${h - 12}:00 PM`}
                                </option>
                            ))}
                        </Select>
                    </div>
                    <div style={{ marginTop: "16px" }}>
                        <Text size={300} weight="semibold" block style={{ marginBottom: "4px" }}>
                            Days
                        </Text>
                        <div style={{ display: "flex", gap: "4px", flexWrap: "wrap" }}>
                            {DAYS_OF_WEEK.map((day) => (
                                <button
                                    key={day}
                                    className={`filter-chip ${selectedDays.has(day) ? "filter-chip-active" : ""}`}
                                    onClick={() => toggleDay(day)}
                                >
                                    {day.slice(0, 3)}
                                </button>
                            ))}
                        </div>
                    </div>
                    <Text size={200} block style={{ marginTop: "8px", color: "#767676" }}>
                        Timezone: {timezone}
                    </Text>
                    <div style={{ display: "flex", gap: "8px", marginTop: "24px" }}>
                        <Button appearance="secondary" onClick={() => setStep(0)}>Back</Button>
                        <Button appearance="primary" onClick={() => setStep(2)}>Next</Button>
                    </div>
                </div>
            )}

            {step === 2 && (
                <div className="onboarding-content">
                    <Text as="h2" size={600} weight="semibold" block>
                        Try a Command
                    </Text>
                    <Text size={400} block style={{ marginTop: "8px", color: "#595959" }}>
                        Use the command bar at the bottom to ask IWL anything. Try typing:
                    </Text>
                    <div className="onboarding-command-example" style={{
                        marginTop: "16px",
                        padding: "12px 16px",
                        background: "#f5f5f5",
                        borderRadius: "8px",
                        fontFamily: "monospace",
                    }}>
                        &quot;Show me my priorities&quot;
                    </div>
                    <Button
                        appearance="primary"
                        onClick={handleFinish}
                        style={{ marginTop: "24px" }}
                    >
                        Get Started
                    </Button>
                </div>
            )}
        </div>
    );
};
