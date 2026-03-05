# Changelog

All notable changes to the Agent Cost Governance — PAYGO solution will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-03-05

### Added

- Initial release of PAYGO cost governance solution.
- Azure Cost Management + Power BI reference architecture for Copilot Studio agent cost visibility.
- Power BI DAX measures for Copilot Credit consumption analysis (current month, environment breakdown, MoM variance).
- Power BI sample data model documentation with recommended tables, relationships, and slicers.
- Azure billing policy setup script using Power Platform REST API.
- Azure Cost Management budget alert ARM template with parameterized thresholds and recipients.
- Resource tagging strategy schema (CostCenter, Environment, BusinessUnit, AgentOwner).
- Reference architecture diagram (draw.io format) and data flow documentation.
- Alternative architecture approaches (Connector vs. Cost Export → Data Lake).
- FSI regulatory alignment mapping (GLBA 501(b), SOX 302/404, FINRA 4511, OCC 2013-29).
- Evidence collection playbook with retention schedules and audit preparation steps.
- Separation of duties RACI matrix for Copilot Admin, Azure Billing Owner, Finance, and Compliance roles.
- Known gaps and roadmap documentation with interim governance positioning statement.
- FSI audit-grade delivery checklist with pre-deployment through post-deployment phases.
