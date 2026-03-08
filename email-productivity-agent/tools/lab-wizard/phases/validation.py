"""Post-deployment readiness checks via Dataverse Web API."""

from __future__ import annotations

from typing import Callable

import requests
from rich.console import Console
from rich.table import Table

from auth import TokenManager

console = Console()

EXPECTED_FLOWS = [
    "EPA - Flow 1",
    "EPA - Flow 2",
    "EPA - Flow 2b",
    "EPA - Flow 3",
    "EPA - Flow 4",
    "EPA - Flow 5",
    "EPA - Flow 6",
    "EPA - Flow 7",
    "EPA - Flow 7b",
]


# ---------------------------------------------------------------------------
# Individual check helpers
# ---------------------------------------------------------------------------

def _check_solution(auth: TokenManager, _config: dict) -> tuple[bool, str]:
    resp = requests.get(
        f"{auth.org_url}/api/data/v9.2/solutions",
        headers=auth.headers("dataverse"),
        params={
            "$filter": "uniquename eq 'EmailProductivityAgent'",
            "$select": "uniquename,version",
        },
    )
    resp.raise_for_status()
    solutions = resp.json().get("value", [])
    if solutions:
        ver = solutions[0].get("version", "?")
        return True, f"v{ver}"
    return False, "Solution not found"


def _check_table(auth: TokenManager, table: str) -> tuple[bool, str]:
    resp = requests.get(
        f"{auth.org_url}/api/data/v9.2/EntityDefinitions(LogicalName='{table}')",
        headers=auth.headers("dataverse"),
        params={"$select": "LogicalName"},
    )
    if resp.status_code == 404:
        return False, "Table not found"
    resp.raise_for_status()
    return True, table


def _check_alternate_keys(auth: TokenManager, table: str) -> tuple[bool, str]:
    resp = requests.get(
        f"{auth.org_url}/api/data/v9.2/EntityDefinitions(LogicalName='{table}')",
        headers=auth.headers("dataverse"),
        params={
            "$select": "LogicalName",
            "$expand": "Keys($select=SchemaName,EntityKeyIndexStatus)",
        },
    )
    if resp.status_code == 404:
        return False, "Table not found"
    resp.raise_for_status()

    keys = resp.json().get("Keys", [])
    if not keys:
        return False, "No alternate keys defined"

    inactive = [k["SchemaName"] for k in keys if k.get("EntityKeyIndexStatus") != "Active"]
    if inactive:
        return False, f"Inactive keys: {', '.join(inactive)}"
    return True, f"{len(keys)} key(s) active"


def _check_security_role(auth: TokenManager, _config: dict) -> tuple[bool, str]:
    resp = requests.get(
        f"{auth.org_url}/api/data/v9.2/roles",
        headers=auth.headers("dataverse"),
        params={
            "$filter": "name eq 'Email Productivity Agent User'",
            "$select": "roleid",
        },
    )
    resp.raise_for_status()
    roles = resp.json().get("value", [])
    if roles:
        return True, roles[0]["roleid"]
    return False, "Role not found"


def _check_pilot_user_role(auth: TokenManager, config: dict) -> tuple[bool, str]:
    pilot_email = config.get("demo_users", {}).get("lisa_taylor")
    if not pilot_email:
        return False, "lisa_taylor email not configured"

    # Resolve actual UPN (wizard-suggested email may differ from Entra UPN)
    from phases.security import _resolve_user_upn
    real_upn = _resolve_user_upn(pilot_email, "Lisa Taylor")
    lookup_email = real_upn or pilot_email

    resp = requests.get(
        f"{auth.org_url}/api/data/v9.2/systemusers",
        headers=auth.headers("dataverse"),
        params={
            "$filter": f"internalemailaddress eq '{lookup_email}'",
            "$select": "systemuserid",
        },
    )
    resp.raise_for_status()
    users = resp.json().get("value", [])
    if not users:
        return False, f"User {lookup_email} not found in environment"

    user_id = users[0]["systemuserid"]

    resp = requests.get(
        f"{auth.org_url}/api/data/v9.2/systemusers({user_id})",
        headers=auth.headers("dataverse"),
        params={
            "$select": "systemuserid",
            "$expand": "systemuserroles_association($select=roleid,name)",
        },
    )
    resp.raise_for_status()
    roles = resp.json().get("systemuserroles_association", [])
    epa_roles = [r for r in roles if r.get("name") == "Email Productivity Agent User"]
    if epa_roles:
        return True, f"{pilot_email} has role"
    return False, f"{pilot_email} missing EPA role"


def _check_nudge_seed(auth: TokenManager, config: dict) -> tuple[bool, str]:
    prefix = config.get("publisher_prefix", "cr")
    resp = requests.get(
        f"{auth.org_url}/api/data/v9.2/{prefix}_nudgeconfigurations",
        headers=auth.headers("dataverse"),
        params={"$top": "1"},
    )
    if resp.status_code == 404:
        return False, "Table not found"
    resp.raise_for_status()
    rows = resp.json().get("value", [])
    if rows:
        return True, "Seed data present"
    return False, "No seed records"


def _check_flows(auth: TokenManager, _config: dict) -> tuple[bool, str]:
    resp = requests.get(
        f"{auth.org_url}/api/data/v9.2/workflows",
        headers=auth.headers("dataverse"),
        params={
            "$filter": "startswith(name,'EPA - Flow')",
            "$select": "name,statecode",
        },
    )
    resp.raise_for_status()
    flows = resp.json().get("value", [])

    found_names = {f["name"] for f in flows}
    missing = [
        n for n in EXPECTED_FLOWS
        if not any(fn.startswith(n) for fn in found_names)
    ]
    inactive = [f["name"] for f in flows if f.get("statecode") != 1]

    if missing:
        return False, f"Missing: {', '.join(missing)}"
    if inactive:
        return False, f"Inactive: {', '.join(inactive)}"
    return True, f"{len(flows)} flows active"


def _check_connection_references(auth: TokenManager, config: dict) -> tuple[bool, str]:
    prefix = config.get("publisher_prefix", "cr")
    resp = requests.get(
        f"{auth.org_url}/api/data/v9.2/connectionreferences",
        headers=auth.headers("dataverse"),
        params={
            "$filter": f"startswith(connectionreferencelogicalname,'{prefix}_')",
            "$select": "connectionreferencelogicalname,connectionreferencedisplayname",
        },
    )
    resp.raise_for_status()
    refs = resp.json().get("value", [])
    if refs:
        names = [r.get("connectionreferencedisplayname", r["connectionreferencelogicalname"]) for r in refs]
        return True, f"{len(refs)} ref(s): {', '.join(names)}"
    return False, "No connection references found"


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

CheckFn = Callable[[TokenManager, dict], tuple[bool, str]]


def run_readiness_check(auth: TokenManager, config: dict) -> bool:
    """Execute all readiness checks and display a summary table."""
    prefix = config.get("publisher_prefix", "cr")
    table_names = [
        f"{prefix}_followuptracking",
        f"{prefix}_nudgeconfiguration",
        f"{prefix}_snoozedconversation",
    ]

    # Build ordered list of (label, check_fn) tuples
    checks: list[tuple[str, CheckFn]] = [
        ("Solution exists", _check_solution),
    ]

    # Per-table checks
    for tbl in table_names:
        checks.append((f"Table: {tbl}", lambda a, c, t=tbl: _check_table(a, t)))
        checks.append((f"Alt keys: {tbl}", lambda a, c, t=tbl: _check_alternate_keys(a, t)))

    checks.extend([
        ("Security role", _check_security_role),
        ("Pilot user role", _check_pilot_user_role),
        ("NudgeConfig seeded", _check_nudge_seed),
        ("Flows deployed", _check_flows),
        ("Connection references", _check_connection_references),
    ])

    console.print("\n[bold cyan]🔍 Running Readiness Checks[/bold cyan]\n")

    results_table = Table(title="Readiness Check Results", border_style="cyan")
    results_table.add_column("Check", style="bold", min_width=28)
    results_table.add_column("Status", justify="center", min_width=4)
    results_table.add_column("Details")

    all_passed = True

    for label, check_fn in checks:
        try:
            passed, details = check_fn(auth, config)
        except requests.HTTPError as exc:
            passed, details = False, f"HTTP {exc.response.status_code}"
        except Exception as exc:  # noqa: BLE001
            passed, details = False, str(exc)

        icon = "✅" if passed else "❌"
        style = "green" if passed else "red"
        results_table.add_row(label, f"[{style}]{icon}[/{style}]", details)

        if not passed:
            all_passed = False

    console.print(results_table)

    if all_passed:
        console.print("\n[bold green]✅ All readiness checks passed![/bold green]")
    else:
        console.print("\n[bold yellow]⚠ Some checks failed — review the table above.[/bold yellow]")

    return all_passed
