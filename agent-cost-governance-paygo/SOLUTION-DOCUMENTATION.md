# Solution Documentation — Agent Cost Governance PAYGO

> **Version**: 1.0.0
> **Last Updated**: 2026-03-05
> **Classification**: Tier-2 Cross-Cutting Governance
> **Status**: Production-Ready Reference Architecture

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture & Data Flow](#2-architecture--data-flow)
3. [Prerequisites](#3-prerequisites)
4. [Deployment Guide](#4-deployment-guide)
5. [Power BI Dashboard Design](#5-power-bi-dashboard-design)
6. [Governance Controls](#6-governance-controls)
7. [Regulatory Alignment](#7-regulatory-alignment)
8. [Testing & Validation](#8-testing--validation)
9. [Known Limitations](#9-known-limitations)
10. [Troubleshooting](#10-troubleshooting)
11. [References](#11-references)

---

## 1. Executive Summary

This solution delivers leadership-quality financial governance for Microsoft Copilot Studio agent deployments operating under the Pay-As-You-Go (PAYGO) billing model. It bridges the gap between Azure Cost Management's raw billing data and the executive-level cost visibility that financial services institutions require for regulatory compliance and fiscal accountability.

The core value proposition is a fully documented, deployable reference architecture that connects Copilot Studio agent consumption — metered in Copilot Credits — through Azure Cost Management into Power BI dashboards with pre-built DAX measures, budget alerts, and FSI regulatory alignment artifacts. The solution is designed for organizations that need to demonstrate cost governance controls to auditors and regulators under frameworks including GLBA 501(b), SOX 302/404, FINRA 4511, and OCC 2013-29.

### Key Outcomes

- **Cost Visibility**: Near-real-time (24-hour latency) dashboards showing Copilot Credit consumption by environment, resource group, and billing period.
- **Budget Controls**: Automated alerts at configurable thresholds (50%, 80%, 100% of monthly budget) with parameterized email recipients.
- **Audit Readiness**: Pre-built evidence collection playbook, separation-of-duties matrix, and regulatory alignment mapping.
- **Deployable Artifacts**: PowerShell provisioning script, ARM template for budget alerts, DAX measures, and resource tagging strategy — all production-ready.

### What This Solution Is Not

This solution does not provide per-agent cost attribution. Azure Cost Management reports Copilot Studio consumption at the **environment level**. Individual agent costs within a shared environment cannot be disaggregated through the Azure billing pipeline. The Power Platform Admin Center has begun introducing agent-level visibility features, but these do not currently flow through to Azure Cost Management or the Power BI connector. This limitation is documented in detail in [Section 9: Known Limitations](#9-known-limitations) and in [Known Gaps and Roadmap](limitations/known-gaps-and-roadmap.md).

---

## 2. Architecture & Data Flow

### 2.1 High-Level Architecture

The solution follows a linear data pipeline from agent consumption to executive reporting:

```
┌─────────────────────┐
│  Copilot Studio     │
│  Agents (PAYGO)     │
│  ┌───────────────┐  │
│  │ Agent A       │  │
│  │ Agent B       │  │
│  │ Agent C       │  │
│  └───────────────┘  │
└────────┬────────────┘
         │ Copilot Credits consumed
         ▼
┌─────────────────────┐
│  PAYGO Billing      │
│  Policy             │
│  (PP Admin Center)  │
│  ┌───────────────┐  │
│  │ Links env to  │  │
│  │ Azure sub +   │  │
│  │ resource group │  │
│  └───────────────┘  │
└────────┬────────────┘
         │ Usage records (up to 24h latency)
         ▼
┌─────────────────────┐
│  Azure Cost         │
│  Management         │
│  ┌───────────────┐  │
│  │ Cost Analysis  │  │
│  │ Budgets       │  │
│  │ Exports       │  │
│  └───────────────┘  │
└────────┬────────────┘
         │ Native connector or Cost Export
         ▼
┌─────────────────────┐     ┌─────────────────────┐
│  Power BI           │     │  Budget Alerts       │
│  Dashboard          │     │  (Azure Monitor)     │
│  ┌───────────────┐  │     │  ┌───────────────┐  │
│  │ Executive     │  │     │  │ 50% threshold │  │
│  │ Environment   │  │     │  │ 80% threshold │  │
│  │ Budget vs Act │  │     │  │ 100% threshold│  │
│  └───────────────┘  │     │  └───────────────┘  │
└─────────────────────┘     └─────────────────────┘
```

For a visual diagram, see [reference-architecture.drawio](src/architecture/reference-architecture.drawio).

### 2.2 Detailed Data Flow

The data flow proceeds through five stages, each with specific latency characteristics and transformation points.

#### Stage 1: Agent Consumption

Copilot Studio agents consume Copilot Credits as they process interactions. Since September 2025, all consumption is metered in Copilot Credits — a unified billing unit that replaced the earlier per-message billing model.

**Copilot Credit consumption rates (as of March 2026):**

| Feature / Action | Credits per Event |
|-----------------|-------------------|
| Classic answer (static/manual) | 1 |
| Generative answer (AI-generated) | 2 |
| Agent action (custom flow, API call) | 5 |
| Tenant graph grounding (organizational data) | 10 |
| Agent flow actions (per 100 actions) | 13 |
| AI tools — basic (per 10 responses) | 1 |
| AI tools — standard (per 10 responses) | 15 |
| AI tools — premium (per 10 responses) | 100 |
| Content processing tool (per page) | 8 |

> **Note**: These rates are subject to change. Always verify against the [official Copilot Studio billing documentation](https://learn.microsoft.com/en-us/microsoft-copilot-studio/requirements-messages-management). Bring-your-own-model configurations may generate separate Azure meters.

**Pricing**: PAYGO rate is **$0.01 per Copilot Credit**. Alternatively, prepaid packs provide 25,000 credits/month at $200/tenant for predictable workloads.

#### Stage 2: Billing Policy Linkage

A PAYGO billing policy in the Power Platform Admin Center links one or more Power Platform environments to an Azure subscription and resource group. This linkage is what causes Copilot Studio consumption to appear in Azure Cost Management.

**Key characteristics:**
- Billing policies are created via the Power Platform Admin Center UI or the Power Platform REST API.
- Each billing policy targets a specific Azure subscription and resource group.
- Multiple environments can be linked to a single billing policy.
- The billing policy determines which Azure subscription is charged for the linked environments' consumption.
- Billing policies require Power Platform Admin or Global Admin permissions to create.

**API endpoint for automation:**
```
POST https://api.powerplatform.com/licensing/billingPolicies?api-version=2024-10-01
```

> **Important**: There is no native Azure PowerShell cmdlet (`New-AzBillingPolicy` or similar) for creating Power Platform billing policies. The [billing-policy-setup.ps1](src/azure/billing-policy-setup.ps1) script uses `Invoke-RestMethod` against the Power Platform REST API. See [Section 4.1](#41-billing-policy-setup) for details.

#### Stage 3: Azure Cost Management Processing

Once the billing policy is active, Azure Cost Management processes the consumption data through its standard pipeline.

**Data freshness:**
- Internal processing refreshes approximately every 4 hours.
- User-facing data latency is **up to 24 hours** for Power Platform billing data.
- New subscriptions may require up to 48 hours before all Cost Management features are fully available.
- End-of-month billing finalization can take up to 5 business days after the billing period closes.
- After invoice publication, charges are final unless Microsoft issues an explicit correction.

**Azure meters for Copilot Studio:**
- Primary meter: `Copilot Studio – Copilot Credit`
- Legacy references may show `Copilot Studio message` meters (pre-September 2025).
- Meter names and categories may vary by tenant configuration, agreement type, and billing region.

> **Callout**: Meter names are not guaranteed to be consistent across all tenants and agreement types. The DAX measures in this solution use pattern matching to accommodate known variations. See [cost-measures.dax](src/power-bi/cost-measures.dax) for implementation.

#### Stage 4: Power BI Ingestion

Power BI connects to Azure Cost Management via one of two pathways:

**Primary pathway — Power BI Native Connector:**
- Built-in connector: Azure Cost Management
- Supported agreement types: Enterprise Agreement (EA), Microsoft Customer Agreement (MCA), Microsoft Partner Agreement (MPA)
- **Data limit**: Approximately **$5 million in raw cost details** per report scope
- Suitable for: Small to mid-sized deployments with moderate monthly spend
- Refresh: Scheduled refresh in Power BI Service (daily recommended)

**Alternative pathway — Cost Export → Data Lake → Power BI:**
- Azure Cost Management exports cost data to an Azure Storage account (CSV or Parquet)
- Power BI connects to the storage account via DirectQuery or Import
- **No practical data limit** (bounded only by storage and Power BI Premium capacity)
- Suitable for: Large enterprises, multi-subscription environments, long-term retention
- Enables incremental refresh, extending practical coverage to ~$65M+ in raw cost data

See [alternative-approaches.md](src/architecture/alternative-approaches.md) for a detailed comparison and decision guide.

#### Stage 5: Alerting

Azure Cost Management budget alerts operate independently of Power BI, providing proactive notifications when spending approaches or exceeds configured thresholds.

**Alert configuration:**
- Budget scope: Subscription or resource group
- Thresholds: Configurable percentages of monthly budget (recommended: 50%, 80%, 100%)
- Recipients: Parameterized email addresses (Finance, IT leadership, platform admin)
- Delivery: Email via Azure Monitor action groups

The [cost-alert-template.json](src/azure/cost-alert-template.json) provides a deployable ARM template with parameterized thresholds and recipients.

### 2.3 Alternative Architectures

This solution supports two primary architectural patterns. The choice depends on data volume, retention requirements, and organizational maturity.

#### Pattern A: Direct Connector (Default)

```
Azure Cost Management → Power BI Connector → Power BI Report
```

**When to use:**
- Monthly Copilot Studio spend is well below $5M
- Organization needs a quick, low-maintenance setup
- No requirement for cost data retention beyond the Azure Cost Management retention window (13 months for actual costs)
- Team has Power BI expertise but limited Azure Data Lake experience

**Advantages:**
- Simplest setup — no additional Azure resources required
- Native connector handles authentication and data modeling
- Minimal ongoing maintenance

**Limitations:**
- $5M raw cost data ceiling per report scope
- Limited to Azure Cost Management's data retention window
- Cannot combine with non-Azure cost data sources easily

#### Pattern B: Cost Export → Data Lake → Power BI

```
Azure Cost Management → Cost Export → Azure Storage → Power BI (DirectQuery/Import)
```

**When to use:**
- Monthly spend exceeds or may approach $5M
- Organization requires long-term cost data retention (e.g., 7+ years for FINRA compliance)
- Multiple subscriptions or billing accounts need to be consolidated
- Advanced analytics or custom ETL processing is required

**Advantages:**
- No practical data volume limit
- Full control over data retention period
- Can enrich cost data with organizational metadata (agent display names, business unit mappings)
- Supports incremental refresh for efficient Power BI processing

**Limitations:**
- Requires additional Azure infrastructure (Storage Account, optionally Data Factory/Synapse)
- Higher operational complexity and maintenance burden
- Additional Azure costs for storage and data processing

See [alternative-approaches.md](src/architecture/alternative-approaches.md) for detailed setup guidance for each pattern.

---

## 3. Prerequisites

### 3.1 Azure Prerequisites

| Requirement | Details |
|------------|---------|
| Azure Subscription | Active subscription with billing enabled |
| RBAC Role | Owner or Contributor on the target resource group |
| Azure Cost Management | Enabled (default for most subscription types) |
| Agreement Type | Enterprise Agreement, Microsoft Customer Agreement, or Microsoft Partner Agreement for Power BI connector; all types supported for Cost Export |
| Azure CLI or PowerShell | Azure CLI 2.50+ or Az PowerShell module 12.0+ for ARM template deployment |
| Resource Group | Dedicated or shared resource group for billing policy association |

### 3.2 Power Platform Prerequisites

| Requirement | Details |
|------------|---------|
| Environment | Production or Sandbox environment with Dataverse enabled |
| Copilot Studio Capacity | Copilot Studio license or PAYGO billing policy active |
| Admin Role | Power Platform Admin, Global Admin, or Dynamics 365 Admin for billing policy creation |
| Billing Policy | PAYGO billing policy linking environment(s) to the Azure subscription |
| Environments Identified | List of environments to be linked, including Environment ID (GUID) and display name |

### 3.3 Power BI Prerequisites

| Requirement | Details |
|------------|---------|
| License | Power BI Pro or Premium Per User (PPU) for report authoring and sharing |
| Power BI Desktop | Latest version for report development |
| Workspace | Power BI Service workspace for report publication and scheduled refresh |
| Connector Access | Azure Cost Management connector requires read access to the billing scope |
| Data Gateway | Not required if using the native connector with Power BI Service; may be required for on-premises scenarios |

### 3.4 Organizational Prerequisites

| Requirement | Details |
|------------|---------|
| Budget Approval | Finance stakeholder sign-off on monthly budget amount and alert thresholds |
| Role Assignments | Separation of duties documented per [separation-of-duties-matrix.md](governance/separation-of-duties-matrix.md) |
| Compliance Sign-off | Compliance/Risk acknowledgment of known limitations (no per-agent attribution, 24h latency) |
| Evidence Repository | Designated storage location for audit evidence with appropriate access controls |

---

## 4. Deployment Guide

### 4.1 Billing Policy Setup

The billing policy links Power Platform environments to an Azure subscription, enabling Copilot Studio consumption to appear in Azure Cost Management.

#### Step 1: Prepare the Azure Resource Group

Create or identify the resource group that will be associated with the billing policy.

```powershell
# Login to Azure
Connect-AzAccount

# Create resource group (if needed)
New-AzResourceGroup `
    -Name "rg-copilot-billing" `
    -Location "eastus" `
    -Tag @{
        CostCenter    = "IT-Operations"
        Environment   = "Production"
        BusinessUnit  = "Digital-Technology"
        AgentOwner    = "platform-team@contoso.com"
    }
```

Apply the required tags per the [tagging strategy](src/azure/tagging-strategy.json).

#### Step 2: Create the Billing Policy

Use the provided script to create the billing policy via the Power Platform REST API.

```powershell
.\src\azure\billing-policy-setup.ps1 `
    -TenantId "your-tenant-id" `
    -SubscriptionId "your-subscription-id" `
    -ResourceGroupName "rg-copilot-billing" `
    -BillingPolicyName "Copilot-Studio-PAYGO" `
    -Location "unitedstates"
```

The script performs the following:
1. Authenticates to Azure AD using interactive login or service principal.
2. Acquires an access token for the Power Platform API (`https://api.powerplatform.com`).
3. Creates a billing policy via `POST /licensing/billingPolicies`.
4. Outputs the billing policy ID for use in environment linking.

> **Important**: The script does NOT automate Power Platform Admin Center UI operations. Environment-to-billing-policy linking must be completed manually in the PPAC or via the API endpoint `/billingPolicies/{id}/environments/add`. The script outputs instructions for this step.

#### Step 3: Link Environments to the Billing Policy

In the Power Platform Admin Center:

1. Navigate to **Billing** → **Billing policies**.
2. Select the billing policy created in Step 2.
3. Click **Add environments**.
4. Select each Copilot Studio environment that should be billed under this policy.
5. Confirm the association.

Alternatively, use the Power Platform REST API:

```
POST https://api.powerplatform.com/licensing/billingPolicies/{policyId}/environments/add?api-version=2024-10-01
Content-Type: application/json

{
    "environmentIds": [
        "environment-guid-1",
        "environment-guid-2"
    ]
}
```

#### Step 4: Verify Billing Data Flow

After linking environments, allow up to **48 hours** for initial billing data to appear in Azure Cost Management.

1. Open the Azure portal → **Cost Management + Billing** → **Cost Management** → **Cost analysis**.
2. Set the scope to the subscription or resource group associated with the billing policy.
3. Add a filter: **Service name** = `Copilot Studio` or **Meter category** = `Copilot Studio`.
4. Verify that cost data appears for the linked environments.

If no data appears after 48 hours:
- Confirm the billing policy is Active in the PPAC.
- Confirm at least one agent in the linked environment has been invoked.
- Check the Azure subscription's billing status (it must be active, not suspended).

### 4.2 Environment Linking Best Practices

#### Environment Isolation Strategy

For maximum cost attribution granularity, consider a **one-environment-per-agent** or **one-environment-per-business-unit** isolation strategy. Since Azure Cost Management reports at the environment level (not individual agent level), environment isolation is the primary mechanism for cost segregation.

| Strategy | Granularity | Operational Overhead | When to Use |
|----------|-------------|---------------------|-------------|
| Single environment, all agents | Lowest — total cost only | Lowest | Small teams, few agents, no charge-back requirement |
| Environment per business unit | Medium — cost per BU | Medium | Departmental charge-back, moderate agent count |
| Environment per agent | Highest — cost per agent | Highest | Strict cost accountability, regulatory requirements |

> **Recommendation**: For FSI organizations, **environment per business unit** provides a practical balance between cost attribution granularity and operational overhead. Reserve environment-per-agent for critical or high-cost agents.

#### Environment Naming Convention

Adopt a consistent naming convention that supports cost identification:

```
Format: {Org}-{BU}-{Purpose}-{Stage}
Example: Contoso-Wealth-AgentPortfolio-Prod
Example: Contoso-Ops-AgentIT-Dev
```

Document the mapping between environment display names and environment GUIDs. This mapping is essential because Azure Cost Management billing data references environments by GUID, not display name.

### 4.3 Power BI Configuration

#### Step 1: Connect to Azure Cost Management

1. Open Power BI Desktop.
2. Select **Get Data** → **Azure** → **Azure Cost Management**.
3. Choose the connection type:
   - **Billing accounts** — for organization-wide scope
   - **Subscriptions** — for subscription-level scope (recommended for this solution)
4. Enter the subscription ID associated with the billing policy.
5. Select the data scope and date range.
6. Load the data.

#### Step 2: Import DAX Measures

Import the DAX measures from [cost-measures.dax](src/power-bi/cost-measures.dax) into the Power BI model. All 9 measures:

- **Total PAYGO Cost (Current Month)**: Filtered sum of Copilot Studio costs for the current calendar month.
- **Total PAYGO Cost (Prior Month)**: Same calculation for the previous month.
- **Cost by Environment/Resource Group**: Breakdown by resource group (which maps to billing policy and linked environments).
- **Month-over-Month Variance (Absolute)**: Dollar change from the prior month.
- **Month-over-Month Variance (%)**: Percentage change from the prior month.
- **Daily Average Cost (Current Month)**: Average daily spend for the current month.
- **Projected Month-End Cost**: Linear extrapolation based on daily average.
- **Budget Utilization %**: Current spend as a percentage of the budget.
- **Budget Remaining**: Budget amount minus current month spend.

See [sample-model.md](src/power-bi/sample-model.md) for the recommended table structure, relationships, and slicer configuration.

#### Step 3: Build Dashboard Views

Build three dashboard views per the design specifications in [Section 5](#5-power-bi-dashboard-design):

1. **Executive Summary** — KPI cards, trend charts, top environments by cost.
2. **Environment Breakdown** — detailed cost table with drill-through to resource-level detail.
3. **Budget vs. Actual** — gauge visualization comparing actual spend to configured budget.

#### Step 4: Configure Scheduled Refresh

1. Publish the report to Power BI Service.
2. Navigate to the dataset settings in the target workspace.
3. Configure scheduled refresh:
   - **Frequency**: Daily (recommended) — aligns with Azure Cost Management's 24-hour data latency.
   - **Time**: After business hours to minimize user impact.
   - **Failure notifications**: Enable and configure for the report owner and backup admin.

#### Step 5: Configure Workspace Access

Grant appropriate access to the Power BI workspace:

| Role | Power BI Access Level | Rationale |
|------|----------------------|-----------|
| Finance Stakeholder | Viewer | View dashboards and export data |
| IT Leadership | Viewer | Executive-level cost monitoring |
| Platform Admin | Contributor | Modify reports, add visualizations |
| Compliance/Risk | Viewer | Audit evidence collection |
| Report Owner | Admin | Full control, manage refresh, access |

### 4.4 Alert Configuration

Deploy the budget alert using the provided ARM template.

#### Using Azure CLI:

```bash
az deployment group create \
    --resource-group "rg-copilot-billing" \
    --template-file "src/azure/cost-alert-template.json" \
    --parameters \
        budgetName="copilot-studio-monthly" \
        budgetAmount=5000 \
        startDate="2026-04-01" \
        alertRecipients='["finance@contoso.com","it-lead@contoso.com","platform-admin@contoso.com"]' \
        thresholdPercentages='[50,80,100]'
```

#### Using PowerShell:

```powershell
New-AzResourceGroupDeployment `
    -ResourceGroupName "rg-copilot-billing" `
    -TemplateFile "src/azure/cost-alert-template.json" `
    -budgetName "copilot-studio-monthly" `
    -budgetAmount 5000 `
    -startDate "2026-04-01" `
    -alertRecipients @("finance@contoso.com", "it-lead@contoso.com", "platform-admin@contoso.com") `
    -thresholdPercentages @(50, 80, 100)
```

#### Alert Threshold Guidance

| Threshold | Action | Audience |
|-----------|--------|----------|
| 50% | Informational — review spending trend | Platform Admin |
| 80% | Warning — assess remaining budget, review agent usage | Finance + Platform Admin |
| 100% | Critical — budget exceeded, initiate cost review | Finance + IT Leadership + Platform Admin |

> **Note**: Azure Cost Management budget alerts are based on **forecasted** and **actual** cost. The 80% alert uses actual cost; forecasted alerts can provide earlier warning. Configure both for comprehensive coverage.

---

## 5. Power BI Dashboard Design

### 5.1 Executive Summary View

The executive summary provides a single-pane view of Copilot Studio PAYGO spending for leadership audiences.

#### Required Components

| Component | Visualization Type | Data Source |
|-----------|--------------------|-------------|
| Total Copilot Credit Cost (Current Month) | KPI Card | `[Total PAYGO Cost Current Month]` DAX measure |
| Month-over-Month Change | KPI Card with trend indicator | `[MoM Variance %]` DAX measure |
| Cost Trend (Last 6 Months) | Line Chart | Monthly aggregated cost over time |
| Top 5 Environments by Cost | Horizontal Bar Chart | Cost by resource group / environment, sorted descending |
| Budget Utilization | Gauge | Actual spend vs. configured budget amount |
| Credit Consumption by Action Type | Donut Chart | Cost by meter subcategory (if available) |

#### Design Principles

- **No more than 6 visualizations** on the executive summary page — leadership audiences need clarity, not density.
- Use the organization's brand colors for visual consistency.
- Include a **data freshness indicator** showing the last refresh timestamp — critical given the 24-hour latency.
- All currency values in USD (or organizational reporting currency) with consistent formatting.
- Include a text box noting: *"Costs reflect environment-level consumption. Per-agent breakdown is not available in Azure Cost Management."*

### 5.2 Environment Breakdown View

This view provides detailed cost analysis at the environment and resource group level.

#### Required Components

| Component | Visualization Type | Data Source |
|-----------|--------------------|-------------|
| Cost Table | Matrix/Table | Environment (resource group), Cost, % of Total, MoM Change |
| Environment Cost Trend | Multi-line Chart | Cost over time per environment (top 5–10) |
| Cost Distribution | Treemap | Proportional cost by environment |
| Daily Cost Detail | Area Chart | Daily cost with environment color coding |

#### Interactivity

- **Cross-filter**: Selecting an environment in the table should filter all other visuals.
- **Drill-through**: From environment summary to daily detail page.
- **Slicer**: Date range slicer (last 30 days, last 90 days, current month, custom).
- **Export**: Enable data export for Finance team reconciliation.

#### Environment GUID Mapping

Azure Cost Management reports environment identifiers as GUIDs. To display human-readable environment names:

1. Create a mapping table in Power BI with columns: `EnvironmentGUID`, `EnvironmentDisplayName`, `BusinessUnit`, `EnvironmentPurpose`.
2. Maintain this table manually or source it from the Power Platform Admin Center via API.
3. Create a relationship between the mapping table and the cost data on the environment identifier field.

> **Callout**: ❌ Agent identifiers within an environment may also appear as GUIDs. There is no built-in mechanism in Azure Cost Management to map these to agent display names. If agent-level PPAC data becomes available via API, consider integrating it as a supplementary data source.

### 5.3 Budget vs. Actual View

This view provides a clear comparison of actual spending against the configured budget.

#### Required Components

| Component | Visualization Type | Data Source |
|-----------|--------------------|-------------|
| Budget Gauge | Gauge | Actual spend vs. budget amount |
| Budget Status | Card with conditional formatting | Green (< 50%), Yellow (50–80%), Red (> 80%) |
| Daily Burn Rate | Line Chart | Cumulative daily spend with budget line overlay |
| Projected Month-End Spend | KPI Card | Linear projection based on daily average |
| Historical Budget Performance | Clustered Bar | Actual vs. Budget by month (last 6 months) |

#### Budget Data Integration

The budget amount can be sourced from:
1. **Manual entry**: A Power BI parameter or table with the monthly budget amount.
2. **Azure Cost Management API**: Query the budget configuration via the Budgets API.
3. **Dataverse**: Store budget targets in a custom Dataverse table for centralized management.

For simplicity, this solution recommends **manual entry** via a Power BI parameter, updated when the budget changes.

---

## 6. Governance Controls

### 6.1 Budget Thresholds

Budget controls are the primary governance mechanism for PAYGO cost management. This solution implements a three-tier alert system:

#### Tier 1: Informational (50% of Budget)

- **Trigger**: Actual spend reaches 50% of the monthly budget.
- **Action**: Email notification to Platform Admin.
- **Purpose**: Early awareness of spending trajectory.
- **Expected response**: Review current month's usage patterns. No action required if trajectory is consistent with historical norms.

#### Tier 2: Warning (80% of Budget)

- **Trigger**: Actual spend reaches 80% of the monthly budget.
- **Action**: Email notification to Finance Stakeholder and Platform Admin.
- **Purpose**: Proactive budget management.
- **Expected response**: Review agent activity logs for unusual spikes. Assess whether remaining budget is sufficient for the remainder of the billing period. Identify any new or experimental agents driving unexpected consumption.

#### Tier 3: Critical (100% of Budget)

- **Trigger**: Actual spend reaches 100% of the monthly budget.
- **Action**: Email notification to Finance Stakeholder, IT Leadership, and Platform Admin.
- **Purpose**: Budget breach notification for immediate review.
- **Expected response**: Convene cost review meeting. Determine whether to increase the budget, throttle agent usage, or accept the overage. Document the decision and rationale for audit purposes.

> **Note**: PAYGO billing does not automatically stop agent consumption when a budget is exceeded. Alerts are notifications only. To enforce hard spending limits, consider implementing environment-level capacity controls in the Power Platform Admin Center (where available).

### 6.2 Separation of Duties

Effective cost governance requires clear role boundaries to prevent conflicts of interest and ensure accountability. See [separation-of-duties-matrix.md](governance/separation-of-duties-matrix.md) for the complete RACI matrix.

#### Critical Separations

| Control | Must NOT be the Same Person |
|---------|----------------------------|
| Agent deployment | Budget approval |
| Cost report authoring | Cost report approval |
| Alert threshold configuration | Alert recipient |
| Billing policy creation | Financial reconciliation |

These separations ensure that:
- The person deploying agents (which generate costs) is not the same person approving the budget.
- The person configuring alerts cannot suppress their own notifications.
- The person with Azure billing access cannot unilaterally reconcile their own cost reports.

### 6.3 Evidence Collection

Evidence collection supports both routine compliance and point-in-time audit requests. See [evidence-collection-playbook.md](governance/evidence-collection-playbook.md) for the complete playbook.

#### Evidence Types

| Evidence Type | Source | Format | Frequency |
|--------------|--------|--------|-----------|
| Cost dashboard screenshot | Power BI | PDF/PNG | Monthly |
| Budget alert configuration | Azure portal | ARM template export | Quarterly |
| Billing policy configuration | PPAC | Screenshot + API response | Quarterly |
| Environment-billing policy mapping | PPAC | Tabular export | Quarterly |
| Role assignment documentation | Azure RBAC + PPAC | Screenshot or API export | Quarterly |
| Tagging compliance report | Azure Resource Graph | Query results export | Monthly |
| Budget variance explanation | Finance team | Written narrative | Monthly |
| Separation of duties attestation | Compliance team | Signed form | Annually |

#### Retention Requirements

- **Minimum retention**: 6 years (FINRA 4511 / SEA Rule 17a-4 baseline).
- **Recommended retention**: 7 years (accommodates organizational policies that extend beyond regulatory minimums and provides a buffer for audit timing).
- **Storage**: Immutable storage (e.g., Azure Blob Storage with WORM policy, SharePoint with records management, or dedicated compliance archival system).

---

## 7. Regulatory Alignment

This section maps the solution's governance controls to specific regulatory requirements applicable to financial services institutions. See [regulatory-alignment.md](governance/regulatory-alignment.md) for the detailed mapping table.

### 7.1 GLBA 501(b) — Gramm-Leach-Bliley Act

**Requirement**: Financial institutions must implement administrative, technical, and physical safeguards to protect the security, confidentiality, and integrity of customer information. The Information Security Program must be appropriate for the institution's size, complexity, and activities.

**Solution Controls**:
- **Budget controls and alerts** demonstrate administrative safeguards over AI agent spending that processes customer data.
- **Separation of duties matrix** establishes accountability for cost governance decisions.
- **Evidence collection playbook** provides the documentation framework required for the written Information Security Program.
- **Tagging strategy** enforces resource classification that supports data governance.

**Evidence Type**: Monthly cost reports, quarterly control attestations, annual Information Security Program review documentation.

**Applicability Note**: GLBA 501(b) applies broadly to "financial institutions" — banks, credit unions, securities firms, insurance companies, tax preparers, and certain service providers. If the organization deploys Copilot Studio agents that interact with or process nonpublic personal information (NPI), cost governance of these agents falls within the scope of the Information Security Program.

### 7.2 SOX 302/404 — Sarbanes-Oxley Act

**Requirement**: CEOs and CFOs must certify the accuracy of financial reports (Section 302) and the effectiveness of internal controls over financial reporting (Section 404). This includes IT controls that support financial reporting processes.

**Solution Controls**:
- **Budget vs. actual dashboards** provide verifiable cost data that supports financial statement accuracy for AI/agent technology expenses.
- **Automated budget alerts** serve as a detective control for cost anomalies that could indicate control failures.
- **Separation of duties** prevents single-person override of cost controls.
- **Tagging strategy** enforces the CostCenter tag, enabling accurate cost allocation to financial reporting line items.
- **Evidence collection** provides the audit trail required for ICFR (Internal Controls over Financial Reporting) assessment.

**Evidence Type**: Quarterly dashboard exports, annual control effectiveness assessment, separation-of-duties attestation.

**Applicability Note**: SOX applies to publicly traded companies. If Copilot Studio agent costs are material to financial statements (or if agents support financial reporting processes), these controls are relevant to the ICFR assessment.

### 7.3 FINRA 4511 — Books and Records

**Requirement**: FINRA member firms must make and preserve books and records as required by FINRA rules, the Securities Exchange Act, and SEC rules. Records must be retained for specified periods in compliant formats (SEA Rule 17a-4).

**Solution Controls**:
- **Cost reports and dashboard exports** constitute business records subject to retention requirements.
- **Evidence collection playbook** specifies a 6-year minimum retention period aligned with SEA Rule 17a-4.
- **Budget decisions and variance explanations** must be documented and retained as business records.
- **Alert history and response documentation** demonstrate ongoing cost monitoring and governance.

**Evidence Type**: Monthly cost reports (PDF), budget decision documentation, alert response logs — all retained for minimum 6 years in compliant storage.

**Applicability Note**: FINRA 4511 applies to broker-dealers. Cost governance records for AI agents used in broker-dealer operations (e.g., client communication agents, compliance assistants) are business records subject to this rule. Note that AI-generated or AI-modified records may be treated as firm communications under FINRA interpretive guidance.

### 7.4 OCC 2013-29 — Third-Party Risk Management

**Requirement**: National banks and federal savings associations must manage risks from third-party relationships through comprehensive due diligence, ongoing monitoring, and board-level reporting.

**Solution Controls**:
- **Azure Cost Management integration** provides visibility into spending on Microsoft's platform (a third-party technology provider).
- **Budget controls** demonstrate financial oversight of third-party technology spending.
- **Tagging strategy** enables cost categorization and allocation for vendor risk reporting.
- **Monthly and quarterly evidence collection** supports ongoing monitoring requirements.

**Evidence Type**: Quarterly vendor cost reports, annual vendor risk assessment documentation, budget performance summaries.

**Applicability Note**: OCC 2013-29 applies to OCC-supervised institutions. Copilot Studio is a cloud service from Microsoft (a third party). Cost governance demonstrates the institution's financial oversight of this third-party relationship, which is a component of the broader vendor risk management program.

---

## 8. Testing & Validation

### 8.1 Pre-Deployment Testing

Before full deployment, validate the end-to-end pipeline in a non-production environment.

#### Test 1: Billing Policy Verification

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Run `billing-policy-setup.ps1` with test parameters | Script completes without errors; billing policy ID returned |
| 2 | Verify billing policy in PPAC | Policy appears with correct subscription and resource group |
| 3 | Link a sandbox environment to the policy | Environment appears under the billing policy's linked environments |
| 4 | Invoke a test agent in the sandbox environment | Agent interaction completes successfully |
| 5 | Wait 24–48 hours | Cost data appears in Azure Cost Management for the linked environment |

#### Test 2: Power BI Data Validation

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Connect Power BI to Azure Cost Management | Connection succeeds; data preview shows Copilot Studio meters |
| 2 | Import DAX measures | All measures calculate without errors |
| 3 | Validate current month total | Matches Azure Cost Management portal (within rounding tolerance) |
| 4 | Validate MoM variance | Correctly calculates against prior month data |
| 5 | Validate environment breakdown | Resource groups align with linked environments |

#### Test 3: Alert Validation

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Deploy ARM template with a low test budget (e.g., $1) | Deployment succeeds; budget appears in Cost Management |
| 2 | Trigger agent interactions exceeding the test budget | Budget alert email received by configured recipients |
| 3 | Verify alert content | Alert includes budget name, current spend, threshold percentage |
| 4 | Clean up: delete or increase the test budget | Test budget removed; production budget confirmed |

### 8.2 Post-Deployment Validation

After production deployment, perform the following validations on a monthly basis for the first quarter.

| Validation | Method | Frequency |
|-----------|--------|-----------|
| Data freshness | Check Power BI last refresh timestamp; should be ≤ 24 hours old | Weekly (first month), then monthly |
| Cost accuracy | Cross-reference Power BI totals with Azure portal | Monthly |
| Alert delivery | Confirm alert emails are being received (not filtered by spam/DLP) | Monthly |
| Tag compliance | Run Azure Resource Graph query to verify tags on billing resource groups | Monthly |
| Role assignments | Review RBAC and PPAC role assignments against separation-of-duties matrix | Quarterly |
| Evidence collection | Verify monthly evidence package is complete and archived | Monthly |

### 8.3 User Acceptance Criteria

| Criterion | Verification Method |
|-----------|-------------------|
| Finance stakeholder can view the executive summary dashboard | Stakeholder confirms access and data relevance |
| Platform admin can identify which environments drive the most cost | Admin demonstrates environment breakdown navigation |
| Compliance officer can locate and export evidence artifacts | Officer performs a dry run of the evidence collection process |
| Budget alert recipients receive notifications | Test alert delivered and confirmed |
| IT leadership can articulate the solution's known limitations | Leadership briefing completed; limitations acknowledged in writing |

---

## 9. Known Limitations

This section summarizes the limitations of the current solution. Each limitation is documented in detail in [Known Gaps and Roadmap](limitations/known-gaps-and-roadmap.md).

### 9.1 No Per-Agent Cost Attribution in Azure Cost Management

**Impact**: High
**Description**: Azure Cost Management reports Copilot Studio consumption at the **environment level**, not the individual agent level. All agents within a shared environment appear as a single aggregated cost line item. It is not possible to determine, through Azure Cost Management alone, how much a specific agent (e.g., "IT Help Desk Agent" vs. "HR FAQ Agent") costs when both operate in the same environment.

**Mitigation**: Use environment isolation (one environment per agent or per business unit) to achieve cost attribution at the desired granularity. See [Section 4.2](#42-environment-linking-best-practices) for environment isolation strategies.

**Platform evolution**: The Power Platform Admin Center has begun introducing agent-level usage visibility and consumption caps (late 2025). These features are evolving and may not yet provide the same granularity or integration with Azure Cost Management. Monitor Microsoft's roadmap for updates.

### 9.2 24-Hour Data Latency

**Impact**: Medium
**Description**: There is a latency of **up to 24 hours** between when a Copilot Studio agent consumes credits and when that consumption appears in Azure Cost Management. Internal processing refreshes approximately every 4 hours, but user-facing data may not update for up to 24 hours. New subscriptions may require up to 48 hours for initial data.

**Mitigation**: Set Power BI scheduled refresh to daily. Include a data freshness indicator on all dashboard pages. Communicate the latency to stakeholders to set expectations. Do not use this solution for real-time cost monitoring or alerting on individual transactions.

### 9.3 Agent Identifiers as GUIDs

**Impact**: Medium
**Description**: Both environment identifiers and agent/bot identifiers appear as GUIDs in Azure Cost Management billing data. There is no built-in mapping to human-readable display names in the billing pipeline.

**Mitigation**: Maintain a manual mapping table in Power BI that maps environment GUIDs to display names (see [Section 5.2](#52-environment-breakdown-view)). Update this table when environments are created, renamed, or decommissioned.

### 9.4 Power BI Connector Data Limit

**Impact**: Medium (for large enterprises)
**Description**: The Power BI Azure Cost Management native connector supports approximately **$5 million in raw cost details** per report scope. Exceeding this limit may result in incomplete data, refresh failures, or degraded performance.

**Mitigation**: For organizations approaching this limit, switch to the Cost Export → Data Lake → Power BI architecture (Pattern B). See [Section 2.3](#23-alternative-architectures) and [alternative-approaches.md](src/architecture/alternative-approaches.md).

### 9.5 Meter Name Variability

**Impact**: Low
**Description**: Azure Cost Management meter names for Copilot Studio may vary by tenant, agreement type, and billing region. The primary meter is `Copilot Studio – Copilot Credit`, but legacy meters (`Copilot Studio message`) and tenant-specific variations may exist.

**Mitigation**: The DAX measures in [cost-measures.dax](src/power-bi/cost-measures.dax) use pattern matching (CONTAINSSTRING) to accommodate known meter name variations. Review and update the filter patterns if new meter names are observed.

### 9.6 No Automated PPAC Configuration

**Impact**: Low
**Description**: The Power Platform Admin Center does not expose all billing policy configuration options via API. Some operations (particularly environment linking and capacity management) may require manual steps in the PPAC UI.

**Mitigation**: The [billing-policy-setup.ps1](src/azure/billing-policy-setup.ps1) script automates what is available via the REST API and provides clear instructions for manual steps. Monitor the Power Platform API documentation for expanded automation capabilities.

### 9.7 Positioning Statement

> This solution is an **interim financial governance bridge**. It provides leadership-quality cost visibility and audit-grade controls using currently available platform capabilities. As Microsoft enhances native per-agent billing granularity, environment-level attribution controls in the Power Platform Admin Center, and Power BI integration, the specific artifacts in this solution may be superseded by native platform features. The governance framework, regulatory alignment, and evidence collection practices will remain valuable regardless of platform evolution.

---

## 10. Troubleshooting

### 10.1 No Cost Data in Azure Cost Management

**Symptom**: After linking environments to a billing policy, no Copilot Studio cost data appears in Azure Cost Management.

**Possible Causes and Resolutions**:

| Cause | Resolution |
|-------|-----------|
| Billing policy is not Active | Verify status in PPAC → Billing → Billing policies. Recreate if necessary. |
| Environment not linked to billing policy | Verify in PPAC that the environment appears under the billing policy's linked environments. |
| No agent activity | Invoke a test agent in the linked environment to generate consumption. |
| New subscription delay | Wait up to 48 hours for initial data in new subscriptions. |
| Azure Cost Management not enabled | Verify Cost Management is accessible in the Azure portal for the subscription. |
| Wrong scope in Cost Analysis | Ensure the Cost Analysis scope matches the subscription/resource group of the billing policy. |
| Agreement type limitation | Power BI connector requires EA, MCA, or MPA. Other agreement types must use Cost Export. |

### 10.2 Power BI Refresh Failures

**Symptom**: Scheduled refresh in Power BI Service fails.

**Possible Causes and Resolutions**:

| Cause | Resolution |
|-------|-----------|
| Expired credentials | Re-authenticate the Azure Cost Management data source in Power BI Service dataset settings. |
| Data volume exceeds connector limit | Check if raw cost data exceeds ~$5M. Switch to Cost Export if so. |
| Service outage | Check Azure Service Health and Power BI Service Health dashboards. |
| Gateway issues | If using an on-premises gateway, verify gateway status and connectivity. |
| Timeout | Reduce the data scope (shorter date range) or enable incremental refresh. |

### 10.3 Budget Alerts Not Received

**Symptom**: Budget threshold is exceeded but alert emails are not received.

**Possible Causes and Resolutions**:

| Cause | Resolution |
|-------|-----------|
| Email filtered by spam/DLP | Check spam folders; whitelist Azure Cost Management alert sender. |
| Action group misconfigured | Verify the action group in Azure Monitor includes the correct email addresses. |
| Budget scope mismatch | Ensure the budget scope covers the resource group linked to the billing policy. |
| Forecast vs. actual mismatch | Budget alerts can be configured for actual or forecasted cost. Verify the alert condition type. |
| Budget date range expired | Budgets have start/end dates. Verify the budget is active for the current period. |

### 10.4 DAX Measure Returns Zero or Unexpected Values

**Symptom**: One or more DAX measures return $0 or incorrect values.

**Possible Causes and Resolutions**:

| Cause | Resolution |
|-------|-----------|
| No Copilot Studio data in model | Verify the data source contains Copilot Studio meters. Check the raw data table. |
| Meter name mismatch | The CONTAINSSTRING filters in the DAX may not match tenant-specific meter names. Check actual meter names in raw data and update filters. |
| Date context issue | Ensure date slicer or filter context includes the period with active consumption. |
| Currency conversion | If the subscription uses non-USD currency, verify the cost column contains expected values. |
| Data model relationship error | Verify relationships between the cost data table and the date table are correct. |

### 10.5 Environment GUID Not Resolving

**Symptom**: The dashboard shows GUIDs instead of environment display names.

**Resolution**: Update the environment mapping table in Power BI:
1. Navigate to the Power Platform Admin Center → Environments.
2. For each environment, note the Display Name and Environment ID (GUID).
3. Update the mapping table in the Power BI model.
4. Refresh the dataset.

---

## 11. References

### Microsoft Documentation

| Resource | URL |
|----------|-----|
| Copilot Studio Licensing | https://learn.microsoft.com/en-us/microsoft-copilot-studio/billing-licensing |
| Copilot Studio Billing Rates | https://learn.microsoft.com/en-us/microsoft-copilot-studio/requirements-messages-management |
| Power Platform PAYGO Setup | https://learn.microsoft.com/en-us/power-platform/admin/pay-as-you-go-set-up |
| PAYGO Usage & Billing | https://learn.microsoft.com/en-us/power-platform/admin/pay-as-you-go-usage-costs |
| Azure Cost Management Data | https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/understand-cost-mgt-data |
| Power BI Cost Management Connector | https://learn.microsoft.com/en-us/power-bi/connect-data/desktop-connect-azure-cost-management |
| Azure Cost Management Automation | https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/manage-automation |
| Manage Copilot Studio Capacity | https://learn.microsoft.com/en-us/power-platform/admin/manage-copilot-studio-messages-capacity |
| Copilot Studio Environments | https://learn.microsoft.com/en-us/microsoft-copilot-studio/environments-first-run-experience |
| Az.CostManagement Module | https://learn.microsoft.com/en-us/powershell/module/az.costmanagement/ |

### Regulatory References

| Regulation | Reference |
|-----------|-----------|
| GLBA 501(b) | Gramm-Leach-Bliley Act, 15 U.S.C. § 6801(b) |
| SOX Section 302 | Sarbanes-Oxley Act, 15 U.S.C. § 7241 |
| SOX Section 404 | Sarbanes-Oxley Act, 15 U.S.C. § 7262 |
| FINRA Rule 4511 | FINRA Rulebook — General Requirements (Books and Records) |
| SEA Rule 17a-4 | Securities Exchange Act Rule 17a-4 (Records Retention) |
| OCC 2013-29 | OCC Bulletin 2013-29 — Third-Party Relationships: Risk Management Guidance |

### Community & Ecosystem

| Resource | URL |
|----------|-----|
| Power Platform Billing Policy API Script | https://gist.github.com/joerodgers/1d996a90f27a9a45ab29882c479f9001 |
| Copilot Studio Usage Estimator | https://microsoft.github.io/copilot-studio-estimator/ |
| FinOps Toolkit for Power BI | https://sebassem.github.io/finops-toolkit/power-bi/setup |
| Copilot Studio & Azure Labs | https://github.com/Azure/Copilot-Studio-and-Azure |

### Internal References

| Document | Path |
|----------|------|
| DAX Measures | [src/power-bi/cost-measures.dax](src/power-bi/cost-measures.dax) |
| Sample Power BI Model | [src/power-bi/sample-model.md](src/power-bi/sample-model.md) |
| Billing Policy Setup Script | [src/azure/billing-policy-setup.ps1](src/azure/billing-policy-setup.ps1) |
| Cost Alert ARM Template | [src/azure/cost-alert-template.json](src/azure/cost-alert-template.json) |
| Tagging Strategy | [src/azure/tagging-strategy.json](src/azure/tagging-strategy.json) |
| Reference Architecture | [src/architecture/reference-architecture.drawio](src/architecture/reference-architecture.drawio) |
| Data Flow | [src/architecture/data-flow.md](src/architecture/data-flow.md) |
| Alternative Approaches | [src/architecture/alternative-approaches.md](src/architecture/alternative-approaches.md) |
| Regulatory Alignment | [governance/regulatory-alignment.md](governance/regulatory-alignment.md) |
| Evidence Collection Playbook | [governance/evidence-collection-playbook.md](governance/evidence-collection-playbook.md) |
| Separation of Duties Matrix | [governance/separation-of-duties-matrix.md](governance/separation-of-duties-matrix.md) |
| Known Gaps and Roadmap | [limitations/known-gaps-and-roadmap.md](limitations/known-gaps-and-roadmap.md) |
| Delivery Checklist | [DELIVERY-CHECKLIST.md](DELIVERY-CHECKLIST.md) |
| Changelog | [CHANGELOG.md](CHANGELOG.md) |
