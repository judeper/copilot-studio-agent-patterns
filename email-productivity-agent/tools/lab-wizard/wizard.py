#!/usr/bin/env python3
"""EPA Lab Wizard — Interactive deployment for Email Productivity Agent demo lab."""

import sys

from rich.console import Console
from rich.panel import Panel
from rich.prompt import Prompt
from rich.rule import Rule

from auth import TokenManager
from config import collect_config, save_config, load_config
from phases.prerequisites import check_prerequisites
from phases.environment import provision_environment
from phases.security import create_security_role, assign_roles_to_users
from phases.copilot import provision_copilot
from phases.connections import setup_connections
from phases.flows import deploy_flows
from phases.validation import run_readiness_check
from phases.demo_staging import stage_demo

console = Console()

MENU = """
[bold]═══════════════════════════════════════[/bold]
[bold cyan]  EPA Lab Wizard — Phase Selection[/bold cyan]
[bold]═══════════════════════════════════════[/bold]

  [bold][1][/bold] Full Setup (all phases)
  [bold][2][/bold] Provision Environment
  [bold][3][/bold] Security Roles
  [bold][4][/bold] Copilot Agent
  [bold][5][/bold] Connections
  [bold][6][/bold] Deploy Flows
  [bold][7][/bold] Assign User Roles
  [bold][8][/bold] Validation Check
  [bold][9][/bold] Demo Staging
  [bold][0][/bold] Exit
"""

# Maps menu choice → (display label, callable key)
PHASE_ORDER = [
    ("Provision Environment", "environment"),
    ("Security Roles", "security_roles"),
    ("Copilot Agent", "copilot"),
    ("Connections", "connections"),
    ("Deploy Flows", "flows"),
    ("Assign User Roles", "assign_roles"),
    ("Validation Check", "validation"),
    ("Demo Staging", "demo_staging"),
]


def _show_banner() -> None:
    console.print(Panel(
        "[bold cyan]Email Productivity Agent — Lab Wizard[/bold cyan]\n\n"
        "Automated provisioning for the EPA demo lab.\n"
        "Follow-up nudges · Snooze auto-removal · Copilot-powered drafts",
        title="🧙 EPA Lab Wizard",
        border_style="cyan",
        padding=(1, 2),
    ))


def _run_phase(
    phase_key: str,
    auth: TokenManager,
    config: dict,
    connection_map: dict | None = None,
) -> tuple[bool, dict | None]:
    """Run a single deployment phase and return (success, connection_map_or_None)."""
    conn_map_out = connection_map

    if phase_key == "environment":
        console.print(Rule("[bold]Provision Environment[/bold]", style="cyan"))
        env_id, org_url = provision_environment(auth, config)
        if env_id and org_url:
            config["environment_id"] = env_id
            config["org_url"] = org_url
            save_config(config)
            auth.set_org_url(org_url)
            return True, conn_map_out
        return False, conn_map_out

    if phase_key == "security_roles":
        console.print(Rule("[bold]Create Security Roles[/bold]", style="cyan"))
        return create_security_role(auth, config), conn_map_out

    if phase_key == "copilot":
        console.print(Rule("[bold]Provision Copilot Agent[/bold]", style="cyan"))
        return provision_copilot(auth, config), conn_map_out

    if phase_key == "connections":
        console.print(Rule("[bold]Setup Connections[/bold]", style="cyan"))
        conn_map_out = setup_connections(auth, config)
        return bool(conn_map_out), conn_map_out

    if phase_key == "flows":
        console.print(Rule("[bold]Deploy Flows[/bold]", style="cyan"))
        if not conn_map_out:
            console.print("[yellow]⚠ No connection map available. Run the Connections phase first.[/yellow]")
            return False, conn_map_out
        return deploy_flows(auth, config, conn_map_out), conn_map_out

    if phase_key == "assign_roles":
        console.print(Rule("[bold]Assign User Roles[/bold]", style="cyan"))
        return assign_roles_to_users(auth, config), conn_map_out

    if phase_key == "validation":
        console.print(Rule("[bold]Validation Check[/bold]", style="cyan"))
        return run_readiness_check(auth, config), conn_map_out

    if phase_key == "demo_staging":
        console.print(Rule("[bold]Demo Staging[/bold]", style="cyan"))
        return stage_demo(auth, config), conn_map_out

    console.print(f"[red]Unknown phase: {phase_key}[/red]")
    return False, conn_map_out


def _run_full_setup(auth: TokenManager, config: dict) -> None:
    """Execute all phases in sequence, stopping on first failure."""
    console.print(Rule("[bold]Full Setup[/bold]", style="cyan"))
    connection_map: dict | None = None

    for label, key in PHASE_ORDER:
        console.print(f"\n[bold cyan]▶ {label}[/bold cyan]")
        success, connection_map = _run_phase(key, auth, config, connection_map)
        if success:
            console.print(f"[green]✅ {label} — complete[/green]\n")
        else:
            console.print(f"[red]❌ {label} — failed. Stopping full setup.[/red]\n")
            return

    console.print(Panel(
        "[bold green]All phases completed successfully![/bold green]",
        border_style="green",
    ))


def main() -> None:
    _show_banner()

    # --- Prerequisites ---------------------------------------------------
    console.print(Rule("[bold]Prerequisites Check[/bold]", style="cyan"))
    if not check_prerequisites():
        console.print("[red]❌ Prerequisites not met. Please resolve the issues above and re-run.[/red]")
        sys.exit(1)
    console.print("[green]✅ Prerequisites OK[/green]\n")

    # --- Configuration ---------------------------------------------------
    config = load_config()
    if config:
        console.print(f"[green]✅ Loaded existing configuration[/green]")
        from rich.prompt import Confirm as _Confirm
        if not _Confirm.ask("  Use existing configuration?", default=True):
            config = collect_config()
    else:
        config = collect_config()

    # --- Auth ------------------------------------------------------------
    auth = TokenManager(
        tenant_id=config["tenant_id"],
        org_url=config.get("org_url") or None,
    )

    # --- Phase menu loop -------------------------------------------------
    connection_map: dict | None = None

    while True:
        console.print(MENU)
        choice = Prompt.ask("  Select phase", default="0")

        if choice == "0":
            console.print("\n[bold cyan]👋 Goodbye![/bold cyan]")
            break

        if choice == "1":
            _run_full_setup(auth, config)
            continue

        idx = int(choice) - 2 if choice.isdigit() else -1
        if 0 <= idx < len(PHASE_ORDER):
            label, key = PHASE_ORDER[idx]
            success, connection_map = _run_phase(key, auth, config, connection_map)
            if success:
                console.print(f"\n[green]✅ {label} — complete[/green]")
            else:
                console.print(f"\n[red]❌ {label} — failed[/red]")
        else:
            console.print("[red]Invalid selection. Please choose 0-9.[/red]")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        console.print("\n\n[yellow]Interrupted — saving configuration…[/yellow]")
        existing = load_config()
        if existing:
            save_config(existing)
        console.print("[bold cyan]👋 Goodbye![/bold cyan]")
        sys.exit(0)
