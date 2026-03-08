# Data Governance Runbook

Operational procedures for data retention, GDPR/CCPA erasure, classification, and audit in the Intelligent Work Layer.

> **Scope**: This runbook covers the Dataverse tables and OneNote integration owned by the Intelligent Work Layer. It does not cover platform-level telemetry (Power Platform analytics, Application Insights) — those are governed by tenant-wide policies.

---

## 1. Data Retention Policy

Each table has a defined retention period. Enforcement is via the **Data Retention Flow** (Flow 8 — scheduled daily) or manual purge.

| Table | Logical Name | Retention | Deletion Strategy | Notes |
|-------|-------------|-----------|-------------------|-------|
| Assistant Cards | `cr_assistantcards` | **90 days** | Hard delete after 90d from `createdon` | Primary card table. Cards with `cr_cardoutcome = EXPIRED` are eligible immediately. |
| Sender Profiles | `cr_senderprofiles` | **365 days** | Hard delete after 365d of inactivity (`modifiedon`) | Retained longer because aggregate sender intelligence improves triage accuracy over time. |
| Error Logs | `cr_errorlogs` | **90 days** | Hard delete after 90d from `cr_occurredon` | Org-owned table — not user-scoped. Contains no PII beyond the affected card ID reference. |
| Episodic Memories | `cr_episodicmemories` | **90 days** | Hard delete after 90d from `createdon` | Decision history entries. High-frequency table — monitor row counts. |
| Semantic Knowledge | `cr_semanticknowledges` | **365 days** | **Soft delete** (set `statecode = 1`) after 365d, hard delete after 730d | Long-term knowledge graph. Soft delete allows recovery during the grace period. |
| Semantic-Episodic Junctions | `cr_semanticepisodic` | Follows parent | Cascade delete when either parent is deleted | Junction table — no independent retention policy. |
| User Personas | `cr_userpersonas` | **365 days** | Hard delete after 365d of inactivity | Behavioral snapshots. Deleted with the user on erasure requests. |
| Skill Registries | `cr_skillregistries` | **365 days** | Hard delete after 365d of inactivity | Skill definitions registered by the user. |
| Briefing Schedules | `cr_briefingschedules` | No expiry | Deleted only on user erasure | Per-user preference row — at most one row per user. |

### Retention Flow Configuration

The Data Retention Flow runs on a daily recurrence and executes age-based queries against each table. To adjust retention periods, update the `addDays()` offsets in the flow's filter expressions — no code changes are needed.

---

## 2. Right-to-Erasure Procedure

**SLA**: Complete erasure within **72 hours** of receiving a verified data subject request (GDPR Article 17) or consumer deletion request (CCPA §1798.105).

### Prerequisites

- Azure CLI authenticated with admin privileges (`az login`)
- Access to the Dataverse org URL
- `scripts/user-data-erasure.ps1` from this repository

### Step-by-Step Procedure

**Step 1 — Verify the request**

Confirm the requestor's identity through your organization's identity verification process. Log the request in your Data Subject Request (DSR) tracker with a timestamp.

**Step 2 — Dry run**

Run the erasure script in `WhatIf` mode to preview the scope of deletion:

```powershell
.\scripts\user-data-erasure.ps1 `
    -OrgUrl "https://yourorg.crm.dynamics.com" `
    -UserEmail "user@example.com" `
    -WhatIf
```

Review the output to confirm the correct user is targeted and the record counts are reasonable.

**Step 3 — Execute erasure**

Run the script without `-WhatIf` to permanently delete the records:

```powershell
.\scripts\user-data-erasure.ps1 `
    -OrgUrl "https://yourorg.crm.dynamics.com" `
    -UserEmail "user@example.com"
```

The script will prompt for confirmation. Type `DELETE` to proceed. For automated pipelines, add `-Force`.

**Step 4 — OneNote cleanup verification**

If OneNote integration is enabled (`cr_onenoteenabled = true`), the script automatically purges user-specific OneNote sections via Graph API. If the automated purge fails, manually delete the user's sections:

1. Open the Intelligent Work Layer OneNote notebook in the M365 Group
2. Search for sections named after the user
3. Delete all matching sections and empty the OneNote recycle bin

**Step 5 — Document completion**

1. Save the script's console output as proof of deletion
2. Update the DSR tracker with completion timestamp and record counts
3. Notify the data subject that erasure is complete

### Erasure Scope — What Is NOT Deleted

| Data | Reason for Retention |
|------|---------------------|
| Aggregated analytics (Power BI) | De-identified / statistical — not personal data under GDPR Recital 26 |
| Platform audit logs | Required for security compliance; managed by tenant admin |
| Shared meeting prep (other users' cards referencing same meeting) | Owned by other users — only the requestor's own cards are deleted |

---

## 3. Data Classification

### PII Inventory by Table

| Table | PII Fields | Sensitivity | Notes |
|-------|-----------|-------------|-------|
| **Assistant Cards** | Sender email (`cr_originalsenderemail`), subject lines, communication drafts (`cr_fulljson`), user decisions (outcome) | **High** | Drafts may contain business-confidential content. `cr_fulljson` contains the full agent response including recommended actions. |
| **Sender Profiles** | Sender email (`cr_senderemail`), behavioral metrics (response rate, dismiss rate, avg response hours) | **High** | Behavioral profiling data — constitutes a user profile under GDPR Article 22. The `cr_sendercategory` field classifies senders (VIP, AUTO_LOW, etc.) based on interaction patterns. |
| **Episodic Memories** | User decisions, timestamps, context of agent interactions | **Medium** | Decision log entries. Contain what the user chose to do (send, dismiss, edit) and why. |
| **Semantic Knowledge** | Extracted knowledge from processed signals, topic associations | **Medium** | May contain names, project references, and organizational context derived from emails/messages. |
| **User Personas** | Behavioral preferences, communication style indicators | **High** | Direct behavioral profiling — captures how the user communicates and makes decisions. |
| **Skill Registries** | Skill names, tool preferences | **Low** | Functional metadata. Minimal PII unless skill names reference personal projects. |
| **Briefing Schedules** | Preferred briefing time, timezone, enabled/disabled flag | **Low** | User preference only. No behavioral data. |
| **Error Logs** | Affected card ID (indirect reference to user data), flow run IDs | **Low** | Org-owned. No direct PII, but `cr_affectedcardid` can be joined to identify the affected user. |

### Data Flow — Where PII Travels

```
Email / Teams / Calendar signal
  → Power Automate Flow (transient processing, no persistent storage outside Dataverse)
  → Copilot Studio Agent (stateless inference, no persistent storage)
  → Dataverse AssistantCards table (persistent — subject to retention)
  → Sender Profile upsert (persistent — subject to retention)
  → OneNote page creation (persistent — subject to erasure, gated by feature flag)
  → Canvas App / PCF component (client-side rendering only, no local storage)
```

---

## 4. Audit Trail

### SKIP Item Audit Logging

When the agent triages a signal as **SKIP**, no AssistantCard is created (by design — SKIP items are intentionally discarded to reduce noise). However, SKIP decisions are still auditable:

| Mechanism | What It Captures | Retention |
|-----------|-----------------|-----------|
| **Flow 1 (Email)** run history | Full flow execution trace including the agent's SKIP decision and reasoning | 28 days (Power Automate default) |
| **Flow 2 (Teams)** run history | Same as Flow 1 for Teams message triggers | 28 days |
| **Flow 3 (Calendar)** run history | Same as Flow 1 for calendar event triggers | 28 days |
| **Episodic Memory** | If episodic logging is enabled, the agent writes a brief decision record even for SKIP items | 90 days |

> **Gap**: Flow run history retention is controlled by the Power Platform and defaults to 28 days. If longer SKIP audit trails are required, enable the episodic memory logging path in the agent prompt or export flow run history to a long-term store.

### Episodic Memory as a Decision Log

The `cr_episodicmemories` table serves as the agent's decision log. Each record captures:

- **What was decided**: Triage tier (SKIP/LIGHT/FULL), confidence score, chosen action
- **Why it was decided**: The agent's reasoning chain, sender context, and matched research findings
- **When**: Timestamp of the decision
- **Outcome**: Whether the user accepted, edited, or dismissed the recommendation

This creates a reviewable audit trail of agent behavior that can be queried for:

- Pattern analysis: "How often does the agent recommend FULL for messages from external senders?"
- Accuracy review: "What percentage of SKIP decisions were overridden by the user?"
- Bias detection: "Does triage tier correlate with sender category in unexpected ways?"

### Querying the Audit Trail

Use the Dataverse Web API or the Canvas App's admin view to query decision history:

```
GET /api/data/v9.2/cr_episodicmemories
  ?$filter=_ownerid_value eq '{userId}' and createdon ge 2025-01-01
  &$orderby=createdon desc
  &$top=50
```

---

## 5. OneNote Data

### What Is Stored in OneNote

When OneNote integration is enabled (`cr_onenoteenabled = true` and `cr_onenoteoptout = false` for the user), the assistant writes:

| Content Type | OneNote Location | Contains PII? | Source |
|-------------|-----------------|---------------|--------|
| Meeting prep | Meetings → This Week | Yes — attendee names, agenda topics, context from prior interactions | Flow 3 (Calendar) post-processing |
| Daily briefing | Briefings → Daily | Yes — summary of open cards, sender names, action items | Daily Briefing Flow (Flow 6) |
| Active to-dos | Active To-Dos section | Yes — task descriptions derived from email/Teams signals | Agent FULL-tier processing |

### OneNote Purge Procedure

**Automated** (via `user-data-erasure.ps1`): The script queries Graph API for OneNote sections matching the user's name or email and deletes them. This covers user-specific sections but may not catch pages embedded in shared sections (e.g., meeting prep for a meeting with multiple attendees).

**Manual follow-up** (if automated purge is insufficient):

1. Navigate to the M365 Group: **Admin Center → Groups → Intelligent Work Layer - OneNote**
2. Open the group's OneNote notebook
3. Search for the user's name and email across all sections
4. Delete any pages containing the user's data
5. Empty the OneNote recycle bin (deleted pages are retained for 60 days otherwise)

### Feature Flag Controls

| Flag | Scope | Effect |
|------|-------|--------|
| `cr_onenoteenabled` | Org-level (config entity) | Master switch. When `false`, no OneNote API calls are made. |
| `cr_onenoteoptout` | Per-user (user settings) | When `true`, OneNote writes are skipped for this specific user even if the org flag is enabled. |

Disabling `cr_onenoteenabled` stops new writes but does **not** delete existing OneNote content. Run the erasure script or perform manual cleanup to remove historical data.

---

## 6. Compliance References

### GDPR (General Data Protection Regulation)

| Article | Relevance | How We Comply |
|---------|-----------|---------------|
| **Article 17** — Right to Erasure | Users can request deletion of all personal data | `user-data-erasure.ps1` script; 72-hour SLA |
| **Article 15** — Right of Access | Users can request a copy of their data | Export via Dataverse Web API or Canvas App admin view |
| **Article 20** — Data Portability | Users can request data in machine-readable format | Dataverse export to JSON/CSV via Web API |
| **Article 22** — Automated Decision-Making | Sender profiling and triage constitute automated profiling | Episodic memory provides explainability; user can override any triage decision |
| **Article 35** — DPIA | High-risk processing (behavioral profiling) requires impact assessment | Conduct DPIA before production deployment |

### CCPA (California Consumer Privacy Act)

| Section | Relevance | How We Comply |
|---------|-----------|---------------|
| **§1798.105** — Right to Delete | Consumers can request deletion | Same erasure script and procedure as GDPR |
| **§1798.110** — Right to Know | Consumers can request disclosure of collected data | Dataverse export via Web API |
| **§1798.100** — Right to Opt-Out | Opt out of sale of personal information | No data is sold; `cr_onenoteoptout` provides per-user opt-out of extended processing |

### Data Residency

Power Platform stores data in the **tenant's configured geographic region**. Dataverse data at rest is encrypted with Microsoft-managed keys (or customer-managed keys if configured). Data does not leave the configured region unless:

- The tenant admin has configured cross-geo data movement
- External connectors (e.g., Graph API for OneNote) route through Microsoft's global infrastructure (data remains within the Microsoft trust boundary)

To verify your data residency configuration:

```
Power Platform Admin Center → Environments → [Your Environment] → Details → Region
```

### Regulatory Note

This runbook provides operational procedures, not legal advice. Consult your organization's Data Protection Officer (DPO) and legal counsel to ensure these procedures satisfy your specific regulatory obligations.
