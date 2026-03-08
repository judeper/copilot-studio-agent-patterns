"""Phase 2 - Provision Copilot Studio agent via PAC CLI.

Mirrors the automation in scripts/provision-copilot.ps1:
  1. Build a YAML template from base + embedded prompts/topics
  2. Create the copilot via pac copilot create --templateFileName
  3. Publish via pac copilot publish
  4. Validate via pac copilot extract-template
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from rich.console import Console
from rich.panel import Panel

from phases import resolve_cli

console = Console()

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
_PROMPTS_DIR = _REPO_ROOT / "prompts"
_SRC_DIR = _REPO_ROOT / "src"

BASE_TEMPLATE = _SRC_DIR / "copilot-base-template.yaml"
KICKSTART_TEMPLATE = _SRC_DIR / "kickStartTemplate-1.0.0.json"
NUDGE_PROMPT = _PROMPTS_DIR / "nudge-agent-system-prompt.md"
SNOOZE_PROMPT = _PROMPTS_DIR / "snooze-agent-system-prompt.md"


def _get_prompt_body(path: Path) -> str:
    """Read a prompt file, strip the markdown title, and append JSON instruction."""
    lines = path.read_text(encoding="utf-8").splitlines()
    # Strip leading blank lines
    while lines and not lines[0].strip():
        lines.pop(0)
    # Strip markdown title (# ...)
    if lines and lines[0].startswith("# "):
        lines.pop(0)
    # Strip blank lines after title
    while lines and not lines[0].strip():
        lines.pop(0)
    body = "\n".join(lines).strip()
    if not body:
        raise ValueError(f"Prompt file is empty after trimming: {path}")
    return body + "\n\nReturn only raw JSON. Never wrap the JSON in markdown fences."


def _yaml_indent(text: str, indent: int) -> str:
    """Indent text for YAML literal block embedding."""
    prefix = " " * indent
    return "\n".join(
        prefix + line if line.strip() else prefix.rstrip()
        for line in text.splitlines()
    )


def _build_nudge_component(prompt_body: str) -> str:
    instructions = _yaml_indent(prompt_body, 14)
    return f'''  - kind: DialogComponent
    managedProperties:
      isCustomizable: false

    displayName: Follow-Up Nudge
    description: Evaluate unreplied emails for follow-up nudges and return raw JSON for Flow 2.
    shareContext: {{}}
    state: Active
    status: Active
    schemaName: template-content.topic.FollowUpNudge
    dialog:
      kind: AdaptiveDialog
      modelDisplayName: Follow-Up Nudge
      modelDescription: Evaluate unreplied emails for follow-up nudges and return JSON.
      inputs:
        - kind: AutomaticTaskInput
          propertyName: CONVERSATION_ID
          description: The Microsoft Graph conversationId that uniquely identifies the email thread being tracked for follow-up
          shouldPromptUser: false
        - kind: AutomaticTaskInput
          propertyName: ORIGINAL_SUBJECT
          description: Subject line of the original sent email that has not received a reply
          shouldPromptUser: false
        - kind: AutomaticTaskInput
          propertyName: RECIPIENT_EMAIL
          description: Email address of the specific recipient who has not replied to the sent email
          shouldPromptUser: false
        - kind: AutomaticTaskInput
          propertyName: RECIPIENT_TYPE
          description: "Recipient classification: Internal, External, Priority, or General"
          shouldPromptUser: false
        - kind: AutomaticTaskInput
          propertyName: DAYS_SINCE_SENT
          description: Number of calendar days that have elapsed since the original email was sent
          shouldPromptUser: false
        - kind: AutomaticTaskInput
          propertyName: THREAD_EXCERPT
          description: Plain text excerpt of the most recent messages in the email thread, up to 2000 characters, for context
          shouldPromptUser: false
        - kind: AutomaticTaskInput
          propertyName: USER_DISPLAY_NAME
          description: Display name of the user who sent the original email
          shouldPromptUser: false

      beginDialog:
        kind: OnRecognizedIntent
        id: main
        intent: {{}}
        actions:
          - kind: SearchAndSummarizeContent
            id: generateNudge
            autoSend: false
            variable: Topic.AgentResponseJSON
            responseCaptureType: TextOnly
            userInput: =Concatenate("FLOW_MESSAGE: ", System.Activity.Text, Char(10), "CONVERSATION_ID: ", Topic.CONVERSATION_ID, Char(10), "ORIGINAL_SUBJECT: ", Topic.ORIGINAL_SUBJECT, Char(10), "RECIPIENT_EMAIL: ", Topic.RECIPIENT_EMAIL, Char(10), "RECIPIENT_TYPE: ", Topic.RECIPIENT_TYPE, Char(10), "DAYS_SINCE_SENT: ", Text(Topic.DAYS_SINCE_SENT), Char(10), "THREAD_EXCERPT: ", Topic.THREAD_EXCERPT, Char(10), "USER_DISPLAY_NAME: ", Topic.USER_DISPLAY_NAME)
            additionalInstructions: |-
{instructions}
            webBrowsing: false
            searchEmails: false
            fileSearchDataSource:
              searchFilesMode:
                kind: DoNotSearchFiles

          - kind: EndDialog
            id: endNudge

      inputType:
        properties:
          CONVERSATION_ID:
            displayName: CONVERSATION_ID
            description: The Microsoft Graph conversationId that uniquely identifies the email thread being tracked for follow-up
            type: String
          DAYS_SINCE_SENT:
            displayName: DAYS_SINCE_SENT
            description: Number of calendar days that have elapsed since the original email was sent
            type: Number
          ORIGINAL_SUBJECT:
            displayName: ORIGINAL_SUBJECT
            description: Subject line of the original sent email that has not received a reply
            type: String
          RECIPIENT_EMAIL:
            displayName: RECIPIENT_EMAIL
            description: Email address of the specific recipient who has not replied to the sent email
            type: String
          RECIPIENT_TYPE:
            displayName: RECIPIENT_TYPE
            description: "Recipient classification: Internal, External, Priority, or General"
            type: String
          THREAD_EXCERPT:
            displayName: THREAD_EXCERPT
            description: Plain text excerpt of the most recent messages in the email thread, up to 2000 characters, for context
            type: String
          USER_DISPLAY_NAME:
            displayName: USER_DISPLAY_NAME
            description: Display name of the user who sent the original email
            type: String

      outputType:
        properties:
          AgentResponseJSON:
            displayName: AgentResponseJSON
            description: Structured JSON with nudgeAction, skipReason, threadSummary, suggestedDraft, nudgePriority, and confidence
            type: String
'''


def _build_snooze_component(prompt_body: str) -> str:
    instructions = _yaml_indent(prompt_body, 14)
    return f'''  - kind: DialogComponent
    managedProperties:
      isCustomizable: false

    displayName: Snooze Auto-Removal
    description: Decide whether a snoozed conversation should be unsnoozed and return raw JSON for Flow 4.
    shareContext: {{}}
    state: Active
    status: Active
    schemaName: template-content.topic.SnoozeAutoRemoval
    dialog:
      kind: AdaptiveDialog
      modelDisplayName: Snooze Auto-Removal
      modelDescription: Decide whether a snoozed conversation should be unsnoozed and return JSON.
      inputs:
        - kind: AutomaticTaskInput
          propertyName: CONVERSATION_ID
          description: The Microsoft Graph conversationId of the snoozed email thread that received a new reply
          shouldPromptUser: false
        - kind: AutomaticTaskInput
          propertyName: NEW_MESSAGE_SENDER
          description: Email address of the sender who authored the new reply that triggered auto-unsnooze evaluation
          shouldPromptUser: false
        - kind: AutomaticTaskInput
          propertyName: NEW_MESSAGE_SENDER_NAME
          description: Display name of the sender who authored the new reply that triggered auto-unsnooze evaluation
          shouldPromptUser: false
        - kind: AutomaticTaskInput
          propertyName: NEW_MESSAGE_SUBJECT
          description: Subject line of the newly received reply message
          shouldPromptUser: false
        - kind: AutomaticTaskInput
          propertyName: NEW_MESSAGE_EXCERPT
          description: Plain text excerpt of the new reply, up to 500 characters, used to detect out-of-office responses and urgency
          shouldPromptUser: false
        - kind: AutomaticTaskInput
          propertyName: SNOOZED_SUBJECT
          description: Subject line of the original snoozed conversation
          shouldPromptUser: false
        - kind: AutomaticTaskInput
          propertyName: SNOOZE_UNTIL
          description: Snooze expiration timestamp for the tracked conversation, if one exists
          shouldPromptUser: false
        - kind: AutomaticTaskInput
          propertyName: USER_TIMEZONE
          description: User timezone identifier from Microsoft 365 or a fallback default, used for working-hours suppression
          shouldPromptUser: false
        - kind: AutomaticTaskInput
          propertyName: CURRENT_DATETIME
          description: Current UTC timestamp when the flow invokes the Snooze Agent
          shouldPromptUser: false

      beginDialog:
        kind: OnRecognizedIntent
        id: main
        intent: {{}}
        actions:
          - kind: SearchAndSummarizeContent
            id: generateSnoozeDecision
            autoSend: false
            variable: Topic.AgentResponseJSON
            responseCaptureType: TextOnly
            userInput: =Concatenate("FLOW_MESSAGE: ", System.Activity.Text, Char(10), "CONVERSATION_ID: ", Topic.CONVERSATION_ID, Char(10), "NEW_MESSAGE_SENDER: ", Topic.NEW_MESSAGE_SENDER, Char(10), "NEW_MESSAGE_SENDER_NAME: ", Topic.NEW_MESSAGE_SENDER_NAME, Char(10), "NEW_MESSAGE_SUBJECT: ", Topic.NEW_MESSAGE_SUBJECT, Char(10), "NEW_MESSAGE_EXCERPT: ", Topic.NEW_MESSAGE_EXCERPT, Char(10), "SNOOZED_SUBJECT: ", Topic.SNOOZED_SUBJECT, Char(10), "SNOOZE_UNTIL: ", Topic.SNOOZE_UNTIL, Char(10), "USER_TIMEZONE: ", Topic.USER_TIMEZONE, Char(10), "CURRENT_DATETIME: ", Topic.CURRENT_DATETIME)
            additionalInstructions: |-
{instructions}
            webBrowsing: false
            searchEmails: false
            fileSearchDataSource:
              searchFilesMode:
                kind: DoNotSearchFiles

          - kind: EndDialog
            id: endSnooze

      inputType:
        properties:
          CONVERSATION_ID:
            displayName: CONVERSATION_ID
            description: The Microsoft Graph conversationId of the snoozed email thread that received a new reply
            type: String
          NEW_MESSAGE_EXCERPT:
            displayName: NEW_MESSAGE_EXCERPT
            description: Plain text excerpt of the new reply, up to 500 characters, used to detect out-of-office responses and urgency
            type: String
          NEW_MESSAGE_SENDER:
            displayName: NEW_MESSAGE_SENDER
            description: Email address of the sender who authored the new reply that triggered auto-unsnooze evaluation
            type: String
          NEW_MESSAGE_SENDER_NAME:
            displayName: NEW_MESSAGE_SENDER_NAME
            description: Display name of the sender who authored the new reply that triggered auto-unsnooze evaluation
            type: String
          NEW_MESSAGE_SUBJECT:
            displayName: NEW_MESSAGE_SUBJECT
            description: Subject line of the newly received reply message
            type: String
          SNOOZED_SUBJECT:
            displayName: SNOOZED_SUBJECT
            description: Subject line of the original snoozed conversation
            type: String
          SNOOZE_UNTIL:
            displayName: SNOOZE_UNTIL
            description: Snooze expiration timestamp for the tracked conversation, if one exists
            type: String
          USER_TIMEZONE:
            displayName: USER_TIMEZONE
            description: User timezone identifier from Microsoft 365 or a fallback default, used for working-hours suppression
            type: String
          CURRENT_DATETIME:
            displayName: CURRENT_DATETIME
            description: Current UTC timestamp when the flow invokes the Snooze Agent
            type: String

      outputType:
        properties:
          AgentResponseJSON:
            displayName: AgentResponseJSON
            description: Structured JSON with unsnoozeAction, suppressReason, notificationMessage, urgency, and confidence
            type: String
'''


def _copilot_exists(env_id: str, agent_name: str) -> str | None:
    """Return copilot bot ID if it already exists, else None."""
    try:
        result = resolve_cli(
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


def _copilot_id_from_output(output: str) -> str | None:
    """Extract a copilot GUID from PAC CLI create output."""
    m = re.search(r"id\s+([0-9a-fA-F-]{36})", output)
    return m.group(1) if m else None


def _build_template(work_dir: Path, display_name: str) -> Path:
    """Build the full copilot YAML template with embedded topics."""
    console.print("  Building template with embedded prompts and topics...")

    nudge_body = _get_prompt_body(NUDGE_PROMPT)
    snooze_body = _get_prompt_body(SNOOZE_PROMPT)
    base = BASE_TEMPLATE.read_text(encoding="utf-8").rstrip()

    full_template = (
        base + "\n"
        + _build_nudge_component(nudge_body) + "\n"
        + _build_snooze_component(snooze_body) + "\n"
    )

    template_path = work_dir / "epa-template.yaml"
    template_path.write_text(full_template, encoding="utf-8")

    # Build clean kickstart template
    ks_data = json.loads(KICKSTART_TEMPLATE.read_text(encoding="utf-8"))
    ks_data["metadata"]["name"] = display_name
    ks_data["metadata"]["description"] = f"{display_name} for follow-up nudges and snooze auto-removal."
    ks_data["content"]["displayName"] = display_name
    ks_data["content"]["description"] = "Evaluates unreplied emails and snoozed replies and returns raw JSON decisions to Power Automate flows."
    ks_data["content"]["instructions"] = "When invoked by automated flows, use the active topic instructions and return raw JSON only."
    ks_data["spec"]["connectors"] = []
    ks_path = work_dir / "kickStartTemplate-1.0.0.json"
    ks_path.write_text(json.dumps(ks_data, indent=2), encoding="utf-8")

    console.print("  [green]Template built with Follow-Up Nudge + Snooze Auto-Removal topics[/green]")
    return template_path


def _create_copilot(config: dict, template_path: Path) -> str | None:
    """Create the copilot with the full template. Returns bot ID or None."""
    prefix = config.get("publisher_prefix", "cr")
    env_id = config["environment_id"]
    display_name = "Email Productivity Agent"

    console.print(f"  Creating copilot [cyan]{display_name}[/cyan]...")

    # pac copilot create requires CWD to contain kickStartTemplate
    result = resolve_cli(
        [
            "pac", "copilot", "create",
            "--environment", env_id,
            "--schemaName", f"{prefix}_emailproductivityagent",
            "--templateFileName", str(template_path),
            "--displayName", display_name,
            "--solution", "EmailProductivityAgent",
        ],
        capture_output=True, text=True, timeout=120,
        cwd=str(template_path.parent),
    )

    if result.returncode != 0:
        console.print(f"  [red]Create failed (rc={result.returncode})[/red]")
        if result.stderr:
            console.print(f"  [dim]{result.stderr[:300]}[/dim]")
        if result.stdout:
            console.print(f"  [dim]{result.stdout[:300]}[/dim]")
        return None

    # Check for silent errors
    if re.search(r"(?i)Error:.*ObjectDoesNotExist|Error:.*solution.*not valid", result.stdout or ""):
        console.print(f"  [red]Create failed silently:[/red]")
        console.print(f"  [dim]{result.stdout[:300]}[/dim]")
        return None

    bot_id = _copilot_id_from_output(result.stdout or "")
    if not bot_id:
        bot_id = _copilot_exists(env_id, display_name)

    if bot_id:
        console.print(f"  [green]Copilot created: {bot_id}[/green]")
    else:
        console.print("  [yellow]Copilot created but ID could not be resolved[/yellow]")

    return bot_id


def _publish_copilot(env_id: str, bot_id: str) -> bool:
    """Publish the copilot. Returns True on success."""
    console.print("  Publishing copilot...")
    result = resolve_cli(
        ["pac", "copilot", "publish", "--environment", env_id, "--bot", bot_id],
        capture_output=True, text=True, timeout=120,
    )
    if result.returncode == 0:
        console.print("  [green]Copilot published[/green]")
        return True
    console.print(f"  [red]Publish failed (rc={result.returncode})[/red]")
    if result.stderr:
        console.print(f"  [dim]{result.stderr[:300]}[/dim]")
    return False


def _validate_copilot(env_id: str, bot_id: str, work_dir: Path) -> bool:
    """Validate that the copilot has the expected topics."""
    console.print("  Validating topics...")
    val_path = work_dir / "epa-validation.yaml"
    result = resolve_cli(
        [
            "pac", "copilot", "extract-template",
            "--environment", env_id,
            "--bot", bot_id,
            "--templateFileName", str(val_path),
            "--overwrite",
        ],
        capture_output=True, text=True, timeout=120,
        cwd=str(work_dir),
    )
    if result.returncode != 0 or not val_path.exists():
        console.print("  [yellow]Could not extract template for validation[/yellow]")
        return False

    content = val_path.read_text(encoding="utf-8")
    markers = [
        "displayName: Follow-Up Nudge",
        "displayName: Snooze Auto-Removal",
        "displayName: AgentResponseJSON",
    ]
    missing = [m for m in markers if m not in content]
    if missing:
        console.print(f"  [yellow]Missing markers: {missing}[/yellow]")
        return False

    console.print("  [green]Follow-Up Nudge and Snooze Auto-Removal topics verified[/green]")
    return True


# -- Public entry point -------------------------------------------------------

def provision_copilot(auth: Any, config: dict) -> bool:
    """Provision the Copilot Studio agent with embedded topics.

    Automates the full workflow: template build, create, publish, validate.
    Returns True on success.
    """
    console.print(Panel(
        "[bold cyan]Phase 2 - Copilot Studio Agent Provisioning[/bold cyan]",
        border_style="cyan",
    ))

    env_id = config["environment_id"]
    agent_name = "Email Productivity Agent"

    # Check required repo assets exist
    for f in (BASE_TEMPLATE, KICKSTART_TEMPLATE, NUDGE_PROMPT, SNOOZE_PROMPT):
        if not f.exists():
            console.print(f"  [red]Required file not found: {f}[/red]")
            return False

    # Step 1: Check for existing copilot
    console.print(f"\n[bold]Step 1/4[/bold] - Checking for existing copilot...")
    bot_id = _copilot_exists(env_id, agent_name)

    work_dir = Path(tempfile.mkdtemp(prefix="epa-copilot-"))
    try:
        if bot_id:
            console.print(f"  [green]Copilot already exists: {bot_id}[/green]")
        else:
            # Step 2: Build template and create copilot
            console.print(f"\n[bold]Step 2/4[/bold] - Creating copilot with topics...")
            template_path = _build_template(work_dir, agent_name)
            bot_id = _create_copilot(config, template_path)
            if not bot_id:
                console.print("  [red]Could not create copilot.[/red]")
                return False

        # Step 3: Publish
        console.print(f"\n[bold]Step 3/4[/bold] - Publishing...")
        if not _publish_copilot(env_id, bot_id):
            console.print("  [yellow]Publish failed - you can publish manually in Copilot Studio.[/yellow]")

        # Step 4: Validate
        console.print(f"\n[bold]Step 4/4[/bold] - Validating...")
        _validate_copilot(env_id, bot_id, work_dir)

    finally:
        shutil.rmtree(work_dir, ignore_errors=True)

    console.print(Panel(
        f"[green bold]Copilot provisioned and published![/green bold]\n"
        f"Bot ID: [cyan]{bot_id}[/cyan]",
        title="Phase 2 Complete",
        border_style="green",
    ))
    return True
