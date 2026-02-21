# Technology Stack

**Project:** Enterprise Work Assistant -- Production Readiness Remediation
**Researched:** 2026-02-20
**Mode:** Ecosystem (Stack dimension)

---

## Recommended Stack

This is a remediation pass on an existing solution. The recommendations below identify where the current stack is correct, where versions need updating, and where package names or API usage is wrong. The goal is correctness, not migration.

### PCF Virtual Control Runtime

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| React | 16.14.0 (declared) / 17.0.2 (loaded at runtime in Model apps) | UI rendering via platform library | PCF virtual controls declare React 16.14.0 in the manifest. The platform loads 16.14.0 for Canvas Apps and 17.0.2 for Model-Driven Apps. You MUST declare 16.14.0 in the manifest regardless of deployment target. The project's current declaration is correct. | HIGH |
| @types/react | ~16.14.0 | TypeScript type definitions | Must match the declared platform library version (16.14.0). The project's `~16.14.0` pinning is correct. Using `@types/react@^18` would cause type errors because React 16 lacks hooks overloads for newer patterns. | HIGH |
| TypeScript | ^5.5.0 | Static type checking | pcf-scripts 1.51.x has fixed TypeScript 5 compatibility issues (manifest type generation for MultiSelectOptionSet). TypeScript 5.x is safe and recommended. The project currently pins `^4.9.5` -- this works but is behind. Update to `^5.5.0` for improved type inference and `satisfies` operator support. | MEDIUM |
| pcf-scripts | ^1.51.1 | Build tooling | Latest as of Feb 2026. Includes Fluent v9 platform library update to 9.68.0 and Node >= 20 requirement. The project pins `^1` which resolves to 1.51.1 -- this is correct. | HIGH |
| pcf-start | ^1.51.1 | Test harness | Companion to pcf-scripts for `npm start` test harness. Same version track. The project pins `^1` -- correct. | HIGH |
| Node.js | >= 20 | Runtime for build tooling | pcf-scripts 1.51.x requires Node >= 20. Node 18 is no longer sufficient. | HIGH |

**Key finding:** The ControlManifest.Input.xml declares `<platform-library name="React" version="16.14.0" />` and `<platform-library name="Fluent" version="9.0" />`. The Fluent version declaration of `9.0` is atypical. The official docs show the allowed range as `>=9.4.0 <=9.46.2` with the platform loading `9.68.0` at runtime. The manifest should declare a specific version within the allowed range, e.g., `9.46.2` (the max allowed declared version). Using `9.0` may work but is not documented as a valid declared version.

### Fluent UI v9

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| @fluentui/react-components | ^9.46.0 | Component library (Badge, Card, Button, Text, etc.) | The project's `^9.46.0` dependency is correct for development type-checking. At runtime, the platform loads 9.68.0 regardless. The declared npm dependency controls only compile-time types and bundle exclusion. | HIGH |
| @fluentui/react-icons | ^2.0.245 | Icon library (MailRegular, ChatRegular, etc.) | Current latest is 2.0.319. The `^2.0.245` range will resolve to latest 2.x automatically. Note: this package does NOT follow strict semver -- breaking changes can appear in patch releases. Consider pinning to a tested version. | MEDIUM |

#### Verified Fluent UI v9 API Details

**Badge `size` prop valid values (confirmed from source):**
```typescript
size?: 'tiny' | 'extra-small' | 'small' | 'medium' | 'large' | 'extra-large'
// Default: 'medium'
```

The project uses `size="small"` and `size="medium"` in CardItem.tsx and CardDetail.tsx. Both are valid values. No issues found here.

**Badge `color` prop valid values:**
```typescript
color?: 'brand' | 'danger' | 'important' | 'informative' | 'severe' | 'subtle' | 'success' | 'warning'
```

The project uses: `"success"`, `"warning"`, `"informative"`, `"subtle"` -- all valid.

**Badge `appearance` prop valid values:**
```typescript
appearance?: 'filled' | 'ghost' | 'outline' | 'tint'
```

The project uses: `"filled"`, `"outline"`, `"tint"` -- all valid.

#### Verified Color Tokens

The following tokens used in the project have been confirmed to exist in `@fluentui/tokens` (the package underlying `@fluentui/react-components`):

| Token | Exists | Source |
|-------|--------|--------|
| `tokens.colorPaletteRedBorder2` | YES | Confirmed in fluentui design-tokens.ts |
| `tokens.colorPaletteMarigoldBorder2` | YES | Confirmed in fluentui design-tokens.ts |
| `tokens.colorPaletteGreenBorder2` | YES | Confirmed in fluentui design-tokens.ts |
| `tokens.colorNeutralStroke1` | YES | Standard neutral token |
| `tokens.colorNeutralForeground3` | YES | Standard neutral token |

**Confidence:** HIGH -- verified against GitHub source for @fluentui/tokens.

#### FluentProvider Usage

The project wraps the component tree with `<FluentProvider theme={prefersDark ? webDarkTheme : webLightTheme}>`. This is correct for PCF virtual controls. The FluentProvider is required for tokens and theme to propagate. Both `webLightTheme` and `webDarkTheme` are exported from `@fluentui/react-components`.

**Important caveat:** In a PCF virtual control, the platform may already provide a FluentProvider higher in the tree. Nesting FluentProviders is supported but can cause theme conflicts. If the control renders with unexpected styling in the actual Power Apps host, consider removing the provider and relying on the platform's provider. For a reference pattern, keeping it explicit is acceptable.

### Copilot Studio Agent

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Copilot Studio | Current (SaaS) | Agent authoring and orchestration | No version to pin -- it is a managed SaaS service. As of Feb 2026: GPT-5 Chat is GA for US/EU regions (since Nov 2025), GPT-4.1 is the default model (since Oct 2025), GPT-4o was retired for generative orchestration in Oct 2025. | HIGH |
| JSON Output Mode | Current | Structured agent responses | Configure in Prompt Builder: select "JSON" in top-right output selector, then define schema via example JSON. Schema is locked at save time. Cannot be modified as raw schema -- only via JSON examples. | HIGH |
| Generative Orchestration | Default (on) | Dynamic tool/topic selection | Active by default for new agents. Agent automatically selects tools, topics, or knowledge to respond. Max 128 tools per agent, recommended limit 25-30 for best performance. | HIGH |

#### Copilot Studio JSON Output Configuration

The JSON output mode is configured **within the Prompt Builder**, not at the agent level:

1. Open the prompt in Prompt Builder
2. Select **JSON** in the top-right corner (replacing "Text" output)
3. Click the settings icon to the left of "Output: JSON" to view/edit format
4. Default mode is "Auto detected" -- schema refreshes on each test
5. Provide a JSON example to set the format; it becomes "Custom" once edited
6. Select **Apply**, then **Test**, then **Save custom**
7. The saved schema is used at runtime -- it does not vary

**Limitations:**
- You cannot modify the JSON schema directly; only via JSON examples
- Array-only formats like `["abc", "def"]` are not supported -- must use objects: `[{"Field1": "abc"}]`
- If the model wraps JSON in markdown code fences, add instruction: "Don't include JSON markdown in your answer"

**Confidence:** HIGH -- verified from official MS Learn docs (updated 2025-11-07).

### Power Automate

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Power Automate Cloud Flows | Current (SaaS) | Workflow orchestration | Manages data pipeline between Copilot Studio agent and Dataverse. No version to pin. | HIGH |
| Agent Flows | Current | Copilot Studio native flows | New flow type that runs within Copilot Studio capacity billing. Created in Copilot Studio directly or converted from Power Automate flows. Consume Copilot Studio capacity per action. | MEDIUM |
| "Run a prompt" action | Current | AI Builder prompt execution | Formerly "Create text with GPT using a prompt" (renamed May 2025). Executes prompts with optional JSON output in cloud flows. | HIGH |
| "Run a flow from Copilot" trigger | Current | Agent-to-flow integration | Trigger type for flows called as tools from Copilot Studio agents. Added as tools via the agent's Tools page. | HIGH |

#### Power Automate Dataverse Choice Column Mapping

When mapping Copilot Studio JSON output fields to Dataverse Choice columns in Power Automate:

- Dataverse Choice columns store an integer `Value` internally, with a human-readable `Label`
- Cloud flow "Create a new row" actions expect the integer `Value`, not the `Label`
- To read the label from a trigger or action output, use the OData formatted value expression:
  ```
  outputs('Get_a_row_by_ID')?['body/fieldname@OData.Community.Display.V1.FormattedValue']
  ```
- To map text to Choice values dynamically, query the **String Maps** Dataverse table filtered by ObjectTypeCode and AttributeName

**Confidence:** HIGH -- well-documented pattern across multiple Microsoft Learn articles and community sources.

### Dataverse

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Dataverse | Current (SaaS) | Data storage for assistant cards | Stores AssistantCard records with columns for trigger_type, priority, card_status, etc. | HIGH |

#### Table Naming Convention

The project uses `cr_assistantcard` (singular) and `cr_assistantcards` (plural) inconsistently across files. Dataverse conventions:

- **Table logical name:** Singular, prefixed with publisher prefix (e.g., `cr_assistantcard`)
- **Entity set name:** Auto-generated plural of logical name (e.g., `cr_assistantcards`)
- **Publisher prefix:** The `cr_` prefix is the default publisher prefix (or a randomly assigned one starting with `cr`). This is acceptable for a reference pattern but production solutions should use a meaningful custom prefix (e.g., `ewa_`)
- **Column logical names:** Lowercase, prefixed (e.g., `cr_triggerttype`, `cr_priority`)

**Resolution:** Use `cr_assistantcard` for the table logical name everywhere. Use `cr_assistantcards` only when referencing the OData entity set (API calls). The PROJECT.md already flags this inconsistency for remediation.

**Confidence:** HIGH -- standard Dataverse conventions confirmed via official docs.

### PAC CLI

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Microsoft Power Platform CLI | 2.2.1 (latest) | PCF build, solution packaging, deployment | Install via `dotnet tool install --global Microsoft.PowerApps.CLI.Tool`. Update via `pac install latest` or `dotnet tool update`. The project docs reference version requirements >= 1.37 per the official React virtual control docs. Current latest is 2.2.1. | HIGH |

**Installation methods:**
```bash
# .NET Tool (cross-platform, recommended)
dotnet tool install --global Microsoft.PowerApps.CLI.Tool

# Update to latest
dotnet tool update --global Microsoft.PowerApps.CLI.Tool

# Or within VS Code: install "Power Platform Tools" extension
```

**Key commands for this project:**
```bash
# Initialize PCF project (already done)
pac pcf init -n AssistantDashboard -ns EnterpriseWorkAssistant -t dataset -fw react

# Build
npm run build

# Test in harness
npm start

# Create solution project
pac solution init --publisher-name EnterpriseWorkAssistant --publisher-prefix cr

# Add PCF reference to solution
pac solution add-reference --path ./src

# Build solution for import
msbuild /t:build /restore

# Or use pac solution pack
pac solution pack --zipfile solution.zip --folder ./solution
```

### Dev Dependencies and Testing

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Jest | ^29.7.0 | Test runner | Industry standard for React component testing. Compatible with TypeScript via ts-jest. | HIGH |
| ts-jest | ^29.2.0 | TypeScript Jest transformer | Enables running .ts/.tsx test files directly. | HIGH |
| @testing-library/react | ^14.3.0 | React component testing | Preferred over Enzyme (deprecated). Note: must use v14.x for React 16 compatibility; v15+ requires React 18. | HIGH |
| @testing-library/jest-dom | ^6.6.0 | DOM assertion matchers | Adds `.toBeInTheDocument()`, `.toHaveTextContent()`, etc. | HIGH |
| jest-environment-jsdom | ^29.7.0 | Browser-like test environment | Required for DOM testing with Jest 29. | HIGH |
| @types/jest | ^29.5.0 | Jest type definitions | TypeScript support for test files. | HIGH |
| eslint | ^8.50.0 | Linting | Already in project. The ^8 pinning is fine; ESLint 9 has breaking config changes not needed here. | MEDIUM |
| @typescript-eslint/eslint-plugin | ^6.0.0 | TypeScript ESLint rules | Already in project. Compatible with TypeScript 5.x despite the ^6 range. | MEDIUM |
| @typescript-eslint/parser | ^6.0.0 | TypeScript ESLint parser | Already in project. | MEDIUM |

**Important testing caveat for PCF:** The `ComponentFramework` namespace types are not available in Jest without mocking. You need to mock the PCF context, dataset, and WebApi interfaces. The pcf-scripts package does not provide test utilities. Create manual mocks or use `jest.fn()` extensively.

### Supporting Libraries (Do NOT Add)

| Library | Why Not |
|---------|---------|
| react-dom | PCF virtual controls do NOT use ReactDOM.render(). The platform manages the React tree. Never import react-dom in a virtual control. |
| @fluentui/react (v8) | Cannot coexist with Fluent v9 in the same manifest. The project correctly uses only v9. |
| axios / node-fetch | PCF controls cannot make arbitrary HTTP calls. All data comes through the PCF dataset API or WebApi. |
| react-router | Single-view control with internal state management. No routing needed. |
| state management libs (Redux, Zustand) | Overkill for a single PCF control. The existing useState/useMemo pattern is correct. |

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| React version | 16.14.0 (platform) | 18.x or 19.x | Cannot override platform-provided React in virtual controls. Some community workarounds exist for standard (non-virtual) controls but defeat the purpose of virtual controls. |
| Component library | @fluentui/react-components (v9) | @fluentui/react (v8) | v8 is supported as a platform library but cannot coexist with v9 in the same manifest. v9 is the current standard (Fluent 2 design system). |
| Build tooling | pcf-scripts | Webpack custom config | pcf-scripts wraps webpack internally. Custom config is possible but fragile and unsupported. Stick with pcf-scripts. |
| Testing | Jest + React Testing Library | Vitest | Vitest is excellent but pcf-scripts uses webpack, not Vite. Adding Vitest creates a parallel build config. Jest is simpler here. |
| TypeScript | 5.5+ | 4.9.5 (current) | 4.9.5 works but lacks `satisfies`, improved inference, and decorator metadata. No reason to stay on 4.9. |
| PAC CLI | dotnet tool (.NET Tool) | Windows MSI | .NET Tool is cross-platform (macOS/Linux/Windows). MSI is Windows-only. For a reference pattern, prefer cross-platform. |

---

## Version Matrix: What the Project Has vs. What It Should Have

| Package | Current | Recommended | Action |
|---------|---------|-------------|--------|
| @fluentui/react-components | ^9.46.0 | ^9.46.0 | KEEP -- correct |
| @fluentui/react-icons | ^2.0.245 | ^2.0.245 | KEEP -- resolves to latest 2.x |
| @types/react | ~16.14.0 | ~16.14.0 | KEEP -- must match platform version |
| typescript | ^4.9.5 | ^5.5.0 | UPDATE -- TS 5 is compatible with pcf-scripts 1.51.x |
| pcf-scripts | ^1 | ^1 | KEEP -- resolves to 1.51.1 |
| pcf-start | ^1 | ^1 | KEEP -- resolves to 1.51.1 |
| eslint | ^8.50.0 | ^8.50.0 | KEEP -- ESLint 9 is breaking change, not needed |
| @typescript-eslint/* | ^6.0.0 | ^6.0.0 | KEEP -- compatible with TS 5 |
| Node.js | (not specified) | >= 20 | VERIFY -- pcf-scripts 1.51.x requires Node >= 20 |
| Platform-library Fluent | 9.0 | 9.46.2 | UPDATE manifest -- 9.0 is not in documented allowed range |

---

## Installation

```bash
# Core (already installed)
npm install @fluentui/react-components @fluentui/react-icons

# Dev dependencies (already installed except testing)
npm install -D typescript@^5.5.0 @types/react@~16.14.0 pcf-scripts@^1 pcf-start@^1 eslint@^8 @typescript-eslint/eslint-plugin@^6 @typescript-eslint/parser@^6

# NEW: Testing dependencies (to add)
npm install -D jest@^29 ts-jest@^29 @testing-library/react@^14 @testing-library/jest-dom@^6 jest-environment-jsdom@^29 @types/jest@^29
```

---

## ControlManifest.Input.xml Correction

The current manifest declares:
```xml
<platform-library name="React" version="16.14.0" />
<platform-library name="Fluent" version="9.0" />
```

Recommended correction:
```xml
<platform-library name="React" version="16.14.0" />
<platform-library name="Fluent" version="9.46.2" />
```

Rationale: The official docs state the allowed Fluent v9 version range is `>=9.4.0 <=9.46.2`, with the platform loading 9.68.0 at runtime. Declaring `9.0` is outside the documented range and may cause issues with future platform updates. Use `9.46.2` (the max allowed declared version) for forward compatibility.

**Confidence:** HIGH -- verified from official Microsoft Learn docs (updated 2025-10-10).

---

## Sources

### Official Documentation (HIGH confidence)
- [React controls & platform libraries - Power Apps | Microsoft Learn](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/react-controls-platform-libraries) -- Updated 2025-10-10. Authoritative source for PCF virtual control React/Fluent versions, platform library table, and manifest format.
- [JSON output - Microsoft Copilot Studio | Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-copilot-studio/process-responses-json-output) -- Updated 2025-11-07. Official guide for JSON output mode in Prompt Builder.
- [Agent flows overview - Microsoft Copilot Studio | Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-copilot-studio/flows-overview) -- Updated 2025-11-21. Agent flows architecture and billing.
- [Add tools to custom agents - Microsoft Copilot Studio | Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-copilot-studio/advanced-plugin-actions) -- Updated 2026-01-29. Tools page, connector/flow/prompt integration.
- [What's new in Copilot Studio - Microsoft Copilot Studio | Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-copilot-studio/whats-new) -- Updated 2026-02-04. Release timeline for GPT-5 GA, GPT-4.1 default, MCP support.
- [Dataverse naming conventions - Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-365/community/cds-and-model-driven-apps-standards-and-naming-conventions) -- Table naming patterns.

### npm Package Registries (HIGH confidence)
- [@fluentui/react-components npm](https://www.npmjs.com/package/@fluentui/react-components) -- Latest 9.73.0
- [@fluentui/react-icons npm](https://www.npmjs.com/package/@fluentui/react-icons) -- Latest 2.0.319
- [pcf-scripts npm](https://www.npmjs.com/package/pcf-scripts) -- Latest 1.51.1
- [Microsoft.PowerApps.CLI NuGet](https://www.nuget.org/packages/Microsoft.PowerApps.CLI) -- Latest 2.2.1

### GitHub Source (HIGH confidence)
- [Badge.types.ts - fluentui repo](https://github.com/microsoft/fluentui/blob/master/packages/react-components/react-badge/library/src/components/Badge/Badge.types.ts) -- Badge size prop type definition.
- [design-tokens.ts - fluentui repo](https://github.com/microsoft/fluentui/blob/master/packages/web-components/src/theme/design-tokens.ts) -- Verified colorPaletteRedBorder2, colorPaletteMarigoldBorder2, colorPaletteGreenBorder2 existence.

### Community / WebSearch (MEDIUM confidence)
- [Power Automate Choice column mapping patterns](https://www.ameyholden.com/articles/dataverse-choice-power-automate-dynamic-no-switch) -- Dynamic choice value resolution.
- [PCF automated testing patterns](https://roger-hill.medium.com/pcf-controls-automated-testing-395caf9b7dfc) -- Jest setup for PCF.
