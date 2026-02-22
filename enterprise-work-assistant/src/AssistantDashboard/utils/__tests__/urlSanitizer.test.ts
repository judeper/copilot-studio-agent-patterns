import { isSafeUrl, SAFE_PROTOCOLS } from '../urlSanitizer';

describe('isSafeUrl', () => {
    it('accepts https URLs', () => {
        expect(isSafeUrl('https://example.com')).toBe(true);
    });

    it('accepts mailto URLs', () => {
        expect(isSafeUrl('mailto:user@example.com')).toBe(true);
    });

    it('rejects javascript: protocol', () => {
        expect(isSafeUrl('javascript:alert(1)')).toBe(false);
    });

    it('rejects data: protocol', () => {
        expect(isSafeUrl('data:text/html,<script>alert(1)</script>')).toBe(false);
    });

    it('rejects vbscript: protocol', () => {
        expect(isSafeUrl('vbscript:msgbox')).toBe(false);
    });

    it('returns false for null', () => {
        expect(isSafeUrl(null)).toBe(false);
    });

    it('returns false for undefined', () => {
        expect(isSafeUrl(undefined)).toBe(false);
    });

    it('returns false for empty string', () => {
        expect(isSafeUrl('')).toBe(false);
    });

    it('handles case-insensitive protocols', () => {
        expect(isSafeUrl('HTTPS://EXAMPLE.COM')).toBe(true);
    });

    it('rejects http: protocol (only https allowed)', () => {
        expect(isSafeUrl('http://example.com')).toBe(false);
    });

    it('rejects relative URLs without scheme', () => {
        expect(isSafeUrl('example.com/path')).toBe(false);
    });
});

describe('SAFE_PROTOCOLS', () => {
    it('contains exactly https: and mailto:', () => {
        expect(SAFE_PROTOCOLS.size).toBe(2);
        expect(SAFE_PROTOCOLS.has('https:')).toBe(true);
        expect(SAFE_PROTOCOLS.has('mailto:')).toBe(true);
    });
});
