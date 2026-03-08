# OneNote Integration Design

This document is the **source of truth** for the OneNote integration layer added to the Intelligent Work Layer. OneNote serves as a downstream knowledge surface — persistent, mobile, offline-capable, annotatable, and indexed by Microsoft Search — that augments (never replaces) the Dataverse card system.

> **Augmentation Principle**: The assistant works identically if OneNote is unavailable. All OneNote writes are gated behind a feature flag (`cr_onenoteenabled`) and wrapped in fail-safe scopes. Dataverse remains the system of record.

---

## Phase Overview

| Phase | Scope | Status |
|-------|-------|--------|
| **Phase 1** | Write-only: meeting prep, daily briefing, active to-dos | `[P1-IMPLEMENTED]` |
| **Phase 2** | Read-back: project logs, sender dossiers, decision logs, annotation promotion to Tier 1 | `[P2-PLANNED]` |
| **Phase 3** | Bi-directional: annotation detection, managed identity, per-agent cost attribution | `[P3-PLANNED]` |

---

## Notebook Structure `[P1-IMPLEMENTED]`

The assistant provisions a single OneNote notebook in a dedicated Microsoft 365 Group. The hierarchy is:

```
Intelligent Work Layer (Notebook)
├── Meetings (Section Group)
│   ├── This Week (Section)
│   └── Archive (Section)
├── Briefings (Section Group)
│   └── Daily (Section)
├── Active To-Dos (Section)
├── Projects (Section)          [P2-PLANNED]
├── People (Section)            [P2-PLANNED]
└── Research Archive (Section)  [P2-PLANNED]
```

> **Naming**: The notebook name includes the user's display name for disambiguation in shared tenant environments: `{UserDisplayName} — Work Layer`.

---

## Permission Model `[P1-IMPLEMENTED]`

### Group-Scoped Access

OneNote operations use a **dedicated M365 Group** with an Azure AD app registration:

| Setting | Value |
|---------|-------|
| API | Microsoft Graph |
| Permission type | Application (admin-consented) |
| Scope | `Notes.ReadWrite.All` scoped to the dedicated group |
| Endpoint pattern | `/groups/{groupId}/onenote/...` |

This avoids two problems:
1. **Least-privilege violation**: Delegated `Notes.ReadWrite` on `/me/` grants access to *all* user notebooks. Group-scoping restricts access to the assistant notebook only.
2. **ALM fragility**: `/me/` endpoints are tied to the Power Automate connection owner's identity, which breaks on ownership changes or service account rotation.

The group ID and notebook ID are stored as **Power Automate environment variables**, not hardcoded.

### External-Sharing Pre-Check

Before every write operation, flows execute a pre-check:

1. `GET /groups/{groupId}/onenote/notebooks/{notebookId}` — retrieve notebook metadata
2. Verify the notebook is not shared with external (guest) users via the `sharedWith` property
3. If externally shared → **block the write**, log to audit table, skip OneNote step

This prevents data leakage of triage content (email subjects, meeting participants, research findings) that Dataverse row-level security would otherwise protect.

---

## Trust Model `[P1-IMPLEMENTED]`

### Phase 1: Tier 3 (User-Curated, Unverified)

OneNote annotations are classified as **Tier 3** in the research hierarchy:

- The agent writes to OneNote but does not read back annotations in Phase 1
- Human annotations (highlights, margin notes, handwritten text) are treated as *user-contributed, unverified* context
- This prevents an injection vector: co-editors, delegates, or compromised accounts could write malicious instructions into OneNote pages that the agent would trust if classified as Tier 1

### Phase 2: Tier 1 Promotion `[P2-PLANNED]`

Promotion to Tier 1 requires:
- Bi-directional read-back capability
- Cryptographic signing: annotations must be attributable to the authenticated user's Entra ID
- Tampering detection via content-hash reconciliation

---

## Template Syntax `[P1-IMPLEMENTED]`

### Placeholder Convention

All HTML templates use **`{{PLACEHOLDER_NAME}}`** syntax:

```html
<h1>{{MEETING_SUBJECT}}</h1>
<p><strong>{{MEETING_DATE}} {{MEETING_TIME}}</strong> | {{MEETING_LOCATION}}</p>
```

### Escaping Rules

- All injected values **must** be HTML-entity-encoded before substitution
- `<` → `&lt;`, `>` → `&gt;`, `&` → `&amp;`, `"` → `&quot;`
- Power Automate flows perform encoding via the `replace()` expression function before template substitution

### Template Files

| Template | Location | Used By |
|----------|----------|---------|
| Meeting Prep | `templates/onenote-meeting-prep.html` | Flow 3 |
| Daily Briefing | `templates/onenote-daily-briefing.html` | Flow 6 |
| Active To-Dos | `templates/onenote-active-todos.html` | Flow 6 |

---

## Phase 1 Scenarios `[P1-IMPLEMENTED]`

### Scenario 1: Meeting Prep Pages (Flow 3)

**Trigger**: Flow 3 processes a FULL-tier calendar event.

**Steps** (added after Dataverse write — step 4d):

1. Check feature flag: `cr_onenoteenabled = true` (from config entity)
2. Check user preference: `cr_onenoteoptout = false` (from user settings)
3. **External-sharing pre-check** (see Permission Model above)
4. Query Dataverse for existing `cr_onenotepageid` on this card row (idempotency check)
5. If page ID exists → `PATCH /groups/{groupId}/onenote/pages/{pageId}/content` (refresh data)
6. If no page ID → `POST /groups/{groupId}/onenote/sections/{meetingsSectionId}/pages` using `onenote-meeting-prep.html` template
7. Store returned page ID in `cr_onenotepageid` on the Dataverse card row
8. Generate deep link: `onenote:https://...` and store in `cr_fulljson` for Canvas app rendering

**Idempotency**: Dataverse is the source of truth for dedup, not OneNote `$filter` (which cannot reliably query HTML attributes and uses eventually-consistent `$search`).

### Scenario 2: Daily Briefing Pages (Flow 6)

**Trigger**: Flow 6 generates the daily briefing.

**Steps** (added after briefing card Dataverse write):

1. Check feature flag + user preference (same as Scenario 1)
2. External-sharing pre-check
3. `POST /groups/{groupId}/onenote/sections/{briefingsSectionId}/pages` using `onenote-daily-briefing.html` template
4. Store `cr_onenotepageid` on the briefing card row
5. **Append to Active To-Dos page** (see Scenario 3)

### Scenario 3: Active To-Dos (Flow 6)

**Trigger**: Same as Scenario 2 — runs as part of the daily briefing flow.

**Semantics**: **Append-only** — each briefing cycle appends a timestamped block of action items. Stale items from previous cycles are not deleted but may be marked with strikethrough in future cycles.

**Steps**:

1. Query Dataverse for the existing Active To-Dos page ID (single page per user)
2. If page exists → `PATCH /groups/{groupId}/onenote/pages/{pageId}/content` with `append` target using ETag (`If-Match` header) for concurrency safety
3. If no page → `POST /groups/{groupId}/onenote/sections/{todosSectionId}/pages` using `onenote-active-todos.html` template
4. Store/update the page ID in a dedicated config row in Dataverse

**Why append-only (not overwrite)**:
- Overwrite creates race conditions when multiple flows fire in parallel or retry under throttling
- Overwrite destroys user annotations (checkmarks, handwritten notes) added between cycles
- ETag checks prevent last-write-wins data loss

---

## Error Handling `[P1-IMPLEMENTED]`

### Fail-Safe, Not Fail-Silent

All OneNote operations are wrapped in a Power Automate **Scope** with **Configure Run After** set to `succeed-only`. If the scope fails:

1. **Log**: Write a structured error record to the `cr_errorlog` Dataverse table (or Application Insights if configured):
   - `cr_flowname`: Which flow failed
   - `cr_errordetail`: Graph API error response
   - `cr_occurredon`: Timestamp
   - `cr_affectedcardid`: Dataverse card ID
2. **Surface**: Set a `cr_onenotesyncstatus` field on the affected card to `"FAILED"` — the Canvas app displays a warning badge
3. **Continue**: The main pipeline (Dataverse write, email send, etc.) is never blocked

> **Key distinction**: "Fail-safe" means failures are logged and surfaced, not silently swallowed. Users and admins know when OneNote sync is broken.

### Rate Limiting

Graph API rate limits for OneNote:
- Throttling: 429 responses with `Retry-After` header
- Power Automate retry policy: exponential backoff, max 3 retries
- If all retries fail → log and continue (fail-safe)

---

## Cross-Referencing `[P1-IMPLEMENTED]`

### Dataverse → OneNote

| Column | Purpose |
|--------|---------|
| `cr_onenotepageid` | OneNote page ID (on AssistantCards rows) |
| `cr_onenotesyncstatus` | Sync status: `SYNCED`, `FAILED`, `PENDING` |

### OneNote → Dataverse

Each OneNote page includes a `data-tag` attribute in the root `<div>`:

```html
<div data-tag="card-id:{{CARD_ID}}">
```

This enables future Phase 2 read-back to map OneNote content back to Dataverse rows.

### Canvas App Deep Links

Cards with a populated `cr_onenotepageid` display an **"Open in OneNote"** button. The deep link format:

```
onenote:https://graph.microsoft.com/v1.0/groups/{groupId}/onenote/pages/{pageId}
```

---

## Feature Flag & User Preferences `[P1-IMPLEMENTED]`

### Feature Flag: `cr_onenoteenabled`

- Stored on a **config entity** in Dataverse (not per-user)
- Default: `true` for environments where OneNote is provisioned
- **Rollback procedure**: Set to `false` — all OneNote writes stop immediately. Existing pages remain in OneNote but no new pages are created. Revert schema/prompt changes in a subsequent deployment.

### User Preference: `cr_onenoteoptout`

- Stored per-user (on user settings entity or user profile)
- Default: `false` (opted in)
- Users can toggle via Canvas app settings
- When `true`, all OneNote writes for that user are skipped

---

## Notebook Provisioning `[P1-IMPLEMENTED]`

### First-Run Setup

The `scripts/provision-onenote.ps1` script handles initial provisioning:

1. Create a dedicated M365 Group (or use existing)
2. Create the OneNote notebook via `POST /groups/{groupId}/onenote/notebooks`
3. Create Section Groups: `Meetings`, `Briefings`
4. Create Sections: `This Week`, `Archive` (under Meetings), `Daily` (under Briefings), `Active To-Dos`
5. Store all IDs in a Dataverse config table
6. Set `cr_onenoteenabled = true`

The script is **idempotent** — safe to re-run. It checks for existing resources before creating.

### Environment Variables

| Variable | Description |
|----------|-------------|
| `OneNote_GroupId` | M365 Group ID |
| `OneNote_NotebookId` | Notebook ID |
| `OneNote_MeetingsThisWeekSectionId` | Section ID for current week meetings |
| `OneNote_MeetingsArchiveSectionId` | Section ID for archived meetings |
| `OneNote_BriefingsDailySectionId` | Section ID for daily briefings |
| `OneNote_ActiveToDosSectionId` | Section ID for active to-dos |

---

## Archival Strategy `[P1-IMPLEMENTED]`

- **Monthly**: Past meeting prep pages older than 30 days are moved from `Meetings > This Week` to `Meetings > Archive` via a scheduled flow
- **Briefings**: Daily briefing pages accumulate in `Briefings > Daily` (OneNote handles pagination natively)
- **Active To-Dos**: Single page with append-only blocks; no archival needed (historical blocks provide audit trail)

---

## API Reference `[P1-IMPLEMENTED]`

### Graph API Endpoints Used

| Operation | Endpoint | Method |
|-----------|----------|--------|
| Create page | `/groups/{groupId}/onenote/sections/{sectionId}/pages` | `POST` |
| Append to page | `/groups/{groupId}/onenote/pages/{pageId}/content` | `PATCH` |
| Search pages | `/groups/{groupId}/onenote/pages?$filter=...&$search=...` | `GET` |
| Read page content | `/groups/{groupId}/onenote/pages/{pageId}/content` | `GET` |
| Get notebook metadata | `/groups/{groupId}/onenote/notebooks/{notebookId}` | `GET` |

### OneNote HTML Content Model

OneNote uses a **restricted HTML subset**. Key constraints:
- Supported tags: `<html>`, `<head>`, `<body>`, `<div>`, `<p>`, `<h1>`–`<h6>`, `<table>`, `<tr>`, `<td>`, `<th>`, `<ul>`, `<ol>`, `<li>`, `<img>`, `<a>`, `<span>`, `<br>`, `<hr>`
- `data-tag` attribute for checkboxes: `data-tag="to-do"` (unchecked), `data-tag="to-do:completed"` (checked)
- `data-absolute-enabled="true"` on `<body>` for absolute positioning layout
- No JavaScript, limited CSS (inline only), no `<script>` or `<link>` tags
- `<meta name="created">` sets page creation timestamp

---

## Phase 2 Scenarios `[P2-PLANNED]`

### Project Logs
Persistent pages per project aggregating related cards, decisions, and outcomes. Updated as new cards arrive.

### Sender Dossiers
Per-sender pages with communication history, response patterns, and relationship context from Sender Profile Analyzer (Flow 9).

### Decision Logs
Append-only pages capturing decisions made via the assistant, with timestamps and reasoning. Indexed by Microsoft Search for future retrieval.

### Annotation Promotion
Read-back pipeline that ingests OneNote annotations, verifies authorship via Entra ID signing, and promotes verified annotations to Tier 1 research sources.

---

## Phase 3 Scenarios `[P3-PLANNED]`

### Bi-Directional Sync
Full read-write loop: the agent reads OneNote content (including annotations) and uses it in triage and research. Changes flow both ways.

### Annotation Detection
Real-time detection of new annotations via Graph API change notifications (webhooks). Triggers re-evaluation of related cards.

### Managed Identity
Replace app registration with managed identity for certificate-free, rotation-free authentication in production environments.

### Per-Agent Cost Attribution
Attribute OneNote API call costs to specific agent instances. Depends on resolution of the Azure Cost Management environment-level limitation documented in the PAYGO governance solution.
