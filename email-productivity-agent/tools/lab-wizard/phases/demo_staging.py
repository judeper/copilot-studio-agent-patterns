"""Demo staging - sends demo emails and stages snooze scenario via Graph API.

Uses a bootstrapped Entra app registration with Mail.ReadWrite application
permission to create drafts in Lisa Taylor's mailbox.  The bootstrap runs
once (interactive admin consent) and subsequent runs are fully silent.
"""

import json
import time
from pathlib import Path

import msal
import requests
from rich.console import Console
from rich.panel import Panel
from rich.prompt import Confirm
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn

from auth import TokenManager

console = Console()

MAIL_APP_CONFIG_FILE = "epa-mail-app.json"

DEMO_EMAILS = [
    {
        "recipient_key": "omar_bennett",
        "label": "Omar Bennett (NUDGE target)",
        "subject": "Q2 Headcount Request - Department Approval Needed",
        "body": (
            "<p>Hi Omar,</p>"
            "<p>I'd like to move forward with the Q2 headcount request for the Operations team. "
            "We discussed adding two FTEs - one for IT support and one for the finance compliance project.</p>"
            "<p>Could you confirm whether the budget allocation has been approved on your end? "
            "I need your sign-off before I can submit the requisition to HR.</p>"
            "<p><strong>Please let me know by end of week.</strong></p>"
            "<p>Thanks,<br>Lisa</p>"
        ),
    },
    {
        "recipient_key": "hadar_caspit",
        "label": "Hadar Caspit (SNOOZE target)",
        "subject": "Q1 Budget Variance - Please Review by Friday",
        "body": (
            "<p>Hi Hadar,</p>"
            "<p>I've prepared the Q1 budget variance report. There are a few line items in the "
            "marketing allocation that look off - could you review and let me know if those "
            "numbers are correct?</p>"
            "<p>I'd like to finalize this before the monthly review.</p>"
            "<p>Thanks,<br>Lisa</p>"
        ),
    },
    {
        "recipient_key": "will_beringer",
        "label": "Will Beringer (SKIP/FYI target)",
        "subject": "FYI: Updated IT Policy - No Action Needed",
        "body": (
            "<p>Hi Will,</p>"
            "<p>Just sharing the updated IT security policy document for your reference. "
            "No action needed on your end - this is purely informational.</p>"
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
    "   - or manually trigger it from the Power Automate portal.\n\n"
    "[bold]2.[/bold] In Teams, find the nudge card for [cyan]Hadar Caspit[/cyan]'s email\n"
    "   and click [bold yellow]Snooze 2 Days[/bold yellow].\n\n"
    "[bold]3.[/bold] In Outlook (as Lisa), move Hadar's original email to the\n"
    "   [bold]EPA-Snoozed[/bold] folder.\n\n"
    "[bold]4.[/bold] Wait ~20 minutes, then manually trigger [bold]Flow 3[/bold]\n"
    "   (Snooze Detection) to verify the snoozed record is created.\n\n"
    "[bold]5.[/bold] Prepare Hadar's delayed reply email for the unsnooze demo:\n"
    "   - Log in as Hadar and reply to Lisa's Q1 Budget Variance email."
)

PERSONA_DISPLAY_NAMES = {
    "lisa_taylor": "Lisa Taylor",
    "omar_bennett": "Omar Bennett",
    "hadar_caspit": "Hadar Caspit",
    "will_beringer": "William Beringer",
    "sonia_rees": "Sonia Rees",
}


# ---------------------------------------------------------------------------
# Mail app bootstrap (Solution B - one-time Entra app registration)
# ---------------------------------------------------------------------------

def _load_mail_app_config() -> dict | None:
    path = Path(MAIL_APP_CONFIG_FILE)
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            pass
    return None


def _save_mail_app_config(cfg: dict):
    Path(MAIL_APP_CONFIG_FILE).write_text(
        json.dumps(cfg, indent=2), encoding="utf-8"
    )


def _bootstrap_mail_app(tenant_id: str) -> dict | None:
    """Create a one-time Entra app registration with Mail.ReadWrite permission.

    Uses the admin's az CLI session to call Microsoft Graph and:
    1. Create an app registration (DemoLabMailBot)
    2. Create a service principal
    3. Assign Mail.ReadWrite application permission
    4. Admin-consent the permission
    5. Create a client secret
    6. Save credentials to epa-mail-app.json
    """
    from phases import resolve_cli
    import shutil

    console.print(Panel(
        "[bold cyan]One-Time Mail App Bootstrap[/bold cyan]\n\n"
        "Creating an Entra app registration with [bold]Mail.ReadWrite[/bold]\n"
        "application permission. This allows the wizard to create email\n"
        "drafts in Lisa Taylor's mailbox without interactive sign-in.\n\n"
        "[dim]This only runs once - credentials are saved for future use.[/dim]",
        title="🔧 Mail App Setup",
        border_style="cyan",
    ))

    az_path = shutil.which("az")
    if not az_path:
        console.print("[red]Azure CLI not found.[/red]")
        return None

    # Step 1: Create app registration
    console.print("  [dim]Creating app registration…[/dim]")
    result = resolve_cli(
        [az_path, "ad", "app", "create",
         "--display-name", "EPA-DemoLab-MailBot",
         "--sign-in-audience", "AzureADMyOrg",
         "--query", "{appId:appId, id:id}",
         "-o", "json"],
        capture_output=True, text=True, timeout=30,
    )
    if result.returncode != 0:
        console.print(f"[red]App creation failed: {(result.stderr or result.stdout or '')[:200]}[/red]")
        return None

    app_info = json.loads(result.stdout)
    app_id = app_info["appId"]
    app_object_id = app_info["id"]
    console.print(f"  [green]App created: {app_id}[/green]")

    # Step 2: Create service principal
    console.print("  [dim]Creating service principal…[/dim]")
    sp_result = resolve_cli(
        [az_path, "ad", "sp", "create", "--id", app_id,
         "--query", "id", "-o", "tsv"],
        capture_output=True, text=True, timeout=30,
    )
    sp_id = sp_result.stdout.strip() if sp_result.returncode == 0 else ""

    if not sp_id:
        # SP may already exist
        sp_lookup = resolve_cli(
            [az_path, "ad", "sp", "show", "--id", app_id,
             "--query", "id", "-o", "tsv"],
            capture_output=True, text=True, timeout=15,
        )
        sp_id = sp_lookup.stdout.strip()

    if not sp_id:
        console.print("[red]Could not create/find service principal.[/red]")
        return None
    console.print(f"  [green]Service principal: {sp_id}[/green]")

    # Step 3: Find Graph SP and Mail.ReadWrite app role
    console.print("  [dim]Looking up Mail.ReadWrite permission…[/dim]")
    graph_sp_result = resolve_cli(
        [az_path, "ad", "sp", "list",
         "--filter", "appId eq '00000003-0000-0000-c000-000000000000'",
         "--query", "[0].{id:id, appRoles:appRoles}",
         "-o", "json"],
        capture_output=True, text=True, timeout=30,
    )
    if graph_sp_result.returncode != 0:
        console.print("[red]Could not find Microsoft Graph service principal.[/red]")
        return None

    graph_data = json.loads(graph_sp_result.stdout)
    graph_sp_id = graph_data["id"]
    mail_rw_id = None
    mail_send_id = None
    for role in graph_data.get("appRoles", []):
        if role.get("value") == "Mail.ReadWrite":
            mail_rw_id = role["id"]
        elif role.get("value") == "Mail.Send":
            mail_send_id = role["id"]

    if not mail_rw_id or not mail_send_id:
        console.print("[red]Mail.ReadWrite or Mail.Send app role not found.[/red]")
        return None

    # Step 4: Assign permissions + admin consent
    console.print(f"  [dim]Mail.ReadWrite role: {mail_rw_id}[/dim]")
    console.print(f"  [dim]Mail.Send role: {mail_send_id}[/dim]")
    console.print("  [dim]Adding permissions to app…[/dim]")

    # Each permission must be a separate argument (not space-separated in one string)
    perm_result = resolve_cli(
        [az_path, "ad", "app", "permission", "add",
         "--id", app_id,
         "--api", "00000003-0000-0000-c000-000000000000",
         "--api-permissions", f"{mail_rw_id}=Role", f"{mail_send_id}=Role"],
        capture_output=True, text=True, timeout=30,
    )
    console.print(f"  [dim]Permission add rc={perm_result.returncode}[/dim]")
    if perm_result.stderr:
        console.print(f"  [dim]{perm_result.stderr.strip()[:200]}[/dim]")

    # Verify permissions were added
    verify_result = resolve_cli(
        [az_path, "ad", "app", "show", "--id", app_id,
         "--query", "requiredResourceAccess", "-o", "json"],
        capture_output=True, text=True, timeout=15,
    )
    rra = json.loads(verify_result.stdout) if verify_result.returncode == 0 else []
    if not rra:
        console.print("  [red]❌ Permissions not added — requiredResourceAccess is empty[/red]")
        return None
    console.print(f"  [green]Permissions registered ({len(rra[0].get('resourceAccess', []))} roles)[/green]")

    # Grant admin consent (with propagation wait)
    console.print("  [dim]Granting admin consent…[/dim]")
    consent_result = resolve_cli(
        [az_path, "ad", "app", "permission", "admin-consent", "--id", app_id],
        capture_output=True, text=True, timeout=60,
    )
    console.print(f"  [dim]Consent rc={consent_result.returncode}[/dim]")
    console.print("  [dim]Waiting 30s for consent to propagate…[/dim]")
    time.sleep(30)

    # Verify roles appear in token
    console.print("  [dim]Verifying token roles…[/dim]")

    # Step 5: Create client secret (needed before we can verify token)
    console.print("  [dim]Creating client secret…[/dim]")
    secret_result = resolve_cli(
        [az_path, "ad", "app", "credential", "reset",
         "--id", app_id,
         "--display-name", "EPA-DemoLab-Secret",
         "--years", "1",
         "-o", "json"],
        capture_output=True, text=True, timeout=30,
    )
    if secret_result.returncode != 0 or not secret_result.stdout.strip():
        console.print(f"[red]Could not create client secret (rc={secret_result.returncode}).[/red]")
        if secret_result.stderr:
            console.print(f"  [dim]{secret_result.stderr[:200]}[/dim]")
        return None

    secret_data = json.loads(secret_result.stdout)
    client_secret = secret_data.get("password", "")
    if not client_secret:
        console.print("[red]Client secret was empty in response.[/red]")
        return None
    console.print(f"  [green]Client secret created (length={len(client_secret)})[/green]")
    console.print("  [dim]Waiting 20s for secret to propagate…[/dim]")
    time.sleep(20)

    # Verify token has the expected roles
    try:
        import base64
        test_app = msal.ConfidentialClientApplication(
            client_id=app_id,
            client_credential=client_secret,
            authority=f"https://login.microsoftonline.com/{tenant_id}",
        )
        test_result = test_app.acquire_token_for_client(
            scopes=["https://graph.microsoft.com/.default"]
        )
        if "access_token" not in test_result:
            console.print(f"  [red]Token acquisition failed: {test_result.get('error_description', '?')[:200]}[/red]")
            console.print("  [dim]Retrying in 15s…[/dim]")
            time.sleep(15)
            test_result = test_app.acquire_token_for_client(
                scopes=["https://graph.microsoft.com/.default"]
            )

        if "access_token" in test_result:
            token_payload = test_result["access_token"].split(".")[1]
            token_payload += "=" * (4 - len(token_payload) % 4)
            decoded = json.loads(base64.b64decode(token_payload))
            roles = decoded.get("roles", [])
            console.print(f"  [green]Token roles: {roles}[/green]")
            if "Mail.ReadWrite" not in roles or "Mail.Send" not in roles:
                console.print("  [yellow]⚠ Missing expected roles — consent may still be propagating.[/yellow]")
                console.print("  [dim]Waiting 60s and retrying consent…[/dim]")
                time.sleep(60)
                resolve_cli(
                    [az_path, "ad", "app", "permission", "admin-consent", "--id", app_id],
                    capture_output=True, text=True, timeout=60,
                )
                time.sleep(15)
        else:
            console.print(f"  [red]Token still failing: {test_result.get('error_description', '?')[:200]}[/red]")
    except Exception as exc:
        console.print(f"  [yellow]Could not verify token: {exc}[/yellow]")

    # Step 6: Save config
    mail_config = {
        "client_id": app_id,
        "client_secret": client_secret,
        "tenant_id": tenant_id,
        "app_object_id": app_object_id,
        "service_principal_id": sp_id,
    }
    _save_mail_app_config(mail_config)
    console.print(f"  [green]Credentials saved to {MAIL_APP_CONFIG_FILE}[/green]\n")

    return mail_config


# ---------------------------------------------------------------------------
# Token acquisition via bootstrapped app
# ---------------------------------------------------------------------------

def _get_mail_token(mail_config: dict) -> str | None:
    """Acquire a Graph token using client credentials (silent, no user interaction)."""
    app = msal.ConfidentialClientApplication(
        client_id=mail_config["client_id"],
        client_credential=mail_config["client_secret"],
        authority=f"https://login.microsoftonline.com/{mail_config['tenant_id']}",
    )
    result = app.acquire_token_for_client(
        scopes=["https://graph.microsoft.com/.default"]
    )
    if "access_token" in result:
        return result["access_token"]
    console.print(f"[red]Token error: {result.get('error_description', '?')}[/red]")
    return None


# ---------------------------------------------------------------------------
# Email helpers
# ---------------------------------------------------------------------------

def _resolve_lisa_upn() -> str | None:
    """Resolve Lisa Taylor's UPN from Entra ID via display name search."""
    from phases.security import _resolve_user_upn
    return _resolve_user_upn("", "Lisa Taylor")


def _create_draft(token: str, lisa_upn: str, to_address: str,
                  subject: str, body_html: str) -> bool:
    """Create a draft email in Lisa's mailbox via Graph application permission."""
    payload = {
        "subject": subject,
        "body": {"contentType": "HTML", "content": body_html},
        "toRecipients": [{"emailAddress": {"address": to_address}}],
    }
    resp = requests.post(
        f"https://graph.microsoft.com/v1.0/users/{lisa_upn}/messages",
        json=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        timeout=30,
    )
    if resp.ok:
        return True
    console.print(f"    [dim]Graph error {resp.status_code}: {resp.text[:200]}[/dim]")
    return False


def _send_draft(token: str, lisa_upn: str, message_id: str) -> bool:
    """Send an existing draft from Lisa's mailbox."""
    resp = requests.post(
        f"https://graph.microsoft.com/v1.0/users/{lisa_upn}/messages/{message_id}/send",
        headers={"Authorization": f"Bearer {token}"},
        timeout=30,
    )
    return resp.status_code == 202


def _create_and_send(token: str, lisa_upn: str, to_address: str,
                     subject: str, body_html: str) -> bool:
    """Create a draft then send it (two-step to land in Sent Items)."""
    payload = {
        "subject": subject,
        "body": {"contentType": "HTML", "content": body_html},
        "toRecipients": [{"emailAddress": {"address": to_address}}],
    }
    # Create draft
    resp = requests.post(
        f"https://graph.microsoft.com/v1.0/users/{lisa_upn}/messages",
        json=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        timeout=30,
    )
    if not resp.ok:
        console.print(f"    [dim]Draft creation failed: {resp.status_code} {resp.text[:200]}[/dim]")
        return False

    msg_id = resp.json().get("id", "")

    # Send the draft
    send_resp = requests.post(
        f"https://graph.microsoft.com/v1.0/users/{lisa_upn}/messages/{msg_id}/send",
        headers={"Authorization": f"Bearer {token}"},
        timeout=30,
    )
    if send_resp.status_code == 202:
        return True

    console.print(f"    [dim]Send failed: {send_resp.status_code} {send_resp.text[:200]}[/dim]")
    return False


def _verify_tracking(auth: TokenManager, config: dict) -> bool:
    """Check Dataverse for follow-up tracking records created by Flow 1."""
    prefix = config.get("publisher_prefix", "cr")
    org_url = config.get("org_url", "")
    if not org_url:
        console.print("[yellow]org_url not set - skipping tracking verification.[/yellow]")
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
        console.print(f"[yellow]Could not query tracking table: {exc}[/yellow]")
        return False

    records = resp.json().get("value", [])
    if not records:
        console.print("[yellow]No tracking records found yet - Flow 1 may still be processing.[/yellow]")
        return False

    table = Table(title="Follow-Up Tracking Records", border_style="cyan")
    table.add_column("Recipient", style="bold")
    table.add_column("Subject", style="green")
    for rec in records:
        table.add_row(
            rec.get(f"{prefix}_recipientemail", "-"),
            rec.get(f"{prefix}_originalsubject", "-"),
        )
    console.print(table)
    return True


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def stage_demo(auth: TokenManager, config: dict) -> bool:
    """Send demo emails from Lisa Taylor's account and stage the snooze scenario."""
    console.print(Panel(
        "[bold cyan]Demo Staging[/bold cyan]\n\n"
        "This phase sends three demo emails from Lisa Taylor's mailbox\n"
        "and verifies that Flow 1 (Sent Items Tracker) picks them up.",
        title="Phase 9 - Demo Staging",
        border_style="cyan",
    ))

    tenant_id = config["tenant_id"]

    # --- Step 1: Bootstrap or load mail app credentials ---
    mail_config = _load_mail_app_config()
    if mail_config:
        console.print("[green]Mail app credentials loaded.[/green]")
    else:
        console.print("[yellow]No mail app found - running one-time bootstrap…[/yellow]\n")
        mail_config = _bootstrap_mail_app(tenant_id)
        if not mail_config:
            console.print("[red]Bootstrap failed. See errors above.[/red]")
            return False

    # --- Step 2: Acquire token via client credentials ---
    console.print("  [dim]Acquiring app token…[/dim]")
    token = _get_mail_token(mail_config)
    if not token:
        console.print("[red]Could not acquire mail token.[/red]")
        return False
    console.print("[green]Mail token acquired (app credentials).[/green]\n")

    # --- Step 3: Resolve Lisa's UPN ---
    lisa_upn = _resolve_lisa_upn()
    if not lisa_upn:
        console.print("[red]Could not resolve Lisa Taylor's UPN.[/red]")
        return False
    console.print(f"  Lisa Taylor UPN: [cyan]{lisa_upn}[/cyan]")

    # --- Step 4: Send demo emails ---
    demo_users = config.get("demo_users", {})
    all_sent = True

    for email_def in DEMO_EMAILS:
        to_addr = demo_users.get(email_def["recipient_key"], "")
        if not to_addr:
            console.print(f"[red]No email configured for {email_def['recipient_key']}[/red]")
            all_sent = False
            continue

        # Resolve real UPN
        from phases.security import _resolve_user_upn
        display = PERSONA_DISPLAY_NAMES.get(email_def["recipient_key"], "")
        real_upn = _resolve_user_upn(to_addr, display)
        if real_upn:
            to_addr = real_upn

        ok = _create_and_send(token, lisa_upn, to_addr,
                              email_def["subject"], email_def["body"])
        if ok:
            console.print(f"  [green]Sent -> {email_def['label']}[/green]  ({to_addr})")
        else:
            console.print(f"  [red]Failed -> {email_def['label']}[/red]  ({to_addr})")
            all_sent = False

    if not all_sent:
        console.print("\n[yellow]Some emails could not be sent. Check errors above.[/yellow]")
        return False

    console.print("\n[green]All demo emails sent successfully![/green]")

    # --- Step 5: Wait for Flow 1 then verify tracking ---
    console.print()
    with Progress(
        SpinnerColumn(),
        TextColumn("[bold cyan]Waiting 30s for Flow 1 to process…[/bold cyan]"),
        console=console, transient=True,
    ) as progress:
        progress.add_task("wait", total=None)
        time.sleep(30)

    _verify_tracking(auth, config)

    # --- Step 6: Show snooze staging instructions ---
    console.print()
    console.print(Panel(
        SNOOZE_INSTRUCTIONS,
        title="Next Steps - Snooze Scenario",
        border_style="yellow",
        padding=(1, 2),
    ))

    return True
