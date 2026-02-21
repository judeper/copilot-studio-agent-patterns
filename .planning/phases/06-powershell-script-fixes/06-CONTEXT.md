# Phase 6: PowerShell Script Fixes - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix deploy-solution.ps1 and create-security-roles.ps1 to work correctly: align build commands with Bun (Phase 3 migration), improve import verification, parameterize hardcoded values, and add robust prerequisite checks. Also fix the deployment guide's manual build commands to match the Bun migration. This is a fix-only phase -- no new scripts or deployment capabilities.

</domain>

<decisions>
## Implementation Decisions

### Import verification
- Keep synchronous `pac solution import` -- no async polling needed for a single PCF component
- Trust the pac exit code for success/failure detection
- Remove the current `pac solution list` verification step (checks existence, not import result)
- Improve error messaging on import failure

### Deployment guide sync
- Update deployment-guide.md Phase 5 manual build commands from `npm install` / `npm run build` to `bun install` / `bun run build` alongside the script changes (don't defer to Phase 7)

### WhatIf support
- Add `-WhatIf` flag to deploy-solution.ps1 that shows planned steps without executing
- Standard PowerShell pattern for reference quality

### Error & failure behavior
- Fail fast, no cleanup on build failure -- partial build artifacts are harmless and overwritten on next run
- Structured exit codes: 0=success, 1=prerequisite failure, 2=build failure, 3=import failure
- Write a timestamped deploy.log alongside console output for troubleshooting
- create-security-roles.ps1: fail the whole script if any privilege is not found (table not published yet), rather than warning and continuing

### Prerequisite checks
- deploy-solution.ps1: check Bun, Node.js, dotnet SDK, PAC CLI, and PAC auth
- create-security-roles.ps1: add upfront Azure CLI (az) installed + authenticated check
- All missing-prerequisite error messages include the install command or URL
- create-security-roles.ps1 `-PublisherPrefix` parameter already exists and works -- no changes needed there

### Claude's Discretion
- Version checking strictness (existence-only vs minimum versions for Bun/Node)
- Exact log file format and rotation
- WhatIf output formatting
- deploy.log file location and naming convention

</decisions>

<specifics>
## Specific Ideas

- Structured exit codes should be documented in the script's help block so CI pipelines can distinguish failure stages
- Log file useful for troubleshooting failed deploys without re-running the script

</specifics>

<deferred>
## Deferred Ideas

- Packaging Power Automate flows and Copilot Studio agents into the solution (currently manual setup) -- would be a new capability beyond this fix-only milestone
- Expanding deploy-solution.ps1 into a full end-to-end deployment orchestrator covering all 7 deployment phases

</deferred>

---

*Phase: 06-powershell-script-fixes*
*Context gathered: 2026-02-21*
