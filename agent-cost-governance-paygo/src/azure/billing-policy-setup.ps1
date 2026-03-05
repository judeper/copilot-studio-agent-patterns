<#
.SYNOPSIS
    Creates an Azure resource group and a Power Platform PAYGO billing policy
    linking Power Platform environments to an Azure subscription for cost tracking.

.DESCRIPTION
    This script automates the Azure-side setup for Copilot Studio PAYGO billing:
    1. Authenticates to Azure (interactive or service principal).
    2. Creates or validates the target resource group with required tags.
    3. Acquires a token for the Power Platform API.
    4. Creates a billing policy via the Power Platform REST API.

    The script does NOT automate Power Platform Admin Center UI operations.
    Environment-to-billing-policy linking must be completed manually in the PPAC
    or via the API endpoint documented in the output.

.PARAMETER TenantId
    Azure AD tenant ID (GUID).

.PARAMETER SubscriptionId
    Azure subscription ID to associate with the billing policy.

.PARAMETER ResourceGroupName
    Name of the resource group to create or use for billing policy association.

.PARAMETER BillingPolicyName
    Display name for the billing policy in the Power Platform Admin Center.

.PARAMETER Location
    Azure region for the resource group (e.g., "eastus", "westus2").
    For the billing policy, use the Power Platform region (e.g., "unitedstates", "europe").

.PARAMETER Tags
    Hashtable of tags to apply to the resource group.
    Defaults to the required tags from tagging-strategy.json.

.EXAMPLE
    .\billing-policy-setup.ps1 `
        -TenantId "00000000-0000-0000-0000-000000000000" `
        -SubscriptionId "11111111-1111-1111-1111-111111111111" `
        -ResourceGroupName "rg-copilot-billing" `
        -BillingPolicyName "Copilot-Studio-PAYGO" `
        -Location "unitedstates"

.NOTES
    Prerequisites:
    - Azure PowerShell module (Az) 12.0+
    - Power Platform Admin or Global Admin role
    - Owner or Contributor role on the target Azure subscription
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$BillingPolicyName,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $false)]
    [hashtable]$Tags = @{
        CostCenter   = "CHANGE-ME"
        Environment  = "Production"
        BusinessUnit = "CHANGE-ME"
        AgentOwner   = "CHANGE-ME@example.com"
    }
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Step 1: Authenticate to Azure
# ---------------------------------------------------------------------------
Write-Host "`n=== Step 1: Azure Authentication ===" -ForegroundColor Cyan
Write-Host "Connecting to Azure (Tenant: $TenantId)..."

Connect-AzAccount -TenantId $TenantId -SubscriptionId $SubscriptionId

$context = Get-AzContext
Write-Host "Authenticated as: $($context.Account.Id)" -ForegroundColor Green
Write-Host "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"

# ---------------------------------------------------------------------------
# Step 2: Create or validate the resource group
# ---------------------------------------------------------------------------
Write-Host "`n=== Step 2: Resource Group Setup ===" -ForegroundColor Cyan

$azureLocation = switch ($Location) {
    "unitedstates" { "eastus" }
    "europe"       { "westeurope" }
    "asia"         { "southeastasia" }
    "australia"    { "australiaeast" }
    "japan"        { "japaneast" }
    "canada"       { "canadacentral" }
    "unitedkingdom" { "uksouth" }
    default        { $Location }
}

$existingRg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if ($existingRg) {
    Write-Host "Resource group '$ResourceGroupName' already exists in $($existingRg.Location)." -ForegroundColor Yellow
    Write-Host "Updating tags..."
    Set-AzResourceGroup -Name $ResourceGroupName -Tag $Tags | Out-Null
} else {
    Write-Host "Creating resource group '$ResourceGroupName' in $azureLocation..."
    New-AzResourceGroup -Name $ResourceGroupName -Location $azureLocation -Tag $Tags | Out-Null
    Write-Host "Resource group created." -ForegroundColor Green
}

# Validate tags
$rg = Get-AzResourceGroup -Name $ResourceGroupName
$requiredTags = @("CostCenter", "Environment", "BusinessUnit", "AgentOwner")
$missingTags = $requiredTags | Where-Object { -not $rg.Tags.ContainsKey($_) }
if ($missingTags) {
    Write-Warning "Missing required tags: $($missingTags -join ', '). Update tags per tagging-strategy.json."
}

Write-Host "Resource group tags:" -ForegroundColor Gray
$rg.Tags.GetEnumerator() | ForEach-Object { Write-Host "  $($_.Key) = $($_.Value)" -ForegroundColor Gray }

# ---------------------------------------------------------------------------
# Step 3: Acquire Power Platform API token
# ---------------------------------------------------------------------------
Write-Host "`n=== Step 3: Power Platform API Token ===" -ForegroundColor Cyan
Write-Host "Acquiring access token for Power Platform API..."

$ppApiResource = "https://api.powerplatform.com"

try {
    $tokenResponse = Get-AzAccessToken -ResourceUrl $ppApiResource
    $ppToken = $tokenResponse.Token
    Write-Host "Token acquired successfully." -ForegroundColor Green
} catch {
    Write-Error @"
Failed to acquire Power Platform API token.
Ensure you have Power Platform Admin or Global Admin role.
Error: $($_.Exception.Message)
"@
    exit 1
}

# ---------------------------------------------------------------------------
# Step 4: Create billing policy via Power Platform REST API
# ---------------------------------------------------------------------------
Write-Host "`n=== Step 4: Create Billing Policy ===" -ForegroundColor Cyan

$billingPolicyBody = @{
    name     = $BillingPolicyName
    location = $Location
    status   = "Enabled"
    billingInstrument = @{
        resourceGroup  = $ResourceGroupName
        subscriptionId = $SubscriptionId
        id             = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
    }
} | ConvertTo-Json -Depth 5

$ppApiVersion = "2024-10-01"
$createPolicyUrl = "https://api.powerplatform.com/licensing/billingPolicies?api-version=$ppApiVersion"

$headers = @{
    "Authorization" = "Bearer $ppToken"
    "Content-Type"  = "application/json"
}

Write-Host "Creating billing policy '$BillingPolicyName'..."
Write-Host "API URL: $createPolicyUrl" -ForegroundColor Gray

try {
    $response = Invoke-RestMethod `
        -Method Post `
        -Uri $createPolicyUrl `
        -Headers $headers `
        -Body $billingPolicyBody

    $billingPolicyId = $response.id
    Write-Host "`nBilling policy created successfully!" -ForegroundColor Green
    Write-Host "  Policy ID:   $billingPolicyId"
    Write-Host "  Policy Name: $($response.name)"
    Write-Host "  Status:      $($response.status)"
    Write-Host "  Location:    $($response.location)"
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 409) {
        Write-Warning "Billing policy '$BillingPolicyName' already exists. Retrieve it from the PPAC."
    } else {
        Write-Error @"
Failed to create billing policy.
Status Code: $statusCode
Error: $($_.Exception.Message)
Ensure you have Power Platform Admin or Global Admin role.
"@
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Step 5: Output next steps (manual PPAC operations)
# ---------------------------------------------------------------------------
Write-Host "`n=== Next Steps (Manual) ===" -ForegroundColor Cyan
Write-Host @"

The billing policy has been created. Complete the following steps manually
in the Power Platform Admin Center (PPAC):

1. Navigate to: https://admin.powerplatform.microsoft.com
2. Go to: Billing > Billing policies
3. Select the policy: '$BillingPolicyName'
4. Click 'Add environments'
5. Select the environments to link to this billing policy
6. Confirm the association

Alternatively, link environments via the REST API:

  POST https://api.powerplatform.com/licensing/billingPolicies/$billingPolicyId/environments/add?api-version=$ppApiVersion
  Content-Type: application/json
  Authorization: Bearer <token>

  {
      "environmentIds": [
          "<environment-guid-1>",
          "<environment-guid-2>"
      ]
  }

After linking environments:
- Allow up to 48 hours for initial billing data to appear in Azure Cost Management.
- Verify data in Azure portal > Cost Management + Billing > Cost analysis.
- Filter by Service name = 'Copilot Studio' to see PAYGO consumption.

"@ -ForegroundColor White

Write-Host "=== Setup Complete ===" -ForegroundColor Green
