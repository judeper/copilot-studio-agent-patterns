import { tokens } from "@fluentui/react-components";

/**
 * Priority-to-color mapping for badge border/background styling.
 * Only valid priority values have entries -- null priority hides the badge entirely.
 */
export const PRIORITY_COLORS: Record<string, string> = {
    High: tokens.colorPaletteRedBorder2,
    Medium: tokens.colorPaletteMarigoldBorder2,
    Low: tokens.colorPaletteGreenBorder2,
};

// Design tokens
export const EWA_COLORS = {
    brand: '#6366f1',
    brandHover: '#4f46e5',
    heartbeat: '#8b5cf6',
    priorityHigh: '#ef4444',
    priorityMedium: '#f59e0b',
    priorityLow: '#22c55e',
    stale: '#f59e0b',
    staleBg: '#fffbeb',
    confidenceHigh: '#16a34a',
    confidenceMid: '#ca8a04',
    confidenceLow: '#dc2626',
    briefingBg: 'linear-gradient(135deg, #f0f4ff 0%, #faf0ff 100%)',
} as const;

// New trigger types for heartbeat
export const HEARTBEAT_TRIGGER_TYPES = [
    'PREP_REQUIRED',
    'STALE_TASK',
    'FOLLOW_UP_NEEDED',
    'PATTERN_ALERT',
] as const;

// Feed section definitions
export const FEED_SECTIONS = {
    action: { title: 'Action Required', defaultExpanded: true },
    heartbeat: { title: 'Proactive Alerts', defaultExpanded: true, accentColor: '#8b5cf6' },
    signals: { title: 'New Signals', defaultExpanded: true },
    fyi: { title: 'FYI', defaultExpanded: false },
    stale: { title: 'Needs Attention', defaultExpanded: false, accentColor: '#f59e0b' },
} as const;

// Context-aware command chips
export const DEFAULT_COMMAND_CHIPS = [
    'What needs attention?',
    'Show high priority',
    'Daily briefing',
];

export const DETAIL_COMMAND_CHIPS = [
    'Summarize this',
    'Delegate to...',
    'Remind me in 2h',
    'Draft reply',
];
