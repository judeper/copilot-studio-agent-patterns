# Phase 2: Table Naming Consistency - Context

**Gathered:** 2026-02-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Standardize Dataverse table naming across all files: `cr_assistantcard` (singular) for the logical name and `cr_assistantcards` (plural) for the entity set name. Fix all inconsistent references in schemas, scripts, code, and config. Natural-language prose in documentation and comments is out of scope.

</domain>

<decisions>
## Implementation Decisions

### Scope boundaries
- Fix all Dataverse API/schema references AND code-level identifiers (TypeScript variable names, interface names, etc.)
- Natural-language references in docs and comments are excluded — only functional references that affect correctness
- Schema definition files (dataverse-table.json, output-schema.json) are source of truth and must be corrected
- Exclude only node_modules and build output directories from the audit

### Ambiguous contexts
- PowerShell scripts: use the correct form based on what the operation is doing — singular (cr_assistantcard) for table definition/metadata operations, plural (cr_assistantcards) for OData/Web API calls
- Fix all violations directly in-place — this is a pre-deployment repo, no need for review-per-fix
- JSON property names in schema files: Claude determines which references are Dataverse-specific vs application-level naming

### Verification approach
- Create a reusable PowerShell audit script that checks naming conventions
- Script reports both violations (incorrect usages) and correct usages as positive confirmation
- Script lives inside `enterprise-work-assistant/` directory
- PowerShell format to match existing project script conventions

### Claude's Discretion
- TypeScript type/interface naming convention (singular vs plural) — follow TypeScript conventions while keeping Dataverse references correct
- Which JSON property names are Dataverse-specific vs application-level — determine based on context

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-table-naming-consistency*
*Context gathered: 2026-02-20*
