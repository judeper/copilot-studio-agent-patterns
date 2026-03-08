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


def _resolve_user_upn(email_hint: str, display_name_hint: str) -> str | None:
    """Look up the actual UPN from Entra ID via Azure CLI.

    The wizard's auto-suggested emails (e.g. lisataylor@domain) may not
    match the real UPN (e.g. LisaT@domain).  Fall back to display-name
    search if the exact email isn't found.
    """
    from phases import resolve_cli
    import json as _json

    # Try exact UPN first
    result = resolve_cli(
        ["az", "ad", "user", "show", "--id", email_hint,
         "--query", "userPrincipalName", "-o", "tsv"],
        capture_output=True, text=True, timeout=15,
    )
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()

    # Fall back to display name search
    first_name = display_name_hint.split()[0] if display_name_hint else ""
    if not first_name:
        return None

    result = resolve_cli(
        ["az", "ad", "user", "list",
         "--filter", f"startswith(displayName,'{display_name_hint}')",
         "--query", "[0].userPrincipalName", "-o", "tsv"],
        capture_output=True, text=True, timeout=15,
    )
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()

    return None


def assign_roles_to_users(auth: TokenManager, config: dict) -> bool:
    """Assign the EPA security role to every demo user.

    Users in Entra ID must be added to the Dataverse environment before
    they appear in systemusers.  This function resolves real UPNs via
    Graph, adds users via ``pac admin assign-user``, then verifies.
    """
    from phases import resolve_cli

    console.print("\n[bold cyan]👤 Assigning Security Roles to Demo Users[/bold cyan]\n")

    role_id = _find_role(auth, ROLE_NAME)
    if not role_id:
        console.print("[red]❌ Security role not found. Run create_security_role first.[/red]")
        return False

    env_id = config.get("environment_id", "")
    demo_users: dict = config.get("demo_users", {})
    if not demo_users:
        console.print("[yellow]⚠ No demo users configured.[/yellow]")
        return True

    # Map persona keys to display names for Graph lookup
    persona_display_names = {
        "lisa_taylor": "Lisa Taylor",
        "omar_bennett": "Omar Bennett",
        "hadar_caspit": "Hadar Caspit",
        "will_beringer": "William Beringer",
        "sonia_rees": "Sonia Rees",
    }

    table = Table(title="Role Assignment Results", border_style="cyan")
    table.add_column("User", style="bold")
    table.add_column("Email")
    table.add_column("Status")

    all_ok = True

    for persona, email in demo_users.items():
        display_name = persona_display_names.get(persona, persona.replace("_", " ").title())

        # Resolve actual UPN from Entra
        real_upn = _resolve_user_upn(email, display_name)
        if not real_upn:
            table.add_row(display_name, email, "[red]❌ Not found in Entra ID[/red]")
            all_ok = False
            continue

        if real_upn.lower() != email.lower():
            console.print(f"  [dim]Resolved {email} → {real_upn}[/dim]")

        # Add user to environment and assign role via PAC CLI
        add_result = resolve_cli(
            [
                "pac", "admin", "assign-user",
                "--environment", env_id,
                "--user", real_upn,
                "--role", ROLE_NAME,
            ],
            capture_output=True, text=True, timeout=60,
        )

        output = (add_result.stdout or "") + (add_result.stderr or "")
        if add_result.returncode == 0 and "Error" not in output:
            table.add_row(display_name, real_upn, "[green]✅ Added & assigned[/green]")
        elif "already" in output.lower():
            table.add_row(display_name, real_upn, "[green]✅ Already assigned[/green]")
        else:
            # Try just the Dataverse association as fallback
            resp = requests.get(
                f"{auth.org_url}/api/data/v9.2/systemusers",
                headers=auth.headers("dataverse"),
                params={
                    "$filter": f"internalemailaddress eq '{real_upn}'",
                    "$select": "systemuserid,fullname",
                },
            )
            resp.raise_for_status()
            users = resp.json().get("value", [])

            if users:
                user_id = users[0]["systemuserid"]
                resp = requests.post(
                    f"{auth.org_url}/api/data/v9.2/systemusers({user_id})/systemuserroles_association/$ref",
                    headers=auth.headers("dataverse"),
                    json={"@odata.id": f"{auth.org_url}/api/data/v9.2/roles({role_id})"},
                )
                if resp.ok or resp.status_code == 409:
                    table.add_row(display_name, real_upn, "[green]✅ Assigned[/green]")
                    continue

            error_snippet = output.strip()[:150] if output.strip() else "unknown error"
            table.add_row(display_name, real_upn, f"[red]❌ {error_snippet}[/red]")
            all_ok = False

    console.print(table)

    if all_ok:
        console.print("\n[green]✅ All demo users have the EPA security role.[/green]")
    else:
        console.print(
            "\n[yellow]⚠ Some users could not be added.\n"
            "   Add them manually: admin.powerplatform.microsoft.com → Environments → Users → Add user[/yellow]"
        )

    return all_ok
