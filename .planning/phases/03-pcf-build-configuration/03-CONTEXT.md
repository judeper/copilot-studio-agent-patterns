# Phase 3: PCF Build Configuration - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Get the PCF control to build successfully with correct platform library versions, proper Fluent UI dependency pins, and clean tooling. This is a greenfield project (no deployed environments, no migration) — the scaffolded code has incorrect imports and version references that need to be fixed before the first build.

</domain>

<decisions>
## Implementation Decisions

### Version pinning strategy
- Use caret range (e.g., `^9.46.0`) for `@fluentui/react-components` in package.json
- Researcher must verify the current stable platform-library ceiling — use whatever is correct, not hardcoded 9.46.2
- Check ALL `@fluentui/*` packages for mutual compatibility and alignment with the platform-library ceiling
- If the verified ceiling differs from 9.46.2, update the roadmap success criteria to reflect the actual version

### Import scope
- This is NOT a migration — the scaffolded code has incorrect `@fluentui/react-theme` imports that were never correct
- Fix all `@fluentui/react-theme` imports to use `@fluentui/react-components`
- Consolidate scattered `@fluentui` imports into clean import blocks while fixing
- Clean up imports across ALL PCF source files, not just affected ones
- `@fluentui/react-theme` should not exist in package.json — it was never a valid dependency for this project
- For API differences between react-theme and react-components token names: Claude uses judgment — swap obvious equivalents, flag ambiguous ones with TODO comments

### Build verification bar
- Build must complete with zero errors AND zero warnings
- Run both `bun run build` and lint — both must pass clean
- Add basic ESLint with standard TypeScript config if not already present
- Enforce TypeScript strict mode (`strict: true` in tsconfig.json) and fix any resulting type errors

### Dependency hygiene
- Use **Bun** as the package manager (not npm/pnpm)
- Success criteria commands become `bun install` and `bun run build` (update roadmap accordingly)
- Commit `bun.lockb` to the repository for deterministic installs
- Audit ALL dependencies in package.json — remove anything unused or unnecessary, not just @fluentui scope
- Run `bun audit` / security vulnerability check — fix auto-fixable issues, flag anything requiring manual attention

### Claude's Discretion
- ESLint rule configuration details
- Exact tsconfig.json compiler options beyond `strict: true`
- How to handle transitive dependency conflicts if they arise

</decisions>

<specifics>
## Specific Ideas

- Bun chosen over npm/pnpm for speed and modern tooling
- Zero-tolerance build output: no warnings, no errors — clean from day one since this is greenfield
- TypeScript strict mode from the start to prevent tech debt accumulation

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-pcf-build-configuration*
*Context gathered: 2026-02-21*
