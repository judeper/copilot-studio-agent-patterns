# Alternative Approaches — Agent Cost Governance PAYGO

This document compares the two architectural patterns for Copilot Studio PAYGO cost reporting and provides guidance on when to use each.

---

## Pattern Comparison

| Aspect | Pattern A: Direct Connector | Pattern B: Cost Export → Data Lake |
|--------|----------------------------|-------------------------------------|
| **Setup complexity** | Low — native Power BI connector | Medium — requires Storage Account, export configuration |
| **Azure infrastructure** | None additional | Storage Account (+ optional Data Factory) |
| **Data volume limit** | ~$5M raw cost details | No practical limit |
| **Data retention** | 13 months (Azure CM limit) | Unlimited (configurable in storage) |
| **Refresh method** | Power BI scheduled refresh | Power BI scheduled/incremental refresh |
| **Incremental refresh** | Limited | Full support |
| **Data enrichment** | Limited (Power Query only) | Full (ETL pipeline, custom joins) |
| **Multi-subscription** | One subscription per connector | Consolidate via exports |
| **Ongoing cost** | None (included in Power BI license) | Storage + optional compute |
| **Maintenance** | Minimal | Moderate (export monitoring, storage management) |

---

## When to Use the Direct Connector (Pattern A)

**Recommended for most organizations starting their PAYGO cost governance journey.**

### Decision Criteria

Use Pattern A when **all** of the following are true:

- Monthly Copilot Studio raw cost data is well below $5M.
- No requirement for cost data retention beyond 13 months.
- Single Azure subscription for all Power Platform billing policies.
- Team has Power BI expertise but limited Azure data engineering resources.
- Quick deployment is a priority over long-term scalability.

### Setup Steps

1. Open Power BI Desktop → Get Data → Azure → Azure Cost Management.
2. Select the subscription scope.
3. Import data and apply DAX measures from [cost-measures.dax](../power-bi/cost-measures.dax).
4. Configure scheduled daily refresh in Power BI Service.

### Limitations to Accept

- Data cannot be combined easily with non-Azure cost sources.
- Historical data is limited to Azure Cost Management's retention window.
- If raw data exceeds $5M, refresh failures or incomplete data may occur.

---

## When to Use Cost Export → Data Lake (Pattern B)

**Recommended for large enterprises, multi-subscription environments, or organizations with regulatory retention requirements.**

### Decision Criteria

Use Pattern B when **any** of the following are true:

- Monthly raw cost data approaches or exceeds $5M.
- FINRA 4511 or other regulations require cost data retention beyond 13 months (6–7 years).
- Multiple Azure subscriptions need to be consolidated into a single report.
- Organization wants to enrich cost data with custom metadata (agent display names, business unit mappings).
- Advanced analytics (anomaly detection, forecasting beyond linear projection) are planned.

### Setup Steps

1. **Create Azure Storage Account:**
   ```bash
   az storage account create \
       --name "stcopilotcostexport" \
       --resource-group "rg-copilot-billing" \
       --location "eastus" \
       --sku "Standard_LRS" \
       --kind "StorageV2"
   ```

2. **Configure Cost Management Export:**
   ```bash
   az costmanagement export create \
       --name "copilot-daily-export" \
       --scope "/subscriptions/{subscription-id}" \
       --storage-account-id "/subscriptions/{sub-id}/resourceGroups/rg-copilot-billing/providers/Microsoft.Storage/storageAccounts/stcopilotcostexport" \
       --storage-container "cost-data" \
       --timeframe "MonthToDate" \
       --recurrence "Daily" \
       --schedule-status "Active" \
       --type "ActualCost"
   ```

3. **Connect Power BI to Storage:**
   - Get Data → Azure → Azure Blob Storage (or Azure Data Lake Storage Gen2).
   - Point to the storage account and container.
   - Configure Power Query to parse CSV/Parquet files.

4. **Enable Incremental Refresh:**
   - In Power BI Desktop, configure incremental refresh on the cost data table.
   - Set the refresh window (e.g., last 3 months of daily data, with full load for historical months).

5. **Optional — Add Data Enrichment:**
   - Create a mapping table with environment GUIDs → display names.
   - Join in Power Query or use Azure Data Factory for automated enrichment.

### Considerations

- **Storage costs**: Minimal — cost export data is typically small (MBs per month for Power Platform).
- **Immutable storage**: For compliance, enable WORM (Write Once, Read Many) policies on the storage container.
- **Monitoring**: Set up Azure Monitor alerts for export health to detect stale data.

---

## Long-Term Retention Scenarios

For organizations with regulatory retention requirements (FINRA 4511: 6 years, organizational policy: 7 years), Pattern B is the only viable approach.

### Retention Architecture

```
Cost Management Export (daily) → Azure Blob Storage
                                    │
                                    ├── Hot tier: Last 12 months (active reporting)
                                    ├── Cool tier: 13–24 months (occasional access)
                                    └── Archive tier: 25+ months (compliance retention)
```

### Cost Optimization

| Storage Tier | Monthly Cost (per GB) | Access Latency | Use Case |
|-------------|----------------------|----------------|----------|
| Hot | ~$0.018 | Immediate | Active Power BI reporting |
| Cool | ~$0.01 | Immediate | Historical lookback |
| Archive | ~$0.002 | Hours (rehydration required) | Regulatory retention |

For typical Copilot Studio cost data volumes (< 1 GB/year), storage costs are negligible regardless of tier.

---

## Connector $5M Raw Cost Limit — Detail

The $5M limit on the Power BI Azure Cost Management connector is based on the **raw (unaggregated) cost line items** in the report scope. Key clarifications:

- **What counts**: Every individual billing line item (one per meter per resource per day).
- **What doesn't count**: The $5M refers to the sum of raw costs, not the number of rows.
- **Incremental refresh workaround**: With incremental refresh enabled, the practical limit extends to approximately $65M by processing data in monthly slices.
- **Symptoms of exceeding the limit**: Incomplete data, refresh timeouts, Power BI errors during data load.

### Self-Assessment

To estimate whether you'll hit the limit:

1. Open Azure Cost Management → Cost Analysis.
2. Set scope to the billing policy subscription.
3. Set timeframe to the reporting period you want in Power BI.
4. Note the total cost for Copilot Studio meters.
5. If total is below $3M, Pattern A is safe (with headroom).
6. If total is $3M–$5M, consider Pattern B proactively.
7. If total exceeds $5M, Pattern B is required.

---

## Hybrid Approach

Some organizations may benefit from a hybrid approach:

- **Pattern A** for real-time operational dashboards (current month, last 30 days).
- **Pattern B** for long-term retention and historical analytics (all-time data).

This requires two separate Power BI datasets but provides the simplicity of the connector for daily operations and the durability of exports for compliance.
