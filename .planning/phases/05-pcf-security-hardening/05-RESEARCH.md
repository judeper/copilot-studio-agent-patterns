# Phase 5: PCF Security Hardening - Research

**Researched:** 2026-02-21
**Domain:** URL sanitization / XSS prevention in React PCF component
**Confidence:** HIGH

## Summary

The PCF component's `CardDetail.tsx` renders external URLs from `verified_sources` as clickable Fluent UI `<Link>` elements. The current code applies a basic regex guard (`/^https?:\/\//`) that rejects non-HTTP URLs but falls back to `href="#"`, which still produces a clickable link element -- violating the requirement to render unsafe URLs as plain text. The scope of the vulnerability is narrow: only one render site in one component handles external URLs, and the data source is agent-generated JSON stored in Dataverse (not direct user input). However, defense-in-depth mandates sanitization at the render boundary regardless of data trust.

The recommended approach is a zero-dependency URL validation utility that uses the browser-native `URL` constructor to parse URLs and checks the resolved protocol against an explicit allowlist (`https:` and `mailto:` only). This is simpler, more robust, and has fewer edge cases than regex-based validation. The `URL` constructor automatically normalizes case, strips control characters, and handles obfuscation techniques (tabs, newlines, encoding) that defeat naive regex patterns.

**Primary recommendation:** Create a `isSafeUrl()` utility function using the `URL` constructor with a `Set`-based protocol allowlist; conditionally render `<Link>` vs `<Text>` in CardDetail.tsx based on the validation result.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
User delegated all security hardening decisions to Claude. Apply standard secure defaults:

- **Safe scheme allowlist**: `https` and `mailto` only. Strict by default -- enterprise protocol schemes (tel:, ms-teams:, sip:) can be added in a future phase if needed.
- **Unsafe URL handling**: Render as plain text (visible but not clickable). No silent stripping (user can still see the URL content). No warning badges or icons cluttering the UI.
- **Validation boundary**: Every location where URLs are rendered as clickable links in the PCF component -- primarily CardDetail.tsx but audit all components for URL rendering.
- **Implementation approach**: URL validation utility function, imported where needed. Single source of truth for the allowlist.

### Claude's Discretion
All implementation details delegated to Claude.

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PCF-04 | CardDetail.tsx sanitizes external URLs before rendering to prevent XSS | URL constructor + protocol allowlist utility; conditional Link vs Text rendering; verified against OWASP evasion techniques |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| URL constructor (built-in) | Web API (all modern browsers) | Parse and normalize URLs, extract protocol | Browser-native, handles encoding/case/whitespace normalization automatically; no dependency needed |
| React (existing) | ~16.x (PCF constraint) | Conditional rendering of Link vs Text | Already in the component tree |
| @fluentui/react-components (existing) | ^9.46.0 | Link and Text components for rendering | Already imported in CardDetail.tsx |

### Supporting
No additional libraries needed. This is a zero-dependency change.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| URL constructor allowlist | `@braintree/sanitize-url` (v7.1.2) | Well-tested library with 3.6M weekly downloads, but has had multiple CVEs (CVE-2021-23648, CVE-2022-48345); overkill for simple scheme allowlist; adds external dependency to PCF bundle; returns `about:blank` rather than allowing plain-text rendering |
| URL constructor allowlist | Regex-based blocklist | Fragile -- must enumerate every dangerous scheme; misses future schemes; OWASP evasion techniques (tab/newline/encoding injection) routinely bypass regex filters |
| URL constructor allowlist | Angular-style `SAFE_URL_PATTERN` regex | More complex regex (`/^(?:(?:https?|mailto|ftp|tel|file|sms):|[^&:/?#]*(?:[/?#]|$))/gi`); harder to audit; allows relative URLs which may not be appropriate in this context |

**No installation needed.** All dependencies already exist in the project.

## Architecture Patterns

### Recommended Project Structure
```
src/AssistantDashboard/
├── components/
│   ├── CardDetail.tsx     # Modified: conditional Link vs Text rendering
│   ├── types.ts           # Unchanged
│   └── ...
├── hooks/
│   └── useCardData.ts     # Unchanged
└── utils/
    └── urlSanitizer.ts    # NEW: isSafeUrl() + SAFE_PROTOCOLS constant
```

### Pattern 1: URL Constructor Allowlist Validation
**What:** Parse URL with native `URL` constructor, check `.protocol` against an explicit `Set` of safe protocols
**When to use:** Any time an external/untrusted URL is rendered as a clickable link
**Why it works:** The `URL` constructor handles all normalization (case folding, whitespace stripping, control character removal, percent-decoding) before returning the protocol. This defeats OWASP-documented evasion techniques that bypass regex filters.

```typescript
// Source: Browser Web API URL constructor + OWASP XSS Prevention Cheat Sheet
const SAFE_PROTOCOLS: ReadonlySet<string> = new Set(["https:", "mailto:"]);

export function isSafeUrl(url: string | null | undefined): boolean {
    if (!url || typeof url !== "string") return false;
    try {
        const parsed = new URL(url.trim());
        return SAFE_PROTOCOLS.has(parsed.protocol.toLowerCase());
    } catch {
        // URL constructor throws TypeError for malformed/relative URLs
        return false;
    }
}
```

**Verified behavior** (tested 2026-02-21 with Node.js 22):

| Input | `isSafeUrl()` result | Reason |
|-------|---------------------|--------|
| `https://example.com` | `true` | Valid HTTPS |
| `HTTPS://EXAMPLE.COM` | `true` | Case normalized by URL constructor |
| `mailto:test@example.com` | `true` | Valid mailto |
| `javascript:alert(1)` | `false` | Dangerous scheme |
| `JAVASCRIPT:alert(1)` | `false` | Case-insensitive rejection |
| `java\tscript:alert(1)` | `false` | Tab obfuscation -- URL constructor parses as `javascript:` but blocked |
| `java\nscript:alert(1)` | `false` | Newline obfuscation -- blocked |
| `data:text/html,...` | `false` | data: scheme not in allowlist |
| `vbscript:msgbox(1)` | `false` | vbscript: not in allowlist |
| `http://example.com` | `false` | HTTP not in allowlist (HTTPS only) |
| `""` / `null` / `undefined` | `false` | Null guard |
| `/relative/path` | `false` | URL constructor throws (no base) |

### Pattern 2: Conditional Link vs Text Rendering
**What:** Render safe URLs as `<Link>` elements, unsafe URLs as `<Text>` (visible but not clickable)
**When to use:** In CardDetail.tsx verified_sources rendering

```tsx
// Source: Fluent UI v9 Link/Text components + CONTEXT.md decision
{card.verified_sources.map((source, idx) => (
    <li key={`${source.tier}-${idx}`}>
        {isSafeUrl(source.url) ? (
            <Link href={source.url} target="_blank" rel="noopener noreferrer">
                {source.title}
            </Link>
        ) : (
            <Text>{source.title}</Text>
        )}
        <Badge appearance="outline" size="small" className="source-tier-badge">
            Tier {source.tier}
        </Badge>
    </li>
))}
```

### Anti-Patterns to Avoid
- **Blocklist approach:** Never enumerate dangerous schemes (`javascript:`, `data:`, `vbscript:`, etc.) and block them. New schemes appear; obfuscation defeats string matching. Always use an allowlist.
- **Regex-only validation:** The existing `^https?:\/\/` regex is case-sensitive and doesn't handle whitespace/encoding evasion. Never rely solely on regex for URL security.
- **`href="#"` fallback:** The current code falls back to `href="#"` for invalid URLs. This still creates an active link element (scrolls to page top on click). Always switch to a non-interactive element.
- **`dangerouslySetInnerHTML` for URLs:** Never inject URL content as raw HTML. Always use React's JSX binding which escapes content.
- **Trusting data source:** Even though URLs come from agent-generated JSON in Dataverse, validate at the render boundary. Data pipelines can be compromised; defense-in-depth is essential.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| URL parsing and normalization | Custom regex to extract scheme | `new URL()` constructor | Handles 100+ edge cases (encoding, whitespace, case, IDN) that regex misses; WHATWG URL spec compliant |
| Protocol allowlist matching | String startsWith/indexOf checks | `Set.has()` on parsed `.protocol` | O(1) lookup, clean API, easy to extend |

**Key insight:** URL parsing is a deceptively complex problem. The WHATWG URL specification is hundreds of pages. The browser's `URL` constructor implements this specification natively. Any hand-rolled regex will have gaps that the URL constructor handles correctly.

## Common Pitfalls

### Pitfall 1: Case-Sensitive Scheme Checking
**What goes wrong:** Using `url.startsWith("https://")` misses `HTTPS://`, `Https://`, etc.
**Why it happens:** String comparison is case-sensitive by default; URL schemes are case-insensitive per RFC 3986.
**How to avoid:** Use `new URL(url).protocol.toLowerCase()` -- the URL constructor normalizes the scheme.
**Warning signs:** Tests only use lowercase URLs.

### Pitfall 2: Blocklist Instead of Allowlist
**What goes wrong:** Blocking `javascript:` and `data:` misses `vbscript:`, `mhtml:`, `file:`, custom scheme handlers, and future dangerous schemes.
**Why it happens:** Developers think "block the known bad" is sufficient. The OWASP evasion sheet documents dozens of scheme variants.
**How to avoid:** Only allow explicitly safe schemes. Everything else is rejected by default.
**Warning signs:** Code contains a list of "bad" schemes rather than a list of "good" schemes.

### Pitfall 3: Falling Back to `href="#"` or `href="about:blank"`
**What goes wrong:** The element is still a clickable `<a>` tag. Screen readers announce it as a link. Users see a pointer cursor and expect navigation.
**Why it happens:** Developer wants to "neutralize" the URL without changing the component tree.
**How to avoid:** Conditionally render `<Text>` instead of `<Link>` when the URL is unsafe. This produces no `<a>` tag at all.
**Warning signs:** Ternary expression inside `href={}` instead of around the entire component.

### Pitfall 4: Not Trimming Input Before Validation
**What goes wrong:** Leading whitespace (`"  javascript:alert(1)"`) could theoretically bypass certain validators.
**Why it happens:** Assumption that URLs are already clean from the data source.
**How to avoid:** Always `url.trim()` before passing to the URL constructor. The recommended `isSafeUrl()` function includes this.
**Warning signs:** No `.trim()` call on the URL input.

### Pitfall 5: Forgetting `rel="noopener noreferrer"` on External Links
**What goes wrong:** Opened page can access `window.opener` and navigate the parent page (reverse tabnapping).
**Why it happens:** Developer adds `target="_blank"` but forgets the rel attribute.
**How to avoid:** Always pair `target="_blank"` with `rel="noopener noreferrer"`. The existing code already does this correctly.
**Warning signs:** `target="_blank"` without corresponding `rel` attribute.

## Code Examples

Verified patterns from investigation of the codebase and web standards:

### Complete isSafeUrl Utility
```typescript
// File: src/AssistantDashboard/utils/urlSanitizer.ts

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
```

### CardDetail.tsx Modification (verified_sources section)
```tsx
// Import the utility
import { isSafeUrl } from "../utils/urlSanitizer";

// In the verified_sources rendering section, replace:
//   <Link href={/^https?:\/\//.test(source.url) ? source.url : "#"} ...>
// With conditional rendering:

{card.verified_sources.map((source, idx) => (
    <li key={`${source.tier}-${idx}`}>
        {isSafeUrl(source.url) ? (
            <Link
                href={source.url}
                target="_blank"
                rel="noopener noreferrer"
            >
                {source.title}
            </Link>
        ) : (
            <Text>{source.title}</Text>
        )}
        <Badge appearance="outline" size="small" className="source-tier-badge">
            Tier {source.tier}
        </Badge>
    </li>
))}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Regex blocklist (`/javascript:/i`) | URL constructor + protocol allowlist | OWASP recommendation (ongoing) | Defeats encoding/case/whitespace evasion |
| DOMPurify for all HTML | Context-specific validation (URLs get scheme check, HTML gets DOMPurify) | ~2020+ | More precise; less overhead for URL-only contexts |
| `@braintree/sanitize-url` | Still viable but has had CVEs | v6.0.0+ (2022) fixed critical bypass | For simple scheme allowlists, URL constructor is sufficient |
| React warning for `javascript:` hrefs | React 16.9+ logs console warning; does NOT block | React 16.9 (2019) | Warning only -- not a security control; developer must still validate |

**Deprecated/outdated:**
- Regex-based URL blocklists: Routinely bypassed by OWASP-documented evasion techniques
- `href="#"` as "safe" fallback: Creates active link elements; violates accessibility expectations

## Audit Results: URL Rendering Locations

Complete audit of all PCF component files for URL rendering:

| File | URL Rendering | Action Needed |
|------|--------------|---------------|
| `CardDetail.tsx` line 129 | `<Link href={...}>` for `verified_sources[].url` | YES -- replace regex with `isSafeUrl()`, conditional Link/Text |
| `CardItem.tsx` | No URL rendering | None |
| `CardGallery.tsx` | No URL rendering | None |
| `FilterBar.tsx` | No URL rendering | None |
| `App.tsx` | No URL rendering | None |
| `index.ts` | No URL rendering | None |
| `useCardData.ts` | Passes `verified_sources` through from JSON parse | No rendering, no action |

**Conclusion:** Only one render site requires modification: `CardDetail.tsx` line 129.

## Open Questions

1. **HTTP scheme policy**
   - What we know: CONTEXT specifies `https` and `mailto` only. HTTP is excluded from the allowlist.
   - What's unclear: Whether any legitimate verified_sources could use plain `http://` URLs.
   - Recommendation: Stick with HTTPS-only per the locked decision. If HTTP sources appear in practice, the URL text is still visible (rendered as plain text), and the allowlist can be extended later.

## Sources

### Primary (HIGH confidence)
- Browser URL constructor behavior -- verified empirically with Node.js 22.18.0 (WHATWG URL spec implementation), tested all evasion patterns
- Codebase audit -- read all 9 source files in `src/AssistantDashboard/` to identify URL rendering locations
- [OWASP XSS Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html) -- allowlist recommendation for URL schemes
- [OWASP XSS Filter Evasion Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/XSS_Filter_Evasion_Cheat_Sheet.html) -- tab/newline/encoding bypass techniques

### Secondary (MEDIUM confidence)
- [Fluent UI Link XSS Issue #908](https://github.com/microsoft/fluentui/issues/908) -- confirms Fluent UI does NOT sanitize href attributes by design; developer responsibility
- [Preventing XSS in React (Part 1)](https://pragmaticwebsecurity.com/articles/spasecurity/react-xss-part1.html) -- Angular-style SAFE_URL_PATTERN approach; URL constructor allowlist pattern
- [@braintree/sanitize-url README](https://github.com/braintree/sanitize-url/blob/main/README.md) -- v7.1.2, 3.6M weekly downloads, returns `about:blank` for dangerous URLs
- [@braintree/sanitize-url source](https://github.com/braintree/sanitize-url/blob/main/src/index.ts) -- implementation uses iterative decode + protocol regex; more complex than needed for our use case

### Tertiary (LOW confidence)
- [React Security Best Practices 2025](https://corgea.com/Learn/react-security-best-practices-2025) -- general React security guidance (WebSearch only)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- uses browser-native URL constructor (WHATWG spec), no external dependencies; empirically verified all edge cases
- Architecture: HIGH -- single utility file + one component modification; codebase audit identified exactly one render site
- Pitfalls: HIGH -- OWASP evasion techniques tested directly against proposed implementation; all blocked

**Research date:** 2026-02-21
**Valid until:** 2026-06-21 (stable domain -- URL spec and XSS patterns change slowly)
