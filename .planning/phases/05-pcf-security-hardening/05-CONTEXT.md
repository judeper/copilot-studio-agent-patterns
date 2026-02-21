# Phase 5: PCF Security Hardening - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Prevent XSS attacks through external URLs rendered in the PCF control. All URLs displayed as clickable links must be validated against a safe scheme allowlist. Dangerous schemes (javascript:, data:, vbscript:, etc.) must never produce active links.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
User delegated all security hardening decisions to Claude. Apply standard secure defaults:

- **Safe scheme allowlist**: `https` and `mailto` only. Strict by default — enterprise protocol schemes (tel:, ms-teams:, sip:) can be added in a future phase if needed.
- **Unsafe URL handling**: Render as plain text (visible but not clickable). No silent stripping (user can still see the URL content). No warning badges or icons cluttering the UI.
- **Validation boundary**: Every location where URLs are rendered as clickable links in the PCF component — primarily CardDetail.tsx but audit all components for URL rendering.
- **Implementation approach**: URL validation utility function, imported where needed. Single source of truth for the allowlist.

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. Follow OWASP URL validation best practices.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 05-pcf-security-hardening*
*Context gathered: 2026-02-21*
