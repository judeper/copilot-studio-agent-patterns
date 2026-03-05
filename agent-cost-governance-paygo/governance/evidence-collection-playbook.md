# Evidence Collection Playbook — Agent Cost Governance PAYGO

This playbook defines the evidence types, collection procedures, frequency, and retention requirements for the PAYGO cost governance solution. It supports audit readiness for GLBA 501(b), SOX 302/404, FINRA 4511, and OCC 2013-29.

---

## Evidence Types

| ID | Evidence Type | Source | Format | Owner |
|----|--------------|--------|--------|-------|
| E1 | Monthly Cost Report | Power BI dashboard export | PDF | Finance Stakeholder |
| E2 | Budget Variance Explanation | Finance team | Written narrative (PDF/email) | Finance Stakeholder |
| E3 | Budget Alert Configuration | Azure portal | ARM template export (JSON) | Platform Admin |
| E4 | Alert Delivery Confirmation | Email records | Screenshot or email archive | Platform Admin |
| E5 | Billing Policy Configuration | Power Platform Admin Center | Screenshot + API response (JSON) | Platform Admin |
| E6 | Environment-Policy Mapping | Power Platform Admin Center | Tabular export (CSV/screenshot) | Platform Admin |
| E7 | Role Assignment Documentation | Azure RBAC + PPAC | Screenshot or API export (JSON) | Platform Admin |
| E8 | Tagging Compliance Report | Azure Resource Graph | Query results (CSV) | Platform Admin |
| E9 | Separation-of-Duties Attestation | Compliance team | Signed form (PDF) | Compliance/Risk |
| E10 | Dashboard Accuracy Validation | Cross-reference Power BI vs. Azure portal | Screenshot comparison | Platform Admin |
| E11 | Annual Information Security Program Review | Compliance/Risk | Review report (PDF) | Compliance/Risk |

---

## Collection Schedule

### Monthly Evidence (Due: 5th business day of each month)

| Evidence | Action | Responsible |
|----------|--------|------------|
| E1 — Monthly Cost Report | Export the Power BI Executive Summary page as PDF. Include all three dashboard views. | Finance Stakeholder |
| E2 — Budget Variance Explanation | If actual spend deviates >10% from budget or prior month, prepare a written explanation. | Finance Stakeholder |
| E4 — Alert Delivery Confirmation | Verify that all budget alerts triggered during the month were received. Archive one sample alert email. | Platform Admin |
| E8 — Tagging Compliance Report | Run the Azure Resource Graph query below and export results. Remediate any non-compliant resource groups. | Platform Admin |
| E10 — Dashboard Accuracy Validation | Compare Power BI total cost with Azure Cost Management portal for the prior month. Document any discrepancies. | Platform Admin |

**Azure Resource Graph query for tagging compliance:**
```kusto
resources
| where type == "microsoft.resources/subscriptions/resourcegroups"
| where resourceGroup contains "copilot" or resourceGroup contains "billing"
| extend CostCenter = tags["CostCenter"],
         Environment = tags["Environment"],
         BusinessUnit = tags["BusinessUnit"],
         AgentOwner = tags["AgentOwner"]
| project name, CostCenter, Environment, BusinessUnit, AgentOwner
| where isempty(CostCenter) or isempty(Environment) or isempty(BusinessUnit) or isempty(AgentOwner)
```

### Quarterly Evidence (Due: 15th business day of each quarter)

| Evidence | Action | Responsible |
|----------|--------|------------|
| E3 — Budget Alert Configuration | Export the ARM template for the current budget alert configuration. Compare with the baseline in this repo. | Platform Admin |
| E5 — Billing Policy Configuration | Screenshot the billing policy in the PPAC showing linked subscription, resource group, and status. | Platform Admin |
| E6 — Environment-Policy Mapping | Export the list of environments linked to each billing policy. Verify all production environments are linked. | Platform Admin |
| E7 — Role Assignment Documentation | Export Azure RBAC role assignments for the billing resource group. Export PPAC admin role assignments. | Platform Admin |

### Annual Evidence (Due: Within 30 days of fiscal year end)

| Evidence | Action | Responsible |
|----------|--------|------------|
| E9 — Separation-of-Duties Attestation | Each role holder in the RACI matrix signs an attestation confirming their understanding of role boundaries. | Compliance/Risk |
| E11 — Annual ISP Review | Review the Information Security Program components related to agent cost governance. Document any changes, additions, or gaps. | Compliance/Risk |

---

## Retention Requirements

| Regulatory Basis | Minimum Retention | Storage Requirement |
|-----------------|-------------------|---------------------|
| FINRA 4511 / SEA Rule 17a-4 | 6 years | Non-rewritable, non-erasable (WORM) for the full retention period |
| SOX 302/404 | 7 years (recommended) | Auditable, tamper-evident storage |
| GLBA 501(b) | Per institutional ISP (typically 5–7 years) | Secure storage with access controls |
| OCC 2013-29 | Per institutional policy (typically 5–7 years) | Accessible for regulatory examination |

**Recommended baseline**: **6 years** minimum retention in immutable storage, with organizational policies potentially extending to 7 years.

### Storage Implementation Options

| Option | WORM Support | Cost | Complexity |
|--------|-------------|------|-----------|
| Azure Blob Storage (immutability policy) | Yes | Low | Low |
| SharePoint with Records Management | Yes (with compliance center) | Included in M365 E5 | Medium |
| Dedicated compliance archival system | Yes | Varies | High |
| On-premises archive | Depends on system | Varies | High |

**Recommended**: Azure Blob Storage with immutability policy in a dedicated container. This aligns with the Azure-centric architecture of this solution.

### Accessibility Requirements (FINRA/SEA 17a-4)

| Period | Accessibility Level |
|--------|-------------------|
| Years 1–2 | Readily accessible — retrievable within hours |
| Years 3–6 | Reasonably accessible — retrievable within days |

Implement this using Azure Blob Storage access tiers:
- **Hot tier**: Years 1–2 (immediate access, higher cost).
- **Cool tier**: Years 3–4 (slightly delayed access, lower cost).
- **Archive tier**: Years 5–6 (rehydration required, lowest cost).

---

## Quarterly Audit Preparation Steps

Perform these steps in the month preceding each quarterly review or regulatory examination:

### Step 1: Evidence Inventory

- [ ] Verify all monthly evidence (E1, E2, E4, E8, E10) has been collected for each month in the quarter.
- [ ] Verify quarterly evidence (E3, E5, E6, E7) has been collected.
- [ ] Identify any gaps and assign remediation owners.

### Step 2: Cross-Reference Validation

- [ ] Compare monthly cost report totals (E1) against Azure Cost Management portal data.
- [ ] Verify budget variance explanations (E2) exist for all months with >10% deviation.
- [ ] Confirm role assignments (E7) match the separation-of-duties matrix.

### Step 3: Control Effectiveness Assessment

- [ ] Review all budget alert triggers during the quarter. Were they appropriate?
- [ ] Review all budget threshold breaches. Were responses documented and timely?
- [ ] Assess whether current budget thresholds remain appropriate for actual spend levels.

### Step 4: Package Compilation

- [ ] Organize evidence into a structured package with consistent naming:
  ```
  YYYY-QN/
  ├── monthly/
  │   ├── YYYY-MM-cost-report.pdf
  │   ├── YYYY-MM-variance-explanation.pdf
  │   ├── YYYY-MM-alert-confirmation.png
  │   ├── YYYY-MM-tagging-compliance.csv
  │   └── YYYY-MM-dashboard-validation.png
  ├── quarterly/
  │   ├── budget-alert-config.json
  │   ├── billing-policy-screenshot.png
  │   ├── environment-mapping.csv
  │   └── role-assignments.json
  └── index.md (evidence inventory with regulatory mapping)
  ```
- [ ] Upload to the designated compliance repository.
- [ ] Verify access controls — only authorized personnel should access the evidence package.

### Step 5: Stakeholder Sign-Off

- [ ] Finance Stakeholder confirms cost report accuracy.
- [ ] Platform Admin confirms technical configuration evidence is current.
- [ ] Compliance/Risk confirms evidence package is complete and meets regulatory requirements.

---

## Monthly Checklist (Quick Reference)

Copy this checklist each month for tracking:

```markdown
## Monthly Evidence Collection — [YYYY-MM]

- [ ] E1: Export Power BI cost report (PDF) — all three views
- [ ] E2: Write budget variance explanation (if >10% deviation)
- [ ] E4: Archive sample budget alert email (if alerts triggered)
- [ ] E8: Run tagging compliance query and export results
- [ ] E10: Cross-reference Power BI vs. Azure portal totals
- [ ] Upload all evidence to compliance repository
- [ ] Update evidence inventory index
```
