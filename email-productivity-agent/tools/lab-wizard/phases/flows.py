"""Phase: Deploy all EPA flows via the Flow Management API and register them in the solution."""

import json
import re
import time
from pathlib import Path

import requests
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TaskProgressColumn
from rich.table import Table

from auth import TokenManager

console = Console()

src_dir = Path(__file__).resolve().parent.parent.parent.parent / "src"

FLOW_DEFINITIONS = [
    {"file": "flow-1-sent-items-tracker.json", "name": "EPA - Flow 1: Sent Items Tracker", "phase": 1},
    {"file": "flow-2-response-detection.json", "name": "EPA - Flow 2: Response Detection & Nudge Delivery", "phase": 1},
    {"file": "flow-2b-card-action-handler.json", "name": "EPA - Flow 2b: Card Action Handler", "phase": 1},
    {"file": "flow-3-snooze-detection.json", "name": "EPA - Flow 3: Snooze Detection", "phase": 2},
    {"file": "flow-4-auto-unsnooze.json", "name": "EPA - Flow 4: Auto-Unsnooze", "phase": 2},
    {"file": "flow-5-data-retention.json", "name": "EPA - Flow 5: Data Retention Cleanup", "phase": 1},
    {"file": "flow-6-snooze-cleanup.json", "name": "EPA - Flow 6: Snooze Cleanup", "phase": 2},
    {"file": "flow-7-settings-card.json", "name": "EPA - Flow 7: Settings Card", "phase": 3},
    {"file": "flow-7b-settings-handler.json", "name": "EPA - Flow 7b: Settings Handler", "phase": 3},
]

SOLUTION_UNIQUE_NAME = "EmailProductivityAgent"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _extract_connection_keys(definition: dict) -> set[str]:
    """Walk the flow definition and collect all unique connectionName values."""
    keys: set[str] = set()
    _walk_for_connections(definition, keys)
    return keys


def _walk_for_connections(obj, keys: set[str]):
    """Recursively walk a dict/list and extract host.connectionName values."""
    if isinstance(obj, dict):
        if "host" in obj and "connectionName" in obj["host"]:
            keys.add(obj["host"]["connectionName"])
        for v in obj.values():
            _walk_for_connections(v, keys)
    elif isinstance(obj, list):
        for item in obj:
            _walk_for_connections(item, keys)


def _patch_timezone(definition: dict, timezone: str):
    """Replace timezone values in any recurrence triggers."""
    triggers = definition.get("triggers", {})
    for trigger in triggers.values():
        if trigger.get("type", "").lower() == "recurrence":
            recurrence = trigger.get("recurrence", {})
            if "timeZone" in recurrence:
                recurrence["timeZone"] = timezone


def _build_connection_references(
    connection_keys: set[str], connection_map: dict[str, str]
) -> dict:
    """Build the connectionReferences payload for the Flow Management API."""
    refs: dict = {}
    for key in connection_keys:
        conn_name = connection_map.get(key)
        if conn_name:
            refs[key] = {
                "connectionName": conn_name,
                "id": f"/providers/Microsoft.PowerApps/apis/{key}",
            }
        else:
            # Include the reference without a connectionName so the API
            # knows the connector; it will need manual linking later.
            console.print(
                f"  [yellow]⚠ No connection found for {key} — "
                f"flow may require manual connection fix.[/yellow]"
            )
            refs[key] = {
                "id": f"/providers/Microsoft.PowerApps/apis/{key}",
            }
    return refs


# ---------------------------------------------------------------------------
# Solution management
# ---------------------------------------------------------------------------

def _ensure_solution(auth: TokenManager, config: dict):
    """Ensure the EmailProductivityAgent solution exists in Dataverse."""
    org_url = auth.org_url
    prefix = config.get("publisher_prefix", "cr")

    # Check if solution exists
    resp = requests.get(
        f"{org_url}/api/data/v9.2/solutions"
        f"?$filter=uniquename eq '{SOLUTION_UNIQUE_NAME}'"
        f"&$select=solutionid,uniquename",
        headers=auth.headers("dataverse"),
        timeout=30,
    )
    resp.raise_for_status()
    results = resp.json().get("value", [])

    if results:
        console.print(f"  [green]Solution '{SOLUTION_UNIQUE_NAME}' already exists.[/green]")
        return

    # Resolve publisher ID
    pub_resp = requests.get(
        f"{org_url}/api/data/v9.2/publishers"
        f"?$filter=customizationprefix eq '{prefix}'"
        f"&$select=publisherid",
        headers=auth.headers("dataverse"),
        timeout=30,
    )
    pub_resp.raise_for_status()
    publishers = pub_resp.json().get("value", [])
    if not publishers:
        console.print(
            f"  [red]Publisher with prefix '{prefix}' not found. "
            f"Cannot create solution.[/red]"
        )
        return

    publisher_id = publishers[0]["publisherid"]

    # Create solution
    solution_payload = {
        "uniquename": SOLUTION_UNIQUE_NAME,
        "friendlyname": "Email Productivity Agent",
        "version": "1.0.0.0",
        "publisherid@odata.bind": f"/publishers({publisher_id})",
    }
    create_resp = requests.post(
        f"{org_url}/api/data/v9.2/solutions",
        headers=auth.headers("dataverse"),
        json=solution_payload,
        timeout=30,
    )
    create_resp.raise_for_status()
    console.print(f"  [green]Created solution '{SOLUTION_UNIQUE_NAME}'.[/green]")


# ---------------------------------------------------------------------------
# Connection references
# ---------------------------------------------------------------------------

def _ensure_connection_references(
    auth: TokenManager, config: dict, connection_map: dict[str, str]
):
    """Create Dataverse connection reference rows for each connector used."""
    org_url = auth.org_url
    prefix = config.get("publisher_prefix", "cr")

    unique_keys = set(connection_map.keys())
    for key in unique_keys:
        sanitized = re.sub(r"[^a-z0-9]", "", key.lower())
        logical_name = f"{prefix}_{sanitized}"

        # Check if already exists
        resp = requests.get(
            f"{org_url}/api/data/v9.2/connectionreferences"
            f"?$filter=connectionreferencelogicalname eq '{logical_name}'"
            f"&$select=connectionreferenceid",
            headers=auth.headers("dataverse"),
            timeout=30,
        )
        resp.raise_for_status()
        if resp.json().get("value"):
            continue

        # Create connection reference
        conn_name = connection_map[key]
        payload = {
            "connectionreferencelogicalname": logical_name,
            "connectionreferencedisplayname": key,
            "connectorid": f"/providers/Microsoft.PowerApps/apis/{key}",
            "connectionid": conn_name,
        }
        headers = auth.headers("dataverse")
        headers["MSCRM.SolutionUniqueName"] = SOLUTION_UNIQUE_NAME

        cr_resp = requests.post(
            f"{org_url}/api/data/v9.2/connectionreferences",
            headers=headers,
            json=payload,
            timeout=30,
        )
        if cr_resp.ok:
            console.print(f"  [green]Created connection reference: {logical_name}[/green]")
        else:
            console.print(
                f"  [yellow]⚠ Connection reference {logical_name}: "
                f"{cr_resp.status_code} — {cr_resp.text[:200]}[/yellow]"
            )


# ---------------------------------------------------------------------------
# Existing flow check
# ---------------------------------------------------------------------------

def _get_existing_flows(auth: TokenManager) -> dict[str, dict]:
    """Return a map of flow display name → {workflowid, statecode} for existing EPA flows."""
    org_url = auth.org_url
    resp = requests.get(
        f"{org_url}/api/data/v9.2/workflows"
        f"?$filter=startswith(name,'EPA - Flow')"
        f"&$select=name,workflowid,statecode",
        headers=auth.headers("dataverse"),
        timeout=30,
    )
    resp.raise_for_status()
    return {
        row["name"]: {"workflowid": row["workflowid"], "statecode": row["statecode"]}
        for row in resp.json().get("value", [])
    }


# ---------------------------------------------------------------------------
# Single flow deployment
# ---------------------------------------------------------------------------

def _deploy_single_flow(
    auth: TokenManager,
    config: dict,
    flow_def: dict,
    connection_map: dict[str, str],
) -> bool:
    """Deploy one flow via the Flow Management API. Returns True on success."""
    env_id = config["environment_id"]
    flow_name = flow_def["name"]
    file_path = src_dir / flow_def["file"]

    if not file_path.exists():
        console.print(f"  [red]File not found: {file_path}[/red]")
        return False

    with open(file_path, "r", encoding="utf-8") as f:
        raw = json.load(f)

    definition = raw.get("definition", {})
    # _metadata is informational only — not sent to the API

    # Inject $connections and $authentication parameters (required by Flow API)
    if "parameters" not in definition:
        definition["parameters"] = {}
    if "$connections" not in definition["parameters"]:
        definition["parameters"]["$connections"] = {
            "defaultValue": {},
            "type": "Object",
        }
    if "$authentication" not in definition["parameters"]:
        definition["parameters"]["$authentication"] = {
            "defaultValue": {},
            "type": "SecureObject",
        }

    # Patch timezone
    _patch_timezone(definition, config.get("timezone", "Eastern Standard Time"))

    # Determine connection keys used by this flow
    conn_keys = _extract_connection_keys(definition)

    # Build connection references for the API
    conn_refs = _build_connection_references(conn_keys, connection_map)

    # Create flow via Flow Management API
    payload = {
        "properties": {
            "displayName": flow_name,
            "definition": definition,
            "state": "Started",
            "connectionReferences": conn_refs,
        }
    }

    try:
        resp = requests.post(
            f"https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple"
            f"/environments/{env_id}/flows?api-version=2016-11-01",
            headers=auth.headers("flow"),
            json=payload,
            timeout=60,
        )
        if not resp.ok:
            console.print(
                f"  [red]✗ Failed to create '{flow_name}': "
                f"{resp.status_code} — {resp.text[:300]}[/red]"
            )
            return False
    except requests.RequestException as exc:
        console.print(f"  [red]✗ Request error for '{flow_name}': {exc}[/red]")
        return False

    console.print(f"  [green]✓ Created '{flow_name}'[/green]")

    # Poll Dataverse for the workflow to sync
    workflow_id = _poll_for_workflow(auth, flow_name)
    if workflow_id:
        _add_to_solution(auth, workflow_id)

    return True


def _poll_for_workflow(auth: TokenManager, flow_name: str, timeout: int = 30) -> str | None:
    """Poll Dataverse until the workflow appears. Returns workflowid or None."""
    org_url = auth.org_url
    # Escape single quotes in the flow name for OData
    safe_name = flow_name.replace("'", "''")
    url = (
        f"{org_url}/api/data/v9.2/workflows"
        f"?$filter=name eq '{safe_name}'"
        f"&$select=workflowid,statecode"
    )
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            resp = requests.get(url, headers=auth.headers("dataverse"), timeout=15)
            resp.raise_for_status()
            rows = resp.json().get("value", [])
            if rows:
                return rows[0]["workflowid"]
        except requests.RequestException:
            pass
        time.sleep(3)

    console.print(
        f"  [yellow]⚠ Workflow '{flow_name}' not yet synced to Dataverse "
        f"(timed out after {timeout}s). You may need to add it to the solution manually.[/yellow]"
    )
    return None


def _add_to_solution(auth: TokenManager, workflow_id: str):
    """Add a workflow component to the EmailProductivityAgent solution."""
    org_url = auth.org_url
    payload = {
        "ComponentType": 29,
        "ComponentId": workflow_id,
        "SolutionUniqueName": SOLUTION_UNIQUE_NAME,
        "AddRequiredComponents": False,
    }
    try:
        resp = requests.post(
            f"{org_url}/api/data/v9.2/AddSolutionComponent",
            headers=auth.headers("dataverse"),
            json=payload,
            timeout=30,
        )
        if resp.ok:
            console.print(f"    [dim]Added to solution.[/dim]")
        else:
            console.print(
                f"    [yellow]⚠ AddSolutionComponent: {resp.status_code} — "
                f"{resp.text[:200]}[/yellow]"
            )
    except requests.RequestException as exc:
        console.print(f"    [yellow]⚠ AddSolutionComponent error: {exc}[/yellow]")


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def deploy_flows(auth: TokenManager, config: dict, connection_map: dict[str, str]) -> bool:
    """Deploy all EPA flows. Returns True if all flows succeeded or already existed."""
    console.print("\n[bold cyan]📦 Deploying EPA Flows[/bold cyan]\n")

    # 1. Ensure the solution exists
    console.print("[bold]1. Verifying solution…[/bold]")
    _ensure_solution(auth, config)

    # 2. Create connection references
    console.print("\n[bold]2. Creating connection references…[/bold]")
    _ensure_connection_references(auth, config, connection_map)

    # 3. Check for existing flows
    console.print("\n[bold]3. Checking for existing flows…[/bold]")
    existing = _get_existing_flows(auth)

    # 4. Deploy flows with progress
    console.print("\n[bold]4. Deploying flows…[/bold]\n")

    total = len(FLOW_DEFINITIONS)
    success_count = 0
    skipped_count = 0
    failed_names: list[str] = []

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TaskProgressColumn(),
        console=console,
    ) as progress:
        task = progress.add_task("Deploying flows", total=total)

        for flow_def in FLOW_DEFINITIONS:
            name = flow_def["name"]
            progress.update(task, description=f"[cyan]{name}[/cyan]")

            # Skip if already active
            if name in existing and existing[name].get("statecode") == 1:
                console.print(f"  [dim]⏭ '{name}' already exists and is active — skipping.[/dim]")
                skipped_count += 1
                progress.advance(task)
                continue

            ok = _deploy_single_flow(auth, config, flow_def, connection_map)
            if ok:
                success_count += 1
            else:
                failed_names.append(name)
            progress.advance(task)

    # Summary
    console.print()
    table = Table(title="Flow Deployment Summary", border_style="cyan")
    table.add_column("Metric", style="bold")
    table.add_column("Count", justify="right")
    table.add_row("Created", f"[green]{success_count}[/green]")
    table.add_row("Skipped (existing)", f"[dim]{skipped_count}[/dim]")
    table.add_row("Failed", f"[red]{len(failed_names)}[/red]")
    table.add_row("Total", str(total))
    console.print(table)

    if failed_names:
        console.print("\n[red]Failed flows:[/red]")
        for name in failed_names:
            console.print(f"  [red]• {name}[/red]")

    all_ok = len(failed_names) == 0
    if all_ok:
        console.print("\n[green bold]✅ All flows deployed successfully![/green bold]")
    else:
        console.print(
            "\n[yellow]⚠ Some flows failed. Review errors above and retry or deploy manually.[/yellow]"
        )

    return all_ok
