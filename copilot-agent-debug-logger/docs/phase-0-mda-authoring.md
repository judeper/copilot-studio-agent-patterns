# Phase-0 Manual Authoring — Agent Debug Console (Model-Driven App)
This runbook documents the Phase-0 manual step for issue #14: creating the **Agent Debug Console** model-driven app (MDA) for the Copilot Agent Debug Logger.
It deliberately does **not** include fabricated MDA XML.
Per **D7**, the supported pattern is: build the app once in the Maker portal, run `pac solution clone` and `pac solution unpack`, then commit the real unpacked XML under `src/Solutions/`.

## Why this is manual
Microsoft model-driven apps cannot be authored code-first from scratch in a supported, reliable way.
The canonical pattern is:
1. Author the MDA in the Power Apps Maker portal.
2. Publish the app and all customizations.
3. Clone/export the unmanaged solution with PAC CLI.
4. Unpack the solution into source control.
5. Treat the unpacked XML as the source of truth.
This is the only Copilot Agent Debug Logger POC step that requires the Power Apps maker UI.
Everything else in this POC is scriptable or represented as source-controlled reference artifacts.
Do **not** hand-write `AppModule`, site map, form, or view XML.
Do **not** update `src/Solutions/other/Solution.xml` or `src/Solutions/other/Customizations.xml` manually.
Those files should change only when the real Maker-authored solution is unpacked.

## What you are building
Create one model-driven app named **Agent Debug Console**.
The app is a read-only maker debug surface for rows in the `cr_agenttrace` Dataverse table.
It includes:
- one site map area named **Traces**;
- one group named **Inspection**;
- one subarea for **Agent Trace**;
- one plain multiline form field for `cr_payload`;
- three views: **Recent Traces**, **Timeline by Correlation ID**, and **Errors Only**;
- Quick Find configured on `cr_correlationid` and `cr_tracelabel`.
No PCF control, custom JavaScript, real payload log, tenant ID, UPN, customer domain, or runtime dump belongs in Phase-0.
Use placeholders only if you need manual smoke-test data.

## Prerequisites
Complete this checklist before opening the Maker portal.
- [ ] A Power Platform environment exists for this POC.
- [ ] You know the environment ID, for example `<environment-id>`.
- [ ] You are a **System Customizer** or **System Administrator** in that environment.
- [ ] PAC CLI 1.32+ is installed; verify with `pac --version`.
- [ ] PAC CLI is authenticated to the target tenant and environment.
- [ ] The unmanaged solution unique name is `CopilotAgentDebugLogger` per **D8**.
- [ ] The provisioning script has run so the `cr_agenttrace` table exists.
If provisioning has not run yet:
```powershell
cd C:\Dev\copilot-studio-agent-patterns\copilot-agent-debug-logger
pwsh scripts\provision-environment.ps1 -EnvironmentId "<environment-id>"
pac auth select --environment "<environment-id>"
```

## Step-by-step Maker portal instructions
Follow these steps exactly for Phase-0.

### Step 1 — Open the solution
1. Navigate to `https://make.powerapps.com`.
2. Top bar → environment selector → choose the target environment.
3. Left nav → **Solutions**.
4. Open **Copilot Agent Debug Logger**.
5. If the display name differs, open the solution whose unique name is `CopilotAgentDebugLogger`.
Expected result: you are inside the unmanaged Debug Logger solution.

### Step 2 — Add the `cr_agenttrace` table to the solution
1. Solution command bar → **+ Add existing** → **Table**.
2. Search `Agent Trace`.
3. Select **Agent Trace** and confirm logical name `cr_agenttrace`.
4. Select **Next**.
5. Tick **Include all objects**.
6. Select **Add**.
Expected result: **Agent Trace** appears in the solution component list.
This makes the app, form, views, and Quick Find solution-aware before unpack.

### Step 3 — Create the model-driven app
1. In the solution → **+ New** → **App** → **Model-driven app**.
2. **Name:** `Agent Debug Console`.
3. **Description:**
   > Maker debug surface for the Copilot Agent Debug Logger. Reads cr_agenttrace rows. Read-only inspection of the trace payloads written by flow-1-log-agent-trace and tool-log-agent-trace.
4. Select **Create**.
5. Confirm the model-driven app designer opens for **Agent Debug Console**.
6. Confirm the generated unique name will unpack with an `AgentDebugConsole` prefix.
Expected result: after `pac solution clone`, the deploy precheck can find `src/Solutions/src/AppModules/cr_AgentDebugConsole/` (Microsoft's canonical layout produced by `pac solution unpack`). The legacy `CanvasApps/AgentDebugConsole_*` path is no longer used — see PR #42.

### Step 4 — Add the Trace site map
1. App designer → left rail → **Site map**.
2. Select **+ New area** and name it `Traces`.
3. Under **Traces**, select **+ New group** and name it `Inspection`.
4. Under **Inspection**, select **+ Add a subarea**.
5. **Type:** **Table**.
6. **Table:** **Agent Trace**.
7. **Default view:** **Recent Traces** after Step 6 creates it.
8. If the designer requires a current view first, leave the default and return here after Step 6.
Expected result: app navigation shows **Traces** → **Inspection** → **Agent Trace**.

### Step 5 — Build the form
1. App designer → **Forms** → **Agent Trace** → **Information** form.
2. Use a 1-column layout.
3. Add every custom `cr_*` column from `cr_agenttrace`.
4. Add the system columns `createdon` and `OwnerId`.
5. Set every field on this inspection form to read-only.
6. Do not add a PCF control or custom JavaScript.
Use this field order:
1. `cr_tracelabel` — top field.
2. `cr_correlationid`.
3. `cr_agentname`.
4. `cr_source`.
5. `cr_sourcename` — _(documented but not stored; see README **Known Issues**. Skip this field from the form or display it read-only; the platform reflects the Choice formatted value here instead of the intended Text(200) source name. The trace label encodes source/step.)_
6. `cr_stepname`.
7. `cr_direction`.
8. `cr_sequence`.
9. `cr_status`.
10. `cr_errormessage`.
11. `cr_payload`.
12. `cr_durationms`.
13. `createdon`.
14. `OwnerId`.
15. `cr_traceid` — read-only technical identifier at the bottom so all 13 `cr_*` fields remain visible.
Configure `cr_payload` as the plain multiline inspection field:
1. Select `cr_payload`.
2. Form control properties → **Number of rows:** `20`.
3. Form control properties → **Wrap text:** **On**.
4. Keep the standard multiline text control.
Expected result: makers can inspect JSON payloads without a custom component.

### Step 6 — Build the 3 views
In the solution → **Tables** → **Agent Trace** → **Views**, create or update these views.

#### View 1: Recent Traces
- Make this the default table view.
- Columns: `cr_tracelabel`, `cr_correlationid`, `cr_source`, `cr_direction`, `cr_status`, `createdon`.
- Sort: `createdon` descending.
- Filter: `createdon` is on or after **Last 7 days**.

#### View 2: Timeline by Correlation ID
- Columns: `cr_correlationid`, `cr_sequence`, `cr_source`, `cr_stepname`, `cr_direction`, `cr_status`, `createdon`.
- Sort: `cr_correlationid` ascending, `cr_sequence` ascending, `createdon` ascending.
- Filter: no additional filter.

#### View 3: Errors Only
- Columns: `cr_tracelabel`, `cr_correlationid`, `cr_status`, `cr_errormessage`, `createdon`.
- Filter: `cr_status` equals `ERROR`.
- Sort: `createdon` descending.
After the views exist, return to the app designer site map and set **Recent Traces** as the **Agent Trace** subarea default view.
Expected result: the app has the three required Phase-0 inspection views.

### Step 7 — Configure Quick Find

1. Solution → **Tables** → **Agent Trace** → **Views**.
2. Open **Agent Trace Quick Find View**.
3. Edit the find/search columns.
4. Add `cr_correlationid` as the primary find column.
5. Add `cr_tracelabel` as the secondary find column.
6. Set displayed columns to match **Recent Traces**: `cr_tracelabel`, `cr_correlationid`, `cr_source`, `cr_direction`, `cr_status`, `createdon`.
7. Save the Quick Find view.

Expected result: searching by a Copilot conversation correlation ID returns matching trace rows.

### Step 8 — Save + Publish

1. App designer → **Save**.
2. App designer → **Publish**.
3. Return to the **Copilot Agent Debug Logger** solution.
4. Solution command bar → **Publish all customizations**.
5. Reopen the app once.
6. Confirm **Agent Trace** appears in navigation.
7. Confirm all three views are selectable.
8. Confirm the form opens and `cr_payload` wraps across multiple lines.

Expected result: the environment contains a published **Agent Debug Console** model-driven app.

Do not skip **Publish all customizations**; otherwise the PAC unpack may miss MDA updates.

### Step 9 — Export and unpack into source

Run these commands after Step 8 is complete.

```powershell
cd C:\Dev\copilot-studio-agent-patterns\copilot-agent-debug-logger\src\Solutions
pac auth select --environment "<environment-id>"

# Clone the solution from the environment. This downloads the solution zip for unpacking.
pac solution clone --name CopilotAgentDebugLogger --environment "<environment-id>"

# Unpack into the existing src/Solutions tree as unmanaged source.
pac solution unpack --zipfile CopilotAgentDebugLogger.zip --folder . --packagetype Unmanaged --allowDelete true

# Verify the MDA appeared. MDAs unpack under CanvasApps; the folder name is a Microsoft solution-packager oddity.
Get-ChildItem CanvasApps\
Get-ChildItem -Recurse -Filter "AgentDebugConsole_*"

# Commit the real unpacked XML.
cd C:\Dev\copilot-studio-agent-patterns
git add copilot-agent-debug-logger\src\Solutions\
git commit -m "feat(debug-logger): commit Agent Debug Console MDA XML (Phase-0 manual authoring)"
```

Expected result: `src/Solutions/CanvasApps/` contains generated MDA artifacts for **Agent Debug Console**.

The existing `.gitkeep` is only a placeholder; it may remain beside the real artifacts or be removed in the Phase-0 commit.

## Verification checklist after unpack

- [ ] `copilot-agent-debug-logger/src/Solutions/CanvasApps/` is non-empty.
- [ ] At least one unpacked artifact matches `AgentDebugConsole_*`.
- [ ] `.gitkeep` is no longer the only file under `CanvasApps/`.
- [ ] `src/Solutions/other/Solution.xml` has updated `<RootComponents />` entries for the MDA and table objects.
- [ ] `src/Solutions/other/Customizations.xml` contains real Maker-authored app, site map, form, and view content.
- [ ] **Recent Traces** includes `cr_correlationid` and sorts by `createdon` descending.
- [ ] **Timeline by Correlation ID** sorts by `cr_correlationid`, `cr_sequence`, then `createdon`.
- [ ] **Errors Only** filters `cr_status = ERROR`.
- [ ] Quick Find includes `cr_correlationid` and `cr_tracelabel` as find columns.
- [ ] The form uses a plain multiline `cr_payload` field with 20 rows and wrap enabled.
- [ ] No real tenant IDs, UPNs, customer domains, payload logs, or runtime dumps were committed.

## Troubleshooting

### `pac solution clone` says the solution was not found

Run `pac auth select --environment "<environment-id>"` and `pac solution list`.

Confirm the solution unique name is `CopilotAgentDebugLogger`.

### The MDA does not appear after unpack

Return to Maker portal and confirm **Agent Debug Console** is listed in the solution.

Open the app designer, select **Publish**, then solution command bar → **Publish all customizations**.

Rerun `pac solution clone` and `pac solution unpack`.

### `CanvasApps` is empty or only contains `.gitkeep`

Phase-0 is not complete.

The folder exists in git only to hold the future MDA location.

MDAs unpack under `CanvasApps/` even though this is a model-driven app; that folder name is a Microsoft solution-packager convention.

### The deploy precheck cannot find `AgentDebugConsole_*`

Confirm the app was named **Agent Debug Console** before publishing.

Confirm the generated unique name did not use an unexpected prefix.

Do not rename solution-packager output by hand; align the app unique name or intentionally update the downstream precheck.

### Quick Find does not find a correlation ID

Reopen **Agent Trace Quick Find View** and ensure `cr_correlationid` is in the find columns, not only displayed columns.

Publish all customizations again.

### The payload field is hard to read

Confirm `cr_payload` uses the standard multiline text control, **Number of rows** is `20`, and **Wrap text** is **On**.

Do not add a PCF control for Phase-0.

## Why this is Phase-0 and not Phase-1

This step cannot run during the autonomous build.

The autonomous agent has no browser automation tooling for the Maker portal.

Microsoft does not document a complete, supported, code-first MDA authoring API.

Per **D7**, the accepted path is Maker portal authoring followed by PAC solution unpack.

Phase-0 captures the one manual action, then turns the result into normal source-controlled solution XML.

Phase-1 and later work should consume the unpacked artifacts, not recreate them.

## When Phase-0 is skipped

`pwsh scripts\deploy-solution.ps1 -EnvironmentId "<environment-id>"` is expected to fail loudly once the deploy precheck is wired.

The friendly failure should point back to this file.

The intended precheck pattern is:

```powershell
$mdaPattern = Join-Path $resolvedSolutionPath "src\AppModules\cr_AgentDebugConsole"
if (-not (Test-Path -Path $mdaPattern -PathType Container)) {
    throw "Phase-0 MDA authoring not done. See docs/phase-0-mda-authoring.md before running deploy."
}
```

(`Test-Path -PathType Container` is critical: `Get-ChildItem -Directory` on this path returns CHILD directories of the MDA folder — which has only XML files inside — and incorrectly evaluates as "empty". See PR #42 for the verified deploy-solution.ps1 implementation.)

This prevents a false-success deployment that lacks the **Agent Debug Console**.

## Handoff notes

This runbook satisfies the autonomous portion of issue #14.

Jude still needs to execute the Maker portal steps and commit the unpacked XML afterward.

Basher's deploy-script work should add the fail-loud precheck shown above.

Until the manual unpack commit lands, the `CanvasApps/` placeholder from R1 may be the only file under `src/Solutions/` (it was kept by Frank's R2 scaffold but is now superseded by PR #42's restructure into the Microsoft-canonical `src/Solutions/src/...` layout).

Do not treat `.gitkeep` as evidence that the MDA exists.
