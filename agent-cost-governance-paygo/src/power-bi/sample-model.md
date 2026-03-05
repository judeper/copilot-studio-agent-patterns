# Power BI Sample Data Model — Copilot Studio PAYGO Cost Governance

This document describes the recommended Power BI data model for the Agent Cost Governance PAYGO solution. It covers required tables, relationships, recommended slicers, and executive dashboard layout guidance.

---

## Required Tables

### 1. Cost Details (Primary Fact Table)

This table is imported from Azure Cost Management via the native connector or Cost Export.

| Column | Data Type | Description |
|--------|-----------|-------------|
| Date | Date | Date of the cost record |
| Cost | Decimal | Cost amount in billing currency |
| MeterCategory | Text | Azure service category (e.g., "Copilot Studio") |
| MeterName | Text | Specific meter name (e.g., "Copilot Studio – Copilot Credit") |
| MeterSubcategory | Text | Meter subcategory (may contain action type detail) |
| ResourceGroup | Text | Azure resource group linked to the billing policy |
| SubscriptionId | Text | Azure subscription ID |
| SubscriptionName | Text | Azure subscription display name |
| Currency | Text | Billing currency code (e.g., "USD") |
| ResourceId | Text | Full Azure resource identifier |
| Tags | Text | JSON string of Azure resource tags |

> **Note**: Column names may vary depending on the connector version and agreement type. The Azure Cost Management connector may use `PreTaxCost`, `CostInBillingCurrency`, or `Cost` for the cost column. Adjust DAX measures accordingly.

### 2. Date Table (Dimension)

A standard date dimension table for time intelligence calculations.

| Column | Data Type | Description |
|--------|-----------|-------------|
| Date | Date | Calendar date (primary key) |
| Year | Integer | Calendar year |
| Month | Integer | Month number (1–12) |
| MonthName | Text | Month display name (January–December) |
| Quarter | Integer | Quarter number (1–4) |
| QuarterLabel | Text | Quarter display label (Q1–Q4) |
| YearMonth | Text | Year-month label (e.g., "2026-03") |
| DayOfMonth | Integer | Day of month (1–31) |
| IsCurrentMonth | Boolean | TRUE if the date is in the current calendar month |

Generate this table using DAX:

```dax
Date Table =
ADDCOLUMNS(
    CALENDARAUTO(),
    "Year", YEAR([Date]),
    "Month", MONTH([Date]),
    "MonthName", FORMAT([Date], "MMMM"),
    "Quarter", QUARTER([Date]),
    "QuarterLabel", "Q" & QUARTER([Date]),
    "YearMonth", FORMAT([Date], "YYYY-MM"),
    "DayOfMonth", DAY([Date]),
    "IsCurrentMonth", IF(
        YEAR([Date]) = YEAR(TODAY()) && MONTH([Date]) = MONTH(TODAY()),
        TRUE(),
        FALSE()
    )
)
```

### 3. Environment Mapping (Dimension)

A manually maintained lookup table that maps environment GUIDs to display names.

| Column | Data Type | Description |
|--------|-----------|-------------|
| EnvironmentGUID | Text | Power Platform environment ID (GUID) |
| EnvironmentDisplayName | Text | Human-readable environment name |
| BusinessUnit | Text | Owning business unit |
| EnvironmentPurpose | Text | Purpose (e.g., "Production", "Development", "Sandbox") |
| AgentOwner | Text | Contact email for the environment owner |
| ResourceGroup | Text | Associated Azure resource group name (join key) |

> **Important**: This table must be updated manually when environments are created, renamed, or decommissioned. Consider sourcing from the Power Platform Admin Center API for automation.

### 4. Budget (Parameter/Dimension)

A simple table or Power BI parameter holding the monthly budget target.

| Column | Data Type | Description |
|--------|-----------|-------------|
| BudgetAmount | Decimal | Monthly budget in billing currency |
| BudgetPeriod | Text | Budget period (e.g., "2026-03") |
| ApprovedBy | Text | Budget approver name/email |
| ApprovalDate | Date | Date of budget approval |

For a single-budget scenario, use a Power BI parameter instead of a table.

---

## Relationships

```
Date Table[Date]  ──────────>  Cost Details[Date]
                               (Many-to-One, Single direction)

Environment Mapping[ResourceGroup]  ──────────>  Cost Details[ResourceGroup]
                                                  (Many-to-One, Single direction)

Budget[BudgetPeriod]  ──────────>  Date Table[YearMonth]
                                   (Many-to-One, Single direction, inactive — use USERELATIONSHIP in measures)
```

### Relationship Notes

- The **Date Table → Cost Details** relationship enables time intelligence functions (TOTALYTD, SAMEPERIODLASTYEAR, etc.).
- The **Environment Mapping → Cost Details** relationship enables display name resolution and business unit filtering.
- The **Budget** relationship is inactive by default to avoid ambiguity; activate it via USERELATIONSHIP in budget-specific measures.

---

## Recommended Slicers

| Slicer | Source | Purpose |
|--------|--------|---------|
| Date Range | Date Table[Date] | Filter by date range (Between selector) |
| Month | Date Table[YearMonth] | Quick month selection |
| Business Unit | Environment Mapping[BusinessUnit] | Filter by organizational unit |
| Environment | Environment Mapping[EnvironmentDisplayName] | Filter by specific environment |
| Environment Purpose | Environment Mapping[EnvironmentPurpose] | Filter by Prod/Dev/Sandbox |

### Slicer Configuration Tips

- Default the date range slicer to "Last 30 days" or "Current month" for the executive summary page.
- Use a dropdown slicer for Business Unit and Environment to save dashboard real estate.
- Consider a "Last Refresh" card (using `MAX('Cost Details'[Date])`) as a visual indicator of data freshness.

---

## Executive Dashboard Layout Guidance

### Page 1: Executive Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│  [Date Range Slicer]                         [Last Refresh: date]  │
├───────────────┬───────────────┬──────────────┬──────────────────────┤
│  Total Cost   │  MoM Change   │  Budget      │  Projected          │
│  (Current Mo) │  (+12.5%)     │  Utilization │  Month-End          │
│  $4,250       │  ▲ $475       │  68% ●       │  $5,800             │
├───────────────┴───────────────┴──────────────┴──────────────────────┤
│                                                                     │
│  [Cost Trend - Line Chart - Last 6 Months]                         │
│                                                                     │
├──────────────────────────────────┬──────────────────────────────────┤
│  [Top 5 Environments by Cost]   │  [Budget Gauge]                  │
│  Horizontal Bar Chart            │  Gauge: Actual vs Budget         │
│                                  │                                  │
└──────────────────────────────────┴──────────────────────────────────┘
```

### Page 2: Environment Breakdown

```
┌─────────────────────────────────────────────────────────────────────┐
│  [Date Range Slicer]  [Business Unit Slicer]  [Environment Slicer] │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  [Environment Cost Table - Matrix with drill-through]              │
│  Columns: Environment | Cost | % of Total | MoM Change             │
│                                                                     │
├──────────────────────────────────┬──────────────────────────────────┤
│  [Environment Cost Trend]        │  [Cost Distribution Treemap]    │
│  Multi-line chart (top 5 envs)   │                                  │
│                                  │                                  │
└──────────────────────────────────┴──────────────────────────────────┘
```

### Page 3: Budget vs. Actual

```
┌─────────────────────────────────────────────────────────────────────┐
│  [Date Range Slicer]                                               │
├───────────────────────┬─────────────────────────────────────────────┤
│  [Budget Status Card] │  [Daily Burn Rate - Line Chart]            │
│  ● Green / Yellow /   │  Cumulative daily spend with budget line   │
│    Red indicator      │  overlay                                    │
│                       │                                             │
├───────────────────────┴─────────────────────────────────────────────┤
│                                                                     │
│  [Historical Budget Performance - Clustered Bar]                   │
│  Actual vs Budget by month (last 6 months)                         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Design Guidelines

- Maximum 6 visuals per page for executive audiences.
- Use consistent number formatting: currency with 2 decimal places, percentages with 1 decimal.
- Include a footer on every page: *"Data source: Azure Cost Management. Latency: up to 24 hours. Costs reflect environment-level consumption — per-agent breakdown unavailable."*
- Use conditional formatting on the Budget Utilization gauge: Green (0–49%), Yellow (50–79%), Red (80%+).
