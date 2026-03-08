"""Phase 1 — Provision Power Platform environment and Dataverse tables."""

from __future__ import annotations

import json
import subprocess
import time
from typing import Any

import requests
from rich.console import Console
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn

from phases import resolve_cli

console = Console()

# ── Dataverse label helper ──────────────────────────────────────────────

def _label(text: str) -> dict:
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.Label",
        "LocalizedLabels": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel",
                "Label": text,
                "LanguageCode": 1033,
            }
        ],
    }


# ── Table / column / key definitions ───────────────────────────────────

def _table_definitions(prefix: str) -> list[dict]:
    """Return the three EPA Dataverse table definitions."""
    p = prefix  # shorthand for column schema names
    P = prefix.capitalize()  # for SchemaName casing

    return [
        {
            "schema": f"{P}_followuptracking",
            "logical": f"{prefix}_followuptracking",
            "display": "Follow Up Tracking",
            "display_plural": "Follow Up Trackings",
            "description": "Tracks sent emails awaiting follow-up",
            "primary_name": {
                "schema": f"{P}_originalsubject",
                "logical": f"{prefix}_originalsubject",
                "label": "Original Subject",
                "max_length": 400,
                "required": True,
            },
            "columns": [
                _string_col(P, "sourcesignalid", "Source Signal ID", 200),
                _memo_col(P, "conversationid", "Conversation ID"),
                _memo_col(P, "internetmessageheaders", "Internet Message Headers", 2000),
                _datetime_col(P, "sentdatetime", "Sent Date Time"),
                _string_col(P, "recipientemail", "Recipient Email", 250),
                _string_col(P, "recipienttype", "Recipient Type", 20),
                _datetime_col(P, "followupdate", "Follow Up Date"),
                _boolean_col(P, "responsereceived", "Response Received", False),
                _boolean_col(P, "nudgesent", "Nudge Sent", False),
                _boolean_col(P, "dismissedbyuser", "Dismissed By User", False),
                _datetime_col(P, "lastchecked", "Last Checked"),
            ],
            "keys": [
                {
                    "SchemaName": f"{prefix}_followup_source_recipient_key",
                    "KeyAttributes": [f"{prefix}_sourcesignalid", f"{prefix}_recipientemail"],
                    "DisplayName": _label("Follow-Up Source+Recipient Key"),
                },
            ],
        },
        {
            "schema": f"{P}_nudgeconfiguration",
            "logical": f"{prefix}_nudgeconfiguration",
            "display": "Nudge Configuration",
            "display_plural": "Nudge Configurations",
            "description": "Per-user nudge timing and preferences",
            "primary_name": {
                "schema": f"{P}_configlabel",
                "logical": f"{prefix}_configlabel",
                "label": "Config Label",
                "max_length": 100,
                "required": True,
            },
            "columns": [
                _string_col(P, "owneruserid", "Owner User ID", 36),
                _integer_col(P, "internaldays", "Internal Follow-Up Days", 3),
                _integer_col(P, "externaldays", "External Follow-Up Days", 5),
                _integer_col(P, "prioritydays", "Priority Follow-Up Days", 1),
                _integer_col(P, "generaldays", "General Follow-Up Days", 7),
                _boolean_col(P, "nudgesenabled", "Nudges Enabled", True),
                _string_col(P, "snoozefolderid", "Snooze Folder ID", 200),
            ],
            "keys": [
                {
                    "SchemaName": f"{prefix}_nudgeconfig_owner_key",
                    "KeyAttributes": [f"{prefix}_owneruserid"],
                    "DisplayName": _label("Nudge Config Owner Key"),
                },
            ],
        },
        {
            "schema": f"{P}_snoozedconversation",
            "logical": f"{prefix}_snoozedconversation",
            "display": "Snoozed Conversation",
            "display_plural": "Snoozed Conversations",
            "description": "Conversations snoozed by the user",
            "primary_name": {
                "schema": f"{P}_originalsubject",
                "logical": f"{prefix}_originalsubject",
                "label": "Original Subject",
                "max_length": 400,
                "required": False,
            },
            "columns": [
                _memo_col(P, "conversationid", "Conversation ID"),
                _string_col(P, "owneruserid", "Owner User ID", 36),
                _string_col(P, "originalmessageid", "Original Message ID", 500),
                _datetime_col(P, "snoozeuntil", "Snooze Until"),
                _string_col(P, "currentfolder", "Current Folder", 200),
                _boolean_col(P, "unsnoozedbyagent", "Unsnoozed By Agent", False),
                _datetime_col(P, "unsnoozeddatetime", "Unsnoozed Date Time"),
            ],
            "keys": [
                {
                    "SchemaName": f"{prefix}_snooze_conv_owner_key",
                    "KeyAttributes": [f"{prefix}_conversationid", f"{prefix}_owneruserid"],
                    "DisplayName": _label("Snooze Conv+Owner Key"),
                },
            ],
        },
    ]


# ── Column builders ────────────────────────────────────────────────────

def _string_col(prefix: str, name: str, label: str, max_len: int) -> dict:
    return {
        "@odata.type": "#Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": f"{prefix}_{name}",
        "DisplayName": _label(label),
        "RequiredLevel": {"Value": "None"},
        "MaxLength": max_len,
        "FormatName": {"Value": "Text"},
    }


def _memo_col(prefix: str, name: str, label: str, max_len: int = 10000) -> dict:
    return {
        "@odata.type": "#Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": f"{prefix}_{name}",
        "DisplayName": _label(label),
        "RequiredLevel": {"Value": "None"},
        "MaxLength": max_len,
    }


def _boolean_col(prefix: str, name: str, label: str, default: bool) -> dict:
    return {
        "@odata.type": "#Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": f"{prefix}_{name}",
        "DisplayName": _label(label),
        "RequiredLevel": {"Value": "None"},
        "DefaultValue": default,
        "OptionSet": {
            "TrueOption": {"Value": 1, "Label": _label("Yes")},
            "FalseOption": {"Value": 0, "Label": _label("No")},
        },
    }


def _datetime_col(prefix: str, name: str, label: str) -> dict:
    return {
        "@odata.type": "#Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": f"{prefix}_{name}",
        "DisplayName": _label(label),
        "RequiredLevel": {"Value": "None"},
        "Format": "DateAndTime",
    }


def _integer_col(prefix: str, name: str, label: str, default: int) -> dict:
    # Note: Dataverse Web API does not support setting default values for
    # IntegerAttributeMetadata. Defaults must be set post-creation via the
    # Maker Portal or solution XML import.
    return {
        "@odata.type": "#Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
        "SchemaName": f"{prefix}_{name}",
        "DisplayName": _label(label),
        "RequiredLevel": {"Value": "None", "CanBeChanged": True},
        "Format": "None",
        "MinValue": 1,
        "MaxValue": 365,
    }


# ── REST helpers ───────────────────────────────────────────────────────

def _dv_get(auth: Any, org_url: str, path: str) -> requests.Response:
    return requests.get(f"{org_url}/api/data/v9.2/{path}", headers=auth.headers("dataverse"))


def _dv_post(auth: Any, org_url: str, path: str, body: dict, extra_headers: dict | None = None) -> requests.Response:
    headers = auth.headers("dataverse")
    if extra_headers:
        headers.update(extra_headers)
    return requests.post(f"{org_url}/api/data/v9.2/{path}", headers=headers, json=body)


# ── Step 1: Environment via PAC CLI ────────────────────────────────────

def _create_environment(config: dict) -> tuple[str, str]:
    """Create or find the Power Platform environment. Returns (env_id, org_url)."""
    env_name = config["environment_name"]
    console.print(f"\n[bold]Step 1/5[/bold] — Creating environment [cyan]{env_name}[/cyan]")

    domain = env_name.lower().replace(" ", "-").replace("_", "-")
    result = resolve_cli(
        [
            "pac", "admin", "create",
            "--name", env_name,
            "--type", "Sandbox",
            "--region", "unitedstates",
            "--domain", domain,
            "--json",
        ],
        capture_output=True, text=True, timeout=300,
    )

    if result.returncode == 0:
        try:
            data = json.loads(result.stdout)
            # pac admin create --json may return an array or a single object
            if isinstance(data, list):
                data = data[0] if data else {}
            env_id = data.get("EnvironmentId") or data.get("environmentId", "")
            org_url = data.get("EnvironmentUrl") or data.get("OrgUrl") or data.get("orgUrl", "")
            if env_id and org_url:
                console.print(f"  [green]✅ Environment created: {env_id}[/green]")
                return env_id, org_url.rstrip("/")
        except json.JSONDecodeError:
            pass

    # Environment may already exist
    if "already exists" in (result.stderr or "") or "already exists" in (result.stdout or ""):
        console.print("  [yellow]Environment already exists — looking it up…[/yellow]")
        return _find_existing_environment(env_name)

    # Also try lookup if create failed for any other reason
    console.print(f"  [yellow]Create returned rc={result.returncode}, attempting lookup…[/yellow]")
    try:
        return _find_existing_environment(env_name)
    except RuntimeError:
        console.print(f"  [red]PAC CLI error:[/red] {result.stderr or result.stdout}")
        raise RuntimeError("Failed to create or find environment")


def _find_existing_environment(name: str) -> tuple[str, str]:
    """List all environments and find one matching the given name."""
    result = resolve_cli(
        ["pac", "admin", "list", "--json"],
        capture_output=True, text=True, timeout=120,
    )
    if result.returncode != 0:
        raise RuntimeError(f"pac admin list failed: {result.stderr}")

    envs: list[dict] = json.loads(result.stdout)
    name_lower = name.lower()
    for env in envs:
        display = (env.get("DisplayName") or env.get("displayName") or "").lower()
        if display == name_lower:
            env_id = env.get("EnvironmentId") or env.get("environmentId", "")
            org_url = env.get("EnvironmentUrl") or env.get("OrgUrl") or env.get("orgUrl", "")
            if not org_url:
                # Some PAC versions use different casing / nested keys
                org_url = (env.get("LinkedEnvironmentMetadata", {}) or {}).get("InstanceUrl", "")
            if env_id:
                console.print(f"  [green]✅ Found existing environment: {env_id}[/green]")
                return env_id, org_url.rstrip("/")

    raise RuntimeError(f"Environment '{name}' not found in pac admin list")


# ── Step 2: Publisher ──────────────────────────────────────────────────

def _ensure_publisher(auth: Any, org_url: str, prefix: str) -> str:
    """Create or find the publisher. Returns publisher ID."""
    console.print(f"\n[bold]Step 2/5[/bold] — Ensuring publisher (prefix=[cyan]{prefix}[/cyan])")

    resp = _dv_get(auth, org_url, f"publishers?$filter=customizationprefix eq '{prefix}'")
    resp.raise_for_status()
    data = resp.json()
    if data.get("value"):
        pub_id = data["value"][0]["publisherid"]
        console.print(f"  [green]✅ Publisher exists: {pub_id}[/green]")
        return pub_id

    body = {
        "uniquename": f"{prefix}_publisher",
        "friendlyname": "EPA Publisher",
        "customizationprefix": prefix,
        "customizationoptionvalueprefix": 10000,
    }
    resp = _dv_post(auth, org_url, "publishers", body)
    if resp.status_code in (204, 201):
        # Extract ID from OData-EntityId header
        entity_id = resp.headers.get("OData-EntityId", "")
        pub_id = entity_id.split("(")[-1].rstrip(")") if "(" in entity_id else ""
        console.print(f"  [green]✅ Publisher created: {pub_id}[/green]")
        return pub_id
    elif resp.status_code == 409:
        console.print("  [yellow]Publisher already exists (409) — refetching…[/yellow]")
        resp2 = _dv_get(auth, org_url, f"publishers?$filter=customizationprefix eq '{prefix}'")
        resp2.raise_for_status()
        return resp2.json()["value"][0]["publisherid"]
    else:
        resp.raise_for_status()
        return ""


# ── Step 3: Solution ───────────────────────────────────────────────────

def _ensure_solution(auth: Any, org_url: str, publisher_id: str) -> str:
    """Create or find the solution. Returns solution ID."""
    console.print("\n[bold]Step 3/5[/bold] — Ensuring solution [cyan]EmailProductivityAgent[/cyan]")

    resp = _dv_get(auth, org_url, "solutions?$filter=uniquename eq 'EmailProductivityAgent'")
    resp.raise_for_status()
    data = resp.json()
    if data.get("value"):
        sol_id = data["value"][0]["solutionid"]
        console.print(f"  [green]✅ Solution exists: {sol_id}[/green]")
        return sol_id

    body = {
        "uniquename": "EmailProductivityAgent",
        "friendlyname": "Email Productivity Agent",
        "version": "1.0.0.0",
        "publisherid@odata.bind": f"/publishers({publisher_id})",
    }
    resp = _dv_post(auth, org_url, "solutions", body)
    if resp.status_code in (204, 201):
        entity_id = resp.headers.get("OData-EntityId", "")
        sol_id = entity_id.split("(")[-1].rstrip(")") if "(" in entity_id else ""
        console.print(f"  [green]✅ Solution created: {sol_id}[/green]")
        return sol_id
    elif resp.status_code == 409:
        console.print("  [yellow]Solution already exists (409) — refetching…[/yellow]")
        resp2 = _dv_get(auth, org_url, "solutions?$filter=uniquename eq 'EmailProductivityAgent'")
        resp2.raise_for_status()
        return resp2.json()["value"][0]["solutionid"]
    else:
        resp.raise_for_status()
        return ""


# ── Step 4: Dataverse tables, columns, keys ────────────────────────────

def _table_exists(auth: Any, org_url: str, logical_name: str) -> bool:
    resp = _dv_get(auth, org_url, f"EntityDefinitions(LogicalName='{logical_name}')?$select=LogicalName")
    return resp.status_code == 200


def _column_exists(auth: Any, org_url: str, table: str, col_logical: str) -> bool:
    resp = _dv_get(
        auth, org_url,
        f"EntityDefinitions(LogicalName='{table}')/Attributes?"
        f"$filter=LogicalName eq '{col_logical}'&$select=LogicalName",
    )
    if resp.status_code != 200:
        return False
    data = resp.json()
    return bool(data.get("value"))


def _key_exists(auth: Any, org_url: str, table: str, key_schema: str) -> bool:
    resp = _dv_get(
        auth, org_url,
        f"EntityDefinitions(LogicalName='{table}')?$expand=Keys($select=SchemaName)",
    )
    if resp.status_code != 200:
        return False
    keys = resp.json().get("Keys", [])
    return any(k.get("SchemaName", "").lower() == key_schema.lower() for k in keys)


def _wait_for_key_activation(auth: Any, org_url: str, table: str, key_schema: str, timeout: int = 60):
    """Poll until an alternate key is Active (or timeout)."""
    start = time.time()
    while time.time() - start < timeout:
        resp = _dv_get(
            auth, org_url,
            f"EntityDefinitions(LogicalName='{table}')?$expand=Keys($select=SchemaName,EntityKeyIndexStatus)",
        )
        if resp.status_code == 200:
            for k in resp.json().get("Keys", []):
                if k.get("SchemaName", "").lower() == key_schema.lower():
                    status = k.get("EntityKeyIndexStatus")
                    if status == "Active":
                        return
        time.sleep(5)
    console.print(f"  [yellow]⚠ Key {key_schema} activation timed out ({timeout}s)[/yellow]")


def _create_tables(auth: Any, org_url: str, prefix: str):
    """Create the three EPA Dataverse tables with columns and alternate keys."""
    console.print("\n[bold]Step 4/5[/bold] — Creating Dataverse tables")

    solution_header = {"MSCRM.SolutionUniqueName": "EmailProductivityAgent"}
    table_defs = _table_definitions(prefix)

    for tdef in table_defs:
        logical = tdef["logical"]
        console.print(f"\n  [cyan]Table:[/cyan] {logical}")

        # Create table if needed
        if _table_exists(auth, org_url, logical):
            console.print(f"    [dim]Table already exists — skipping creation[/dim]")
        else:
            pn = tdef["primary_name"]
            primary_attr = {
                "@odata.type": "#Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "IsPrimaryName": True,
                "SchemaName": pn["schema"],
                "DisplayName": _label(pn["label"]),
                "RequiredLevel": {
                    "Value": "ApplicationRequired" if pn["required"] else "None",
                    "CanBeChanged": True,
                },
                "MaxLength": pn["max_length"],
                "FormatName": {"Value": "Text"},
            }
            body = {
                "SchemaName": tdef["schema"],
                "DisplayName": _label(tdef["display"]),
                "DisplayCollectionName": _label(tdef["display_plural"]),
                "Description": _label(tdef["description"]),
                "OwnershipType": "UserOwned",
                "HasActivities": False,
                "IsActivity": False,
                "HasNotes": False,
                "PrimaryNameAttribute": pn["logical"],
                "Attributes": [primary_attr],
            }
            resp = _dv_post(auth, org_url, "EntityDefinitions", body, solution_header)
            if resp.status_code in (201, 204):
                console.print(f"    [green]✅ Table created[/green]")
            elif resp.status_code == 409:
                console.print(f"    [dim]Table already exists (409)[/dim]")
            else:
                console.print(f"    [red]❌ Failed ({resp.status_code}): {resp.text[:200]}[/red]")
                continue

        # Create columns
        for col in tdef["columns"]:
            col_logical = col["SchemaName"].lower()
            if _column_exists(auth, org_url, logical, col_logical):
                console.print(f"    [dim]Column {col_logical} exists[/dim]")
                continue

            resp = _dv_post(
                auth, org_url,
                f"EntityDefinitions(LogicalName='{logical}')/Attributes",
                col, solution_header,
            )
            if resp.status_code in (201, 204):
                console.print(f"    [green]+ {col_logical}[/green]")
            elif resp.status_code == 409:
                console.print(f"    [dim]Column {col_logical} exists (409)[/dim]")
            else:
                console.print(f"    [red]❌ Column {col_logical} failed ({resp.status_code}): {resp.text[:150]}[/red]")

        # Create alternate keys
        for key_def in tdef["keys"]:
            key_schema = key_def["SchemaName"]
            if _key_exists(auth, org_url, logical, key_schema):
                console.print(f"    [dim]Key {key_schema} exists[/dim]")
                continue

            resp = _dv_post(
                auth, org_url,
                f"EntityDefinitions(LogicalName='{logical}')/Keys",
                key_def, solution_header,
            )
            if resp.status_code in (201, 204):
                console.print(f"    [green]🔑 Key {key_schema} created — waiting for activation…[/green]")
                _wait_for_key_activation(auth, org_url, logical, key_schema)
                console.print(f"    [green]✅ Key activated[/green]")
            elif resp.status_code == 409:
                console.print(f"    [dim]Key {key_schema} exists (409)[/dim]")
            else:
                console.print(f"    [red]❌ Key {key_schema} failed ({resp.status_code}): {resp.text[:150]}[/red]")

    # Publish customizations
    console.print("\n  [dim]Publishing customizations…[/dim]")
    resolve_cli(
        ["pac", "org", "publish", "--all"],
        capture_output=True, text=True, timeout=120,
    )
    console.print("  [green]✅ Customizations published[/green]")


# ── Step 5: Seed default NudgeConfiguration ────────────────────────────

def _seed_nudge_config(auth: Any, org_url: str, prefix: str):
    """Insert a default NudgeConfiguration row if the table is empty."""
    console.print("\n[bold]Step 5/5[/bold] — Seeding default Nudge Configuration")

    table_set = f"{prefix}_nudgeconfigurations"
    resp = _dv_get(auth, org_url, f"{table_set}?$top=1")
    if resp.status_code == 200 and resp.json().get("value"):
        console.print("  [dim]Default record already exists — skipping[/dim]")
        return

    body = {
        f"{prefix}_internaldays": 3,
        f"{prefix}_externaldays": 5,
        f"{prefix}_prioritydays": 1,
        f"{prefix}_generaldays": 7,
        f"{prefix}_nudgesenabled": True,
    }
    resp = _dv_post(auth, org_url, table_set, body)
    if resp.status_code in (201, 204):
        console.print("  [green]✅ Default nudge configuration seeded[/green]")
    elif resp.status_code == 409:
        console.print("  [dim]Record already exists (409)[/dim]")
    else:
        console.print(f"  [yellow]⚠ Seed failed ({resp.status_code}): {resp.text[:200]}[/yellow]")


# ── Public entry point ─────────────────────────────────────────────────

def provision_environment(auth: Any, config: dict) -> tuple[str, str]:
    """Provision the Power Platform environment and Dataverse schema.

    Returns (environment_id, org_url).
    """
    console.print(Panel(
        "[bold cyan]Phase 1 — Environment & Dataverse Provisioning[/bold cyan]",
        border_style="cyan",
    ))

    prefix = config.get("publisher_prefix", "cr")

    # Step 1 — Environment
    env_id, org_url = _create_environment(config)
    config["environment_id"] = env_id
    config["org_url"] = org_url

    # Authenticate PAC to the new environment
    console.print("\n  [dim]Authenticating PAC CLI to environment…[/dim]")
    resolve_cli(
        ["pac", "auth", "create", "--environment", env_id],
        capture_output=True, text=True, timeout=60,
    )

    # Update auth module with org URL
    auth.set_org_url(org_url)

    with Progress(SpinnerColumn(), TextColumn("{task.description}"), console=console) as progress:
        task = progress.add_task("Provisioning Dataverse schema…", total=None)

        # Step 2 — Publisher
        publisher_id = _ensure_publisher(auth, org_url, prefix)

        # Step 3 — Solution
        _ensure_solution(auth, org_url, publisher_id)

        # Step 4 — Tables
        _create_tables(auth, org_url, prefix)

        # Step 5 — Seed defaults
        _seed_nudge_config(auth, org_url, prefix)

        progress.update(task, description="[green]Provisioning complete[/green]")

    console.print(Panel(
        f"[green bold]Environment provisioned successfully![/green bold]\n\n"
        f"  Environment ID : [cyan]{env_id}[/cyan]\n"
        f"  Org URL        : [cyan]{org_url}[/cyan]",
        title="✅ Phase 1 Complete",
        border_style="green",
    ))

    return env_id, org_url
