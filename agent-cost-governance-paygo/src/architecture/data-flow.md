# Data Flow — Agent Cost Governance PAYGO

This document describes the data flow from Copilot Studio agent consumption through to Power BI dashboards and budget alerts, including latency characteristics, transformation points, and known constraints.

---

## Primary Flow: Power BI Native Connector

This is the default and recommended flow for organizations with moderate Copilot Studio spend (below $5M in raw cost details).

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Copilot     │     │  Billing     │     │  Azure Cost  │     │  Power BI    │
│  Studio      │────>│  Policy      │────>│  Management  │────>│  Dashboard   │
│  Agents      │     │  (PPAC)      │     │              │     │              │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
  Copilot Credits      Links env to         Aggregates          Native connector
  consumed per          Azure sub +          usage data          imports cost data
  interaction           resource group       by meter            into Power BI model
```

### Stage-by-Stage Detail

#### 1. Agent Consumption → Billing Policy

- **Trigger**: Each Copilot Studio agent interaction consumes Copilot Credits based on the action type (Classic=1, Generative=2, Agent Action=5, etc.).
- **Latency**: Near-instantaneous — credits are consumed at interaction time.
- **Data format**: Internal Microsoft metering events (not directly accessible).
- **Granularity**: Per-interaction credit consumption, associated with the environment in which the agent runs.

#### 2. Billing Policy → Azure Cost Management

- **Trigger**: The PAYGO billing policy maps environment consumption to an Azure subscription and resource group.
- **Latency**: **Up to 24 hours**. Internal processing refreshes approximately every 4 hours, but user-facing data may not update for the full 24-hour window. New subscriptions may require up to 48 hours for initial data.
- **Data format**: Azure billing records with meter category, meter name, cost, resource group, date, and subscription metadata.
- **Granularity**: **Environment level**. All agents within an environment appear as a single cost line item under the linked resource group. There is no per-agent breakdown in Azure Cost Management.

#### 3. Azure Cost Management → Power BI

- **Trigger**: Power BI scheduled refresh (daily recommended).
- **Latency**: Depends on refresh schedule — typically daily.
- **Data format**: Tabular data imported into the Power BI data model via the Azure Cost Management connector.
- **Granularity**: Same as Azure Cost Management — environment/resource group level.
- **Limit**: The native connector supports approximately **$5 million in raw cost details** per report scope. Exceeding this may cause incomplete data or refresh failures.

### End-to-End Latency

| Scenario | Typical Latency | Maximum Latency |
|----------|----------------|-----------------|
| Agent interaction to Azure CM data | 4–12 hours | 24 hours (48h for new subscriptions) |
| Azure CM data to Power BI refresh | Per refresh schedule | +24 hours (daily refresh) |
| Total: Interaction to dashboard | 4–36 hours | 48–72 hours |

---

## Alternative Flow: Cost Export → Data Lake → Power BI

This flow is recommended for organizations with high Copilot Studio spend, long-term retention requirements, or advanced analytics needs.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Copilot     │     │  Billing     │     │  Azure Cost  │     │  Azure       │     │  Power BI    │
│  Studio      │────>│  Policy      │────>│  Management  │────>│  Storage     │────>│  Dashboard   │
│  Agents      │     │  (PPAC)      │     │              │     │  Account     │     │              │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
  Copilot Credits      Links env to         Scheduled           CSV or Parquet       DirectQuery or
  consumed             Azure sub            export              files in blob        Import with
                                                                storage              incremental refresh
```

### Stage-by-Stage Detail

#### 1–2. Agent Consumption → Azure Cost Management

Same as the primary flow (see above).

#### 3. Azure Cost Management → Azure Storage

- **Trigger**: Scheduled Cost Management export (daily or monthly).
- **Latency**: Export runs on schedule + Azure CM data freshness (up to 24h total).
- **Data format**: CSV or Parquet files in Azure Blob Storage.
- **Retention**: Configurable — files persist until deleted. Supports long-term retention (7+ years for compliance).
- **Cost**: Azure Storage costs (minimal for cost data volumes).

#### 4. Azure Storage → Power BI

- **Trigger**: Power BI scheduled refresh or DirectQuery.
- **Latency**: Per refresh schedule.
- **Data format**: Tabular data from CSV/Parquet files.
- **Granularity**: Same as Azure Cost Management data. Can be enriched with additional metadata (agent display names, business unit mappings) via Power Query transformations.
- **Limit**: No practical data limit (bounded by Power BI Premium capacity for large models).

### When to Switch to the Alternative Flow

| Indicator | Threshold | Action |
|-----------|-----------|--------|
| Monthly raw cost data | Approaching $5M | Switch to Cost Export |
| Retention requirement | > 13 months (Azure CM retention limit) | Switch to Cost Export |
| Multi-subscription consolidation | > 1 subscription | Consider Cost Export for unified view |
| Custom enrichment needed | Agent name mapping, BU tags | Cost Export + Power Query |
| Incremental refresh required | Large datasets, slow refresh | Cost Export + incremental refresh |

---

## Known Constraints

### Environment-Level Attribution

Azure Cost Management does not break down costs by individual Copilot Studio agent within an environment. If Environment A contains Agent X and Agent Y, the total cost for Environment A is reported, but the split between Agent X and Agent Y is not available.

**Workarounds:**
- Deploy agents in separate environments for cost isolation.
- Use Power Platform Admin Center for emerging agent-level usage visibility (not yet integrated with Azure Cost Management).

### Meter Name Variability

The Azure meter name for Copilot Studio may vary:
- `Copilot Studio – Copilot Credit` (current standard)
- `Copilot Studio message` (legacy, pre-September 2025)
- Tenant-specific variations possible

The DAX measures in [cost-measures.dax](../power-bi/cost-measures.dax) use CONTAINSSTRING pattern matching to accommodate known variations.

### Data Freshness Window

Cost data should not be considered final until after the billing period closes (up to 5 business days after month-end). During the finalization window, costs may be adjusted. Power BI dashboards should include a data freshness disclaimer for stakeholders.

### PAYGO vs. Prepaid

This data flow tracks PAYGO consumption only. If the organization also uses prepaid Copilot Credit packs, those costs appear as a one-time purchase, not as per-credit consumption. The DAX measures are designed for PAYGO metered consumption; prepaid pack costs require separate handling.
