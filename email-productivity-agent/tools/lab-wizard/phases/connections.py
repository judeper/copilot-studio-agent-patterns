"""Phase: Connection creation and verification via PowerApps API."""

import time
import webbrowser

import requests
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

from auth import TokenManager

console = Console()

REQUIRED_CONNECTIONS = [
    {"key": "shared_office365", "name": "Office 365 Outlook", "premium": False},
    {"key": "shared_office365users", "name": "Office 365 Users", "premium": False},
    {"key": "shared_microsoftcopilot", "name": "Microsoft Copilot Studio", "premium": False},
    {"key": "shared_teams", "name": "Microsoft Teams", "premium": False},
    {"key": "shared_commondataserviceforapps", "name": "Microsoft Dataverse", "premium": False},
    {"key": "shared_webcontents", "name": "HTTP with Microsoft Entra ID", "premium": True},
]

POLL_INTERVAL = 15


def _build_instructions(env_id: str) -> str:
    """Build the instruction text for the connection creation panel."""
    url = f"https://make.powerautomate.com/environments/{env_id}/connections"
    lines = [
        f"[bold yellow]Create the following 6 connections in Power Automate:[/bold yellow]\n",
        f"  URL: [link={url}]{url}[/link]\n",
    ]
    for i, conn in enumerate(REQUIRED_CONNECTIONS, 1):
        tag = " [magenta](Premium)[/magenta]" if conn["premium"] else ""
        lines.append(f"  {i}. [cyan]{conn['name']}[/cyan]{tag}")
    lines.append(
        "\n[dim]Note: HTTP with Microsoft Entra ID requires "
        "Base Resource URL:[/dim] [bold]https://graph.microsoft.com[/bold]"
    )
    return "\n".join(lines)


def _parse_api_key(api_id: str) -> str:
    """Extract the connector key from a full apiId path.

    Example: /providers/Microsoft.PowerApps/apis/shared_office365 → shared_office365
    """
    return api_id.rsplit("/", 1)[-1] if "/" in api_id else api_id


def _parse_connection_name(raw_name: str) -> str:
    """Extract the connection instance name from the full resource name.

    The PowerApps API returns names like
    '{env_id}/shared_office365/abcdef-1234'. We need 'abcdef-1234'.
    """
    if "/connections/" in raw_name:
        return raw_name.split("/connections/")[-1]
    # Fallback: take last segment
    return raw_name.rsplit("/", 1)[-1]


def _poll_connections(auth: TokenManager, env_id: str) -> dict[str, str]:
    """Call the PowerApps API and return a map of connected api_keys → connection names."""
    url = (
        "https://api.powerapps.com/providers/Microsoft.PowerApps/connections"
        f"?api-version=2016-11-01&$filter=environment eq '{env_id}'"
    )
    resp = requests.get(url, headers=auth.headers("powerapps"), timeout=30)
    resp.raise_for_status()

    connected: dict[str, str] = {}
    for conn in resp.json().get("value", []):
        props = conn.get("properties", {})
        api_id = props.get("apiId", "")
        statuses = props.get("statuses", [])
        is_connected = (
            len(statuses) > 0 and statuses[0].get("status") == "Connected"
        )
        if is_connected:
            api_key = _parse_api_key(api_id)
            conn_name = _parse_connection_name(conn.get("name", ""))
            connected[api_key] = conn_name
    return connected


def _display_status(connected: dict[str, str]) -> int:
    """Show a table of required connections and their status. Returns found count."""
    table = Table(title="Connection Status", border_style="cyan")
    table.add_column("#", justify="right", width=3)
    table.add_column("Connection", min_width=30)
    table.add_column("Status", justify="center", min_width=14)

    found = 0
    for i, req in enumerate(REQUIRED_CONNECTIONS, 1):
        if req["key"] in connected:
            status = "[green]✅ Connected[/green]"
            found += 1
        else:
            status = "[yellow]⏳ Not found[/yellow]"
        table.add_row(str(i), req["name"], status)

    console.print(table)
    console.print(
        f"\n  [bold]{found}/{len(REQUIRED_CONNECTIONS)}[/bold] connections verified."
    )
    return found


def setup_connections(auth: TokenManager, config: dict) -> dict[str, str]:
    """Guide the user through connection creation and poll until all are verified.

    Returns:
        dict mapping api_key → connection instance name for use by flows.py,
        or an empty dict if the user chose to skip.
    """
    env_id = config["environment_id"]

    console.print(
        Panel(
            _build_instructions(env_id),
            title="🔌 Step: Create Connections",
            border_style="cyan",
        )
    )

    # Try to open the browser
    conn_url = f"https://make.powerautomate.com/environments/{env_id}/connections"
    try:
        webbrowser.open(conn_url)
        console.print("[dim]Opened browser to connection page.[/dim]\n")
    except Exception:
        console.print("[dim]Could not open browser — please navigate manually.[/dim]\n")

    console.print(
        "[bold]Polling for connections every 15 seconds… "
        "(press Ctrl+C to skip)[/bold]\n"
    )

    required_keys = {c["key"] for c in REQUIRED_CONNECTIONS}

    while True:
        try:
            connected = _poll_connections(auth, env_id)
            found = _display_status(connected)

            if found >= len(REQUIRED_CONNECTIONS):
                console.print(
                    "\n[green bold]✅ All connections verified![/green bold]\n"
                )
                # Return only the keys we care about
                return {k: v for k, v in connected.items() if k in required_keys}

            console.print(
                f"[dim]Next check in {POLL_INTERVAL}s…[/dim]\n"
            )
            time.sleep(POLL_INTERVAL)

        except KeyboardInterrupt:
            console.print("\n")
            skip = console.input(
                "[yellow]⚠ Skip connection verification? "
                "Flows may fail without all connections. (y/N): [/yellow]"
            )
            if skip.strip().lower() == "y":
                console.print("[yellow]Skipping connection verification.[/yellow]\n")
                # Return whatever we found so far
                connected = _poll_connections(auth, env_id)
                return {k: v for k, v in connected.items() if k in required_keys}
            console.print("[dim]Resuming polling…[/dim]\n")
            continue
