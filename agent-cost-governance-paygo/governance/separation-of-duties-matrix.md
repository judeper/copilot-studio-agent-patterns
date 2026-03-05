# Separation of Duties Matrix — Agent Cost Governance PAYGO

This document defines the RACI (Responsible, Accountable, Consulted, Informed) matrix for PAYGO cost governance activities. Proper separation of duties prevents conflicts of interest and ensures no single individual can unilaterally control both cost generation and cost reporting.

---

## Roles

| Role | Description | Typical Title |
|------|-------------|---------------|
| **Copilot Admin** | Builds, deploys, and manages Copilot Studio agents. Controls which agents are active and their configuration. | Power Platform Developer, Copilot Studio Maker, Citizen Developer |
| **Azure Billing Owner** | Manages the Azure subscription, billing policies, and resource groups used for PAYGO billing. Controls budget configuration and alert thresholds. | Cloud Infrastructure Lead, Azure Platform Admin |
| **Finance Stakeholder** | Owns the budget for Copilot Studio spending. Approves budget amounts, reviews variances, and manages charge-back processes. | IT Finance Manager, Technology CFO, Business Unit Controller |
| **Compliance / Risk** | Ensures governance controls meet regulatory requirements. Reviews evidence packages and conducts or coordinates audits. | Compliance Officer, Risk Manager, Internal Auditor |

---

## RACI Matrix

| Activity | Copilot Admin | Azure Billing Owner | Finance Stakeholder | Compliance / Risk |
|----------|:-------------:|:-------------------:|:-------------------:|:-----------------:|
| **Agent Deployment** | **R/A** | I | I | I |
| **Environment Creation** | R | **A** | C | I |
| **Billing Policy Creation** | C | **R/A** | C | I |
| **Environment-Policy Linking** | C | **R/A** | I | I |
| **Budget Amount Approval** | I | C | **R/A** | C |
| **Budget Alert Configuration** | I | **R** | **A** | C |
| **Alert Threshold Setting** | I | R | **A** | C |
| **Power BI Dashboard Development** | C | **R** | **A** | C |
| **Dashboard Access Provisioning** | I | **R** | A | C |
| **Monthly Cost Report Review** | I | C | **R/A** | I |
| **Budget Variance Explanation** | C | C | **R/A** | I |
| **Tagging Strategy Definition** | C | **R** | C | **A** |
| **Tag Compliance Monitoring** | I | **R/A** | I | C |
| **Evidence Collection** | C | **R** | R | **A** |
| **Quarterly Audit Preparation** | I | R | R | **R/A** |
| **Separation-of-Duties Attestation** | R | R | R | **R/A** |
| **Regulatory Alignment Review** | I | C | C | **R/A** |
| **Known Limitations Communication** | R | R | I | **A** |

**Legend**: R = Responsible (does the work), A = Accountable (approves/owns), C = Consulted, I = Informed

---

## Critical Separation Requirements

The following separations **must** be maintained. No single individual should hold both roles in any pair:

| Separation | Role A | Role B | Rationale |
|-----------|--------|--------|-----------|
| **Cost generation vs. budget approval** | Copilot Admin | Finance Stakeholder | The person deploying agents (which generate costs) must not be the person approving the budget. |
| **Alert configuration vs. alert recipient** | Azure Billing Owner | Finance Stakeholder | The person setting alert thresholds must not be the sole recipient — prevents alert suppression. |
| **Report authoring vs. report approval** | Azure Billing Owner | Finance Stakeholder | The person building cost reports must not unilaterally approve their own reports. |
| **Billing policy creation vs. financial reconciliation** | Azure Billing Owner | Finance Stakeholder | The person controlling billing infrastructure must not reconcile the resulting financial data. |
| **Evidence collection vs. evidence review** | Azure Billing Owner / Copilot Admin | Compliance / Risk | The people generating evidence must not be the sole reviewers of that evidence. |

---

## Exception Process

If organizational constraints prevent strict role separation (e.g., small teams), document the following:

1. **Which separation cannot be maintained** and why.
2. **Compensating controls** in place (e.g., secondary approval, automated audit logs, periodic external review).
3. **Compliance/Risk acknowledgment** of the exception.
4. **Review date** — exceptions must be reviewed and re-approved at least annually.

Exception documentation should be included in the quarterly evidence package and retained per the [Evidence Collection Playbook](evidence-collection-playbook.md).

---

## Role Assignment Template

Use this template to document current role assignments:

| Role | Assigned To | Email | Effective Date | Last Verified |
|------|------------|-------|----------------|---------------|
| Copilot Admin | [Name] | [email] | [YYYY-MM-DD] | [YYYY-MM-DD] |
| Azure Billing Owner | [Name] | [email] | [YYYY-MM-DD] | [YYYY-MM-DD] |
| Finance Stakeholder | [Name] | [email] | [YYYY-MM-DD] | [YYYY-MM-DD] |
| Compliance / Risk | [Name] | [email] | [YYYY-MM-DD] | [YYYY-MM-DD] |

Update this table when role assignments change. Include the completed table in the quarterly evidence package (Evidence E7).
