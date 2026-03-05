# Delivery Checklist — Agent Cost Governance PAYGO

> FSI Audit-Grade Deployment Checklist
>
> Complete each phase sequentially. Every checkbox must be checked and evidenced before proceeding to the next phase. Archive evidence per the [Evidence Collection Playbook](governance/evidence-collection-playbook.md).

---

## Phase 1: Pre-Deployment Validation

- [ ] Confirm Azure subscription is active with Owner or Contributor role on the target resource group.
- [ ] Confirm Power Platform environment exists with Copilot Studio capacity allocated.
- [ ] Confirm Power BI Pro or Premium Per User license is available for dashboard author.
- [ ] Confirm Azure Cost Management is enabled on the target subscription.
- [ ] Identify and document the Azure resource group to be used for billing policy linkage.
- [ ] Confirm administrative roles: Power Platform Admin or Global Admin for billing policy creation.
- [ ] Obtain sign-off from Finance stakeholder on budget thresholds and alert recipients.
- [ ] Obtain sign-off from Compliance/Risk on regulatory alignment mapping.
- [ ] Review [Known Gaps and Roadmap](limitations/known-gaps-and-roadmap.md) with all stakeholders.
- [ ] Document the list of Power Platform environments to be linked to the billing policy.

---

## Phase 2: Azure Cost Management Setup

- [ ] Create or identify the Azure resource group for billing policy association.
- [ ] Apply required tags to the resource group per [Tagging Strategy](src/azure/tagging-strategy.json): CostCenter, Environment, BusinessUnit, AgentOwner.
- [ ] Run [billing-policy-setup.ps1](src/azure/billing-policy-setup.ps1) to create the billing policy via Power Platform REST API.
- [ ] Verify the billing policy appears in the Power Platform Admin Center under Billing Policies.
- [ ] Confirm the billing policy is linked to the correct Azure subscription and resource group.
- [ ] Screenshot the billing policy configuration as audit evidence.
- [ ] Verify Azure Cost Management shows the Power Platform billing data (allow up to 48 hours for initial data).

---

## Phase 3: Power Platform Environment Linking

- [ ] Associate each target Power Platform environment with the billing policy created in Phase 2.
- [ ] For each environment, verify the billing policy association in the Power Platform Admin Center.
- [ ] Confirm that Copilot Studio agents in linked environments are generating usage records.
- [ ] Validate that usage data appears in Azure Cost Management within 24 hours of agent activity.
- [ ] Document the environment-to-billing-policy mapping (Environment Name, Environment ID, Billing Policy Name).
- [ ] Screenshot the environment linking configuration as audit evidence.

---

## Phase 4: Power BI Configuration

- [ ] Open Power BI Desktop and connect to Azure Cost Management using the native connector.
- [ ] Configure the connector scope to the subscription or billing account containing Power Platform usage.
- [ ] Import the DAX measures from [cost-measures.dax](src/power-bi/cost-measures.dax) into the Power BI model.
- [ ] Configure the data model per [sample-model.md](src/power-bi/sample-model.md): tables, relationships, and slicers.
- [ ] Build the Executive Summary view: total Copilot Credit cost, month-over-month trend, top environments.
- [ ] Build the Environment Breakdown view: cost per environment, resource group, and service category.
- [ ] Build the Budget vs. Actual view: actual spend against configured budget thresholds.
- [ ] Validate data accuracy: cross-reference Power BI totals with Azure Cost Management portal.
- [ ] Configure scheduled refresh (daily or as appropriate for organizational requirements).
- [ ] Publish the report to Power BI Service and configure workspace access for authorized users.
- [ ] Screenshot the dashboard as audit evidence.

---

## Phase 5: Governance Controls Implementation

- [ ] Deploy the budget alert using [cost-alert-template.json](src/azure/cost-alert-template.json) via Azure CLI or portal.
- [ ] Configure alert thresholds: 50%, 80%, and 100% of monthly budget.
- [ ] Verify alert recipients receive a test notification (or confirm via Azure Monitor activity log).
- [ ] Review and document the separation of duties per [separation-of-duties-matrix.md](governance/separation-of-duties-matrix.md).
- [ ] Confirm no single individual holds both Copilot Admin and Azure Billing Owner roles.
- [ ] Map current controls to regulatory requirements per [regulatory-alignment.md](governance/regulatory-alignment.md).
- [ ] Document any control gaps identified during mapping and assign remediation owners.

---

## Phase 6: Testing & Validation

- [ ] Trigger a test agent interaction in a linked environment and verify the Copilot Credit cost appears in Azure Cost Management within 24 hours.
- [ ] Verify the Power BI dashboard reflects the test interaction cost after scheduled refresh.
- [ ] Verify budget alerts fire correctly when simulated thresholds are approached (or confirm alert rule configuration).
- [ ] Validate that tagging strategy is applied: all relevant resource groups have required tags.
- [ ] Cross-reference environment-level billing data with Power Platform Admin Center Copilot Studio capacity reports.
- [ ] Perform a dry run of the evidence collection process per [evidence-collection-playbook.md](governance/evidence-collection-playbook.md).
- [ ] Document all test results with timestamps and screenshots.

---

## Phase 7: Post-Deployment

- [ ] Distribute the Power BI dashboard link to Finance, Compliance, and IT leadership stakeholders.
- [ ] Schedule the first monthly cost review meeting.
- [ ] Confirm the evidence collection schedule is entered in the team calendar (monthly + quarterly cadence).
- [ ] Archive all Phase 1–6 evidence in the designated compliance repository.
- [ ] Set a 90-day review checkpoint to reassess known limitations and Microsoft roadmap updates.
- [ ] Document lessons learned and any deviations from this checklist.

---

## Phase 8: Audit Evidence Archive

- [ ] Compile all screenshots, configuration exports, and test results into the audit evidence package.
- [ ] Verify the evidence package maps to each control in [regulatory-alignment.md](governance/regulatory-alignment.md).
- [ ] Obtain sign-off from Compliance/Risk that the evidence package is complete.
- [ ] Store the evidence package per retention policy (minimum 6 years per FINRA 4511 / SEA Rule 17a-4).
- [ ] Confirm the evidence storage location meets organizational security and access control requirements.
- [ ] Record the archive location and access procedure in the solution's operational runbook.
