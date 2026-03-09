/**
 * Protocols considered safe for rendering as clickable links.
 * Strict allowlist: https and mailto only.
 * Enterprise protocol schemes (tel:, ms-teams:, sip:) deferred to future phase.
 */
export const SAFE_PROTOCOLS: ReadonlySet<string> = new Set(["https:", "mailto:"]);

/**
 * Validates whether a URL is safe to render as a clickable link.
 *
 * Uses the browser-native URL constructor for parsing, which handles:
 * - Case normalization (HTTPS: -> https:)
 * - Whitespace stripping
 * - Control character removal (tabs, newlines in scheme)
 * - Percent-decoding
 *
 * Returns false for:
 * - Dangerous schemes (javascript:, data:, vbscript:, etc.)
 * - Malformed URLs that the URL constructor cannot parse
 * - Null, undefined, or empty string inputs
 * - Relative URLs (no scheme)
 *
 * @param url - The URL string to validate
 * @returns true if the URL uses a safe protocol scheme
 */
export function isSafeUrl(url: string | null | undefined): boolean {
    if (!url || typeof url !== "string") return false;
    try {
        const parsed = new URL(url.trim());
        return SAFE_PROTOCOLS.has(parsed.protocol.toLowerCase());
    } catch {
        return false;
    }
}
