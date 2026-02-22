# Phase 3: PCF Build Configuration - Research

**Researched:** 2026-02-21
**Domain:** PCF platform-library versioning, Fluent UI v9 dependency management, TypeScript/ESLint build tooling
**Confidence:** HIGH

## Summary

This phase resolves three concrete issues in the PCF control's build configuration: an incorrect `platform-library` Fluent version in the manifest (`9.0` instead of `9.46.2`), incorrect `@fluentui/react-theme` imports in two source files that should use `@fluentui/react-components` (which re-exports the same `tokens` object), and build/lint hygiene with Bun as the package manager.

The codebase is in surprisingly good shape. The `package.json` already pins `@fluentui/react-components` to `^9.46.0`, TypeScript `strict: true` is already enabled in `tsconfig.json`, ESLint is already configured with `@typescript-eslint/recommended`, and most source files already import from `@fluentui/react-components`. Only `FilterBar.tsx` and `CardGallery.tsx` have the wrong import source (`@fluentui/react-theme` instead of `@fluentui/react-components` for `tokens`).

**Primary recommendation:** Fix the manifest version from `9.0` to `9.46.2`, replace the two `@fluentui/react-theme` token imports with `@fluentui/react-components`, switch to Bun as the package manager, and verify a clean build with zero errors and zero warnings.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Use caret range (e.g., `^9.46.0`) for `@fluentui/react-components` in package.json
- Researcher must verify the current stable platform-library ceiling -- use whatever is correct, not hardcoded 9.46.2
- Check ALL `@fluentui/*` packages for mutual compatibility and alignment with the platform-library ceiling
- If the verified ceiling differs from 9.46.2, update the roadmap success criteria to reflect the actual version
- This is NOT a migration -- the scaffolded code has incorrect `@fluentui/react-theme` imports that were never correct
- Fix all `@fluentui/react-theme` imports to use `@fluentui/react-components`
- Consolidate scattered `@fluentui` imports into clean import blocks while fixing
- Clean up imports across ALL PCF source files, not just affected ones
- `@fluentui/react-theme` should not exist in package.json -- it was never a valid dependency for this project
- For API differences between react-theme and react-components token names: Claude uses judgment -- swap obvious equivalents, flag ambiguous ones with TODO comments
- Build must complete with zero errors AND zero warnings
- Run both `bun run build` and lint -- both must pass clean
- Add basic ESLint with standard TypeScript config if not already present
- Enforce TypeScript strict mode (`strict: true` in tsconfig.json) and fix any resulting type errors
- Use **Bun** as the package manager (not npm/pnpm)
- Success criteria commands become `bun install` and `bun run build` (update roadmap accordingly)
- Commit `bun.lockb` to the repository for deterministic installs
- Audit ALL dependencies in package.json -- remove anything unused or unnecessary, not just @fluentui scope
- Run `bun audit` / security vulnerability check -- fix auto-fixable issues, flag anything requiring manual attention

### Claude's Discretion
- ESLint rule configuration details
- Exact tsconfig.json compiler options beyond `strict: true`
- How to handle transitive dependency conflicts if they arise

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PCF-01 | ControlManifest.Input.xml platform-library version updated to 9.46.2 (current ceiling) | **Verified:** Official Microsoft docs confirm `9.46.2` is the current ceiling. The manifest currently declares `version="9.0"` which is incorrect. The allowed range is `>=9.4.0 <=9.46.2`. At runtime, the platform loads `9.68.0` but the manifest MUST declare a version within the allowed range. |
| PCF-05 | Fluent UI token imports use @fluentui/react-components (platform-shared), not @fluentui/react-theme | **Verified:** `@fluentui/react-components` is a facade package that re-exports `tokens` from `@fluentui/react-theme` internally. The token names are identical -- no API mapping needed. Only 2 files affected: `FilterBar.tsx` and `CardGallery.tsx`. |
| PCF-06 | @fluentui/react-components version pinned to compatible ceiling (^9.46.0) in package.json | **Already correct:** `package.json` already declares `"@fluentui/react-components": "^9.46.0"`. No change needed for this specific requirement. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @fluentui/react-components | ^9.46.0 | Fluent UI v9 React component library | Platform-shared library for PCF virtual controls; re-exports tokens, themes, and all components |
| @fluentui/react-icons | ^2.0.245 | Fluent UI icon set | Companion icon library for Fluent UI v9 |
| pcf-scripts | ^1 | PCF build toolchain | Microsoft's official build scripts for PCF controls; uses webpack internally |
| typescript | ^4.9.5 | TypeScript compiler | Used by pcf-scripts for type checking and compilation |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| eslint | ^8.50.0 | JavaScript/TypeScript linter | Already configured; runs via `bun run lint` |
| @typescript-eslint/eslint-plugin | ^6.0.0 | TypeScript-specific lint rules | Already configured with recommended preset |
| @typescript-eslint/parser | ^6.0.0 | ESLint parser for TypeScript | Already configured in `.eslintrc.json` |
| bun | (runtime) | Package manager and script runner | User decision: replaces npm for `install`, `run build`, `run lint` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Bun | npm | npm is the default for PCF; Bun is faster but has no documented PCF-specific testing. Bun's Node.js compatibility is high and pcf-scripts uses standard webpack/node APIs, so risk is LOW. |
| ESLint 8 + .eslintrc.json | ESLint 9+ flat config | ESLint 8 is already configured and working; migrating to flat config adds scope beyond this phase. Not recommended for this phase. |

**Installation:**
```bash
bun install
```

## Architecture Patterns

### Current File Structure (No Changes Needed)
```
enterprise-work-assistant/src/
├── .eslintrc.json              # ESLint config (already exists)
├── package.json                # Dependencies (needs Bun lockfile)
├── tsconfig.json               # TypeScript config (strict already enabled)
├── AssistantDashboard.pcfproj  # MSBuild project file
├── AssistantDashboard/
│   ├── ControlManifest.Input.xml  # NEEDS FIX: platform-library version
│   ├── index.ts                   # PCF entry point (imports clean)
│   ├── components/
│   │   ├── types.ts               # Type definitions (no @fluentui imports)
│   │   ├── App.tsx                # Root component (imports clean)
│   │   ├── CardDetail.tsx         # Detail view (imports clean)
│   │   ├── CardItem.tsx           # Card component (imports clean)
│   │   ├── CardGallery.tsx        # NEEDS FIX: @fluentui/react-theme import
│   │   └── FilterBar.tsx          # NEEDS FIX: @fluentui/react-theme import
│   ├── hooks/
│   │   └── useCardData.ts         # Data hook (no @fluentui imports)
│   ├── strings/
│   │   └── AssistantDashboard.1033.resx
│   └── styles/
│       └── AssistantDashboard.css
└── Solutions/
    └── Solution.cdsproj
```

### Pattern 1: Token Import Consolidation
**What:** Merge duplicate `@fluentui/react-components` import lines and eliminate `@fluentui/react-theme` imports
**When to use:** Any file importing `tokens` from `@fluentui/react-theme`
**Example:**
```typescript
// BEFORE (FilterBar.tsx):
import { Badge, Text } from "@fluentui/react-components";
import { tokens } from "@fluentui/react-theme";

// AFTER (FilterBar.tsx):
import { Badge, Text, tokens } from "@fluentui/react-components";
```

### Pattern 2: Clean Import Blocks (Already Used in Most Files)
**What:** Files that already import both named components and `tokens` from `@fluentui/react-components` correctly
**Example:**
```typescript
// CardItem.tsx and CardDetail.tsx already follow this pattern:
import {
    Card,
    Badge,
    Text,
} from "@fluentui/react-components";
import { tokens } from "@fluentui/react-components";
```
These two separate import statements from the same module are valid TypeScript. Consolidating them into a single import is optional and a style preference, not a correctness issue. The CONTEXT.md says to "consolidate scattered @fluentui imports into clean import blocks while fixing", so consolidation during import cleanup is appropriate.

### Anti-Patterns to Avoid
- **Importing from internal `@fluentui` sub-packages directly:** Always import from `@fluentui/react-components` as the facade package. Never add `@fluentui/react-theme` as a direct dependency.
- **Pinning exact versions without caret:** Use `^9.46.0` not `9.46.0` to allow compatible patch/minor updates within the ceiling.
- **Declaring manifest version outside allowed range:** The platform-library Fluent version MUST be within `>=9.4.0 <=9.46.2`. Do not use `9.0`, `9.68.0`, or any value outside this range.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Design tokens | Custom CSS variables or hardcoded colors | `tokens` from `@fluentui/react-components` | Tokens auto-adapt to light/dark themes and platform theming |
| Theme provider | Custom context for theme state | `FluentProvider` from `@fluentui/react-components` | Already correctly implemented in `App.tsx` |
| Dependency auditing | Manual review of node_modules | `bun audit` | Automated vulnerability scanning against npm advisory database |

**Key insight:** The PCF platform shares React and Fluent UI instances across controls. Using the platform-library mechanism (not bundling your own) ensures theme consistency and smaller bundle sizes.

## Common Pitfalls

### Pitfall 1: Platform-Library Version Mismatch
**What goes wrong:** The manifest declares a Fluent version outside the allowed range (`>=9.4.0 <=9.46.2`), causing deployment failure with error "platform library fluent_X_X_X with version X.X.X is not supported by the platform"
**Why it happens:** Newer PAC CLI versions (1.50.1+) generate manifests with `9.68.0` which is not yet in the allowed range. Older scaffolding may use `9.0` which is below the minimum.
**How to avoid:** Always set `version="9.46.2"` (the ceiling) in the manifest. Verify against the [official supported versions table](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/react-controls-platform-libraries#supported-platform-libraries-list).
**Warning signs:** Build succeeds locally but deployment to Power Platform fails.

### Pitfall 2: @fluentui/react-theme as Direct Dependency
**What goes wrong:** `@fluentui/react-theme` is listed in `package.json` as a direct dependency, potentially pulling a version incompatible with the platform-provided `@fluentui/react-components`.
**Why it happens:** `react-theme` is a real npm package that exports `tokens`, so imports resolve during development. But in a virtual PCF control, the platform provides `react-components` at runtime, and having a separate `react-theme` version can cause token mismatches.
**How to avoid:** Import `tokens` from `@fluentui/react-components` only. Do not add `@fluentui/react-theme` to `package.json`.
**Warning signs:** `@fluentui/react-theme` appears anywhere in `package.json` dependencies.

### Pitfall 3: Bun Lockfile Not Committed
**What goes wrong:** Different developers or CI environments resolve different dependency versions, causing "works on my machine" issues.
**Why it happens:** `.gitignore` may not include `bun.lockb`, or developers forget to commit it.
**How to avoid:** Commit `bun.lockb` and ensure `.gitignore` does not exclude it.
**Warning signs:** `bun.lockb` missing from git, or `git status` shows it as untracked.

### Pitfall 4: pcf-scripts Compatibility with Bun
**What goes wrong:** `bun run build` (which invokes `pcf-scripts build`) may behave differently than `npm run build` due to subtle Node.js compatibility differences in Bun.
**Why it happens:** pcf-scripts uses webpack internally and spawns child Node processes. Bun aims for full Node.js compatibility but edge cases exist.
**How to avoid:** Test `bun run build` thoroughly. If issues arise, Bun supports `--bun` flag to force Bun runtime or falls back to Node.js for child processes. The build script is standard webpack, so compatibility risk is LOW.
**Warning signs:** Build errors that don't reproduce with `npm run build`.

### Pitfall 5: ESLint console.warn Warning
**What goes wrong:** The existing ESLint config has `"no-console": "warn"`, and the codebase uses `console.warn` in `useCardData.ts` line 63. This will produce a lint warning, violating the zero-warnings requirement.
**Why it happens:** The `no-console` rule flags all console methods including `warn`.
**How to avoid:** Either disable the rule for that specific line with `// eslint-disable-next-line no-console`, or configure the rule to allow `console.warn` (e.g., `"no-console": ["warn", { "allow": ["warn"] }]`).
**Warning signs:** Lint output shows warning count > 0.

## Code Examples

### Fix 1: ControlManifest.Input.xml Platform-Library Version
```xml
<!-- BEFORE (current): -->
<platform-library name="Fluent" version="9.0" />

<!-- AFTER (correct): -->
<platform-library name="Fluent" version="9.46.2" />
```
Source: [Microsoft Learn - Supported platform libraries list](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/react-controls-platform-libraries#supported-platform-libraries-list)

### Fix 2: FilterBar.tsx Import Consolidation
```typescript
// BEFORE:
import { Badge, Text } from "@fluentui/react-components";
import { tokens } from "@fluentui/react-theme";

// AFTER:
import { Badge, Text, tokens } from "@fluentui/react-components";
```

### Fix 3: CardGallery.tsx Import Consolidation
```typescript
// BEFORE:
import { Text } from "@fluentui/react-components";
import { tokens } from "@fluentui/react-theme";

// AFTER:
import { Text, tokens } from "@fluentui/react-components";
```

### Fix 4: CardItem.tsx Import Consolidation (Optional Cleanup)
```typescript
// BEFORE (correct but scattered):
import {
    Card,
    Badge,
    Text,
} from "@fluentui/react-components";
import { tokens } from "@fluentui/react-components";

// AFTER (consolidated):
import {
    Card,
    Badge,
    Text,
    tokens,
} from "@fluentui/react-components";
```

### Fix 5: CardDetail.tsx Import Consolidation (Optional Cleanup)
```typescript
// BEFORE (correct but scattered):
import {
    Button,
    Badge,
    Text,
    Link,
    Textarea,
    Spinner,
    MessageBar,
    MessageBarBody,
} from "@fluentui/react-components";
import { tokens } from "@fluentui/react-components";

// AFTER (consolidated):
import {
    Button,
    Badge,
    Text,
    Link,
    Textarea,
    Spinner,
    MessageBar,
    MessageBarBody,
    tokens,
} from "@fluentui/react-components";
```

### Token Name Verification
All token names currently used in the codebase are valid Fluent UI v9 tokens and exist in both `@fluentui/react-theme` and `@fluentui/react-components`:
- `tokens.colorNeutralForeground1` -- valid
- `tokens.colorNeutralForeground3` -- valid
- `tokens.colorNeutralStroke1` -- valid
- `tokens.colorPaletteRedBorder2` -- valid
- `tokens.colorPaletteMarigoldBorder2` -- valid
- `tokens.colorPaletteGreenBorder2` -- valid

No API mapping or name changes are required. The `tokens` object exported from `@fluentui/react-components` is the same as from `@fluentui/react-theme`.

Source: [Fluent UI tokens type definitions](https://github.com/microsoft/fluentui/blob/master/packages/tokens/src/types.ts)

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `@fluentui/react-theme` for tokens | `@fluentui/react-components` re-exports tokens | Fluent UI v9 GA | Use facade package for all imports |
| `platform-library version="9.0"` | `version="9.46.2"` (ceiling) | PCF platform library GA | Manifest must declare version within allowed range |
| npm as package manager | Bun (user decision) | N/A | Faster installs, native TypeScript support, `bun.lockb` replaces `package-lock.json` |
| `.eslintrc.json` (legacy config) | `eslint.config.js` (flat config) | ESLint 9+ | NOT migrating in this phase -- ESLint 8 with `.eslintrc.json` is still functional |

**Deprecated/outdated:**
- `@fluentui/react-theme` as a direct dependency: Use `@fluentui/react-components` facade instead
- `platform-library version="9.0"`: Below minimum allowed version (`9.4.0`). Use `9.46.2`.

## Existing State Assessment

### What's Already Correct (No Changes Needed)
1. `package.json` already has `"@fluentui/react-components": "^9.46.0"` (PCF-06 satisfied)
2. `tsconfig.json` already has `"strict": true` (user requirement already met)
3. `.eslintrc.json` already has `@typescript-eslint/recommended` config
4. `App.tsx`, `CardDetail.tsx`, `CardItem.tsx`, `index.ts` already import from `@fluentui/react-components`
5. `@fluentui/react-theme` is NOT in `package.json` (already absent -- good)

### What Needs Fixing
1. `ControlManifest.Input.xml`: `version="9.0"` must become `version="9.46.2"` (PCF-01)
2. `FilterBar.tsx`: `import { tokens } from "@fluentui/react-theme"` must change to `@fluentui/react-components` (PCF-05)
3. `CardGallery.tsx`: `import { tokens } from "@fluentui/react-theme"` must change to `@fluentui/react-components` (PCF-05)
4. `bun.lockb`: Must be generated via `bun install` and committed
5. `.gitignore`: No changes needed (does not exclude `bun.lockb`)
6. `package-lock.json`: If it exists, should be removed (Bun replaces npm)
7. ESLint `no-console` rule: Must accommodate `console.warn` in `useCardData.ts` for zero-warning build
8. Import consolidation: `CardItem.tsx` and `CardDetail.tsx` have duplicate import lines from `@fluentui/react-components` (functional but should be consolidated per CONTEXT.md)

### Dependency Audit Notes
Current dependencies to verify during implementation:
- `@fluentui/react-components: ^9.46.0` -- correct, keep
- `@fluentui/react-icons: ^2.0.245` -- used in `CardItem.tsx` and `CardDetail.tsx`, keep
- `@types/react: ~16.14.0` -- matches platform-library React version, keep
- `@typescript-eslint/eslint-plugin: ^6.0.0` -- used by ESLint config, keep
- `@typescript-eslint/parser: ^6.0.0` -- used by ESLint config, keep
- `eslint: ^8.50.0` -- used for linting, keep
- `pcf-scripts: ^1` -- PCF build toolchain, keep
- `pcf-start: ^1` -- PCF test harness, keep
- `typescript: ^4.9.5` -- used by pcf-scripts, keep

All dependencies appear to be actively used. No unused packages identified.

## Open Questions

1. **Bun + pcf-scripts compatibility**
   - What we know: pcf-scripts uses webpack internally (standard Node.js APIs). Bun aims for full Node.js compatibility. No documented incompatibilities found.
   - What's unclear: Whether `bun run build` (invoking `pcf-scripts build`) works identically to `npm run build` in all edge cases. No community reports of issues were found, but also no explicit "works with Bun" confirmation.
   - Recommendation: Try `bun install && bun run build` first. If it fails, the fallback is to keep Bun for `install` but use `npx` or Node.js for the build step. Risk is LOW based on Bun's Node.js compatibility track record.

2. **`bun audit` availability and output**
   - What we know: `bun audit` is a documented Bun command that queries the npm advisory database.
   - What's unclear: Whether it supports `--fix` for auto-fixing (early Bun versions did not).
   - Recommendation: Run `bun audit` and report results. Manual fixes if auto-fix is unavailable.

## Sources

### Primary (HIGH confidence)
- [Microsoft Learn - React controls & platform libraries](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/react-controls-platform-libraries) - Supported platform libraries table confirming allowed Fluent version range `>=9.4.0 <=9.46.2`, version loaded at runtime `9.68.0`
- [Fluent UI tokens types.ts](https://github.com/microsoft/fluentui/blob/master/packages/tokens/src/types.ts) - Verified all 6 token names used in codebase exist in Fluent UI v9
- [DeepWiki - FluentUI react-components architecture](https://deepwiki.com/microsoft/fluentui/3.1-react-v9-(@fluentuireact-components)) - Confirmed `@fluentui/react-components` is a facade re-exporting from `@fluentui/react-theme`

### Secondary (MEDIUM confidence)
- [GitHub Issue #1265 - Wrong version of FluentUI](https://github.com/microsoft/powerplatform-build-tools/issues/1265) - Documents PAC CLI version mismatch bug (generates 9.68.0 instead of 9.46.2)
- [Bun audit documentation](https://bun.com/docs/pm/cli/audit) - Confirms `bun audit` queries npm vulnerability database
- [Andrew Butenko - Virtual PCFs with FluentUI 9](https://butenko.pro/2025/02/14/how-to-make-virtual-pcfs-work-with-fluentui-9-components-were-introduced-after-version-9-46-2/) - Confirms 9.46.2 is the actual runtime version loaded by the platform

### Tertiary (LOW confidence)
- Bun + pcf-scripts compatibility: No direct sources found. Assessment based on Bun's general Node.js compatibility claims and pcf-scripts' use of standard webpack APIs.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Official Microsoft docs confirm versions, token names verified in source
- Architecture: HIGH - Codebase already read in full, all files inspected, changes are surgical
- Pitfalls: HIGH - Version mismatch issue well-documented in Microsoft's own issue tracker and community
- Bun compatibility: MEDIUM - No direct sources, but assessed as LOW risk based on Bun's Node.js compat

**Research date:** 2026-02-21
**Valid until:** 2026-04-21 (60 days -- platform-library versions are stable, changes announced in PCF release notes)
