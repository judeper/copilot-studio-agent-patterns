# Regulatory Alignment — Agent Cost Governance PAYGO

This document maps the solution's governance controls to specific regulatory requirements applicable to financial services institutions. Each regulation includes the specific requirement, the solution control that addresses it, and the evidence type for audit and examination purposes.

---

## Alignment Matrix

| Regulation | Section | Requirement Summary | Solution Control | Evidence Type | Collection Frequency |
|-----------|---------|---------------------|-----------------|---------------|---------------------|
| **GLBA** | 501(b) | Implement administrative, technical, and physical safeguards appropriate to the institution's size and complexity | Budget controls, alert thresholds, separation of duties, tagging strategy | Monthly cost reports, quarterly control attestations, annual ISP review | Monthly / Quarterly / Annually |
| **GLBA** | 501(b) | Appoint a qualified individual to oversee the information security program | Separation-of-duties matrix designates Platform Admin and Compliance roles | Role assignment documentation, org chart excerpt | Annually |
| **GLBA** | 501(b) | Regularly test and monitor safeguards | Budget alert validation, Power BI dashboard accuracy checks | Test results, alert delivery confirmation | Monthly |
| **SOX** | 302 | CEO/CFO certification of financial report accuracy | Budget vs. actual dashboards with auditable data lineage from Azure CM | Quarterly dashboard exports, data lineage documentation | Quarterly |
| **SOX** | 404 | Annual assessment of internal controls over financial reporting (ICFR) | Separation of duties, automated budget alerts (detective control), tagging for cost allocation | Annual ICFR assessment report, control effectiveness documentation | Annually |
| **SOX** | 404 | Audit trail for financial decisions | Budget approval records, variance explanations, alert response documentation | Written narratives, email records, approval logs | Per occurrence |
| **FINRA** | 4511 | Make and preserve books and records per FINRA, Exchange Act, and SEC rules | Cost reports, budget decisions, alert histories retained per evidence collection playbook | Archived cost reports (PDF), decision logs | Monthly (6-year retention) |
| **FINRA** | 4511 / SEA 17a-4 | Retain records for specified periods in compliant formats | Evidence collection with 6-year minimum retention in immutable storage | Storage configuration documentation, retention policy | Annually (verify) |
| **FINRA** | 4511 | Records must be readily accessible for examination | Power BI dashboards with historical data; archived evidence in searchable repository | Dashboard access demonstration, archive index | On demand |
| **OCC** | 2013-29 | Comprehensive due diligence and ongoing monitoring of third-party relationships | Azure Cost Management provides ongoing financial monitoring of Microsoft (third party) | Monthly and quarterly vendor cost reports | Monthly / Quarterly |
| **OCC** | 2013-29 | Board-level reporting on third-party risks | Executive summary Power BI dashboard exportable for board packages | Quarterly board report excerpts | Quarterly |
| **OCC** | 2013-29 | Financial oversight of third-party spending | Budget controls with multi-tier alerts; budget approval workflow | Budget approval records, alert configuration exports | Monthly |

---

## Detailed Control Mapping

### GLBA 501(b) — Information Security Program

**Regulation**: Financial institutions must develop, implement, and maintain a comprehensive written Information Security Program (ISP) that includes administrative, technical, and physical safeguards to protect the security, confidentiality, and integrity of customer information.

**How this solution contributes**:

| ISP Component | Solution Contribution |
|--------------|----------------------|
| Administrative safeguards | Budget governance, separation of duties, evidence collection playbook |
| Risk assessment integration | Cost visibility enables risk-proportionate investment in agent security |
| Board/management reporting | Executive dashboard provides leadership-quality cost visibility |
| Program monitoring | Budget alerts provide continuous monitoring of agent-related spending |
| Documentation | SOLUTION-DOCUMENTATION.md, evidence playbook, RACI matrix |

**What this solution does NOT address** (out of scope):
- Technical safeguards for agent data handling (addressed by platform security controls).
- Physical safeguards (addressed by Azure datacenter controls).
- Customer information classification (addressed by data governance controls).

---

### SOX 302/404 — Internal Controls Over Financial Reporting

**Regulation**: Public companies must assess and report on the effectiveness of internal controls over financial reporting. IT controls that support financial reporting processes are in scope.

**How this solution contributes**:

| ICFR Control Objective | Solution Control | Control Type |
|-----------------------|-----------------|--------------|
| Accuracy of cost reporting | Azure Cost Management data lineage → Power BI | Detective |
| Completeness of cost capture | Billing policy ensures all linked environments report costs | Preventive |
| Timeliness of reporting | Daily Power BI refresh; 24-hour latency disclosed | Detective |
| Authorization of spending | Budget approval workflow, separation of duties | Preventive |
| Anomaly detection | Budget threshold alerts at 50%, 80%, 100% | Detective |
| Segregation of duties | RACI matrix separating deployment, budgeting, reporting, and reconciliation | Preventive |

**Materiality note**: If Copilot Studio agent costs are immaterial to financial statements, these controls may be documented but excluded from the ICFR scope assessment. Materiality determination is the responsibility of the Finance and Audit teams.

---

### FINRA 4511 — Books and Records

**Regulation**: FINRA member firms must make and preserve books and records as required under FINRA rules, the Exchange Act, and SEC rules, including SEA Rule 17a-4.

**How this solution contributes**:

| Record Requirement | Solution Artifact | Retention Period |
|-------------------|-------------------|-----------------|
| Business records related to IT spending | Monthly cost reports (PDF export from Power BI) | 6 years |
| Budget decisions and approvals | Budget approval documentation, variance explanations | 6 years |
| Alert notifications and responses | Alert history from Azure Monitor, response logs | 6 years |
| Control configuration records | ARM template exports, billing policy screenshots | 6 years |
| Audit evidence packages | Compiled evidence from evidence collection playbook | 6 years |

**SEA Rule 17a-4 compliance considerations**:
- Records should be stored in non-rewritable, non-erasable format (WORM) for the retention period.
- Azure Blob Storage with immutability policies satisfies the WORM requirement.
- Records must be readily accessible for the first 2 years, then reasonably accessible for the remaining 4 years.

---

### OCC 2013-29 — Third-Party Risk Management

**Regulation**: National banks and federal savings associations must manage risks arising from third-party relationships through due diligence, ongoing monitoring, and board reporting.

**How this solution contributes**:

| Risk Management Phase | Solution Contribution |
|----------------------|----------------------|
| Due diligence | Cost governance artifacts demonstrate financial oversight of Microsoft's platform |
| Contract management | Budget controls enable monitoring of actual spend against expected terms |
| Ongoing monitoring | Monthly cost reports, automated alerts, quarterly evidence collection |
| Board reporting | Executive dashboard exportable for board risk committee packages |
| Termination planning | Cost data supports transition cost analysis if migrating away from the platform |

**Third-party context**: Microsoft Copilot Studio is a cloud service — a third-party technology provider. This solution provides the financial monitoring component of the broader vendor risk management program. Technical risk assessment, security evaluation, and contractual oversight are addressed by other organizational functions.

---

## Evidence Summary by Regulation

| Regulation | Minimum Evidence Package |
|-----------|-------------------------|
| GLBA 501(b) | Monthly cost reports, quarterly control attestations, annual ISP review, role assignments, alert test results |
| SOX 302/404 | Quarterly dashboard exports, annual ICFR assessment, separation-of-duties attestation, data lineage documentation |
| FINRA 4511 | Monthly cost reports (6-year WORM retention), budget decisions, alert histories, control configurations |
| OCC 2013-29 | Quarterly vendor cost reports, annual risk assessment, board-level summaries, monitoring evidence |

See [evidence-collection-playbook.md](evidence-collection-playbook.md) for detailed collection procedures and schedules.
