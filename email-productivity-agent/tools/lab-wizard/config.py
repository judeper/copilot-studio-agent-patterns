"""Configuration collection and persistence for the EPA Lab Wizard."""

import json
import re
import sys
from pathlib import Path

from rich.console import Console
from rich.panel import Panel
from rich.prompt import Prompt, Confirm
from rich.table import Table

console = Console()

CONFIG_FILE = "epa-config.json"

GUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

COMMON_TIMEZONES = [
    "Eastern Standard Time",
    "Central Standard Time",
    "Mountain Standard Time",
    "Pacific Standard Time",
    "UTC",
]

DEFAULT_PERSONAS = {
    "lisa_taylor": ("Lisa Taylor", "Dir. Operations — main demo character"),
    "omar_bennett": ("Omar Bennett", "HR Manager — NUDGE target"),
    "hadar_caspit": ("Hadar Caspit", "Finance Manager — SNOOZE target"),
    "will_beringer": ("Will Beringer", "IT Admin — SKIP/FYI target"),
    "sonia_rees": ("Sonia Rees", "Customer Support — below-threshold target"),
}


def _validate_guid(value: str) -> str | None:
    if GUID_RE.match(value.strip()):
        return value.strip()
    return None


def _validate_email(value: str) -> str | None:
    if EMAIL_RE.match(value.strip()):
        return value.strip().lower()
    return None


def _prompt_guid(label: str, default: str = "") -> str:
    while True:
        value = Prompt.ask(f"  {label}", default=default or None)
        if _validate_guid(value):
            return value.strip()
        console.print("  [red]Invalid GUID format. Expected: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx[/red]")


def _prompt_email(label: str, default: str = "") -> str:
    while True:
        value = Prompt.ask(f"  {label}", default=default or None)
        if _validate_email(value):
            return value.strip().lower()
        console.print("  [red]Invalid email format.[/red]")


def _detect_tenant_domain(admin_email: str) -> str:
    return admin_email.split("@")[1] if "@" in admin_email else ""


def _suggest_user_email(persona_key: str, domain: str) -> str:
    name_part = persona_key.replace("_", "")
    return f"{name_part}@{domain}"


def load_config() -> dict | None:
    path = Path(CONFIG_FILE)
    if path.exists():
        try:
            with open(path) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            return None
    return None


def save_config(config: dict):
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2)
    console.print(f"\n[green]✅ Configuration saved to {CONFIG_FILE}[/green]")


def collect_config() -> dict:
    """Interactive TUI to collect all deployment configuration."""
    console.print(Panel(
        "[bold cyan]Email Productivity Agent — Lab Setup Wizard[/bold cyan]\n\n"
        "This wizard will collect your environment details and deploy the\n"
        "Email Productivity Agent to your Power Platform lab.",
        title="🧙 EPA Lab Wizard",
        border_style="cyan",
    ))

    # Check for existing config
    existing = load_config()
    if existing:
        console.print(f"\n[yellow]Found existing config in {CONFIG_FILE}[/yellow]")
        if Confirm.ask("  Use existing configuration?", default=True):
            _display_config(existing)
            if Confirm.ask("  Proceed with this config?", default=True):
                return existing

    config: dict = {}

    # Tenant ID
    console.print("\n[bold]1. Tenant ID[/bold] [dim](Azure Portal → Microsoft Entra ID → Overview)[/dim]")
    config["tenant_id"] = _prompt_guid("Tenant ID")

    # Admin Email
    console.print("\n[bold]2. Admin Email[/bold] [dim](your admin account)[/dim]")
    config["admin_email"] = _prompt_email("Admin Email")

    domain = _detect_tenant_domain(config["admin_email"])

    # Environment Name
    console.print("\n[bold]3. Environment Name[/bold]")
    config["environment_name"] = Prompt.ask("  Environment Name", default="EPA-Demo-Lab")

    # Publisher Prefix
    console.print("\n[bold]4. Publisher Prefix[/bold] [dim](must match repo defaults)[/dim]")
    config["publisher_prefix"] = Prompt.ask("  Publisher Prefix", default="cr")

    # Time Zone
    console.print("\n[bold]5. Time Zone[/bold] [dim](for Flow 2 daily 9 AM schedule)[/dim]")
    for i, tz in enumerate(COMMON_TIMEZONES, 1):
        console.print(f"  {i}. {tz}")
    tz_choice = Prompt.ask("  Select time zone", default="1")
    try:
        config["timezone"] = COMMON_TIMEZONES[int(tz_choice) - 1]
    except (ValueError, IndexError):
        config["timezone"] = COMMON_TIMEZONES[0]

    # Demo Users
    console.print("\n[bold]6. Demo User Emails[/bold]")
    console.print(f"  [dim]Auto-suggesting @{domain} emails — press Enter to accept or type to override[/dim]\n")

    config["demo_users"] = {}
    for key, (name, role) in DEFAULT_PERSONAS.items():
        default = _suggest_user_email(key, domain) if domain else ""
        console.print(f"  [cyan]{name}[/cyan] — {role}")
        config["demo_users"][key] = _prompt_email(f"  Email for {name}", default=default)

    # These will be populated during deployment
    config["environment_id"] = ""
    config["org_url"] = ""

    _display_config(config)

    if not Confirm.ask("\nProceed with this configuration?", default=True):
        console.print("[yellow]Exiting. Re-run to reconfigure.[/yellow]")
        sys.exit(0)

    save_config(config)
    return config


def _display_config(config: dict):
    """Show configuration summary as a rich table."""
    table = Table(title="Configuration Summary", border_style="cyan")
    table.add_column("Setting", style="bold")
    table.add_column("Value", style="green")

    table.add_row("Tenant ID", config.get("tenant_id", ""))
    table.add_row("Admin Email", config.get("admin_email", ""))
    table.add_row("Environment", config.get("environment_name", ""))
    table.add_row("Prefix", config.get("publisher_prefix", ""))
    table.add_row("Time Zone", config.get("timezone", ""))

    if config.get("environment_id"):
        table.add_row("Environment ID", config["environment_id"])
    if config.get("org_url"):
        table.add_row("Org URL", config["org_url"])

    for key, (name, _) in DEFAULT_PERSONAS.items():
        email = config.get("demo_users", {}).get(key, "")
        table.add_row(f"  {name}", email)

    console.print()
    console.print(table)
