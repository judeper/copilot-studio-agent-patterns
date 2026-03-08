"""Demo staging — sends demo emails and stages snooze scenario via Graph API."""

import time
import msal
import requests
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn

from auth import TokenManager, AZURE_CLI_CLIENT_ID

console = Console()

DEMO_EMAILS = [
    {
        "recipient_key": "omar_bennett",
        "label": "Omar Bennett (NUDGE target)",
        "subject": "Q2 Headcount Request — Department Approval Needed",
        "body": (
            "<p>Hi Omar,</p>"
            "<p>I'd like to move forward with the Q2 headcount request for the Operations team. "
            "We discussed adding two FTEs — one for IT support and one for the finance compliance project.</p>"
            "<p>Could you confirm whether the budget allocation has been approved on your end? "
            "I need your sign-off before I can submit the requisition to HR.</p>"
            "<p><strong>Please let me know by end of week.</strong></p>"
            "<p>Thanks,<br>Lisa</p>"
        ),
    },
    {
        "recipient_key": "hadar_caspit",
        "label": "Hadar Caspit (SNOOZE target)",
        "subject": "Q1 Budget Variance — Please Review by Friday",
        "body": (
            "<p>Hi Hadar,</p>"
            "<p>I've prepared the Q1 budget variance report. There are a few line items in the "
            "marketing allocation that look off — could you review and let me know if those "
            "numbers are correct?</p>"
            "<p>I'd like to finalize this before the monthly review.</p>"
            "<p>Thanks,<br>Lisa</p>"
        ),
    },
    {
        "recipient_key": "will_beringer",
        "label": "Will Beringer (SKIP/FYI target)",
        "subject": "FYI: Updated IT Policy — No Action Needed",
        "body": (
            "<p>Hi Will,</p>"
            "<p>Just sharing the updated IT security policy document for your reference. "
            "No action needed on your end — this is purely informational.</p>"
            "<p>The changes mainly affect the VPN configuration for remote workers. "
            "I've already coordinated with the vendor.</p>"
            "<p>Just keeping you in the loop.</p>"
            "<p>Thanks,<br>Lisa</p>"
        ),
    },
]

SNOOZE_INSTRUCTIONS = (
    "[bold cyan]Manual Snooze Staging Steps[/bold cyan]\n\n"
    "[bold]1.[/bold] Wait for Flow 2 (Response Detection) to run its scheduled check\n"
    "   — or manually trigger it from the Power Automate portal.\n\n"
    "[bold]2.[/bold] In Teams, find the nudge card for [cyan]Hadar Caspit[/cyan]'s email\n"
    "   and click [bold yellow]Snooze 2 Days[/bold yellow].\n\n"
    "[bold]3.[/bold] In Outlook (as Lisa), move Hadar's original email to the\n"
    "   [bold]EPA-Snoozed[/bold] folder.\n\n"
    "[bold]4.[/bold] Wait ~20 minutes, then manually trigger [bold]Flow 3[/bold]\n"
    "   (Snooze Detection) to verify the snoozed record is created.\n\n"
    "[bold]5.[/bold] Prepare Hadar's delayed reply email for the unsnooze demo:\n"
    "   — Log in as Hadar and reply to Lisa's Q1 Budget Variance email."
)


def _acquire_lisa_graph_token(tenant_id: str) -> str | None:
    """Get a Graph token that can send mail as Lisa Taylor.

    First tries the admin's existing az CLI token with /users/{id}/sendMail
    (requires Mail.Send application permission). If that fails, falls back
    to device-code login as Lisa directly.
    """
    from phases import resolve_cli
    import shutil

    az_path = shutil.which("az")
    if not az_path:
        console.print("[red]Azure CLI not found.[/red]")
        return None

    # Try the current az session's Graph token (admin)
    token_result = resolve_cli(
        ["az", "account", "get-access-token",
         "--resource", "https://graph.microsoft.com",
         "--query", "accessToken", "-o", "tsv"],
        capture_output=True, text=True, timeout=30,
    )

    if token_result.returncode == 0 and token_result.stdout.strip():
        token = token_result.stdout.strip()
        console.print("[green]✅ Graph token acquired from current session[/green]\n")
        return token

    console.print("[red]Could not acquire Graph token. Run: az login[/red]")
    return None


def _resolve_lisa_user_id(graph_token: str) -> str | None:
    """Look up Lisa Taylor's Graph user ID."""
    from phases.security import _resolve_user_upn

    lisa_upn = _resolve_user_upn("lisataylor@placeholder", "Lisa Taylor")
    if not lisa_upn:
        return None

    resp = requests.get(
        f"https://graph.microsoft.com/v1.0/users/{lisa_upn}?$select=id",
        headers={"Authorization": f"Bearer {graph_token}"},
        timeout=15,
    )
    if resp.ok:
        return resp.json().get("id")
    return None
    return None


def _send_email(graph_token: str, from_user_id: str, to_address: str, subject: str, body_html: str) -> bool:
    """Send an email via Graph API using /users/{id}/sendMail (application permission)
    with fallback to /me/sendMail (delegated permission)."""
    payload = {
        "message": {
            "subject": subject,
            "body": {"contentType": "HTML", "content": body_html},
            "toRecipients": [{"emailAddress": {"address": to_address}}],
        },
        "saveToSentItems": True,
    }
    headers = {
        "Authorization": f"Bearer {graph_token}",
        "Content-Type": "application/json",
    }

    # Try application-level send via /users/{id}/sendMail
    if from_user_id:
        resp = requests.post(
            f"https://graph.microsoft.com/v1.0/users/{from_user_id}/sendMail",
            json=payload, headers=headers, timeout=30,
        )
        if resp.status_code == 202:
            return True
        console.print(f"    [dim]/users send: {resp.status_code} — trying /me fallback…[/dim]")

    # Fallback to /me/sendMail (delegated)
    resp = requests.post(
        "https://graph.microsoft.com/v1.0/me/sendMail",
        json=payload, headers=headers, timeout=30,
    )
    if not resp.ok:
        console.print(f"    [dim]Graph error {resp.status_code}: {resp.text[:200]}[/dim]")
    return resp.status_code == 202


def _verify_tracking(auth: TokenManager, config: dict) -> bool:
    """Check Dataverse for follow-up tracking records created by Flow 1."""
    prefix = config.get("publisher_prefix", "cr")
    org_url = config.get("org_url", "")
    if not org_url:
        console.print("[yellow]⚠ org_url not set — skipping tracking verification.[/yellow]")
        return False

    url = (
        f"{org_url}/api/data/v9.2/{prefix}_followuptrackings"
        f"?$select={prefix}_recipientemail,{prefix}_originalsubject"
        f"&$top=10&$orderby=createdon desc"
    )
    try:
        resp = requests.get(url, headers=auth.headers("dataverse"), timeout=30)
        resp.raise_for_status()
    except requests.RequestException as exc:
        console.print(f"[yellow]⚠ Could not query tracking table: {exc}[/yellow]")
        return False

    records = resp.json().get("value", [])
    if not records:
        console.print("[yellow]No tracking records found yet — Flow 1 may still be processing.[/yellow]")
        return False

    table = Table(title="Follow-Up Tracking Records", border_style="cyan")
    table.add_column("Recipient", style="bold")
    table.add_column("Subject", style="green")
    for rec in records:
        table.add_row(
            rec.get(f"{prefix}_recipientemail", "—"),
            rec.get(f"{prefix}_originalsubject", "—"),
        )
    console.print(table)
    return True


def stage_demo(auth: TokenManager, config: dict) -> bool:
    """Send demo emails from Lisa Taylor's account and stage the snooze scenario."""
    console.print(Panel(
        "[bold cyan]Demo Staging[/bold cyan]\n\n"
        "This phase sends three demo emails from Lisa Taylor's mailbox\n"
        "and verifies that Flow 1 (Sent Items Tracker) picks them up.",
        title="📧 Phase 9 — Demo Staging",
        border_style="cyan",
    ))

    # --- Step 1: Get Graph token and resolve Lisa's user ID ---------------
    graph_token = _acquire_lisa_graph_token(config["tenant_id"])
    if not graph_token:
        console.print("[red]❌ Could not obtain Graph token.[/red]")
        return False

    lisa_user_id = _resolve_lisa_user_id(graph_token)
    if lisa_user_id:
        console.print(f"  [green]Lisa Taylor user ID: {lisa_user_id}[/green]")
    else:
        console.print("  [yellow]⚠ Could not resolve Lisa's user ID — will try /me fallback[/yellow]")

    demo_users = config.get("demo_users", {})

    # Map persona keys to display names for UPN resolution
    _persona_names = {
        "lisa_taylor": "Lisa Taylor",
        "omar_bennett": "Omar Bennett",
        "hadar_caspit": "Hadar Caspit",
        "will_beringer": "William Beringer",
        "sonia_rees": "Sonia Rees",
    }

    all_sent = True

    for email_def in DEMO_EMAILS:
        to_addr = demo_users.get(email_def["recipient_key"], "")
        if not to_addr:
            console.print(f"[red]❌ No email configured for {email_def['recipient_key']}[/red]")
            all_sent = False
            continue

        # Resolve real UPN in case wizard-suggested email differs
        from phases.security import _resolve_user_upn
        display = _persona_names.get(email_def["recipient_key"], "")
        real_upn = _resolve_user_upn(to_addr, display)
        if real_upn:
            to_addr = real_upn

        ok = _send_email(graph_token, lisa_user_id, to_addr, email_def["subject"], email_def["body"])
        if ok:
            console.print(f"  [green]✅ Sent → {email_def['label']}[/green]  ({to_addr})")
        else:
            console.print(f"  [red]❌ Failed → {email_def['label']}[/red]  ({to_addr})")
            all_sent = False

    if not all_sent:
        console.print("\n[yellow]⚠ Could not send emails via Graph API (Mail.Send permission may not be granted).[/yellow]")
        console.print(Panel(
            "[bold cyan]Manual Email Staging[/bold cyan]\n\n"
            "Sign into Outlook as [bold]Lisa Taylor[/bold] and send these 3 emails:\n\n"
            + "\n".join(
                f"  [bold]{i}.[/bold] To: [cyan]{demo_users.get(e['recipient_key'], e['recipient_key'])}[/cyan]\n"
                f"     Subject: [green]{e['subject']}[/green]"
                for i, e in enumerate(DEMO_EMAILS, 1)
            )
            + "\n\n[dim]After sending, Flow 1 (Sent Items Tracker) will pick them up automatically.[/dim]",
            title="📧 Manual Fallback",
            border_style="yellow",
        ))
        return True  # Don't block — user can send manually

    console.print("\n[green]All demo emails sent successfully.[/green]")

    # --- Step 2: Wait for Flow 1 then verify tracking --------------------
    console.print()
    with Progress(
        SpinnerColumn(),
        TextColumn("[bold cyan]Waiting 30 s for Flow 1 (Sent Items Tracker) to process…[/bold cyan]"),
        console=console,
        transient=True,
    ) as progress:
        progress.add_task("wait", total=None)
        time.sleep(30)

    _verify_tracking(auth, config)

    # --- Step 3: Show snooze staging instructions ------------------------
    console.print()
    console.print(Panel(
        SNOOZE_INSTRUCTIONS,
        title="🔧 Next Steps — Snooze Scenario",
        border_style="yellow",
        padding=(1, 2),
    ))

    return True
