"""Security role creation and user assignment via Dataverse Web API."""

import requests
from rich.console import Console
from rich.table import Table
from rich.progress import Progress

from auth import TokenManager

console = Console()

ROLE_NAME = "Email Productivity Agent User"
TABLES = ["followuptracking", "nudgeconfiguration", "snoozedconversation"]
CRUD_ACTIONS = ["Create", "Read", "Write", "Delete"]


def _get_root_business_unit(auth: TokenManager) -> str | None:
    """Return the root business unit ID."""
    resp = requests.get(
        f"{auth.org_url}/api/data/v9.2/businessunits",
        headers=auth.headers("dataverse"),
        params={"$filter": "parentbusinessunitid eq null", "$select": "businessunitid"},
    )
    resp.raise_for_status()
    units = resp.json().get("value", [])
    return units[0]["businessunitid"] if units else None


def _find_role(auth: TokenManager, role_name: str) -> str | None:
    """Return the role ID if it exists, else None."""
    resp = requests.get(
        f"{auth.org_url}/api/data/v9.2/roles",
        headers=auth.headers("dataverse"),
        params={"$filter": f"name eq '{role_name}'", "$select": "roleid"},
    )
    resp.raise_for_status()
    roles = resp.json().get("value", [])
    return roles[0]["roleid"] if roles else None


def create_security_role(auth: TokenManager, config: dict) -> bool:
    """Create the EPA security role and assign table-level CRUD privileges."""
    prefix = config.get("publisher_prefix", "cr")
    console.print("\n[bold cyan]🔒 Creating Security Role[/bold cyan]\n")

    # Step 1 — Root business unit
    bu_id = _get_root_business_unit(auth)
    if not bu_id:
        console.print("[red]❌ Could not find root business unit.[/red]")
        return False
    console.print(f"  Root Business Unit: [green]{bu_id}[/green]")

    # Step 2 — Check / create role
    role_id = _find_role(auth, ROLE_NAME)
    if role_id:
        console.print(f"  Role already exists: [green]{role_id}[/green]")
    else:
        resp = requests.post(
            f"{auth.org_url}/api/data/v9.2/roles",
            headers=auth.headers("dataverse"),
            json={
                "name": ROLE_NAME,
                "description": "Ownership-based access to EPA Dataverse tables",
                "businessunitid@odata.bind": f"/businessunits({bu_id})",
            },
        )
        resp.raise_for_status()
        role_id = _find_role(auth, ROLE_NAME)
        if not role_id:
            console.print("[red]❌ Role creation succeeded but lookup failed.[/red]")
            return False
        console.print(f"  Role created: [green]{role_id}[/green]")

    # Step 3 — Assign privileges for each table × action
    table_names = [f"{prefix}_{t}" for t in TABLES]
    total_privs = len(table_names) * len(CRUD_ACTIONS)

    with Progress(console=console) as progress:
        task = progress.add_task("  Adding privileges…", total=total_privs)

        for table in table_names:
            for action in CRUD_ACTIONS:
                priv_name = f"prv{action}{table}"
                # Look up privilege ID
                resp = requests.get(
                    f"{auth.org_url}/api/data/v9.2/privileges",
                    headers=auth.headers("dataverse"),
                    params={
                        "$filter": f"name eq '{priv_name}'",
                        "$select": "privilegeid",
                    },
                )
                resp.raise_for_status()
                privs = resp.json().get("value", [])

                if not privs:
                    console.print(f"  [yellow]⚠ Privilege not found: {priv_name}[/yellow]")
                    progress.advance(task)
                    continue

                priv_id = privs[0]["privilegeid"]

                resp = requests.post(
                    f"{auth.org_url}/api/data/v9.2/roles({role_id})/Microsoft.Dynamics.CRM.AddPrivilegesRole",
                    headers=auth.headers("dataverse"),
                    json={
                        "Privileges": [
                            {
                                "Depth": "Basic",
                                "PrivilegeId": priv_id,
                                "BusinessUnitId": bu_id,
                            }
                        ]
                    },
                )
                resp.raise_for_status()
                progress.advance(task)

    console.print(f"\n[green]✅ Security role [bold]{ROLE_NAME}[/bold] configured with {total_privs} privileges.[/green]")
    return True


def assign_roles_to_users(auth: TokenManager, config: dict) -> bool:
    """Assign the EPA security role to every demo user."""
    console.print("\n[bold cyan]👤 Assigning Security Roles to Demo Users[/bold cyan]\n")

    role_id = _find_role(auth, ROLE_NAME)
    if not role_id:
        console.print("[red]❌ Security role not found. Run create_security_role first.[/red]")
        return False

    demo_users: dict = config.get("demo_users", {})
    if not demo_users:
        console.print("[yellow]⚠ No demo users configured.[/yellow]")
        return True

    table = Table(title="Role Assignment Results", border_style="cyan")
    table.add_column("User", style="bold")
    table.add_column("Email")
    table.add_column("Status")

    all_ok = True

    for persona, email in demo_users.items():
        # Resolve system user
        resp = requests.get(
            f"{auth.org_url}/api/data/v9.2/systemusers",
            headers=auth.headers("dataverse"),
            params={
                "$filter": f"internalemailaddress eq '{email}'",
                "$select": "systemuserid,fullname",
            },
        )
        resp.raise_for_status()
        users = resp.json().get("value", [])

        if not users:
            table.add_row(persona, email, "[red]❌ User not found[/red]")
            all_ok = False
            continue

        user_id = users[0]["systemuserid"]
        display_name = users[0].get("fullname", persona)

        # Associate role
        resp = requests.post(
            f"{auth.org_url}/api/data/v9.2/systemusers({user_id})/systemuserroles_association/$ref",
            headers=auth.headers("dataverse"),
            json={"@odata.id": f"{auth.org_url}/api/data/v9.2/roles({role_id})"},
        )

        if resp.status_code == 409:
            table.add_row(display_name, email, "[green]✅ Already assigned[/green]")
        elif resp.ok:
            table.add_row(display_name, email, "[green]✅ Assigned[/green]")
        else:
            table.add_row(display_name, email, f"[red]❌ {resp.status_code}[/red]")
            all_ok = False

    console.print(table)

    if all_ok:
        console.print("\n[green]✅ All demo users have the EPA security role.[/green]")
    else:
        console.print("\n[yellow]⚠ Some assignments failed — see table above.[/yellow]")

    return all_ok
