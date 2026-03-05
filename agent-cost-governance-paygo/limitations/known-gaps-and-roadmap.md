# Known Gaps and Roadmap — Agent Cost Governance PAYGO

This document provides a comprehensive inventory of the solution's known limitations, their impact, available workarounds, and relevant Microsoft roadmap signals. It serves as the single source of truth for what this solution cannot do and where the platform is heading.

---

## Known Gaps

### 1. No Per-Agent Cost Attribution in Azure Cost Management

**Severity**: High
**Status**: Platform limitation — no immediate resolution expected

**Description**: Azure Cost Management reports Copilot Studio PAYGO consumption at the **environment level**. When multiple agents operate within the same Power Platform environment, their individual credit consumption is aggregated into a single cost line item. There is no mechanism in Azure Cost Management to attribute cost to a specific agent (e.g., "IT Help Desk Agent" vs. "HR FAQ Agent") within a shared environment.

**Impact**:
- Charge-back to individual agent owners is not possible without environment isolation.
- Cost anomaly investigation cannot identify which agent within an environment caused a spike.
- Budget allocation at the agent level requires manual estimation or proxy metrics.

**Workarounds**:
- **Environment isolation**: Deploy each agent (or group of agents) in a separate Power Platform environment. Since billing policies link environments to resource groups, each environment's cost is reported separately in Azure Cost Management. This is the most reliable workaround but increases operational overhead.
- **PPAC usage monitoring**: The Power Platform Admin Center has begun introducing agent-level usage visibility and consumption caps (late 2025). While not integrated with Azure Cost Management or Power BI, it provides supplementary per-agent data within the admin center.
- **Custom telemetry**: Implement Application Insights or Dataverse logging within agent flows to track per-agent invocation counts, then use invocation ratios as a proxy for cost allocation.

**Microsoft roadmap**: Microsoft has signaled investment in granular agent-level billing and monitoring. Features such as per-agent consumption caps and agent-level usage dashboards in the PPAC are in early rollout. However, there is no confirmed timeline for per-agent cost data flowing through to Azure Cost Management or the Power BI connector.

---

### 2. 24-Hour Data Latency

**Severity**: Medium
**Status**: Platform characteristic — unlikely to change significantly

**Description**: There is a latency of **up to 24 hours** between when a Copilot Studio agent consumes Copilot Credits and when that consumption appears in Azure Cost Management. The Azure billing pipeline processes usage events in approximately 4-hour cycles internally, but user-facing data updates may not reflect until the full 24-hour window has elapsed. For new subscriptions, initial data may take up to 48 hours.

**Impact**:
- Dashboards always show data that is at least several hours old.
- Real-time cost monitoring or alerting on individual transactions is not possible.
- Rapid cost containment responses (e.g., disabling a runaway agent within minutes) cannot rely on Azure Cost Management data.

**Workarounds**:
- Include a prominent data freshness indicator on all Power BI dashboard pages.
- Communicate the latency to all stakeholders and set appropriate expectations.
- For urgent cost investigations, check the Power Platform Admin Center's capacity reports, which may update more frequently than Azure Cost Management.
- Configure Power BI scheduled refresh to run daily to ensure dashboards reflect the latest available data.

**Microsoft roadmap**: Azure Cost Management's internal processing frequency is improving, but sub-hour latency for Power Platform billing is not on any published roadmap. The 24-hour latency is consistent with other Azure consumption-based services.

---

### 3. Agent Identifiers as GUIDs

**Severity**: Medium
**Status**: Platform design — no change expected

**Description**: Both Power Platform environment identifiers and Copilot Studio agent/bot identifiers appear as GUIDs (e.g., `a1b2c3d4-e5f6-7890-abcd-ef1234567890`) in Azure Cost Management billing data. There is no built-in mapping to human-readable display names within the Azure billing pipeline.

**Impact**:
- Raw billing data and Power BI reports display GUIDs unless manually mapped.
- New environments or agents require manual updates to the mapping table.
- Stale mappings (renamed or deleted environments) create confusion in historical reports.

**Workarounds**:
- Maintain a manual mapping table in Power BI (see [sample-model.md](../src/power-bi/sample-model.md), Environment Mapping table).
- Consider automating the mapping table refresh using the Power Platform Admin Center API to periodically fetch environment display names.
- Adopt a consistent environment naming convention (e.g., `{Org}-{BU}-{Purpose}-{Stage}`) so that even when GUIDs are displayed, the associated resource group names provide context.

**Microsoft roadmap**: No published plans to include display-name resolution in Azure Cost Management billing records for Power Platform. The Entra Agent Identity feature (2025) assigns Entra IDs to agents, which may eventually enable identity-based cost attribution, but this is speculative.

---

### 4. Power BI Connector Raw Data Limit

**Severity**: Medium (for large enterprises)
**Status**: Connector limitation — workaround available

**Description**: The Power BI Azure Cost Management native connector supports approximately **$5 million in raw (unaggregated) cost details** per report scope. Exceeding this limit may result in incomplete data, refresh failures, or degraded performance.

**Impact**:
- Large enterprises with significant Power Platform spend may not be able to use the native connector.
- Refresh failures may go unnoticed, causing dashboards to display stale data.

**Workarounds**:
- **Incremental refresh**: With Power BI incremental refresh configured, the practical limit extends to approximately $65 million by processing data in monthly slices.
- **Cost Export**: Switch to the Cost Export → Azure Storage → Power BI architecture (Pattern B). This removes the connector's data limit entirely. See [alternative-approaches.md](../src/architecture/alternative-approaches.md) for implementation guidance.
- **Scope reduction**: Reduce the Power BI report scope to a single subscription or resource group to lower the data volume.

**Microsoft roadmap**: No published plans to raise the $5M connector limit. The FinOps toolkit and Cost Export pathway are Microsoft's recommended approach for large-scale cost reporting.

---

### 5. Meter Name Variability

**Severity**: Low
**Status**: Platform characteristic

**Description**: The Azure Cost Management meter name for Copilot Studio may vary by tenant configuration, agreement type (EA, MCA, MPA), and billing region. The current standard meter is `Copilot Studio – Copilot Credit`, but legacy meters (`Copilot Studio message`, pre-September 2025) and tenant-specific variations have been observed.

**Impact**:
- DAX measures using strict text matching may miss cost data from non-standard meters.
- New meter names introduced by Microsoft may not be captured without updating the filter logic.

**Workarounds**:
- The DAX measures in [cost-measures.dax](../src/power-bi/cost-measures.dax) use `CONTAINSSTRING` pattern matching to accommodate known variations.
- Periodically review the raw cost data in Azure Cost Management to identify any new or changed meter names.
- Update the DAX filter predicates if new meter names are observed.

**Microsoft roadmap**: Meter standardization is an ongoing effort across Azure. The shift from "messages" to "Copilot Credits" (September 2025) simplified the meter landscape, but further changes are possible as the platform evolves.

---

### 6. No Automated PPAC Configuration

**Severity**: Low
**Status**: API limitations — improving over time

**Description**: The Power Platform Admin Center does not expose all billing and environment configuration options via API. While billing policy creation is available via the REST API, some operations — particularly environment-to-policy linking, capacity management, and agent-level settings — may require manual steps in the PPAC UI.

**Impact**:
- Fully automated, repeatable provisioning is not possible for all aspects of the solution.
- Manual steps introduce the possibility of human error and are harder to audit.

**Workarounds**:
- The [billing-policy-setup.ps1](../src/azure/billing-policy-setup.ps1) script automates what is available via the REST API and provides clear, step-by-step instructions for manual PPAC operations.
- Document manual steps with screenshots in the evidence collection package.
- Monitor the Power Platform API changelog for expanded automation capabilities.

**Microsoft roadmap**: Microsoft has been steadily expanding the Power Platform REST API surface area. Billing policy management was added in the 2024-10-01 API version. Further API expansion for environment and agent management is expected.

---

## Positioning Statement

> **This solution is an interim financial governance bridge.** It provides leadership-quality cost visibility and audit-grade controls using currently available platform capabilities. As Microsoft enhances native per-agent billing granularity, environment-level attribution controls in the Power Platform Admin Center, and Power BI integration capabilities, the specific artifacts in this solution may be superseded by native platform features. The governance framework, regulatory alignment, and evidence collection practices will remain valuable regardless of platform evolution.

---

## Roadmap Monitoring

The following Microsoft resources should be monitored for updates that may affect this solution's known gaps:

| Resource | URL | What to Watch For |
|----------|-----|-------------------|
| Microsoft 365 Roadmap | https://www.microsoft.com/en-us/microsoft-365/roadmap | Copilot Studio billing and governance features |
| Power Platform Release Plans | https://learn.microsoft.com/en-us/power-platform/release-plan/ | PPAC API expansion, billing enhancements |
| Azure Cost Management Updates Blog | https://azure.microsoft.com/en-us/blog/tag/cost-management/ | Connector improvements, new export capabilities |
| Copilot Studio Documentation | https://learn.microsoft.com/en-us/microsoft-copilot-studio/ | Licensing changes, new meters, API updates |

**Review cadence**: Quarterly, aligned with evidence collection and audit preparation.
