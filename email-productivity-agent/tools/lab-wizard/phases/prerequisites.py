"""Phase 0 — Verify prerequisites (PAC CLI, Azure CLI, Python packages)."""

from __future__ import annotations

import shutil
import subprocess
import sys

from rich.console import Console
from rich.table import Table

console = Console()


def _check_command(cmd: list[str], label: str) -> tuple[bool, str]:
    """Run a command and return (success, version_or_error).

    On Windows, CLI tools like ``pac`` and ``az`` are often ``.CMD`` batch
    wrappers that ``subprocess.run`` cannot locate without ``shell=True``.
    We resolve the executable via ``shutil.which`` first so that ``.CMD``
    files are found correctly.
    """
    resolved = shutil.which(cmd[0])
    if resolved is None:
        return False, "not found on PATH"
    run_cmd = [resolved] + cmd[1:]
    try:
        result = subprocess.run(run_cmd, capture_output=True, text=True, timeout=15)
        # PAC CLI prints version info to stdout even when it treats --version
        # as an unrecognised flag (non-zero exit).  Accept stdout output that
        # looks like a version banner regardless of the exit code.
        stdout = result.stdout.strip()
        if stdout:
            first_line = stdout.split("\n")[0]
            if result.returncode == 0 or "version" in first_line.lower() or "cli" in first_line.lower():
                return True, first_line
        if result.returncode == 0:
            return True, "(no version info)"
        return False, result.stderr.strip().split("\n")[0] if result.stderr else "unknown error"
    except FileNotFoundError:
        return False, "not found on PATH"
    except subprocess.TimeoutExpired:
        return False, "timed out"


def _check_package(name: str) -> tuple[bool, str]:
    """Check whether a Python package is importable."""
    try:
        mod = __import__(name)
        version = getattr(mod, "__version__", "installed")
        return True, version
    except ImportError:
        return False, "not installed"


def check_prerequisites() -> bool:
    """Check and display status for PAC CLI, Azure CLI, and Python packages.

    Returns True if the required PAC CLI is found, False otherwise.
    """
    console.print("\n[bold cyan]Phase 0 — Checking prerequisites[/bold cyan]\n")

    table = Table(title="Prerequisite Check", border_style="cyan")
    table.add_column("Component", style="bold")
    table.add_column("Status")
    table.add_column("Detail", style="dim")

    # --- PAC CLI (required) ---
    pac_ok, pac_detail = _check_command(["pac", "--version"], "PAC CLI")
    table.add_row(
        "PAC CLI [bold red](required)[/bold red]",
        "[green]✅ Found[/green]" if pac_ok else "[red]❌ Missing[/red]",
        pac_detail,
    )

    # --- Azure CLI (optional) ---
    az_ok, az_detail = _check_command(["az", "version", "--output", "none"], "Azure CLI")
    table.add_row(
        "Azure CLI [dim](optional)[/dim]",
        "[green]✅ Found[/green]" if az_ok else "[yellow]⚠ Missing[/yellow]",
        az_detail if az_ok else f"{az_detail} — not required but helpful",
    )

    # --- Python packages ---
    packages = ["rich", "requests", "msal"]
    for pkg in packages:
        pkg_ok, pkg_detail = _check_package(pkg)

        if not pkg_ok and pkg == "msal":
            console.print(f"\n[yellow]⚠ '{pkg}' is not installed.[/yellow]")
            try:
                from rich.prompt import Confirm
                if Confirm.ask(f"  Install {pkg} now?", default=True):
                    console.print(f"  [dim]Installing {pkg}…[/dim]")
                    install = subprocess.run(
                        [sys.executable, "-m", "pip", "install", pkg, "--quiet"],
                        capture_output=True, text=True, timeout=120,
                    )
                    if install.returncode == 0:
                        pkg_ok, pkg_detail = True, "just installed"
                        console.print(f"  [green]✅ {pkg} installed successfully[/green]")
                    else:
                        pkg_detail = f"install failed: {install.stderr.strip()[:80]}"
            except Exception:
                pass

        table.add_row(
            f"Python: {pkg}",
            "[green]✅ Found[/green]" if pkg_ok else "[red]❌ Missing[/red]",
            pkg_detail,
        )

    console.print(table)

    if not pac_ok:
        console.print(
            "\n[red bold]PAC CLI is required but was not found.[/red bold]\n"
            "Install via: [cyan]dotnet tool install --global Microsoft.PowerApps.CLI.Tool[/cyan]\n"
            "Or download from: [link]https://aka.ms/PowerAppsCLI[/link]\n"
        )
        return False

    console.print("\n[green]✅ All required prerequisites met.[/green]\n")
    return True
