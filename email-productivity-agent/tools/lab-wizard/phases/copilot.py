"""Phase 2 — Provision Copilot Studio agent via PAC CLI."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

from rich.console import Console
from rich.panel import Panel
from rich.prompt import Confirm

console = Console()

# Paths to prompt/topic files (relative to this module)
_REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
_PROMPTS_DIR = _REPO_ROOT / "prompts"
_SRC_DIR = _REPO_ROOT / "src"

PROMPT_FILE = _PROMPTS_DIR / "nudge-agent-system-prompt.md"
NUDGE_TOPIC = _SRC_DIR / "nudge-topic.yaml"
SNOOZE_TOPIC = _SRC_DIR / "snooze-topic.yaml"


def _copilot_exists(env_id: str, agent_name: str) -> str | None:
    """Check if a copilot with the given name already exists.

    Returns the copilot ID if found, None otherwise.
    """
    try:
        result = subprocess.run(
            ["pac", "copilot", "list", "--environment", env_id, "--json"],
            capture_output=True, text=True, timeout=60,
        )
        if result.returncode != 0:
            return None

        copilots: list[dict] = json.loads(result.stdout)
        name_lower = agent_name.lower()
        for bot in copilots:
            display = (bot.get("DisplayName") or bot.get("displayName") or bot.get("name") or "").lower()
            if display == name_lower:
                return bot.get("BotId") or bot.get("botId") or bot.get("id", "")
    except (json.JSONDecodeError, subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return None


def _create_copilot(config: dict) -> str | None:
    """Create the Copilot Studio agent. Returns the bot ID or None."""
    prefix = config.get("publisher_prefix", "cr")
    env_id = config["environment_id"]

    result = subprocess.run(
        [
            "pac", "copilot", "create",
            "--name", "Email Productivity Agent",
            "--environment", env_id,
            "--solution", "EmailProductivityAgent",
            "--schema-name", f"{prefix}_emailproductivityagent",
            "--json",
        ],
        capture_output=True, text=True, timeout=120,
    )

    if result.returncode == 0:
        try:
            data = json.loads(result.stdout)
            bot_id = data.get("BotId") or data.get("botId") or data.get("id", "")
            console.print(f"  [green]✅ Copilot created: {bot_id}[/green]")
            return bot_id
        except json.JSONDecodeError:
            console.print(f"  [green]✅ Copilot created (could not parse ID)[/green]")
            return "unknown"

    console.print(f"  [red]❌ Failed to create copilot (rc={result.returncode})[/red]")
    if result.stderr:
        console.print(f"  [dim]{result.stderr[:300]}[/dim]")
    if result.stdout:
        console.print(f"  [dim]{result.stdout[:300]}[/dim]")
    return None


def _show_prompt_instructions():
    """Display instructions for pasting the system prompt."""
    if PROMPT_FILE.exists():
        console.print(Panel(
            f"[bold yellow]System Prompt File Found[/bold yellow]\n\n"
            f"  📄 [cyan]{PROMPT_FILE}[/cyan]\n\n"
            f"Copy the contents of this file and paste it into the\n"
            f"[bold]Instructions[/bold] field in Copilot Studio.\n\n"
            f"[dim]This step cannot be automated via PAC CLI.[/dim]",
            title="📋 Paste System Prompt",
            border_style="yellow",
        ))
    else:
        console.print(Panel(
            f"[red]System prompt file not found at:[/red]\n"
            f"  {PROMPT_FILE}\n\n"
            f"You will need to create it manually in Copilot Studio.",
            title="⚠ Missing Prompt File",
            border_style="red",
        ))


def _show_manual_config_guidance():
    """Display guidance for manual Copilot Studio configuration steps."""
    topic_files = []
    if NUDGE_TOPIC.exists():
        topic_files.append(f"  • [cyan]{NUDGE_TOPIC.name}[/cyan] → {NUDGE_TOPIC}")
    if SNOOZE_TOPIC.exists():
        topic_files.append(f"  • [cyan]{SNOOZE_TOPIC.name}[/cyan] → {SNOOZE_TOPIC}")

    topics_text = "\n".join(topic_files) if topic_files else "  [dim]Topic files not found in src/[/dim]"

    console.print(Panel(
        "[bold cyan]Manual Configuration Steps[/bold cyan]\n\n"
        "[bold]1. Open Copilot Studio[/bold]\n"
        "   Navigate to https://copilotstudio.microsoft.com and select\n"
        "   the [cyan]Email Productivity Agent[/cyan] in your environment.\n\n"
        "[bold]2. Paste System Prompt[/bold]\n"
        "   Go to [bold]Settings → Instructions[/bold] and paste the contents of\n"
        "   [cyan]nudge-agent-system-prompt.md[/cyan].\n\n"
        "[bold]3. Create Topics[/bold]\n"
        "   Create topics from the following YAML definitions:\n"
        f"{topics_text}\n\n"
        "[bold]4. Publish the Agent[/bold]\n"
        "   Click [bold]Publish[/bold] in the top bar to make the agent live.\n\n"
        "[dim]These steps require the Copilot Studio UI and cannot be\n"
        "fully automated via the PAC CLI.[/dim]",
        title="🛠️ Copilot Studio Setup",
        border_style="cyan",
    ))


# ── Public entry point ─────────────────────────────────────────────────

def provision_copilot(auth: Any, config: dict) -> bool:
    """Provision the Copilot Studio agent.

    Returns True when the user confirms completion of manual steps.
    """
    console.print(Panel(
        "[bold cyan]Phase 2 — Copilot Studio Agent Provisioning[/bold cyan]",
        border_style="cyan",
    ))

    env_id = config["environment_id"]
    agent_name = "Email Productivity Agent"

    # Step 1 — Check if copilot already exists
    console.print(f"\n  Checking for existing copilot [cyan]{agent_name}[/cyan]…")
    existing_id = _copilot_exists(env_id, agent_name)

    if existing_id:
        console.print(f"  [green]✅ Copilot already exists: {existing_id}[/green]")
    else:
        # Step 2 — Create copilot
        console.print(f"  Creating copilot [cyan]{agent_name}[/cyan]…")
        bot_id = _create_copilot(config)
        if not bot_id:
            console.print("  [red]Could not create copilot. Create it manually in Copilot Studio.[/red]")

    # Step 3 — Show prompt instructions
    _show_prompt_instructions()

    # Step 4 — Show manual configuration guidance
    _show_manual_config_guidance()

    # Wait for user confirmation
    console.print()
    confirmed = Confirm.ask(
        "  Have you completed the manual Copilot Studio configuration?",
        default=False,
    )

    if confirmed:
        console.print(Panel(
            "[green bold]Copilot Studio agent configured![/green bold]",
            title="✅ Phase 2 Complete",
            border_style="green",
        ))
    else:
        console.print(Panel(
            "[yellow]You can complete the manual steps later.\n"
            "The agent infrastructure is in place.[/yellow]",
            title="⏸️ Phase 2 Deferred",
            border_style="yellow",
        ))

    return confirmed
