"""MSAL-based authentication for Dataverse, Flow, PowerApps, and Graph APIs."""

import sys
import msal
from rich.console import Console
from rich.panel import Panel

console = Console()

# Well-known first-party client ID for Azure CLI (works without app registration)
AZURE_CLI_CLIENT_ID = "04b07795-a710-4532-b849-a740e3164627"

SCOPES = {
    "dataverse": "{org_url}/.default",
    "flow": "https://service.flow.microsoft.com/.default",
    "powerapps": "https://service.powerapps.com/.default",
    "graph": "https://graph.microsoft.com/.default",
}


class TokenManager:
    """Manages MSAL tokens for multiple API scopes."""

    def __init__(self, tenant_id: str, org_url: str | None = None):
        self.tenant_id = tenant_id
        self.org_url = org_url
        self._app = msal.PublicClientApplication(
            AZURE_CLI_CLIENT_ID,
            authority=f"https://login.microsoftonline.com/{tenant_id}",
        )
        self._cache: dict[str, str] = {}

    def _resolve_scope(self, scope_key: str) -> list[str]:
        scope = SCOPES[scope_key]
        if "{org_url}" in scope:
            if not self.org_url:
                raise ValueError("org_url required for Dataverse scope")
            scope = scope.replace("{org_url}", self.org_url)
        return [scope]

    def get_token(self, scope_key: str) -> str:
        """Get a cached or fresh token for the given scope key."""
        if scope_key in self._cache:
            return self._cache[scope_key]

        scopes = self._resolve_scope(scope_key)

        # Try silent acquisition first
        accounts = self._app.get_accounts()
        if accounts:
            result = self._app.acquire_token_silent(scopes, account=accounts[0])
            if result and "access_token" in result:
                self._cache[scope_key] = result["access_token"]
                return result["access_token"]

        # Device code flow
        flow = self._app.initiate_device_flow(scopes=scopes)
        if "user_code" not in flow:
            console.print(f"[red]Failed to create device flow: {flow.get('error_description', 'Unknown error')}[/red]")
            sys.exit(1)

        console.print(Panel(
            f"[bold yellow]To authenticate for [cyan]{scope_key}[/cyan], visit:[/bold yellow]\n\n"
            f"  [bold white]{flow['verification_uri']}[/bold white]\n\n"
            f"  Enter code: [bold green]{flow['user_code']}[/bold green]",
            title="🔐 Authentication Required",
            border_style="yellow",
        ))

        result = self._app.acquire_token_by_device_flow(flow)
        if "access_token" not in result:
            console.print(f"[red]Authentication failed: {result.get('error_description', 'Unknown error')}[/red]")
            sys.exit(1)

        self._cache[scope_key] = result["access_token"]
        console.print(f"[green]✅ Authenticated for {scope_key}[/green]")
        return result["access_token"]

    def headers(self, scope_key: str) -> dict:
        """Get Authorization headers for API calls."""
        return {
            "Authorization": f"Bearer {self.get_token(scope_key)}",
            "Content-Type": "application/json",
            "OData-MaxVersion": "4.0",
            "OData-Version": "4.0",
        }

    def set_org_url(self, org_url: str):
        """Set OrgUrl after environment provisioning."""
        self.org_url = org_url
        self._cache.pop("dataverse", None)
