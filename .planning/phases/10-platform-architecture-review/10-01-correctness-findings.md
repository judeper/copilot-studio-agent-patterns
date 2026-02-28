# Correctness Agent -- Platform Architecture Findings

## Summary

**19 issues found: 7 deploy-blocking, 12 non-blocking**

This report validates the factual accuracy of every platform-layer artifact: Dataverse table definitions, output schemas, Power Automate flow specifications, deployment scripts, and Copilot Studio agent prompts. Each claim is checked against known Power Platform capabilities and cross-referenced across files.

## Methodology

Reviewed all 16 platform-layer files systematically against the following sources of truth:
- Dataverse column types, constraints, and API conventions
- Power Automate expression language and connector action names
- Copilot Studio agent configuration capabilities
- PAC CLI command syntax and Dataverse Web API endpoints
- JSON Schema draft-07 specification
- Cross-file consistency (schema-to-prompt, schema-to-flow, schema-to-script)

## Findings

### Deploy-Blocking Issues

**COR-01: output-schema.json priority field uses "N/A" string but schema uses null**
- **Artifact:** `schemas/output-schema.json` (line 38) vs. `prompts/main-agent-system-prompt.md` (line 98, 227, 234)
- **Issue:** The `priority` field in output-schema.json defines `enum: ["High", "Medium", "Low", null]` with null as the not-applicable value. However, the main agent prompt instructs the agent to output `priority = "N/A"` for SKIP items (line 98: `priority = "N/A"`). The prompt's OUTPUT SCHEMA section (line 234) also shows `"priority": "<High | Medium | Low | N/A>"`. This mismatch means the agent will output the string `"N/A"` which would fail JSON Schema validation since `"N/A"` is not in the enum.
- **Evidence:** output-schema.json line 38: `"enum": ["High", "Medium", "Low", null]`. Prompt line 98: `priority = "N/A"`. Prompt line 234: `"priority": "<High | Medium | Low | N/A>"`.
- **Impact:** The Dataverse table DOES have an "N/A" Choice option (value 100000003), and the flow's Compose expression maps "N/A" to that value. But the canonical schema says null. This creates a contract mismatch -- the agent will produce "N/A" strings (per prompt), the flow will handle it (maps string to integer), but the authoritative schema says null.
- **Suggested Fix:** Align the output-schema.json to include "N/A" in the enum: `"enum": ["High", "Medium", "Low", "N/A", null]`, or change the prompt to output null for not-applicable priority. The current bridge works at runtime but violates the canonical contract.

**COR-02: output-schema.json temporal_horizon uses null but prompt uses "N/A"**
- **Artifact:** `schemas/output-schema.json` (line 43) vs. `prompts/main-agent-system-prompt.md` (line 98, 227, 234)
- **Issue:** Same pattern as COR-01. The `temporal_horizon` field in the schema defines `enum: ["TODAY", "THIS_WEEK", "NEXT_WEEK", "BEYOND", null]`. But the prompt instructs SKIP items to use `temporal_horizon = "N/A"` and the OUTPUT SCHEMA in the prompt shows `"N/A"` as a valid value. The flow's Compose expression maps "N/A" to Dataverse integer 100000004 (which exists in the table definition).
- **Evidence:** output-schema.json line 43: `"enum": ["TODAY", "THIS_WEEK", "NEXT_WEEK", "BEYOND", null]`. Prompt line 98: `temporal_horizon = "N/A"`. Prompt line 234: `"<TODAY | THIS_WEEK | NEXT_WEEK | BEYOND | N/A>"`.
- **Suggested Fix:** Add "N/A" to the output-schema.json enum or change the prompt to output null.

**COR-03: Prompt references "USER_VIP" sender category not defined in Dataverse schema**
- **Artifact:** `prompts/main-agent-system-prompt.md` (line 78) vs. `schemas/senderprofile-table.json` (line 63-74)
- **Issue:** The sender-adaptive triage section of the prompt says: `sender_category = "AUTO_HIGH" or "USER_VIP"`. The value "USER_VIP" does not exist in the senderprofile-table.json Choice options. The defined options are: AUTO_HIGH, AUTO_MEDIUM, AUTO_LOW, USER_OVERRIDE.
- **Evidence:** Prompt line 78: `sender_category = "AUTO_HIGH" or "USER_VIP":`. senderprofile-table.json defines only AUTO_HIGH (100000000), AUTO_MEDIUM (100000001), AUTO_LOW (100000002), USER_OVERRIDE (100000003).
- **Impact:** If the agent interprets "USER_VIP" as a valid category, it would never match real data. The prompt should reference "USER_OVERRIDE" instead of "USER_VIP."
- **Suggested Fix:** Change prompt line 78 from `"USER_VIP"` to `"USER_OVERRIDE"`.

**COR-04: provision-environment.ps1 uses `pac admin create` -- incorrect PAC CLI command**
- **Artifact:** `scripts/provision-environment.ps1` (line 66-73)
- **Issue:** The script uses `pac admin create` to create an environment. The correct PAC CLI command is `pac admin create --name ... --type ...` which is valid. However, the `--async` flag (line 73) followed by polling via `pac admin list --json` relies on `pac admin list` returning JSON, but the `--json` flag support for `pac admin list` is version-dependent. Older PAC CLI versions may not support `--json` for this subcommand.
- **Evidence:** Line 73: `--async`. Lines 82-88: `pac admin list --json 2>&1` then `$envListRaw | ConvertFrom-Json`.
- **Impact:** If the PAC CLI version does not support `--json` for `pac admin list`, the polling loop will fail.
- **Suggested Fix:** Document the minimum PAC CLI version required, or add a fallback parsing mechanism for non-JSON output. The `pac admin list` command gained JSON output support in PAC CLI 1.29+.

**COR-05: provision-environment.ps1 calls `pac auth create` again inside the script despite deployment guide suggesting it was done externally**
- **Artifact:** `scripts/provision-environment.ps1` (line 59) vs. `docs/deployment-guide.md` (line 42-43)
- **Issue:** The deployment guide (Phase 1, Step 1.1) instructs users to run `pac auth create --tenant "<your-tenant-id>"` before running the script. Then the script itself (line 59) runs `pac auth create --tenant $TenantId` again. Running `pac auth create` twice will create a duplicate auth profile, which is harmless but confusing. More critically, the second `pac auth create` call will prompt for interactive authentication (browser login), which breaks non-interactive/automated execution.
- **Evidence:** deployment-guide.md line 42: `pac auth create --tenant "<your-tenant-id>"`. provision-environment.ps1 line 59: `pac auth create --tenant $TenantId`.
- **Suggested Fix:** Replace the `pac auth create` call in the script with a validation check: `$authList = pac auth list 2>&1; if ($authList -match "No profiles") { throw "No PAC auth found..." }`. Let the deployment guide handle initial auth.

**COR-06: create-security-roles.ps1 privilege names use incorrect format**
- **Artifact:** `scripts/create-security-roles.ps1` (lines 106-113)
- **Issue:** The script constructs privilege names as `prvCreate${entityName}`, `prvRead${entityName}`, etc. where `$entityName = "cr_assistantcard"`. This produces names like `prvCreatecr_assistantcard`. However, Dataverse privilege names follow the format `prvCreate{EntitySchemaName}` where the schema name uses PascalCase. The schema name for `cr_assistantcard` would be `cr_AssistantCard` (PascalCase after the publisher prefix). So the correct privilege name would be `prvCreatecr_AssistantCard`, not `prvCreatecr_assistantcard`.
- **Evidence:** Lines 106-113 construct privilege names from `$entityName` which is set to the lowercase logical name.
- **Impact:** The privilege lookup query (`$filter=name eq '$privName'`) will fail because Dataverse privilege names use the schema name (PascalCase) not the logical name (lowercase).
- **Suggested Fix:** Use the schema name (PascalCase) for privilege name construction. Change `$entityName = "${PublisherPrefix}_assistantcard"` to `$entityName = "${PublisherPrefix}_AssistantCard"` and similarly for the sender profile entity.

**COR-07: Card Outcome Tracker flow does NOT fire on DISMISSED outcomes but Sprint 4 requires it to**
- **Artifact:** `docs/agent-flows.md` (Flow 5, step 2) vs. `schemas/senderprofile-table.json` (cr_dismisscount description, line 87)
- **Issue:** The Card Outcome Tracker flow (Flow 5, step 2) explicitly filters: "Only update sender profile for SENT_AS_IS or SENT_EDITED outcomes (not DISMISSED or EXPIRED)." The design note says "Dismissals are intentionally excluded." However, senderprofile-table.json defines `cr_dismisscount` (line 87) with description "Sprint 4: Times the user dismissed cards from this sender. Updated by the Card Outcome Tracker flow." Sprint 4 verification checklist in deployment-guide.md states: "Card Outcome Tracker increments cr_dismisscount on DISMISSED outcomes." This is a contradiction: the flow spec excludes DISMISSED from processing, but Sprint 4 requires it for dismiss count tracking.
- **Evidence:** agent-flows.md Flow 5 step 2 excludes DISMISSED. senderprofile-table.json line 87: "Updated by the Card Outcome Tracker flow." deployment-guide.md Sprint 4 verification: "Card Outcome Tracker increments cr_dismisscount on DISMISSED outcomes."
- **Suggested Fix:** Update Flow 5 to handle three branches: SENT_AS_IS/SENT_EDITED (update response count + avg hours), DISMISSED (increment cr_dismisscount), and EXPIRED (no action). The current flow spec needs a Sprint 4 addendum.

### Non-Blocking Issues

**COR-08: dataverse-table.json `confidencescore` type listed as "WholeNumber" -- not a standard Dataverse type name**
- **Artifact:** `schemas/dataverse-table.json` (line 89)
- **Issue:** The type is listed as `"WholeNumber"`. The actual Dataverse column type name is `"Integer"` or `"WholeNumber"` depending on context. In the Dataverse Web API, the attribute metadata type is `IntegerAttributeMetadata`. The provisioning script correctly uses `IntegerAttributeMetadata`. The JSON schema uses this as a documentation type name, which is technically a display name not an API type. This is not blocking because the provisioning script handles it correctly.
- **Evidence:** dataverse-table.json line 89: `"type": "WholeNumber"`. provision-environment.ps1 line 330: `"@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"`.
- **Suggested Fix:** For documentation accuracy, consider using either "Integer" (API name) or keeping "WholeNumber" (Maker UI name) but documenting the mapping.

**COR-09: dataverse-table.json uses "MultilineText" but Dataverse API type is "Memo"**
- **Artifact:** `schemas/dataverse-table.json` (lines 98, 104)
- **Issue:** The `cr_fulljson` and `cr_humanizeddraft` columns are listed with `"type": "MultilineText"`. The actual Dataverse API attribute metadata type is `MemoAttributeMetadata`. The provisioning script correctly uses `MemoAttributeMetadata`. The JSON documentation type "MultilineText" is the Maker portal UI label, not the API type.
- **Evidence:** dataverse-table.json line 98: `"type": "MultilineText"`. provision-environment.ps1 line 362: `"@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"`.
- **Suggested Fix:** Consistent with COR-08 -- document which naming convention is used.

**COR-10: output-schema.json `item_summary` has `maxLength: 300` but JSON Schema draft-07 maxLength is for string length validation only**
- **Artifact:** `schemas/output-schema.json` (line 33)
- **Issue:** JSON Schema draft-07 `maxLength` validates the number of characters in a string. This is semantically correct for documentation but is not enforced by Power Automate's Parse JSON action (which ignores maxLength). The Dataverse column maxLength is 300, so if the agent produces a summary longer than 300 characters, the Dataverse write will fail with a truncation error.
- **Evidence:** output-schema.json line 33: `"maxLength": 300`. dataverse-table.json line 42: `"maxLength": 300`.
- **Suggested Fix:** This is correctly documented. However, consider adding a truncation expression in the flow before the Dataverse write: `@{take(body('Parse_JSON')?['item_summary'], 300)}`. Not blocking because the agent prompt constrains summary length.

**COR-11: Trigger Type Compose expression in agent-flows.md only maps 3 values, but 6 exist**
- **Artifact:** `docs/agent-flows.md` (Flow 1, step 7, Trigger Type Value expression)
- **Issue:** The Compose expression for Trigger Type maps EMAIL -> 100000000, TEAMS_MESSAGE -> 100000001, CALENDAR_SCAN -> 100000002. But the Dataverse table defines 6 trigger types including DAILY_BRIEFING (100000003), SELF_REMINDER (100000004), and COMMAND_RESULT (100000005). The expression has no mapping for these three types and would default to 100000002 (CALENDAR_SCAN) if any of them appeared.
- **Evidence:** agent-flows.md step 7 Trigger Type expression: `if(equals(...,'EMAIL'),100000000,if(equals(...,'TEAMS_MESSAGE'),100000001,100000002))`. The default fallback is CALENDAR_SCAN (100000002).
- **Impact:** Non-blocking for Flows 1-3 since they hardcode TRIGGER_TYPE to their respective values. But this expression would be incorrect if reused for Daily Briefing or other flows.
- **Suggested Fix:** Add a note that this expression is specific to Flows 1-3. The Daily Briefing flow and Command Execution flow should use their own Compose expressions with the correct integer values.

**COR-12: briefing-output-schema.json `fyi_items` and `stale_alerts` are not in `required` array**
- **Artifact:** `schemas/briefing-output-schema.json` (lines 6-12)
- **Issue:** The `required` array lists only `briefing_type`, `briefing_date`, `total_open_items`, `day_shape`, and `action_items`. The `fyi_items` and `stale_alerts` arrays are not required, which is correct per the prompt ("Omit the array if none qualify"). However, the briefing prompt's OUTPUT FORMAT section (line 134-165) shows them as always present. The prompt's CONSTRAINTS section (line 173-174) correctly says "Omit the array if none qualify." This is internally consistent but could cause issues if the Parse JSON action in the Daily Briefing flow expects these fields.
- **Evidence:** briefing-output-schema.json lines 6-12 (required array). daily-briefing-agent-prompt.md line 173-174 (omit if none qualify).
- **Suggested Fix:** In the Daily Briefing flow's Parse JSON action, use `{}` (empty schema) for fyi_items and stale_alerts to handle their optional presence, similar to the draft_payload approach.

**COR-13: Agent prompt SKIP example outputs `"N/A"` for temporal_horizon but Example 2 (LIGHT) outputs `"N/A"` for temporal_horizon**
- **Artifact:** `prompts/main-agent-system-prompt.md` (line 227, 295, 345)
- **Issue:** All few-shot examples for EMAIL and TEAMS_MESSAGE set `temporal_horizon` to `"N/A"` (string). The output-schema.json enum does not include `"N/A"` (only null). The CALENDAR_SCAN example uses real horizon values. This reinforces the "N/A" string pattern documented in COR-02.
- **Evidence:** Prompt line 227: `"temporal_horizon": "N/A"` in SKIP example. Line 295: `"temporal_horizon": "N/A"` in LIGHT example. output-schema.json line 43: `enum: ["TODAY", "THIS_WEEK", "NEXT_WEEK", "BEYOND", null]`.
- **Suggested Fix:** Covered by COR-02 fix.

**COR-14: Deployment guide JSON output mode example shows `"temporal_horizon": "N/A"` string**
- **Artifact:** `docs/deployment-guide.md` (line 130)
- **Issue:** The JSON example provided for configuring JSON output mode in Copilot Studio includes `"temporal_horizon": "N/A"`. This reinforces the "N/A" string convention from the prompt rather than the null convention from the schema.
- **Evidence:** deployment-guide.md line 130: `"temporal_horizon": "N/A"`.
- **Suggested Fix:** Covered by COR-01/COR-02 fix.

**COR-15: Deployment guide input variable table missing SENDER_PROFILE**
- **Artifact:** `docs/deployment-guide.md` (lines 152-158) vs. `prompts/main-agent-system-prompt.md` (lines 23-28)
- **Issue:** The deployment guide's "Set Up Input Variables" section (Phase 2, Step 2.3) lists 4 input variables: TRIGGER_TYPE, PAYLOAD, USER_CONTEXT, CURRENT_DATETIME. The main agent prompt defines a 5th runtime input: `{{SENDER_PROFILE}}` (Sprint 4 addition). This variable is not documented in the deployment guide's input variable table.
- **Evidence:** deployment-guide.md lines 152-158 (4 variables). main-agent-system-prompt.md lines 23-28 (5 variables including SENDER_PROFILE).
- **Suggested Fix:** Add SENDER_PROFILE to the input variables table in the deployment guide. Type: Multi-line text. Description: JSON object with sender intelligence, or null for first-time senders.

**COR-16: provision-environment.ps1 does not create Sprint 4 columns on SenderProfile table**
- **Artifact:** `scripts/provision-environment.ps1` vs. `schemas/senderprofile-table.json` (lines 82-111)
- **Issue:** The provisioning script creates the base SenderProfile columns (senderemail, senderdisplayname, signalcount, responsecount, avgresponsehours, lastsignaldate, sendercategory, isinternal) but does NOT create the Sprint 4 columns: cr_dismisscount, cr_avgeditdistance, cr_responserate, cr_dismissrate. These are defined in senderprofile-table.json but missing from the provisioning script.
- **Evidence:** senderprofile-table.json defines 12 columns. The provisioning script only creates 8 of them (base + Sprint 1B).
- **Suggested Fix:** Add Sprint 4 column creation calls to the provisioning script for cr_dismisscount (WholeNumber), cr_avgeditdistance (WholeNumber), cr_responserate (Decimal, precision 4), cr_dismissrate (Decimal, precision 4).

**COR-17: provision-environment.ps1 does not create the alternate key on SenderProfile table**
- **Artifact:** `scripts/provision-environment.ps1` vs. `schemas/senderprofile-table.json` (lines 8-14)
- **Issue:** The senderprofile-table.json defines an alternate key `cr_senderemail_key` on the `cr_senderemail` column for safe upsert patterns. The provisioning script creates the SenderProfile table and its columns but does not create the alternate key via the Dataverse Web API.
- **Evidence:** senderprofile-table.json lines 8-14 define the alternate key. The provisioning script has no alternate key creation code.
- **Impact:** Without the alternate key, the List-Condition-Add/Update upsert pattern in the flows still works, but it lacks the concurrency safety that an alternate key provides. Concurrent flow runs could create duplicate sender profiles.
- **Suggested Fix:** Add alternate key creation via the Dataverse Web API: `POST /api/data/v9.2/EntityDefinitions(LogicalName='cr_senderprofile')/Keys` with the key definition.

**COR-18: Security roles script privilege depth comment says "1=User, 2=BU, 3=Parent-child BU, 4=Org" but uses string "Basic" not integer**
- **Artifact:** `scripts/create-security-roles.ps1` (line 128)
- **Issue:** The plan's checklist mentions verifying "security role privilege depth values (1=User, 2=BU, 3=Parent-child BU, 4=Org)." The script uses `Depth = "Basic"` in the AddPrivilegesRole API call, which is the correct string enum value for the Dataverse Web API (not integers). The string values are: Basic (User), Local (BU), Deep (Parent-child BU), Global (Org). This is correct API usage.
- **Evidence:** create-security-roles.ps1 line 128: `Depth = "Basic"`.
- **Impact:** Non-blocking -- the script is correct. The plan's numeric reference is an implementation detail of older APIs.
- **Suggested Fix:** None needed for the script. The plan's checklist could be updated to use string enum names.

**COR-19: Simplified Parse JSON schema in agent-flows.md uses `["string", "null"]` type arrays which ARE supported**
- **Artifact:** `docs/agent-flows.md` (lines 37-53)
- **Issue:** The simplified schema uses `"type": ["string", "null"]` for fields like `research_log`, `key_findings`, `confidence_score`, and `low_confidence_note`. Power Automate's Parse JSON action DOES support type arrays (this is a JSON Schema primitive feature, different from `oneOf`/`anyOf` which are schema composition keywords). The documentation correctly notes that `oneOf` is not supported but the simplified schema avoids it. This is correctly handled.
- **Evidence:** agent-flows.md lines 45-51 use type arrays. The note about oneOf/anyOf (line 34) is accurate.
- **Suggested Fix:** None needed -- this is correct.

### Validated (No Issues)

1. **Dataverse column types**: All types in dataverse-table.json (Choice, Text, WholeNumber, MultilineText, DateTime, Boolean) are valid Dataverse column types. maxLength values are within limits (Text max 4000, Memo max 1048576).
2. **Choice option values**: All Choice options start at 100000000 (Dataverse convention for custom choices). Values are sequential and consistent across table definitions, provisioning script, and flow expressions.
3. **UserOwned ownership type**: Both tables correctly specify `"ownershipType": "UserOwned"`, which enables row-level security.
4. **Primary name attributes**: `cr_itemsummary` (Text, 300) for AssistantCards and `cr_senderemail` (Text, 320) for SenderProfile are valid primary name column types.
5. **Alternate key column type**: The alternate key on `cr_senderemail` (Text type) is a supported key column type in Dataverse.
6. **JSON Schema draft-07 syntax**: Both output-schema.json and briefing-output-schema.json use valid draft-07 syntax including `$schema`, `type`, `required`, `properties`, `enum`, `minimum`, `maximum`, `items`, `additionalProperties`.
7. **Nullable field syntax**: The `["type", "null"]` pattern in output-schema.json is valid JSON Schema syntax for nullable fields.
8. **Power Automate connector action names**: "When a new email arrives (V3)", "Get my profile (V2)", "Execute Agent and wait", "Add a new row", "When someone is mentioned", "Get events (V4)", "When a row is added, modified or deleted" are all real connector actions.
9. **Power Automate expression syntax**: Expression functions used -- `equals()`, `not()`, `and()`, `or()`, `contains()`, `toLower()`, `body()`, `outputs()`, `triggerOutputs()`, `utcNow()`, `addDays()`, `string()`, `if()`, `empty()`, `first()`, `add()`, `split()`, `last()`, `trim()`, `startsWith()`, `substring()`, `take()`, `div()`, `sub()`, `ticks()`, `mul()`, `float()`, `greater()`, `greaterOrEquals()`, `length()` -- are all valid Power Automate expression functions.
10. **Copilot Studio connector**: "Execute Agent and wait" is the correct action name in the Microsoft Copilot Studio connector (distinct from AI Builder "Run a prompt").
11. **PAC CLI commands**: `pac auth create`, `pac admin create`, `pac admin list`, `pac org select`, `pac solution import` are all valid PAC CLI commands.
12. **Dataverse Web API endpoints**: `/api/data/v9.2/EntityDefinitions`, `/api/data/v9.2/EntityDefinitions(...)/Attributes`, `/api/data/v9.2/roles`, `/api/data/v9.2/privileges`, `/api/data/v9.2/businessunits` are all valid Dataverse Web API endpoints.
13. **Azure CLI token acquisition**: `az account get-access-token --resource $OrgUrl --query accessToken -o tsv` is a valid approach for acquiring Dataverse access tokens.
14. **PowerShell syntax**: Parameter validation attributes (`[Parameter(Mandatory)]`, `[ValidateSet()]`, `[CmdletBinding(SupportsShouldProcess)]`), error handling (`$ErrorActionPreference`, try/catch), and JSON serialization (`ConvertTo-Json -Depth 20`) are all syntactically correct.
15. **Solution.cdsproj structure**: Valid MSBuild project file with correct SDK reference, SolutionPackageType, and ProjectReference to the PCF project.
16. **Cross-reference: output-schema.json fields to Dataverse columns**: All 12 output-schema.json fields have corresponding Dataverse columns or are stored in cr_fulljson (research_log, key_findings, verified_sources, draft_payload, low_confidence_note).
17. **Cross-reference: Choice mapping values**: All Choice value mappings in agent-flows.md match the definitions in dataverse-table.json and provision-environment.ps1.
18. **Copilot Studio runtime variable syntax**: The `{{VARIABLE_NAME}}` pattern used in prompts matches the input variable injection format in Copilot Studio.
