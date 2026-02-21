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
