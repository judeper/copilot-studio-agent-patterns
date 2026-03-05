# Agent Cost Governance — PAYGO

A Tier-2 Cross-Cutting Governance solution providing leadership-quality PAYGO cost visibility for Copilot Studio agents using Azure Cost Management and Power BI.

## Problem Statement

- Organizations deploying Copilot Studio agents under PAYGO billing lack consolidated, leadership-ready cost dashboards.
- Azure Cost Management reports Power Platform consumption at the **environment level**, not individual agent level, making per-agent charge-back difficult.
- Financial services institutions require audit-grade evidence of cost governance controls mapped to GLBA, SOX, FINRA, and OCC regulations.

## Solution Summary

- **Billing Policy → Azure Cost Management → Power BI** pipeline providing near-real-time (24h latency) cost visibility.
- Pre-built DAX measures for Copilot Credit consumption, environment breakdown, and month-over-month variance.
- Deployable Azure artifacts: billing policy setup script, cost alert ARM template, and tagging strategy.
- FSI regulatory alignment mapping with evidence collection playbook and separation-of-duties matrix.

## Quick Links

- [Solution Documentation](SOLUTION-DOCUMENTATION.md) — full specification
- [Delivery Checklist](DELIVERY-CHECKLIST.md) — audit-grade deployment checklist
- [DAX Measures](src/power-bi/cost-measures.dax) — Power BI cost calculations
- [Billing Policy Setup](src/azure/billing-policy-setup.ps1) — provisioning script
- [Cost Alert Template](src/azure/cost-alert-template.json) — budget alert ARM template
- [Architecture](src/architecture/data-flow.md) — data flow reference
- [Regulatory Alignment](governance/regulatory-alignment.md) — FSI regulation mapping
- [Known Gaps](limitations/known-gaps-and-roadmap.md) — limitations and roadmap

## Prerequisites

- **Azure**: Subscription with Owner/Contributor role; Cost Management enabled.
- **Power Platform**: Environment with Copilot Studio capacity; Admin role.
- **Power BI**: Pro or Premium Per User license.

## Intended Audience

FinOps / Finance, Platform Administrators, Compliance / Risk, IT Leadership.

## Architecture

```
Copilot Studio Agents → PAYGO Billing Policy → Azure Cost Management → Power BI Dashboard → Budget Alerts
```

## Known Limitations

- ❌ No per-agent cost attribution in Azure Cost Management — billing is at environment level.
- ❌ 24-hour data latency between consumption and reporting.
- ❌ Agent/environment identifiers appear as GUIDs — display-name mapping required.
- ❌ Power BI connector supports ≤$5M raw cost details — use Cost Export for larger datasets.
- See [Known Gaps and Roadmap](limitations/known-gaps-and-roadmap.md) for details.

## Positioning

This solution is an **interim financial governance bridge** providing leadership-quality cost visibility using currently available platform capabilities while Microsoft enhances native per-agent billing granularity.

## License

Inherits the repository license.
