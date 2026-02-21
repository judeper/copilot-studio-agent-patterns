# Phase 2: Table Naming Consistency - Research

**Researched:** 2026-02-20
**Domain:** Dataverse table naming conventions across schema, scripts, code, and documentation
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Fix all Dataverse API/schema references AND code-level identifiers (TypeScript variable names, interface names, etc.)
- Natural-language references in docs and comments are excluded — only functional references that affect correctness
- Schema definition files (dataverse-table.json, output-schema.json) are source of truth and must be corrected
- Exclude only node_modules and build output directories from the audit
- PowerShell scripts: use the correct form based on what the operation is doing — singular (cr_assistantcard) for table definition/metadata operations, plural (cr_assistantcards) for OData/Web API calls
- Fix all violations directly in-place — this is a pre-deployment repo, no need for review-per-fix
- JSON property names in schema files: Claude determines which references are Dataverse-specific vs application-level naming
- Create a reusable PowerShell audit script that checks naming conventions
- Script reports both violations (incorrect usages) and correct usages as positive confirmation
- Script lives inside `enterprise-work-assistant/` directory
- PowerShell format to match existing project script conventions

### Claude's Discretion
- TypeScript type/interface naming convention (singular vs plural) — follow TypeScript conventions while keeping Dataverse references correct
- Which JSON property names are Dataverse-specific vs application-level — determine based on context

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SCHM-07 | Table logical name uses consistent singular/plural convention (cr_assistantcard) across all files — schema, scripts, docs, and code | Complete inventory of all 50+ references across 14 files; naming rules documented; audit script pattern defined |
</phase_requirements>

## Summary

This phase is a naming consistency audit and fix pass, not a technology integration. The Dataverse table `cr_assistantcard` (logical name, singular) and `cr_assistantcards` (entity set name, plural) must be used in the correct contexts everywhere. The codebase is small (14 files with references) and the rules are deterministic: singular for table definition/metadata contexts, plural for OData Web API entity set contexts.

After exhaustive grep analysis of the entire `enterprise-work-assistant/` directory, the current naming is **already largely correct**. The dataverse-table.json schema file correctly defines `tableName: "cr_assistantcard"` and `entitySetName: "cr_assistantcards"`. PowerShell scripts correctly use singular form for `EntityDefinitions(LogicalName='..._assistantcard')` and `SchemaName` properties. The primary key column `cr_assistantcardid` is correctly derived from the singular logical name (this is a Dataverse convention -- primary key is always `{logicalname}id`).

The main work is: (1) creating the reusable audit script, (2) running it to confirm zero violations or catch edge cases, and (3) fixing any violations found.

**Primary recommendation:** Build the audit script first, run it to discover any violations, fix them, then run again to confirm zero violations. The audit script becomes a permanent verification artifact.

## Dataverse Naming Rules

### Rule Reference (HIGH confidence)

Dataverse has three distinct name forms for tables. Each is used in specific contexts:

| Name Form | Example | Where Used |
|-----------|---------|------------|
| **Logical Name** (singular) | `cr_assistantcard` | `EntityDefinitions(LogicalName='...')`, `SchemaName` in creation payloads, table metadata queries, privilege names (`prvCreate{name}`), column prefixing (`cr_assistantcard.cr_fulljson`) |
| **Entity Set Name** (plural) | `cr_assistantcards` | OData Web API data operations: `GET /api/data/v9.2/cr_assistantcards`, `POST /api/data/v9.2/cr_assistantcards`, OData `@odata.bind` references |
| **Primary Key Column** | `cr_assistantcardid` | Derived from logical name + `id` suffix. Used in Power Apps formulas, record lookups, GUID matching |

**Key distinction:** Metadata operations use the logical name (singular). Data operations through OData use the entity set name (plural). The primary key column name is always `{logicalname}id`.

### Application-Level Names (not Dataverse-specific)

These names are application conventions, not Dataverse API contracts:

| Name | Context | Naming Convention |
|------|---------|-------------------|
| `AssistantCard` (singular) | TypeScript interface name | Standard TypeScript: interfaces are singular nouns |
| `AssistantCard[]` | TypeScript array type | Singular interface + array brackets |
| `AssistantCards` | Display name / prose references in comments, README, Write-Host strings | Natural language plural |
| `cardDataset` | PCF dataset property name | Application-level, not Dataverse-specific |

## Complete File Inventory

### Schema Files

**`schemas/dataverse-table.json`** -- SOURCE OF TRUTH
- Line 2: `"tableName": "cr_assistantcard"` -- CORRECT (logical name, singular)
- Line 3: `"entitySetName": "cr_assistantcards"` -- CORRECT (entity set name, plural)
- Column `logicalName` values (cr_triagetier, cr_triggertype, etc.) -- CORRECT (all use singular table prefix)
- **Status: No changes needed**

**`schemas/output-schema.json`**
- No table name references. This is the agent JSON output contract, not Dataverse-specific.
- **Status: No changes needed**

### PowerShell Scripts

**`scripts/provision-environment.ps1`**
- Line 6: `provisions the AssistantCards Dataverse table` -- natural language (excluded per scope)
- Line 98-100: `# 3. Create AssistantCards Table...` / `Write-Host "Creating AssistantCards..."` -- natural language (excluded)
- Line 118: `SchemaName = "${PublisherPrefix}_assistantcard"` -- CORRECT (singular for metadata creation)
- Line 182: `EntityDefinitions(LogicalName='${PublisherPrefix}_assistantcard')` -- CORRECT (singular for metadata lookup)
- **Status: No Dataverse API violations. Natural language references excluded per scope.**

**`scripts/create-security-roles.ps1`**
- Line 7: `depth on the AssistantCards table` -- natural language (excluded)
- Line 59: `description = "...CRUD access to AssistantCards table..."` -- natural language in a description string (excluded)
- Line 79-81: `# 4. Add Privileges for AssistantCards` / `Write-Host "Configuring privileges on AssistantCards table..."` -- natural language (excluded)
- Line 84: `EntityDefinitions(LogicalName='${PublisherPrefix}_assistantcard')` -- CORRECT (singular for metadata)
- Line 88: `$entityName = "${PublisherPrefix}_assistantcard"` -- CORRECT (singular for privilege name construction)
- Line 90-96: `prvCreate${entityName}`, `prvRead${entityName}`, etc. -- CORRECT (privilege names use logical name)
- Line 135: `Write-Host "Table: ${PublisherPrefix}_assistantcard..."` -- functional reference displaying the logical name -- CORRECT
- **Status: No Dataverse API violations. Natural language references excluded per scope.**

**`scripts/deploy-solution.ps1`**
- Line 146: `Write-Host "  2. Configure dataset binding to AssistantCards"` -- natural language (excluded)
- **Status: No Dataverse API violations.**

### TypeScript / PCF Code

**`src/AssistantDashboard/components/types.ts`**
- Line 26: `export interface AssistantCard {` -- CORRECT (TypeScript convention: singular interface name)
- Line 45: `cards: AssistantCard[];` -- CORRECT (singular interface + array)
- **Status: No changes needed. Singular interface name is correct TypeScript convention.**

**`src/AssistantDashboard/hooks/useCardData.ts`**
- Lines 2, 16, 24, 30, 42: `AssistantCard` type references -- CORRECT (TypeScript type usage)
- Line 37: `record.getValue("cr_fulljson")` -- CORRECT (column logical name, not table name)
- Line 46: `record.getValue("cr_itemsummary")` -- CORRECT (column logical name)
- Line 56: `record.getValue("cr_humanizeddraft")` -- CORRECT (column logical name)
- **Status: No changes needed.**

**`src/AssistantDashboard/components/App.tsx`**
- Lines 3, 13, 18: `AssistantCard` type references -- CORRECT
- **Status: No changes needed.**

**`src/AssistantDashboard/components/CardDetail.tsx`**
- Lines 14, 17: `AssistantCard` type references -- CORRECT
- **Status: No changes needed.**

**`src/AssistantDashboard/components/CardItem.tsx`**
- Lines 13, 16: `AssistantCard` type references -- CORRECT
- **Status: No changes needed.**

**`src/AssistantDashboard/components/CardGallery.tsx`**
- Lines 4, 8: `AssistantCard` type references -- CORRECT
- **Status: No changes needed.**

**`src/AssistantDashboard/index.ts`**
- Lines 5, 25: `AssistantCard` type references -- CORRECT
- **Status: No changes needed.**

**`src/AssistantDashboard/ControlManifest.Input.xml`**
- Line 10: `<!-- Dataset: bound to AssistantCards Dataverse table in Canvas app -->` -- XML comment, natural language (excluded)
- **Status: No changes needed.**

### Documentation

**`docs/deployment-guide.md`**
- Line 43: `` The `cr_assistantcard` table (entity set name `cr_assistantcards`) `` -- CORRECT (accurately describes both names)
- Line 242: `Dataverse retention policy for AssistantCards` -- natural language (excluded)
- Line 255: `AssistantCards table has all columns` -- natural language (excluded)
- **Status: No violations in functional references.**

**`docs/canvas-app-setup.md`**
- Line 26: `the entity logical name is \`cr_assistantcard\`` -- CORRECT (documenting logical name)
- Line 29: `The logical names (e.g., \`cr_assistantcard\`, \`cr_fulljson\`) are used in Dataverse API calls` -- CORRECT
- Lines 133, 138, 160, 163: `cr_assistantcardid` -- CORRECT (primary key column is `{logicalname}id`)
- **Status: No violations.**

**`docs/agent-flows.md`**
- Line 3: `Dataverse \`Assistant Cards\` table` -- display name reference (excluded)
- **Status: No violations.**

**`README.md`**
- Line 42: `DATAVERSE (AssistantCards)` -- natural language in ASCII diagram (excluded)
- Line 70: `AssistantCards table definition` -- natural language (excluded)
- Line 83: `typed AssistantCard[]` -- TypeScript type reference (correct)
- **Status: No violations.**

## Architecture Patterns

### Pattern 1: Audit Script Design

**What:** A PowerShell script that greps the codebase for all `cr_assistantcard` patterns and classifies each hit as correct or violation.

**When to use:** Run after any file changes to verify naming consistency. Included in the project as a permanent artifact.

**Design approach:**
```
1. Define regex patterns for violations vs correct usage
2. Search all files excluding node_modules/, out/, bin/, obj/
3. For each match, classify based on context:
   - EntityDefinitions(LogicalName='...') -> expects singular
   - SchemaName = '...' -> expects singular
   - prv{Action}... -> expects singular
   - /api/data/v9.2/... -> expects plural (entity set)
   - @odata.bind -> expects plural
   - TypeScript interface/type -> application-level (not a violation)
   - Natural language prose -> excluded
4. Report violations with file:line:context
5. Report correct usages as positive confirmation
6. Exit with non-zero code if violations found
```

**Matching the existing script conventions:**
- Use `param()` block with documented parameters
- Use `$ErrorActionPreference = "Stop"`
- Use section comment separators (`# ─────────────────────────────────────`)
- Use `Write-Host` with `-ForegroundColor` for output
- Include `.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE` in comment-based help
- Script should be runnable from the `enterprise-work-assistant/` directory

### Pattern 2: Context-Sensitive Classification

The audit cannot be a simple "find bad string" scan. The same string `cr_assistantcard` is correct in some contexts and the plural `cr_assistantcards` is correct in others. The script must classify by context:

**Singular is correct when:**
- Used in `EntityDefinitions(LogicalName='...')` API calls
- Used in `SchemaName` property values
- Used in privilege name construction (`prv{Action}{logicalname}`)
- Used in column logical name references (`cr_assistantcard.cr_column`)
- Documenting the logical name explicitly

**Plural is correct when:**
- Used in OData entity set URLs (`/api/data/v9.2/cr_assistantcards`)
- Used in `@odata.bind` references
- Documenting the entity set name explicitly

**Neither is a violation when:**
- Natural language prose in comments, Write-Host, docstrings
- TypeScript type/interface names (`AssistantCard`)
- Display names (`"Assistant Cards"`)
- Primary key column name (`cr_assistantcardid`)

### Anti-Patterns to Avoid
- **Overzealous fixing:** Changing TypeScript `AssistantCard` to `AssistantCards` would break the codebase and violate TypeScript conventions.
- **Ignoring context:** A simple regex replacing all `cr_assistantcards` with `cr_assistantcard` would break OData entity set references.
- **Missing the primary key:** `cr_assistantcardid` is correct as-is. It derives from the logical name, not the entity set name.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File search across codebase | Manual file-by-file review | PowerShell `Get-ChildItem -Recurse` + `Select-String` | Reliable, repeatable, catches all files |
| Pattern matching | Custom string parsing | Regex with context capture groups | Standard approach, handles all edge cases |

**Key insight:** The audit script IS the deliverable for this phase. It proves the naming is correct and catches future regressions.

## Common Pitfalls

### Pitfall 1: Confusing Logical Name with Entity Set Name
**What goes wrong:** Using `cr_assistantcards` (plural) in metadata API calls or `cr_assistantcard` (singular) in OData data URLs.
**Why it happens:** Dataverse has two different name systems for the same table.
**How to avoid:** The audit script must check context -- metadata operations use singular, data operations use plural.
**Warning signs:** 404 errors from Dataverse API, "entity not found" errors in scripts.

### Pitfall 2: Over-Correcting TypeScript Names
**What goes wrong:** Changing `interface AssistantCard` to `interface AssistantCards` thinking it should match the Dataverse entity set name.
**Why it happens:** Confusing Dataverse naming with TypeScript naming conventions.
**How to avoid:** TypeScript interfaces are always singular nouns by convention. `AssistantCard` is the correct TypeScript name. The Dataverse entity set name has no bearing on TypeScript interface naming.
**Warning signs:** TypeScript type names that look like plurals (`interface AssistantCards { ... }`).

### Pitfall 3: Missing cr_assistantcardid References
**What goes wrong:** Incorrectly flagging `cr_assistantcardid` as a violation because it contains the singular form.
**Why it happens:** The primary key column is `{logicalname}id` by Dataverse convention.
**How to avoid:** The audit script must recognize `cr_assistantcardid` as a correct primary key reference, not a table name reference.
**Warning signs:** False positives in the audit output for primary key references.

### Pitfall 4: False Positives on Natural Language
**What goes wrong:** Flagging `Write-Host "Configuring privileges on AssistantCards table..."` as a violation.
**Why it happens:** The audit script matches any occurrence of the pattern.
**How to avoid:** Per the user's decision, natural language references in docs and comments are excluded. The script should distinguish functional API references from prose.
**Warning signs:** Excessive violation counts driven by documentation strings.

## Code Examples

### Audit Script Core Pattern (PowerShell)

```powershell
# Source: Project convention from existing scripts

# Search all files, excluding build outputs
$files = Get-ChildItem -Path $SearchRoot -Recurse -File |
    Where-Object {
        $_.FullName -notmatch '[\\/](node_modules|out|bin|obj|\.git)[\\/]'
    }

# For each file, search for the pattern
foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match 'cr_assistantcard') {
        $lines = Get-Content $file.FullName
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match 'cr_assistantcard') {
                # Classify: is this singular where plural is needed, or vice versa?
                # Report result
            }
        }
    }
}
```

### Correct Singular Usage (Metadata Context)
```powershell
# EntityDefinitions lookup -- uses logical name (singular)
$entityMeta = Invoke-RestMethod -Uri "$apiBase/EntityDefinitions(LogicalName='cr_assistantcard')"

# SchemaName in table creation -- uses logical name (singular)
SchemaName = "cr_assistantcard"

# Privilege name construction -- uses logical name (singular)
$entityName = "cr_assistantcard"
$privilegeNames = @("prvCreate${entityName}", "prvRead${entityName}")
```

### Correct Plural Usage (Data Operations Context)
```powershell
# OData entity set URL -- uses entity set name (plural)
$records = Invoke-RestMethod -Uri "$apiBase/cr_assistantcards"

# OData bind reference -- uses entity set name (plural)
"@odata.bind" = "/cr_assistantcards($recordId)"
```

### Correct TypeScript Usage
```typescript
// Interface name -- TypeScript convention (singular)
export interface AssistantCard { ... }

// Array of cards -- singular type + array
const cards: AssistantCard[] = [];

// Column name references -- use Dataverse column logical names
const value = record.getValue("cr_fulljson");
```

## Current State Assessment

Based on the complete file inventory above:

| Category | Files Checked | Violations Found | Status |
|----------|--------------|-----------------|--------|
| Schema files | 2 | 0 | Clean |
| PowerShell scripts | 3 | 0 | Clean |
| TypeScript/PCF code | 7 | 0 | Clean |
| Documentation | 4 | 0 | Clean |
| README | 1 | 0 | Clean |
| **Total** | **17** | **0** | **Clean** |

**Finding:** The codebase currently has zero naming violations. All Dataverse API references use the correct singular/plural form. All TypeScript types correctly use singular `AssistantCard`. All natural language references (excluded from scope) consistently use `AssistantCards` as a display name.

This means the primary deliverable is the **audit script** that proves and maintains this correctness, plus a verification pass confirming zero violations.

## Open Questions

1. **Edge case: future OData data operations in scripts**
   - What we know: Current scripts only use metadata operations (singular), never data operations (plural entity set URL). No OData data calls exist in the codebase.
   - What's unclear: Whether future scripts will add data operations.
   - Recommendation: The audit script should handle both patterns so it remains valid as the codebase grows.

## Sources

### Primary (HIGH confidence)
- Direct codebase analysis via exhaustive grep of all files in `enterprise-work-assistant/`
- `schemas/dataverse-table.json` -- authoritative source for table naming conventions
- PowerShell scripts -- existing API call patterns confirm Dataverse naming conventions

### Secondary (MEDIUM confidence)
- Dataverse naming convention knowledge (logical name vs entity set name vs schema name) -- well-established platform convention verified against script usage patterns in this codebase

## Metadata

**Confidence breakdown:**
- File inventory: HIGH -- exhaustive grep with manual verification of every match
- Naming rules: HIGH -- verified against actual Dataverse API call patterns in scripts
- Audit script design: HIGH -- straightforward PowerShell pattern matching, matching existing script conventions
- Violation assessment: HIGH -- every reference manually classified

**Research date:** 2026-02-20
**Valid until:** Indefinite (naming conventions are stable; file inventory valid until new files are added)
